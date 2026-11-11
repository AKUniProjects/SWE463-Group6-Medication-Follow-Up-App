import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/medication.dart';
import 'package:medication_follow_up_app/services/medication_repository.dart';
import 'package:medication_follow_up_app/services/medication_validation.dart';

import 'support/memory_medication_store.dart';

void main() {
  late MemoryMedicationStore store;
  late StoredMedicationRepository repo;
  String? uid;
  setUp(() {
    uid = 'patient-1';
    store = MemoryMedicationStore();
    repo = StoredMedicationRepository(store, currentPatientId: () => uid);
  });
  tearDown(() => store.close());
  Matcher failure(MedicationError code) =>
      throwsA(isA<MedicationException>().having((e) => e.code, 'code', code));

  test('create trims name, sorts times, edit retains ID and fields', () async {
    final first = await repo.create(
      medicationDraft(name: '  Fictional vitamin  ', times: ['20:00', '08:00']),
    );
    expect(first.name, 'Fictional vitamin');
    expect(first.scheduledTimes, ['08:00', '20:00']);
    final edited = await repo.update(first.copyWith(name: 'Renamed vitamin'));
    expect(edited.id, first.id);
    expect(edited.revision, first.revision + 1);
    expect(edited.scheduledTimes, first.scheduledTimes);
    expect(edited.stockUnit, first.stockUnit);
    expect(store.documents, hasLength(1));
    expect(store.records(uid!).single.name, 'Renamed vitamin');
  });

  test(
    'saved data and dose receipts survive a storage/repository restart',
    () async {
      final m = await repo.create(medicationDraft());
      await repo.consumeStock(
        patientId: uid!,
        medicationId: m.id,
        doseRecordId: 'dose-1',
      );
      final restored = MemoryMedicationStore.restore(store.export());
      addTearDown(restored.close);
      final newRepo = StoredMedicationRepository(
        restored,
        currentPatientId: () => uid,
      );
      final result = await newRepo.consumeStock(
        patientId: uid!,
        medicationId: m.id,
        doseRecordId: 'dose-1',
      );
      expect(result.status, ConsumptionStatus.alreadyConsumed);
      expect(result.medication.stockAmount, 7);
      expect(result.medication.scheduledTimes, ['08:00', '20:00']);
    },
  );

  test(
    'deactivation retains metadata and prevents later edits/deductions',
    () async {
      final m = await repo.create(medicationDraft());
      final deleted = await repo.deactivate(m);
      expect(deleted.isActive, isFalse);
      expect(store.records(uid!).single.name, m.name);
      await expectLater(
        repo.update(deleted.copyWith(name: 'Invalid')),
        failure(MedicationError.missing),
      );
      await expectLater(
        repo.consumeStock(
          patientId: uid!,
          medicationId: m.id,
          doseRecordId: 'later',
        ),
        failure(MedicationError.missing),
      );
    },
  );

  test(
    'zero stock persists, inclusive threshold and unit-aware estimates',
    () async {
      var m = await repo.create(
        medicationDraft(dose: 500, doseUnit: 'mg', stock: 8),
      );
      expect(
        m.estimatedDays,
        4,
      ); // 1 counted tablet twice daily, not 500 tablets.
      expect(m.isLowStock, isFalse);
      m = await repo.updateSupply(m, 7);
      expect(m.isLowStock, isTrue);
      expect(m.estimatedDays, 3.5);
      m = await repo.updateSupply(m, 0);
      expect(m.estimatedDays, 0);
      expect(store.records(uid!).single.stockAmount, 0);
      final unknown = await repo.create(
        medicationDraft(dose: 500, doseUnit: 'mg', unitsPerDose: null),
      );
      expect(unknown.estimatedDays, isNull);
      final result = await repo.consumeStock(
        patientId: uid!,
        medicationId: unknown.id,
        doseRecordId: 'unknown-1',
      );
      expect(result.status, ConsumptionStatus.unknownConsumption);
      expect(result.medication.stockAmount, 8);
    },
  );

  test(
    'concurrent repeated confirmations deduct once; no negative stock',
    () async {
      final m = await repo.create(medicationDraft(stock: 1));
      final results = await Future.wait(
        List.generate(
          5,
          (_) => repo.consumeStock(
            patientId: uid!,
            medicationId: m.id,
            doseRecordId: 'scheduled-dose-1',
          ),
        ),
      );
      expect(
        results.where((r) => r.status == ConsumptionStatus.consumed),
        hasLength(1),
      );
      expect(
        results.where((r) => r.status == ConsumptionStatus.alreadyConsumed),
        hasLength(4),
      );
      expect(store.records(uid!).single.stockAmount, 0);
      final next = await repo.consumeStock(
        patientId: uid!,
        medicationId: m.id,
        doseRecordId: 'scheduled-dose-2',
      );
      expect(next.status, ConsumptionStatus.insufficientStock);
      expect(store.receipts[m.id], {'scheduled-dose-1'});
      final restocked = await repo.updateSupply(next.medication, 5);
      final repeated = await repo.consumeStock(
        patientId: uid!,
        medicationId: m.id,
        doseRecordId: 'scheduled-dose-1',
      );
      expect(repeated.medication.stockAmount, restocked.stockAmount);
    },
  );

  test(
    'stale edit cannot restore stock consumed by another operation',
    () async {
      final original = await repo.create(medicationDraft());
      await repo.consumeStock(
        patientId: uid!,
        medicationId: original.id,
        doseRecordId: 'dose-1',
      );
      await expectLater(
        repo.update(original.copyWith(name: 'A stale edit')),
        failure(MedicationError.conflict),
      );
      expect(store.records(uid!).single.stockAmount, 7);
      expect(store.records(uid!).single.name, original.name);
    },
  );

  test('patient B and signed-out callers cannot mutate patient A', () async {
    final m = await repo.create(medicationDraft());
    uid = 'patient-B';
    for (final operation in [
      () => repo.update(m),
      () => repo.updateSupply(m, 20),
      () => repo.deactivate(m),
      () => repo.create(medicationDraft()),
      () => repo.consumeStock(
        patientId: 'patient-1',
        medicationId: m.id,
        doseRecordId: 'dose-1',
      ),
      () => repo.update(m.copyWith(patientId: 'patient-B')),
    ]) {
      await expectLater(operation(), failure(MedicationError.forbidden));
    }
    uid = null;
    await expectLater(
      repo.updateSupply(m, 0),
      failure(MedicationError.signedOut),
    );
    expect(store.records('patient-1').single.stockAmount, 8);
  });

  test('failed transaction leaves medication and receipts unchanged', () async {
    final m = await repo.create(medicationDraft());
    store.failWrites = true;
    await expectLater(
      repo.consumeStock(
        patientId: uid!,
        medicationId: m.id,
        doseRecordId: 'dose-1',
      ),
      failure(MedicationError.unavailable),
    );
    expect(store.records(uid!).single.stockAmount, 8);
    expect(store.receipts[m.id], isEmpty);
    await expectLater(
      repo.create(medicationDraft()),
      failure(MedicationError.unavailable),
    );
    expect(store.documents, hasLength(1));
  });

  test('missing record is recoverable', () async {
    await expectLater(
      repo.update(medicationDraft().copyWith(id: 'gone')),
      failure(MedicationError.missing),
    );
  });

  test(
    'repository rejects invalid names, doses, times, stock and units',
    () async {
      final good = medicationDraft();
      for (final bad in <Medication>[
        good.copyWith(name: '  '),
        good.copyWith(doseAmount: 0),
        good.copyWith(doseAmount: -1),
        good.copyWith(doseAmount: double.nan),
        good.copyWith(doseAmount: double.infinity),
        good.copyWith(stockAmount: -1),
        good.copyWith(refillThreshold: -1),
        good.copyWith(doseUnit: 'invalid'),
        good.copyWith(stockUnit: 'invalid'),
        good.copyWith(scheduledTimes: []),
        good.copyWith(scheduledTimes: ['08:00', '08:00']),
        good.copyWith(scheduledTimes: ['24:00']),
        good.copyWith(unitsPerDose: 0),
      ]) {
        await expectLater(repo.create(bad), failure(MedicationError.invalid));
      }
      expect(store.documents, isEmpty);
    },
  );

  test(
    'numeric form rules reject non-integers, non-finite and missing input',
    () {
      for (final value in ['', '-1', '1.5', 'NaN', 'Infinity', 'abc']) {
        expect(validateStock(value), isNotNull, reason: value);
      }
      expect(validateStock('0'), isNull);
      for (final value in ['', '0', '-1', 'NaN', 'Infinity', 'abc']) {
        expect(validateDose(value), isNotNull, reason: value);
      }
      expect(validateDose('0.5'), isNull);
      expect(validateConsumption(''), isNull);
      expect(validateConsumption('0'), isNotNull);
    },
  );
}
