import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/medication.dart';
import 'package:medication_follow_up_app/services/medication_repository.dart';
import 'package:medication_follow_up_app/services/medication_reminders.dart';
import 'package:medication_follow_up_app/state/medication_provider.dart';

import 'support/memory_medication_store.dart';

/// Models a committed write whose response arrives after a newer live snapshot.
class DelayedResultStore extends MemoryMedicationStore {
  Completer<void>? delayNextResult;

  @override
  Future<T> transaction<T>(
    String medicationId,
    Future<T> Function(MedicationTransaction transaction) action,
  ) async {
    final delay = delayNextResult;
    delayNextResult = null;
    final result = await super.transaction(medicationId, action);
    await delay?.future;
    return result;
  }
}

class RecordingReminders implements MedicationReminderGateway {
  final calls = <String>[];
  final refills = <Medication>[];
  bool fail = false;
  @override
  bool get isAvailable => true;
  @override
  Future<void> syncSchedule(Medication m) async {
    calls.add('schedule:${m.id}');
  }

  @override
  Future<void> syncRefill(RefillAlert alert) async {
    if (fail) throw StateError('permission or platform failure');
    calls.add('refill:${alert.medication.stockAmount}');
    refills.add(alert.medication);
  }

  @override
  Future<void> cancelMedication(String patientId, String medicationId) async {
    calls.add('cancel-med:$medicationId');
  }

  @override
  Future<void> cancelRefill(String patientId, String medicationId) async {
    calls.add('cancel-refill:$medicationId');
  }

  @override
  Future<void> clearPatient(String patientId) async {
    calls.add('clear:$patientId');
  }
}

Future<void> flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late MemoryMedicationStore store;
  late StoredMedicationRepository repo;
  late MedicationProvider state;
  late RecordingReminders reminders;
  String? uid;
  setUp(() {
    uid = 'patient-1';
    store = MemoryMedicationStore();
    repo = StoredMedicationRepository(store, currentPatientId: () => uid);
    reminders = RecordingReminders();
    state = MedicationProvider(repo, reminders: reminders);
  });
  tearDown(() async {
    state.dispose();
    await store.close();
  });

  test('loading, read failure, retry and active/inactive filtering', () async {
    var m = await repo.create(medicationDraft());
    m = await repo.deactivate(m);
    store.failReads = true;
    state.updateSession(uid);
    expect(state.isLoading, isTrue);
    await flush();
    expect(state.errorMessage, isNotNull);
    expect(state.activeMedications, isEmpty);
    store.failReads = false;
    state.retry();
    await flush();
    expect(state.errorMessage, isNull);
    expect(state.isLoading, isFalse);
    expect(state.activeMedications, isEmpty);
    expect(state.find(m.id)?.isActive, isFalse);
  });

  test(
    'write pending blocks duplicate submissions; failure keeps data unchanged',
    () async {
      state.updateSession(uid);
      await flush();
      store.holdWrites = Completer<void>();
      final pending = state.save(medicationDraft(), creating: true);
      expect(state.isBusy, isTrue);
      expect(await state.save(medicationDraft(), creating: true), isNull);
      expect(store.transactions, 1);
      store.holdWrites!.complete();
      await pending;
      await flush();
      expect(state.activeMedications, hasLength(1));
      store.failWrites = true;
      final original = state.activeMedications.single;
      expect(await state.updateSupply(original, 0), isNull);
      expect(state.writeError, isNotNull);
      expect(state.activeMedications.single.stockAmount, original.stockAmount);
      expect(state.isBusy, isFalse);
    },
  );

  test('logout clears records and old pending writes cannot populate the new account', () async {
    await repo.create(medicationDraft());
    state.updateSession(uid);
    await flush();
    expect(state.activeMedications, hasLength(1));
    store.holdWrites = Completer<void>();
    final oldWrite = state.save(
      medicationDraft(name: 'Private A draft'),
      creating: true,
    );
    uid = 'patient-B';
    state.updateSession(uid);
    expect(state.activeMedications, isEmpty);
    expect(state.isBusy, isFalse);
    store.holdWrites!.complete();
    expect(await oldWrite, isNull);
    await flush();
    expect(state.activeMedications, isEmpty);
    expect(store.records('patient-B'), isEmpty);
    expect(store.records('patient-1'), hasLength(1));
    expect(reminders.calls, contains('clear:patient-1'));
  });

  test('live supply changes refresh subscribed state and stock consumption is idempotent', () async {
    final m = await repo.create(medicationDraft());
    state.updateSession(uid);
    await flush();
    var notifications = 0;
    state.addListener(() => notifications++);
    await repo.updateSupply(m, 6);
    await flush();
    expect(state.activeMedications.single.stockAmount, 6);
    await state.consumeStock(medicationId: m.id, doseRecordId: 'dose-1');
    await state.consumeStock(medicationId: m.id, doseRecordId: 'dose-1');
    await flush();
    expect(state.activeMedications.single.stockAmount, 5);
    expect(notifications, greaterThan(0));
  });

  test(
    'a delayed consumption response cannot replace a newer live balance',
    () async {
      state.dispose();
      await store.close();
      final delayedStore = DelayedResultStore();
      store = delayedStore;
      repo = StoredMedicationRepository(store, currentPatientId: () => uid);
      state = MedicationProvider(repo, reminders: reminders);
      final medication = await repo.create(medicationDraft());
      state.updateSession(uid);
      await flush();

      final response = Completer<void>();
      delayedStore.delayNextResult = response;
      final pending = state.consumeStock(
        medicationId: medication.id,
        doseRecordId: 'earlier-dose',
      );
      await flush();
      expect(state.find(medication.id)!.stockAmount, 7);
      await repo.consumeStock(
        patientId: uid!,
        medicationId: medication.id,
        doseRecordId: 'later-dose',
      );
      await flush();
      expect(state.find(medication.id)!.stockAmount, 6);

      response.complete();
      await pending;
      await flush();
      expect(state.find(medication.id)!.stockAmount, 6);
      expect(
        reminders.calls.where((c) => c.startsWith('refill:')).last,
        'refill:6',
      );
    },
  );

  test('refill upsert/update/cancel and deletion hooks do not repeat on unchanged data', () async {
    var m = await repo.create(medicationDraft(stock: 7));
    state.updateSession(uid);
    await flush();
    store.emit();
    store.emit();
    await flush();
    expect(
      reminders.calls.where((c) => c.startsWith('schedule:')),
      hasLength(1),
    );
    expect(reminders.calls.where((c) => c.startsWith('refill:')), ['refill:7']);
    m = (await state.updateSupply(m, 6))!;
    await flush();
    expect(reminders.calls.where((c) => c.startsWith('refill:')), [
      'refill:7',
      'refill:6',
    ]);
    m = (await state.updateSupply(m, 20))!;
    await flush();
    expect(reminders.calls, contains('cancel-refill:${m.id}'));
    await state.deactivate(m);
    await flush();
    expect(reminders.calls, contains('cancel-med:${m.id}'));
    expect(state.activeMedications, isEmpty);
    expect(state.find(m.id), isNotNull);
  });

  test(
    'notification failure does not undo a write; retry synchronizes once',
    () async {
      reminders.fail = true;
      state.updateSession(uid);
      await flush();
      final saved = await state.save(medicationDraft(stock: 0), creating: true);
      await flush();
      expect(saved, isNotNull);
      expect(state.writeError, isNull);
      expect(state.reminderError, isNotNull);
      expect(state.activeMedications.single.stockAmount, 0);
      reminders.fail = false;
      state.retryReminderSync();
      await flush();
      expect(state.reminderError, isNull);
      expect(reminders.calls.where((c) => c == 'refill:0'), hasLength(1));
      expect(
        reminders.calls.where((c) => c.startsWith('schedule:')),
        hasLength(1),
      );
    },
  );

  test(
    'refill alert estimates refresh when consumption or daily times change',
    () async {
      var medication = await repo.create(medicationDraft(stock: 6));
      state.updateSession(uid);
      await flush();
      expect(reminders.refills.single.estimatedDays, 3);
      medication = (await state.save(
        medication.copyWith(unitsPerDose: 2),
        creating: false,
      ))!;
      await flush();
      expect(reminders.refills, hasLength(2));
      expect(reminders.refills.last.estimatedDays, 1.5);
      medication = (await state.save(
        medication.copyWith(scheduledTimes: ['08:00']),
        creating: false,
      ))!;
      await flush();
      expect(reminders.refills, hasLength(3));
      expect(reminders.refills.last.estimatedDays, 3);
      await state.save(
        medication.copyWith(clearUnitsPerDose: true),
        creating: false,
      );
      await flush();
      expect(reminders.refills, hasLength(4));
      expect(reminders.refills.last.estimatedDays, isNull);
      store.emit();
      await flush();
      expect(reminders.refills, hasLength(4));
    },
  );

  test(
    'scope filters out another patient, even if a store returns mixed records',
    () async {
      await repo.create(medicationDraft());
      uid = 'patient-B';
      await repo.create(medicationDraft(patientId: uid!, name: 'B only'));
      state.updateSession(uid);
      await flush();
      expect(state.activeMedications.single.name, 'B only');
      state.updateSession(null);
      expect(state.allMedications, isEmpty);
      expect(state.errorMessage, isNull);
    },
  );
}
