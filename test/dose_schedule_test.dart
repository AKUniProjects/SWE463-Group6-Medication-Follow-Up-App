// Unit tests for the pure dose-schedule logic (no Firebase, no widgets).
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/dose_record.dart';
import 'package:medication_follow_up_app/models/medication.dart';
import 'package:medication_follow_up_app/services/dose_policy.dart';
import 'package:medication_follow_up_app/services/dose_schedule.dart';

/// Builds a fictional medication; only the fields these tests need vary.
Medication med(
  String id, {
  String patientId = 'patient-1',
  String name = 'Vitamin D',
  List<String> times = const ['08:00'],
  bool isActive = true,
}) => Medication(
  id: id,
  patientId: patientId,
  name: name,
  doseAmount: 1,
  doseUnit: 'tablet',
  scheduledTimes: times,
  stockAmount: 30,
  refillThreshold: 7,
  isActive: isActive,
);

/// A saved record, as the repository would return it.
DoseRecord saved(
  String id, {
  String patientId = 'patient-1',
  DoseStatus status = DoseStatus.taken,
  DateTime? scheduledTime,
}) => DoseRecord(
  id: id,
  medicationId: 'med-1',
  patientId: patientId,
  medicationName: 'Vitamin D',
  scheduledTime: scheduledTime ?? DateTime(2026, 11, 13, 8),
  status: status,
  confirmedAt: status == DoseStatus.taken ? DateTime(2026, 11, 13, 8, 4) : null,
);

final day = DateTime(2026, 11, 13);

void main() {
  group('DosePolicy', () {
    test('defaults are the team-agreed values', () {
      const policy = DosePolicy();
      expect(policy.overdueAfter, const Duration(minutes: 30));
      expect(policy.missedAfter, const Duration(hours: 4));
      expect(policy.overdueAfter < policy.missedAfter, isTrue);
      expect(policy.missWhenNextDoseDue, isTrue);
      expect(policy.countFutureDosesInToday, isTrue);
      expect(policy.overdueCountsAsMissed, isFalse);
    });
  });

  group('doseIdFor', () {
    test('uses medicationId_yyyyMMdd_HHmm with zero padding', () {
      expect(
        doseIdFor('med-1', DateTime(2026, 3, 5), '08:05'),
        'med-1_20260305_0805',
      );
    });

    test('is stable and accepted by the stock receipt pattern', () {
      final first = doseIdFor('aB3xYz', day, '20:00');
      final second = doseIdFor(
        'aB3xYz',
        DateTime(2026, 11, 13, 23, 59),
        '20:00',
      );
      // The time of day inside [day] is ignored: only the date counts.
      expect(second, first);
      expect(
        RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9_.:-]{0,299}$').hasMatch(first),
        isTrue,
      );
    });
  });

  group('scheduledDosesForDay', () {
    test('creates one scheduled dose per daily time', () {
      final doses = scheduledDosesForDay(
        patientId: 'patient-1',
        medications: [
          med('med-1', times: ['08:00', '20:00']),
        ],
        day: day,
      );

      expect(doses, hasLength(2));
      expect(doses.map((d) => d.id), [
        'med-1_20261113_0800',
        'med-1_20261113_2000',
      ]);
      expect(doses.first.scheduledTime, DateTime(2026, 11, 13, 8));
      expect(doses.last.scheduledTime, DateTime(2026, 11, 13, 20));
      for (final dose in doses) {
        expect(dose.status, DoseStatus.scheduled);
        expect(dose.confirmedAt, isNull);
        expect(dose.medicationName, 'Vitamin D');
        expect(dose.doseAmount, 1);
        expect(dose.doseUnit, 'tablet');
      }
    });

    test('opening Today twice gives the same IDs (no duplicates)', () {
      List<String> ids() => scheduledDosesForDay(
        patientId: 'patient-1',
        medications: [
          med('med-1', times: ['08:00', '20:00']),
        ],
        day: day,
      ).map((d) => d.id).toList();
      expect(ids(), ids());
    });

    test('two medications at the same time are both kept', () {
      final doses = scheduledDosesForDay(
        patientId: 'patient-1',
        medications: [
          med('med-1', name: 'Vitamin D'),
          med('med-2', name: 'Medication B'),
        ],
        day: day,
      );
      expect(doses.map((d) => d.id).toSet(), {
        'med-1_20261113_0800',
        'med-2_20261113_0800',
      });
    });

    test('skips inactive medications and other patients', () {
      final doses = scheduledDosesForDay(
        patientId: 'patient-1',
        medications: [
          med('deleted', isActive: false),
          med('someone-else', patientId: 'patient-2'),
        ],
        day: day,
      );
      expect(doses, isEmpty);
    });

    test('skips a malformed time without crashing', () {
      final doses = scheduledDosesForDay(
        patientId: 'patient-1',
        medications: [
          med('med-1', times: ['8am', '09:30']),
        ],
        day: day,
      );
      expect(doses.map((d) => d.id), ['med-1_20261113_0930']);
    });
  });

  group('mergeWithSaved', () {
    final generated = scheduledDosesForDay(
      patientId: 'patient-1',
      medications: [
        med('med-1', times: ['08:00', '20:00']),
      ],
      day: day,
    );

    test('a saved record replaces the generated dose with the same ID', () {
      final merged = mergeWithSaved(
        patientId: 'patient-1',
        generated: generated,
        saved: [saved('med-1_20261113_0800')],
      );

      expect(merged, hasLength(2)); // replaced, not added
      expect(merged.first.status, DoseStatus.taken);
      expect(merged.first.confirmedAt, DateTime(2026, 11, 13, 8, 4));
      expect(merged.last.status, DoseStatus.scheduled);
    });

    test('keeps saved history whose medication no longer generates doses', () {
      final merged = mergeWithSaved(
        patientId: 'patient-1',
        generated: generated,
        saved: [
          saved(
            'old-med_20261113_0600',
            scheduledTime: DateTime(2026, 11, 13, 6),
          ),
        ],
      );
      expect(merged.map((d) => d.id), [
        'old-med_20261113_0600',
        'med-1_20261113_0800',
        'med-1_20261113_2000',
      ]);
    });

    test("drops another patient's saved records", () {
      final merged = mergeWithSaved(
        patientId: 'patient-1',
        generated: generated,
        saved: [saved('med-1_20261113_0800', patientId: 'patient-2')],
      );
      expect(merged.every((d) => d.patientId == 'patient-1'), isTrue);
      expect(merged.first.status, DoseStatus.scheduled);
    });

    test('sorts by time, then by medication name', () {
      final merged = mergeWithSaved(
        patientId: 'patient-1',
        generated: scheduledDosesForDay(
          patientId: 'patient-1',
          medications: [
            med('m-z', name: 'Zinc', times: ['08:00']),
            med('m-a', name: 'Aspirin', times: ['08:00', '07:00']),
          ],
          day: day,
        ),
        saved: const [],
      );
      expect(merged.map((d) => '${d.medicationName} ${d.scheduledTime.hour}'), [
        'Aspirin 7',
        'Aspirin 8',
        'Zinc 8',
      ]);
    });
  });
}
