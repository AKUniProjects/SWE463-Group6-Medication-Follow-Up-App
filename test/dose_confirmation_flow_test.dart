// End-to-end widget test of Feature #4 in the real app wiring (fakes for
// Firebase): Today -> Mark as Taken -> 04b Dose Confirmed -> back to Today.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/dose_record.dart';
import 'package:medication_follow_up_app/screens/dose_confirmed_screen.dart';
import 'package:medication_follow_up_app/services/medication_repository.dart';
import 'package:medication_follow_up_app/state/auth_provider.dart';

import 'support/app_providers.dart';
import 'support/controllable_auth_repository.dart';
import 'support/memory_dose_store.dart';
import 'support/memory_medication_store.dart';

final markAsTaken = find.ancestor(
  of: find.text('Mark as Taken'),
  matching: find.byWidgetPredicate((widget) => widget is FilledButton),
);

void main() {
  late ControllableAuthRepository authRepo;
  late AuthProvider auth;
  late MemoryMedicationStore medicationStore;
  late MemoryDoseStore doseStore;

  /// Signs in the fictional patient at 07:00 with one 08:00 medication
  /// (8 tablets, 1 per dose) and shows Today.
  Future<void> openToday(WidgetTester tester) async {
    authRepo = ControllableAuthRepository()..profiles[patient.id] = patient;
    auth = AuthProvider(authRepo)..start();
    medicationStore = MemoryMedicationStore();
    doseStore = MemoryDoseStore();
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
        doseStore: doseStore,
        doseClock: () => DateTime(2026, 11, 13, 7),
      ),
    );
    authRepo.emit(patient.id);
    await tester.pumpAndSettle();
    await medications.create(medicationDraft(times: ['08:00']));
    await tester.pumpAndSettle();
  }

  testWidgets('Taken -> 04b -> Today shows the saved dose (P1-T01, T16)', (
    tester,
  ) async {
    await openToday(tester);
    expect(find.text('0 of 1 doses taken'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);

    await tester.ensureVisible(markAsTaken);
    await tester.tap(markAsTaken);
    await tester.pumpAndSettle();

    // 04b appears only after the save, with the UPDATED progress.
    expect(find.byType(DoseConfirmedScreen), findsOneWidget);
    expect(find.text('Dose recorded!'), findsOneWidget);
    expect(find.text('Fictional vitamin · 1 tablet'), findsOneWidget);
    expect(find.text('1 of 1 doses taken'), findsOneWidget);

    await tester.tap(find.text('Continue to Today'));
    await tester.pumpAndSettle();

    expect(find.byType(DoseConfirmedScreen), findsNothing);
    // We scrolled down to tap the button; scroll back up to the progress.
    await tester.scrollUntilVisible(find.text('1 of 1 doses taken'), -200);
    expect(find.text('1 of 1 doses taken'), findsOneWidget);
    expect(markAsTaken, findsNothing); // taken doses have no button
    final saved = doseStore.documents.keys.single;
    expect(doseStore.record(saved)!.status, DoseStatus.taken);
    // Person 2's stock went from 8 to 7: deducted exactly once.
    expect(medicationStore.records(patient.id).single.stockAmount, 7);
  });

  testWidgets('a failed save shows an error with Retry (P1-T03)', (
    tester,
  ) async {
    await openToday(tester);
    doseStore.failWrites = true;

    await tester.ensureVisible(markAsTaken);
    await tester.tap(markAsTaken);
    await tester.pumpAndSettle();

    expect(find.byType(DoseConfirmedScreen), findsNothing);
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget); // still unconfirmed

    doseStore.failWrites = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Dose recorded!'), findsOneWidget);
  });
}
