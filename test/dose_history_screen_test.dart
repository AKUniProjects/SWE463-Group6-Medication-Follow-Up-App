// Widget tests for 07 Dose History with a real DoseProvider, the in-memory
// store and a fixed clock (Thu 13 Nov 2026, 12:00).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/dose_record.dart';
import 'package:medication_follow_up_app/models/medication.dart';
import 'package:medication_follow_up_app/screens/dose_history_screen.dart';
import 'package:medication_follow_up_app/services/dose_repository.dart';
import 'package:medication_follow_up_app/state/dose_provider.dart';
import 'package:provider/provider.dart';

import 'support/memory_dose_store.dart';

final clock = DateTime(2026, 11, 13, 12);

DoseRecord saved(String id, DateTime scheduled, DoseStatus status) =>
    DoseRecord(
      id: id,
      medicationId: 'm1',
      patientId: 'patient-1',
      medicationName: 'Vitamin D',
      scheduledTime: scheduled,
      status: status,
      confirmedAt: status == DoseStatus.taken
          ? scheduled.add(const Duration(minutes: 4))
          : null,
    );

const morning = Medication(
  id: 'm1',
  patientId: 'patient-1',
  name: 'Vitamin D',
  doseAmount: 1,
  doseUnit: 'tablet',
  scheduledTimes: ['08:00', '20:00'],
  stockAmount: 30,
  refillThreshold: 7,
);

void main() {
  late MemoryDoseStore store;
  late DoseProvider provider;
  late int backTaps;

  /// Shows History for patient-1 with whatever is in [store]. No
  /// medications by default, so nothing becomes missed on its own.
  Future<void> pumpHistory(
    WidgetTester tester, {
    List<Medication> medications = const [],
  }) async {
    provider = DoseProvider(
      StoredDoseRepository(store, currentPatientId: () => 'patient-1'),
      now: () => clock,
      tickInterval: null,
    );
    addTearDown(provider.dispose);
    provider.updateSession(patientId: 'patient-1', medications: medications);
    backTaps = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider<DoseProvider>.value(
        value: provider,
        child: MaterialApp(
          home: DoseHistoryScreen(onBackToToday: () => backTaps++),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Like testWidgets, but creates a fresh store INSIDE the test. (setUp
  /// runs outside testWidgets' fake-time zone, and stream events from an
  /// object created there are not delivered by pump.)
  void historyTest(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      store = MemoryDoseStore();
      await body(tester);
    });
  }

  historyTest('Week groups by day; Month lists the period (P1-T04)', (
    tester,
  ) async {
    store
      ..seed(
        saved('m1_20261113_0800', DateTime(2026, 11, 13, 8), DoseStatus.taken),
      )
      ..seed(
        saved(
          'm1_20261112_2000',
          DateTime(2026, 11, 12, 20),
          DoseStatus.missed,
        ),
      )
      ..seed(
        saved('m1_20261101_0800', DateTime(2026, 11, 1, 8), DoseStatus.taken),
      ); // 12 days ago: Month only
    await pumpHistory(tester);

    // Week: newest first, one card per day.
    expect(find.text("Today's doses"), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('8:04 AM · Confirmed • Taken'), findsOneWidget);
    expect(find.text('8:00 PM · Not confirmed • Missed'), findsOneWidget);
    expect(find.textContaining('Nov 1'), findsNothing);

    // Month: same screen, switched in place.
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(find.text('3 scheduled doses recorded'), findsOneWidget);
    expect(find.text('Nov 1, 8:04 AM • Taken'), findsOneWidget);
    expect(find.byType(DoseHistoryScreen), findsOneWidget); // no new route

    // The bottom button switches back to Week.
    await tester.tap(find.text('View weekly records'));
    await tester.pumpAndSettle();
    expect(find.text("Today's doses"), findsOneWidget);
  });

  historyTest('no records shows the empty state and Back to Today (P1-T05)', (
    tester,
  ) async {
    await pumpHistory(tester);

    expect(find.text('No history yet'), findsOneWidget);
    await tester.tap(find.text('Back to Today'));
    expect(backTaps, 1);
  });

  historyTest('a dose confirmed on Today appears without restarting', (
    tester,
  ) async {
    // At 12:00 the 08:00 dose is already missed; 20:00 is still upcoming.
    await pumpHistory(tester, medications: [morning]);
    expect(find.textContaining('Confirmed • Taken'), findsNothing);

    // Start the save, then pump: in testWidgets, async work only advances
    // while the test pumps (awaiting it directly would wait forever).
    final saving = provider.confirm(provider.todayDoses.last);
    await tester.pumpAndSettle();
    expect(await saving, isNotNull);

    expect(find.text("Today's doses"), findsOneWidget);
    expect(find.textContaining('Confirmed • Taken'), findsOneWidget);
  });

  historyTest('a load error shows Retry, and Retry recovers', (tester) async {
    store.failReads = true;
    await pumpHistory(tester);
    expect(find.text('Retry'), findsOneWidget);

    store
      ..failReads = false
      ..seed(
        saved('m1_20261113_0800', DateTime(2026, 11, 13, 8), DoseStatus.taken),
      );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(find.text("Today's doses"), findsOneWidget);
  });
}
