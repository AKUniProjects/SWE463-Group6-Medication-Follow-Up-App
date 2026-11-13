// Feature #6 follow-up reminders, without widgets:
// - DoseProvider decides which doses get a follow-up (fake gateway).
// - NotificationService schedules/cancels them once (fake Android plugin).
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/dose_record.dart';
import 'package:medication_follow_up_app/models/medication.dart';
import 'package:medication_follow_up_app/services/dose_follow_ups.dart';
import 'package:medication_follow_up_app/services/dose_repository.dart';
import 'package:medication_follow_up_app/services/notification_service.dart';
import 'package:medication_follow_up_app/state/dose_provider.dart';

import 'support/fake_notification_plugin.dart';
import 'support/memory_dose_store.dart';

Medication med(String id, List<String> times) => Medication(
  id: id,
  patientId: 'patient-1',
  name: 'Medicine $id',
  doseAmount: 1,
  doseUnit: 'tablet',
  scheduledTimes: times,
  stockAmount: 30,
  refillThreshold: 7,
);

DoseRecord dose(String id, DateTime time, {String medicationId = 'm1'}) =>
    DoseRecord(
      id: id,
      medicationId: medicationId,
      patientId: 'patient-1',
      medicationName: 'Medicine $medicationId',
      scheduledTime: time,
      status: DoseStatus.scheduled,
    );

/// Records what the provider asks for, instead of talking to Android.
class RecordingFollowUps implements DoseFollowUpGateway {
  final syncs = <List<FollowUp>>[];
  final cancelled = <String>[];
  bool fail = false;

  @override
  Future<void> syncFollowUps(String patientId, List<FollowUp> followUps) async {
    if (fail) throw StateError('plugin crashed');
    syncs.add(followUps);
  }

  @override
  Future<void> cancelFollowUp(DoseRecord dose) async => cancelled.add(dose.id);
}

void main() {
  group('DoseProvider follow-ups', () {
    late MemoryDoseStore store;
    late DateTime clock;
    late RecordingFollowUps gateway;
    late DoseProvider provider;

    setUp(() {
      store = MemoryDoseStore();
      clock = DateTime(2026, 11, 13, 7); // 07:00, before both doses
      gateway = RecordingFollowUps();
      provider = DoseProvider(
        StoredDoseRepository(store, currentPatientId: () => 'patient-1'),
        now: () => clock,
        tickInterval: null,
        followUps: gateway,
      );
    });

    tearDown(() => provider.dispose());

    /// patient-1 with m1 at 08:00 and 20:00; waits for the first load.
    Future<void> start() async {
      provider.updateSession(
        patientId: 'patient-1',
        medications: [
          med('m1', ['08:00', '20:00']),
        ],
      );
      await pumpEventQueue();
    }

    test('schedules one follow-up per unconfirmed dose, at +30 min', () async {
      await start();

      // Today's 08:00 and 20:00, plus tomorrow's two (app may stay closed).
      final last = gateway.syncs.last;
      expect(
        [for (final f in last) f.at],
        [
          DateTime(2026, 11, 13, 8, 30),
          DateTime(2026, 11, 13, 20, 30),
          DateTime(2026, 11, 14, 8, 30),
          DateTime(2026, 11, 14, 20, 30),
        ],
      );
    });

    test('repeated evaluations do not sync again (no duplicates)', () async {
      await start();
      final before = gateway.syncs.length;

      await provider.evaluateStatuses();
      await provider.evaluateStatuses();
      await pumpEventQueue();

      expect(gateway.syncs.length, before);
    });

    test('confirming a dose cancels its follow-up', () async {
      await start();
      clock = DateTime(2026, 11, 13, 8, 5);

      final first = provider.todayDoses.first;
      await provider.confirm(first);
      await pumpEventQueue();

      expect(gateway.cancelled, [first.id]);
      // The next sync no longer asks for it.
      expect(
        gateway.syncs.last.map((f) => f.dose.id),
        isNot(contains(first.id)),
      );
    });

    test(
      'an unconfirmed dose shows in needsFollowUp: overdue, then missed',
      () async {
        await start();
        expect(provider.needsFollowUp, isEmpty); // 07:00: nothing late

        // 08:40: the 08:00 dose is overdue (+30 min).
        clock = DateTime(2026, 11, 13, 8, 40);
        await provider.evaluateStatuses();
        await pumpEventQueue();
        expect(provider.needsFollowUp.single.status, DoseStatus.overdue);

        // 12:10: past +4 h, so it is missed (saved once, still listed).
        clock = DateTime(2026, 11, 13, 12, 10);
        await provider.evaluateStatuses();
        await provider.evaluateStatuses();
        await pumpEventQueue();
        expect(provider.needsFollowUp.single.status, DoseStatus.missed);
        expect(
          provider.history(HistoryPeriod.week).single.status,
          DoseStatus.missed,
        );
      },
    );

    test('a taken dose is never listed for follow-up later', () async {
      await start();
      clock = DateTime(2026, 11, 13, 8, 5);
      await provider.confirm(provider.todayDoses.first); // 08:00 taken
      await pumpEventQueue();

      clock = DateTime(2026, 11, 13, 13); // past the missed threshold
      await provider.evaluateStatuses();
      await pumpEventQueue();

      expect(provider.todayDoses.first.status, DoseStatus.taken);
      expect(provider.needsFollowUp, isEmpty);
    });

    test('a failing gateway never blocks dose tracking', () async {
      gateway.fail = true;
      await start();
      clock = DateTime(2026, 11, 13, 8, 5);

      final result = await provider.confirm(provider.todayDoses.first);

      expect(provider.errorMessage, isNull);
      expect(result?.record.status, DoseStatus.taken);
    });
  });

  group('NotificationService follow-ups (fake Android)', () {
    late FakeNotificationPlugin plugin;
    late NotificationService service;
    final at0830 = DateTime(2026, 11, 13, 8, 30);
    final dose0800 = dose('m1_20261113_0800', DateTime(2026, 11, 13, 8));
    final dose2000 = dose('m1_20261113_2000', DateTime(2026, 11, 13, 20));

    setUp(() {
      plugin = FakeNotificationPlugin();
      service = NotificationService(plugin, supported: true);
    });

    tearDown(() => service.dispose());

    Iterable<FakeScheduled> followUps() => plugin.scheduled.values.where(
      (r) => r.decoded.kind == ReminderKind.followUp,
    );

    test(
      'schedules a one-time follow-up with the dose in the payload',
      () async {
        await service.syncFollowUps('patient-1', [FollowUp(dose0800, at0830)]);

        final reminder = followUps().single;
        expect(reminder.at, at0830);
        expect(reminder.title, 'Missed dose follow-up');
        expect(reminder.body, contains('Medicine m1 (08:00)'));
        expect(reminder.decoded.doseId, 'm1_20261113_0800');
      },
    );

    test('syncing the same list again schedules nothing new', () async {
      final list = [FollowUp(dose0800, at0830)];
      await service.syncFollowUps('patient-1', list);
      await service.syncFollowUps('patient-1', list);

      expect(plugin.scheduleOnceCalls, 1);
      expect(followUps(), hasLength(1));
    });

    test('a dose left out of the list is cancelled; daily ones stay', () async {
      await service.syncSchedule(med('m1', ['08:00']));
      await service.syncFollowUps('patient-1', [
        FollowUp(dose0800, at0830),
        FollowUp(dose2000, DateTime(2026, 11, 13, 20, 30)),
      ]);

      await service.syncFollowUps('patient-1', [
        FollowUp(dose2000, DateTime(2026, 11, 13, 20, 30)),
      ]);

      expect(followUps().single.decoded.doseId, dose2000.id);
      expect(
        plugin.scheduled.values.where(
          (r) => r.decoded.kind == ReminderKind.dose,
        ),
        hasLength(1),
      );
    });

    test('cancelFollowUp removes it (confirmed dose)', () async {
      await service.syncFollowUps('patient-1', [FollowUp(dose0800, at0830)]);

      await service.cancelFollowUp(dose0800);

      expect(followUps(), isEmpty);
    });

    test('deleting a medication also cancels its follow-ups', () async {
      await service.syncFollowUps('patient-1', [FollowUp(dose0800, at0830)]);

      await service.cancelMedication('patient-1', 'm1');

      expect(followUps(), isEmpty);
    });

    test('does nothing where notifications are unsupported', () async {
      final web = NotificationService(plugin, supported: false);
      addTearDown(web.dispose);

      await web.syncFollowUps('patient-1', [FollowUp(dose0800, at0830)]);

      expect(plugin.scheduled, isEmpty);
    });
  });
}
