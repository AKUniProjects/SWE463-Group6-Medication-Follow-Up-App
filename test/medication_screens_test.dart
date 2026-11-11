import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:medication_follow_up_app/screens/medications_screen.dart';
import 'package:medication_follow_up_app/screens/medication_editor_screen.dart';
import 'package:medication_follow_up_app/screens/medication_delete_screen.dart';
import 'package:medication_follow_up_app/screens/refill_tracking_screen.dart';
import 'package:medication_follow_up_app/services/medication_repository.dart';
import 'package:medication_follow_up_app/state/medication_provider.dart';
import 'package:medication_follow_up_app/theme/app_theme.dart';
import 'package:medication_follow_up_app/widgets/update_supply_dialog.dart';

import 'support/memory_medication_store.dart';

void main() {
  late MemoryMedicationStore store;
  late StoredMedicationRepository repo;
  late MedicationProvider state;
  setUp(() {
    store = MemoryMedicationStore();
    repo = StoredMedicationRepository(
      store,
      currentPatientId: () => 'patient-1',
    );
    state = MedicationProvider(repo);
  });
  tearDown(() async {
    state.dispose();
    await store.close();
  });

  Future<void> pump(
    WidgetTester tester, [
    Widget? home,
    double scale = 1,
  ]) async {
    state.updateSession('patient-1');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: home ?? const MedicationsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> chooseTime(WidgetTester tester, String hour) async {
    await tap(tester, find.text('Add time'));
    await tester.tap(find.byTooltip('Switch to text input mode'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), hour);
    await tester.enterText(fields.at(1), '00');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('medication-name')),
      '  Demo vitamin  ',
    );
    await tester.enterText(find.byKey(const Key('medication-dose')), '1');
    await chooseTime(tester, '8');
    await chooseTime(tester, '9');
    await tester.ensureVisible(find.byKey(const Key('medication-stock')));
    await tester.enterText(find.byKey(const Key('medication-stock')), '8');
    await tester.ensureVisible(find.byKey(const Key('medication-consumption')));
    await tester.enterText(
      find.byKey(const Key('medication-consumption')),
      '1',
    );
  }

  testWidgets(
    'empty list has inline Add; invalid form and Cancel write nothing',
    (tester) async {
      await pump(tester);
      expect(find.textContaining('No medications yet'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      await tap(tester, find.text('Add medication'));
      await tester.enterText(find.byKey(const Key('medication-dose')), '-1');
      await tester.ensureVisible(find.byKey(const Key('medication-stock')));
      await tester.enterText(find.byKey(const Key('medication-stock')), '-2');
      await tap(tester, find.text('Save medication'));
      expect(find.text('Enter a medication name'), findsOneWidget);
      expect(find.textContaining('positive finite dose'), findsOneWidget);
      expect(find.text('Choose at least one daily time'), findsOneWidget);
      expect(find.textContaining('whole number from 0'), findsOneWidget);
      expect(store.documents, isEmpty);
      await tap(tester, find.text('Cancel'));
      expect(find.byType(MedicationEditorScreen), findsNothing);
      expect(store.documents, isEmpty);
    },
  );

  testWidgets(
    'add two picker times, reject duplicate, remove a time, save persists',
    (tester) async {
      await pump(tester);
      await tap(tester, find.text('Add medication'));
      await fill(tester);
      await chooseTime(tester, '8');
      expect(find.text('That daily time is already added'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      await tap(tester, find.byTooltip('Remove 09:00'));
      expect(find.text('09:00'), findsNothing);
      await chooseTime(tester, '9');
      await tap(tester, find.text('Save medication'));
      expect(find.byType(MedicationEditorScreen), findsNothing);
      expect(find.text('Demo vitamin'), findsOneWidget);
      final saved = store.records('patient-1').single;
      expect(saved.scheduledTimes, ['08:00', '09:00']);
      expect(saved.stockAmount, 8);
      expect(saved.unitsPerDose, 1);
      expect(find.text('Medication added'), findsOneWidget);
    },
  );

  testWidgets(
    'edit cancel/save, refill cancel/zero, delete Keep/Confirm use one record',
    (tester) async {
      final original = await repo.create(medicationDraft());
      await pump(tester);
      await tap(tester, find.text(original.name));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('medication-name')))
            .controller!
            .text,
        original.name,
      );
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('20:00'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('medication-name')),
        'Unsaved name',
      );
      await tap(tester, find.text('Cancel'));
      expect(store.records('patient-1').single.name, original.name);
      await tap(tester, find.text(original.name));
      await tester.enterText(
        find.byKey(const Key('medication-name')),
        'Updated vitamin',
      );
      await tap(tester, find.text('Save changes'));
      expect(store.documents, hasLength(1));
      expect(store.records('patient-1').single.id, original.id);
      expect(
        store.records('patient-1').single.scheduledTimes,
        original.scheduledTimes,
      );
      await tap(tester, find.text('Refill tracking'));
      await tap(tester, find.text('Update quantity'));
      await tester.enterText(find.byKey(const Key('supply-quantity')), '-1');
      await tap(tester, find.text('Save quantity'));
      expect(find.byType(UpdateSupplyDialog), findsOneWidget);
      expect(store.records('patient-1').single.stockAmount, 8);
      await tap(tester, find.text('Cancel'));
      await tap(tester, find.text('Update quantity'));
      await tester.enterText(find.byKey(const Key('supply-quantity')), '0');
      await tap(tester, find.text('Save quantity'));
      expect(find.byType(UpdateSupplyDialog), findsNothing);
      expect(store.records('patient-1').single.stockAmount, 0);
      expect(find.text('Out of stock'), findsOneWidget);
      expect(find.text('Refill updated'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('0 tablet remaining'), findsOneWidget);
      await tap(tester, find.text('Updated vitamin'));
      await tap(tester, find.text('Delete medication'));
      expect(find.byType(MedicationDeleteScreen), findsOneWidget);
      await tap(tester, find.text('Keep medication'));
      expect(find.byType(MedicationEditorScreen), findsOneWidget);
      expect(store.records('patient-1').single.isActive, isTrue);
      await tap(tester, find.text('Delete medication'));
      await tap(tester, find.text('Confirm delete'));
      expect(find.byType(MedicationEditorScreen), findsNothing);
      expect(find.byType(MedicationDeleteScreen), findsNothing);
      expect(state.activeMedications, isEmpty);
      expect(store.records('patient-1').single.isActive, isFalse);
      expect(store.records('patient-1').single.id, original.id);
    },
  );

  testWidgets(
    'failed and pending save preserves draft and blocks duplicate taps',
    (tester) async {
      await pump(tester);
      await tap(tester, find.text('Add medication'));
      await fill(tester);
      store.holdWrites = Completer<void>();
      store.failWrites = true;
      final save = find.text('Save medication');
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(store.transactions, 1);
      store.holdWrites!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(MedicationEditorScreen), findsOneWidget);
      expect(
        find.textContaining('Could not access medication data'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('medication-name')))
            .controller!
            .text,
        '  Demo vitamin  ',
      );
      expect(store.documents, isEmpty);
      store.failWrites = false;
      await tap(tester, find.text('Save medication'));
      expect(store.documents, hasLength(1));
    },
  );

  testWidgets('missing record and read failure/retry have recoverable UI', (
    tester,
  ) async {
    await pump(tester, const MedicationEditorScreen(medicationId: 'gone'));
    expect(find.textContaining('no longer available'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.failReads = true;
    state.retry();
    await pump(tester);
    expect(find.text('Retry'), findsOneWidget);
    store.failReads = false;
    await tap(tester, find.text('Retry'));
    expect(find.textContaining('No medications yet'), findsOneWidget);
  });

  for (final screen in ['list', 'editor', 'refill']) {
    testWidgets('$screen fits 320px at double text size', (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await repo.create(
        medicationDraft(
          name: 'Long fictional extended release medication',
          dose: 500,
          doseUnit: 'mg',
          unitsPerDose: null,
        ),
      );
      final home = switch (screen) {
        'editor' => const MedicationEditorScreen(),
        'refill' => const RefillTrackingScreen(),
        _ => const MedicationsScreen(),
      };
      await pump(tester, home, 2);
      if (screen == 'refill') {
        await tester.scrollUntilVisible(
          find.textContaining('Days remaining unavailable'),
          150,
        );
        expect(
          find.textContaining('Days remaining unavailable'),
          findsOneWidget,
        );
      }
      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
