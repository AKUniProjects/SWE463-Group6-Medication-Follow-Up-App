// DoseProvider tests: real repository rules + in-memory store + a clock we
// control. No Firebase, no widgets.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/dose_record.dart';
import 'package:medication_follow_up_app/models/medication.dart';
import 'package:medication_follow_up_app/services/dose_policy.dart';
import 'package:medication_follow_up_app/services/dose_repository.dart';
import 'package:medication_follow_up_app/services/medication_repository.dart';
import 'package:medication_follow_up_app/state/dose_provider.dart';

import 'support/memory_dose_store.dart';

Medication med(
  String id,
  List<String> times, {
  String patientId = 'patient-1',
}) => Medication(
  id: id,
  patientId: patientId,
  name: 'Medicine $id',
  doseAmount: 1,
  doseUnit: 'tablet',
  scheduledTimes: times,
  stockAmount: 30,
  refillThreshold: 7,
);

/// A saved record for setting up history.
DoseRecord saved(String id, DateTime scheduled, DoseStatus status) =>
    DoseRecord(
      id: id,
      medicationId: 'm1',
      patientId: 'patient-1',
      medicationName: 'Medicine m1',
      scheduledTime: scheduled,
      status: status,
      confirmedAt: status == DoseStatus.taken ? scheduled : null,
    );

void main() {
  late MemoryDoseStore store;
  late DateTime clock;
  late String? signedIn;
  late List<String> stockCalls;
  late ConsumptionStatus stockResult;
  late bool stockOffline;
  late DoseProvider provider;

  DoseProvider build({DosePolicy policy = const DosePolicy()}) => DoseProvider(
    StoredDoseRepository(store, currentPatientId: () => signedIn),
    now: () => clock,
    policy: policy,
    tickInterval: null, // tests call evaluateStatuses() themselves
    consumeStock: ({required medicationId, required doseRecordId}) async {
      stockCalls.add(doseRecordId);
      if (stockOffline) throw StateError('offline');
      return stockResult;
    },
  );

  /// Signs patient-1 in with medication m1 at 08:00 and 20:00, then lets
  /// the first load finish.
  Future<void> start(DoseProvider p, {String? patientId = 'patient-1'}) async {
    p.updateSession(
      patientId: patientId,
      medications: [
        med('m1', ['08:00', '20:00']),
      ],
    );
    await pumpEventQueue();
  }

  setUp(() {
    store = MemoryDoseStore();
    clock = DateTime(2026, 11, 13, 7); // 07:00, before both doses
    signedIn = 'patient-1';
    stockCalls = [];
    stockResult = ConsumptionStatus.consumed;
    stockOffline = false;
    provider = build();
  });

  tearDown(() => provider.dispose());

  test("loads today's doses with 0 of 2 progress", () async {
    await start(provider);

    expect(provider.isLoading, isFalse);
    expect(provider.todayDoses.map((d) => d.id), [
      'm1_20261113_0800',
      'm1_20261113_2000',
    ]);
    expect(provider.progress.taken, 0);
    expect(provider.progress.total, 2);
  });

  test('no medications shows 0 of 0 without dividing by zero', () async {
    provider.updateSession(patientId: 'patient-1', medications: const []);
    await pumpEventQueue();
    expect(provider.progress.total, 0);
    expect(provider.progress.fraction, 0);
  });

  group('confirm', () {
    test(
      'Taken updates the dose, progress and stock once (P1-T01, T16)',
      () async {
        await start(provider);
        clock = DateTime(2026, 11, 13, 8, 4);

        final result = await provider.confirm(provider.todayDoses.first);

        expect(result!.record.status, DoseStatus.taken);
        expect(result.record.confirmedAt, DateTime(2026, 11, 13, 8, 4));
        expect(result.progress.taken, 1); // 04b shows the UPDATED progress
        expect(await result.stockWarning, isNull);
        expect(provider.todayDoses.first.status, DoseStatus.taken);
        expect(provider.progress.percent, 50);
        expect(stockCalls, ['m1_20261113_0800']);
      },
    );

    test('a double tap while saving is ignored (P1-T02)', () async {
      await start(provider);
      final dose = provider.todayDoses.first;
      store.holdWrites = Completer<void>();

      final first = provider.confirm(dose);
      expect(provider.isPending(dose.id), isTrue); // button shows a spinner
      final second = await provider.confirm(dose);
      expect(second, isNull);

      store.holdWrites!.complete();
      expect(await first, isNotNull);
      expect(store.writes, 1);
      expect(provider.isPending(dose.id), isFalse);
    });

    test('another dose cannot be confirmed while one is saving', () async {
      await start(provider);
      store.holdWrites = Completer<void>();

      final first = provider.confirm(provider.todayDoses.first);
      expect(provider.isConfirming, isTrue); // all Taken buttons disabled
      expect(await provider.confirm(provider.todayDoses.last), isNull);

      store.holdWrites!.complete();
      await first;
      expect(provider.isConfirming, isFalse);
      expect(store.writes, 1);
    });

    test('a failed save keeps the dose unconfirmed (P1-T03)', () async {
      await start(provider);
      store.failWrites = true;

      final result = await provider.confirm(provider.todayDoses.first);

      expect(result, isNull);
      expect(provider.confirmError, contains('Could not save'));
      expect(provider.todayDoses.first.status, DoseStatus.scheduled);
      expect(stockCalls, isEmpty); // no stock change without a saved dose
    });

    test('empty stock gives a warning but the dose stays taken', () async {
      await start(provider);
      stockResult = ConsumptionStatus.insufficientStock;

      final result = await provider.confirm(provider.todayDoses.first);

      expect(result!.record.status, DoseStatus.taken);
      expect(await result.stockWarning, contains('supply looks empty'));
    });

    test('stock is retried later with the same dose ID when offline', () async {
      await start(provider);
      stockOffline = true;
      final result = await provider.confirm(provider.todayDoses.first);
      expect(
        await result!.stockWarning,
        contains('when the connection returns'),
      );

      stockOffline = false;
      await provider.evaluateStatuses();
      expect(stockCalls, ['m1_20261113_0800', 'm1_20261113_0800']);

      await provider.evaluateStatuses(); // nothing left to retry
      expect(stockCalls, hasLength(2));
    });
  });

  group('evaluateStatuses', () {
    test(
      'saves overdue, then missed; taken stays taken (P1-T10, T12)',
      () async {
        await start(provider);
        final morning = provider.todayDoses.first;

        clock = DateTime(2026, 11, 13, 8, 30);
        await provider.evaluateStatuses();
        await pumpEventQueue();
        expect(provider.todayDoses.first.status, DoseStatus.overdue);
        expect(provider.needsReview.map((d) => d.id), [morning.id]);

        clock = DateTime(2026, 11, 13, 12);
        await provider.evaluateStatuses();
        await pumpEventQueue();
        expect(store.record(morning.id)!.status, DoseStatus.missed);
        // Missed is final, so it no longer asks for review.
        expect(provider.needsReview, isEmpty);

        // Evening dose taken, then checked long after: still taken.
        await provider.confirm(provider.todayDoses.last);
        clock = DateTime(2026, 11, 13, 23, 59);
        await provider.evaluateStatuses();
        expect(store.record('m1_20261113_2000')!.status, DoseStatus.taken);
      },
    );

    test('a late dose shows its real status at once, before saving', () async {
      await start(provider);
      clock = DateTime(2026, 11, 13, 13);
      // A medication is added: its 08:00 dose is already 5 hours late.
      provider.updateSession(
        patientId: 'patient-1',
        medications: [
          med('m1', ['08:00', '20:00']),
          med('m2', ['12:00']),
        ],
      );
      // No await: what the screen shows immediately.
      final shown = {for (final d in provider.todayDoses) d.id: d.status};
      expect(shown['m1_20261113_0800'], DoseStatus.missed);
      expect(shown['m2_20261113_1200'], DoseStatus.overdue);
      expect(shown['m1_20261113_2000'], DoseStatus.scheduled);

      await pumpEventQueue(); // the save check runs right away too
      expect(store.record('m1_20261113_0800')!.status, DoseStatus.missed);
    });

    test('a dose that is missed now cannot be confirmed', () async {
      await start(provider);
      final morning = provider.todayDoses.first; // copy shows "scheduled"
      clock = DateTime(2026, 11, 13, 13);

      expect(await provider.confirm(morning), isNull);
      expect(provider.confirmError, contains('missed'));
      expect(store.record(morning.id)?.status, isNot(DoseStatus.taken));
    });

    test('running it twice writes nothing more (P1-T11)', () async {
      await start(provider);
      clock = DateTime(2026, 11, 13, 8, 30);
      await provider.evaluateStatuses();
      await pumpEventQueue();
      final writes = store.writes;

      await provider.evaluateStatuses();
      await pumpEventQueue();
      expect(store.writes, writes);
    });
  });

  group('history', () {
    setUp(() {
      store.seed(
        saved('m1_20261113_0600', DateTime(2026, 11, 13, 6), DoseStatus.taken),
      ); // today
      store.seed(
        saved('m1_20261109_0800', DateTime(2026, 11, 9, 8), DoseStatus.missed),
      ); // 4 days ago
      store.seed(
        saved('m1_20261101_0800', DateTime(2026, 11, 1, 8), DoseStatus.taken),
      ); // 12 days ago
      store.seed(
        saved('m1_20261001_0800', DateTime(2026, 10, 1, 8), DoseStatus.taken),
      ); // 43 days ago: outside both
    });

    test('Week and Month filter in place, newest first (P1-T04)', () async {
      await start(provider);

      expect(provider.history(HistoryPeriod.week).map((d) => d.id), [
        'm1_20261113_0600',
        'm1_20261109_0800',
      ]);
      expect(provider.history(HistoryPeriod.month).map((d) => d.id), [
        'm1_20261113_0600',
        'm1_20261109_0800',
        'm1_20261101_0800',
      ]);
    });

    test('a reloaded app shows the same saved records (P1-T14)', () async {
      await start(provider);
      final reopened = build();
      addTearDown(reopened.dispose);
      await start(reopened);

      expect(reopened.history(HistoryPeriod.month).length, 3);
    });
  });

  test('a patient with no records has empty history (P1-T05)', () async {
    await start(provider);
    expect(provider.history(HistoryPeriod.month), isEmpty);
  });

  test('switching account drops the previous patient data (P1-T15)', () async {
    store.seed(
      saved('m1_20261113_0600', DateTime(2026, 11, 13, 6), DoseStatus.taken),
    );
    await start(provider);
    expect(provider.history(HistoryPeriod.week), isNotEmpty);

    signedIn = 'patient-2';
    provider.updateSession(
      patientId: 'patient-2',
      medications: [
        med('p2med', ['09:00'], patientId: 'patient-2'),
      ],
    );
    // Cleared at once, before any new data arrives.
    expect(provider.history(HistoryPeriod.week), isEmpty);
    await pumpEventQueue();

    expect(provider.history(HistoryPeriod.week), isEmpty);
    expect(
      provider.todayDoses.every((d) => d.patientId == 'patient-2'),
      isTrue,
    );
  });

  test('a load error can be retried', () async {
    store.failReads = true;
    await start(provider);
    expect(provider.errorMessage, isNotNull);

    store.failReads = false;
    provider.retry();
    await pumpEventQueue();
    expect(provider.errorMessage, isNull);
    expect(provider.todayDoses, hasLength(2));
  });

  test('progress can count only due doses (policy flag)', () async {
    provider.dispose();
    provider = build(policy: const DosePolicy(countFutureDosesInToday: false));
    await start(provider);
    clock = DateTime(2026, 11, 13, 9); // 08:00 due, 20:00 not yet

    expect(provider.progress.total, 1);
  });
}
