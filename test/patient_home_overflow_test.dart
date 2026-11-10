// Regression: the dose card's trailing chip + "Taken" button overflowed the
// ListTile by 40px. Overflow errors are NOT suppressed here, so any
// RenderFlex overflow fails these tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/dose_record.dart';
import 'package:medication_follow_up_app/screens/patient_home_screen.dart';
import 'package:medication_follow_up_app/services/sample_data.dart';

DoseRecord dose(DoseStatus status, int hour) => DoseRecord(
      id: 'dose-${status.name}',
      medicationId: 'med-${status.name}',
      patientId: 'patient-001',
      medicationName: 'Medicine ${status.name}',
      scheduledTime: DateTime(2026, 10, 17, hour),
      status: status,
    );

void main() {
  final records = [
    dose(DoseStatus.scheduled, 8),
    dose(DoseStatus.taken, 9),
    dose(DoseStatus.overdue, 10),
    dose(DoseStatus.missed, 11),
  ];

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('no overflow at ${width.toInt()}px, text x$scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 4000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: PatientHomeScreen(
              medications: SampleData.medications,
              doseRecords: records,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        for (final label in ['Scheduled', 'Overdue', 'Missed']) {
          expect(find.text(label), findsWidgets);
        }
        // "Taken" appears as the taken dose's chip and as 3 buttons.
        expect(find.widgetWithText(TextButton, 'Taken'), findsNWidgets(3));
      });
    }
  }

  testWidgets('Taken button still works', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PatientHomeScreen(
          medications: SampleData.medications,
          doseRecords: [dose(DoseStatus.scheduled, 8)],
        ),
      ),
    );
    await tester.tap(find.widgetWithText(TextButton, 'Taken'));
    await tester.pump();
    expect(find.text('Medicine scheduled marked taken'), findsOneWidget);
  });
}
