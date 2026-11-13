// Feature #6 in the real app wiring (fakes for Firebase and the plugin):
// late dose -> banner / bell / notification tap -> Missed Follow-up page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/screens/missed_dose_screen.dart';
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

  /// Signs in the fictional patient at 08:40 with a medication at 08:00
  /// and 20:00, so the 08:00 dose is overdue (+30 min) and not confirmed.
  Future<void> openToday(WidgetTester tester) async {
    final authRepo = ControllableAuthRepository()
      ..profiles[patient.id] = patient;
    final auth = AuthProvider(authRepo)..start();
    final medicationStore = MemoryMedicationStore();
    plugin = FakeNotificationPlugin();
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
        doseClock: () => DateTime(2026, 11, 13, 8, 40),
        notifications: NotificationService(plugin, supported: true),
      ),
    );
    authRepo.emit(patient.id);
    await tester.pumpAndSettle();
    await medications.create(medicationDraft());
    await tester.pumpAndSettle();
  }

  testWidgets('follow-ups are scheduled only for doses not late yet', (
    tester,
  ) async {
    await openToday(tester);

    final times = [
      for (final r in plugin.scheduled.values)
        if (r.decoded.kind == ReminderKind.followUp) r.at,
    ]..sort();
    // 08:00 is already overdue, so no follow-up is scheduled for it.
    expect(times, [
      DateTime(2026, 11, 13, 20, 30),
      DateTime(2026, 11, 14, 8, 30),
      DateTime(2026, 11, 14, 20, 30),
    ]);
  });

  testWidgets('Today banner opens Missed Follow-up; Review opens History', (
    tester,
  ) async {
    await openToday(tester);

    // The banner is below the dose cards: ListView only builds what is on
    // screen, so scroll Today until it is visible.
    final banner = find.text('1 unconfirmed dose needs your review');
    await tester.scrollUntilVisible(
      banner,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(banner);
    await tester.pumpAndSettle();

    expect(find.byType(MissedDoseScreen), findsOneWidget);
    expect(
      find.text('Fictional vitamin has no recorded confirmation.'),
      findsOneWidget,
    );
    expect(
      find.text('This is a follow-up reminder, not medical advice.'),
      findsOneWidget,
    );
    expect(find.text('Overdue'), findsOneWidget);

    await tester.tap(find.text('Review dose history'));
    await tester.pumpAndSettle();

    expect(find.byType(MissedDoseScreen), findsNothing);
    expect(find.text('Dose history'), findsOneWidget); // History tab
  });

  testWidgets('bell shows a Missed follow-up row; Back to Today works', (
    tester,
  ) async {
    await openToday(tester);

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Missed follow-up'));
    await tester.pumpAndSettle();
    expect(find.byType(MissedDoseScreen), findsOneWidget);

    await tester.tap(find.text('Back to Today'));
    await tester.pumpAndSettle();

    expect(find.byType(MissedDoseScreen), findsNothing);
    expect(find.text("Today's medications"), findsOneWidget);
  });

  testWidgets('tapping a follow-up notification opens the page', (
    tester,
  ) async {
    await openToday(tester);

    plugin.tap(
      const ReminderPayload(
        kind: ReminderKind.followUp,
        patientId: 'patient-1',
        medicationId: 'any',
        time: '08:00',
      ).encode(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MissedDoseScreen), findsOneWidget);

    // The app bar back arrow returns to Today.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(MissedDoseScreen), findsNothing);
    expect(find.text("Today's medications"), findsOneWidget);
  });
}
