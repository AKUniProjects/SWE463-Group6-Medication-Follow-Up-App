import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/medication.dart';
import 'package:medication_follow_up_app/services/medication_reminders.dart';
import 'package:medication_follow_up_app/services/notification_service.dart';

import 'support/fake_notification_plugin.dart';

/// Feature #3 scheduling rules (guide 5.3), checked against a fake plugin.
void main() {
  Medication med(
    String id, {
    String patientId = 'patient-1',
    String name = 'Metformin',
    List<String> times = const ['08:00'],
    bool active = true,
    int stock = 30,
  }) => Medication(
    id: id,
    patientId: patientId,
    name: name,
    doseAmount: 1,
    doseUnit: 'tablet',
    scheduledTimes: times,
    stockAmount: stock,
    refillThreshold: 5,
    isActive: active,
    stockUnit: 'tablets',
  );

  late FakeNotificationPlugin plugin;
  late NotificationService service;

  setUp(() {
    plugin = FakeNotificationPlugin();
    service = NotificationService(plugin, supported: true);
  });

  List<FakeScheduled> doseReminders() => [
    for (final r in plugin.scheduled.values)
      if (r.decoded.kind == ReminderKind.dose) r,
  ];

  test('one medication with one time schedules one daily reminder', () async {
    await service.syncSchedule(med('m1'));

    final reminders = doseReminders();
    expect(reminders, hasLength(1));
    expect(reminders.single.hour, 8);
    expect(reminders.single.minute, 0);
    expect(reminders.single.title, 'Time for Metformin');
    expect(reminders.single.body, contains('1 tablet at 08:00'));
    expect(service.scheduledCount, 1);
  });

  test('multiple times get one reminder each, with unique IDs', () async {
    await service.syncSchedule(med('m1', times: ['08:00', '14:00', '20:00']));

    expect(doseReminders().map((r) => r.hour), unorderedEquals([8, 14, 20]));
    expect(plugin.scheduled.keys.toSet(), hasLength(3));
  });

  test('two medications at the same time are both kept', () async {
    await service.syncSchedule(med('m1'));
    await service.syncSchedule(med('m2', name: 'Vitamin D'));

    expect(
      doseReminders().map((r) => r.title),
      unorderedEquals(['Time for Metformin', 'Time for Vitamin D']),
    );
  });

  test(
    'editing a time removes the old reminder and adds the new one',
    () async {
      await service.syncSchedule(med('m1', times: ['08:00']));
      await service.syncSchedule(med('m1', times: ['09:30']));

      final reminders = doseReminders();
      expect(reminders, hasLength(1));
      expect((reminders.single.hour, reminders.single.minute), (9, 30));
    },
  );

  test('restarting the app does not duplicate reminders', () async {
    await service.syncSchedule(med('m1', times: ['08:00', '20:00']));
    final idsBefore = plugin.scheduled.keys.toSet();

    // A new service on the same "phone" = the app was reopened.
    final reopened = NotificationService(plugin, supported: true);
    await reopened.syncSchedule(med('m1', times: ['08:00', '20:00']));

    expect(plugin.scheduled.keys.toSet(), idsBefore);
  });

  test(
    'disabling or deleting a medication cancels only its reminders',
    () async {
      // The coordinator is Person 2's class that MedicationProvider uses.
      final coordinator = MedicationReminderCoordinator(service);
      await coordinator.reconcile(med('m1'));
      await coordinator.reconcile(med('m2'));

      await coordinator.reconcile(med('m1', active: false));

      expect(doseReminders().map((r) => r.decoded.medicationId), ['m2']);
    },
  );

  test('low stock schedules a refill reminder, refilled cancels it', () async {
    final coordinator = MedicationReminderCoordinator(service);
    await coordinator.reconcile(med('m1', stock: 3));

    final refill = plugin.scheduled.values
        .where((r) => r.decoded.kind == ReminderKind.refill)
        .single;
    expect(refill.body, contains('3 tablets remaining'));
    expect(refill.hour, 9);

    await coordinator.reconcile(med('m1', stock: 30));
    expect(
      plugin.scheduled.values.where(
        (r) => r.decoded.kind == ReminderKind.refill,
      ),
      isEmpty,
    );
  });

  test('sign-out clears that patient\'s reminders', () async {
    await service.syncSchedule(med('m1'));
    await service.clearPatient('patient-1');

    expect(plugin.scheduled, isEmpty);
    expect(service.scheduledCount, 0);
  });

  test(
    'a new patient on the phone removes the previous one\'s reminders',
    () async {
      await service.syncSchedule(med('m1', patientId: 'patient-1'));
      await service.syncSchedule(med('m9', patientId: 'patient-2'));

      expect(plugin.scheduled.values.map((r) => r.decoded.patientId).toSet(), {
        'patient-2',
      });
    },
  );

  test('denied permission still schedules and reports "denied"', () async {
    plugin
      ..enabled = false
      ..grantOnRequest = false;

    await service.requestPermission();
    await service.syncSchedule(med('m1'));

    expect(service.permission, ReminderPermission.denied);
    expect(doseReminders(), hasLength(1)); // shown once the user allows it
  });

  test('granting permission updates the state', () async {
    plugin.enabled = false;
    await service.start();
    expect(service.permission, ReminderPermission.denied);

    await service.requestPermission(); // the fake grants it

    expect(service.permission, ReminderPermission.granted);
  });

  test('uses exact timing only when Android allows it', () async {
    await service.syncSchedule(med('m1'));
    expect(doseReminders().single.exact, isFalse);

    await service.requestExactAlarms();
    await service.syncSchedule(med('m1', times: ['08:00', '20:00']));

    expect(doseReminders().every((r) => r.exact), isTrue);
  });

  test('unsupported platforms never touch the plugin', () async {
    final web = NotificationService(plugin, supported: false);
    await MedicationReminderCoordinator(web).reconcile(med('m1'));

    expect(web.isAvailable, isFalse);
    expect(web.permission, ReminderPermission.unsupported);
    expect(plugin.initializeCalls, 0);
    expect(plugin.scheduled, isEmpty);
  });

  test('tapping a notification is reported on the taps stream', () async {
    await service.syncSchedule(med('m1'));
    final payload = plugin.scheduled.values.single.payload;

    final tapped = expectLater(
      service.taps,
      emits(isA<ReminderPayload>().having((p) => p.medicationId, 'med', 'm1')),
    );
    plugin.tap(payload);
    await tapped;
  });

  test('notification IDs are stable and positive', () {
    expect(notificationId('dose/p/m/08:00'), notificationId('dose/p/m/08:00'));
    expect(
      notificationId('dose/p/m/08:00'),
      isNot(notificationId('dose/p/m/08:01')),
    );
    expect(notificationId('anything'), greaterThanOrEqualTo(0));
  });
}
