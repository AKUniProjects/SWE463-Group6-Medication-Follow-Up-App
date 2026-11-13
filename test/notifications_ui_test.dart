// Feature #3 in the real app wiring (fakes for Firebase and the plugin):
// bell -> Notifications overlay -> Due Reminder / Permissions -> Today.
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/screens/medication_due_screen.dart';
import 'package:medication_follow_up_app/screens/notification_settings_screen.dart';
import 'package:medication_follow_up_app/services/medication_repository.dart';
import 'package:medication_follow_up_app/services/notification_service.dart';
import 'package:medication_follow_up_app/state/auth_provider.dart';

import 'support/app_providers.dart';
import 'support/controllable_auth_repository.dart';
import 'support/fake_notification_plugin.dart';
import 'support/memory_dose_store.dart';
import 'support/memory_medication_store.dart';

void main() {
  late FakeNotificationPlugin plugin;

  /// Signs in the fictional patient at 08:05 with one 08:00 medication
  /// (so it is due) holding [stock] tablets (7 or less = low stock).
  Future<void> openToday(
    WidgetTester tester, {
    int stock = 3,
    bool allowNotifications = true,
  }) async {
    final authRepo = ControllableAuthRepository()
      ..profiles[patient.id] = patient;
    final auth = AuthProvider(authRepo)..start();
    final medicationStore = MemoryMedicationStore();
    plugin = FakeNotificationPlugin(enabled: allowNotifications)
      ..grantOnRequest = allowNotifications;
    final medications = StoredMedicationRepository(
      medicationStore,
      currentPatientId: () => auth.isPatient ? auth.userId : null,
    );
    addTearDown(() async {
      auth.dispose();
      await authRepo.close();
      await medicationStore.close();
    });

    await tester.pumpWidget(
      appWithProviders(
        auth,
        medications: medications,
        doseStore: MemoryDoseStore(),
        doseClock: () => DateTime(2026, 11, 13, 8, 5),
        notifications: NotificationService(plugin, supported: true),
      ),
    );
    authRepo.emit(patient.id);
    await tester.pumpAndSettle();
    await medications.create(medicationDraft(times: ['08:00'], stock: stock));
    await tester.pumpAndSettle();
  }

  Future<void> openBell(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
  }

  testWidgets('adding a medication schedules its Android reminder', (
    tester,
  ) async {
    await openToday(tester);

    // Through Person 2's MedicationProvider -> coordinator -> our service.
    final dose = plugin.scheduled.values
        .where((r) => r.decoded.kind == ReminderKind.dose)
        .single;
    expect(dose.title, 'Time for Fictional vitamin');
    expect((dose.hour, dose.minute), (8, 0));
  });

  testWidgets('bell shows live reminders: due dose and low stock', (
    tester,
  ) async {
    await openToday(tester);
    expect(find.text('2'), findsOneWidget); // badge: 1 due + 1 low stock

    await openBell(tester);

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Medication due'), findsOneWidget);
    expect(find.text('Fictional vitamin • 8:00 AM'), findsOneWidget);
    expect(find.text('Refill reminder'), findsOneWidget);
    expect(find.text('Fictional vitamin • 3 tablet remaining'), findsOneWidget);
    expect(find.text('Notification settings'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Medication due'), findsNothing);
  });

  testWidgets('no fake rows when nothing is due or low', (tester) async {
    await openToday(tester, stock: 30);
    // Mark the due dose as taken so nothing is due any more.
    await tester.ensureVisible(find.text('Mark as Taken'));
    await tester.tap(find.text('Mark as Taken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to Today'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byTooltip('Notifications'), -200);
    await openBell(tester);

    expect(find.text('No reminders right now.'), findsOneWidget);
    expect(find.text('Medication due'), findsNothing);
  });

  testWidgets('Medication due -> Due Reminder -> Open today', (tester) async {
    await openToday(tester);
    await openBell(tester);

    await tester.tap(find.text('Medication due'));
    await tester.pumpAndSettle();

    expect(find.byType(MedicationDueScreen), findsOneWidget);
    expect(find.text('Due Reminder'), findsOneWidget);
    expect(find.text('1 tablet • 8:00 AM'), findsOneWidget);

    await tester.tap(find.text('Open today'));
    await tester.pumpAndSettle();

    expect(find.byType(MedicationDueScreen), findsNothing);
    expect(find.text('Hello, ${patient.displayName}'), findsOneWidget);
  });

  testWidgets('denied permission: explained, and tracking still works', (
    tester,
  ) async {
    await openToday(tester, allowNotifications: false);
    await openBell(tester);

    await tester.tap(find.text('Notification settings'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationSettingsScreen), findsOneWidget);
    expect(
      find.text('Notifications disabled in Android settings.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Continue without notifications'));
    await tester.pumpAndSettle();

    // Back on Today, and doses can still be confirmed.
    expect(find.byType(NotificationSettingsScreen), findsNothing);
    expect(find.text('Mark as Taken'), findsOneWidget);
  });

  testWidgets('granted permission shows what is scheduled', (tester) async {
    await openToday(tester);
    await openBell(tester);
    await tester.tap(find.text('Notification settings'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications are on.'), findsOneWidget);
    // 1 daily dose reminder + 1 refill reminder + 2 follow-ups (#6) for
    // the 08:00 dose today and tomorrow (each at 08:30).
    expect(find.textContaining('4 reminders are scheduled'), findsOneWidget);
    expect(find.text('Allow exact timing'), findsOneWidget);
  });

  testWidgets('tapping a notification opens Today', (tester) async {
    await openToday(tester);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    plugin.tap(
      plugin.scheduled.values
          .firstWhere((r) => r.decoded.kind == ReminderKind.dose)
          .payload,
    );
    await tester.pumpAndSettle();

    expect(find.text('Hello, ${patient.displayName}'), findsOneWidget);
  });
}
