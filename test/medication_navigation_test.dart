import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/screens/medications_screen.dart';
import 'package:medication_follow_up_app/screens/patient_home_screen.dart';
import 'package:medication_follow_up_app/services/medication_repository.dart';
import 'package:medication_follow_up_app/state/auth_provider.dart';
import 'package:medication_follow_up_app/widgets/medication_widgets.dart';

import 'support/app_providers.dart';
import 'support/controllable_auth_repository.dart';
import 'support/memory_medication_store.dart';

void main() {
  testWidgets(
    'Today editor returns to Medications without saving a cancelled draft',
    (tester) async {
      final authRepo = ControllableAuthRepository();
      authRepo.profiles[patient.id] = patient;
      final auth = AuthProvider(authRepo)..start();
      final store = MemoryMedicationStore();
      final repository = StoredMedicationRepository(
        store,
        currentPatientId: () => auth.isPatient ? auth.userId : null,
      );
      addTearDown(() async {
        auth.dispose();
        await authRepo.close();
        await store.close();
      });
      await tester.pumpWidget(appWithProviders(auth, medications: repository));
      authRepo.emit(patient.id);
      await tester.pumpAndSettle();
      await repository.create(medicationDraft());
      await tester.pumpAndSettle();
      // Today also shows the name on its dose card (Person 1), so tap the
      // name inside the Medication plan card.
      final planCard = find.descendant(
        of: find.byType(MedicationCard),
        matching: find.text('Fictional vitamin'),
      );
      await tester.scrollUntilVisible(
        planCard,
        200,
        scrollable: find
            .descendant(
              of: find.byType(PatientHomeScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(planCard);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('medication-name')),
        'Unsaved draft',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(MedicationsScreen), findsOneWidget);
      expect(find.text('My medications'), findsOneWidget);
      expect(store.records(patient.id).single.name, 'Fictional vitamin');
    },
  );
}
