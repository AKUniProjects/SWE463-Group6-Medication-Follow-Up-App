// Unit tests for overdue/missed rules. Time is passed in as a fixed value,
// so no test waits for real minutes or hours to pass.
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/dose_record.dart';
import 'package:medication_follow_up_app/services/dose_policy.dart';
import 'package:medication_follow_up_app/services/dose_status_service.dart';

/// A fictional dose on 13 Nov 2026 at [hour]:[minute].
DoseRecord dose({
  int hour = 8,
  int minute = 0,
  DoseStatus status = DoseStatus.scheduled,
  String medicationId = 'med-1',
}) => DoseRecord(
  id: '${medicationId}_20261113_${hour}00',
  medicationId: medicationId,
  patientId: 'patient-1',
  medicationName: 'Vitamin D',
  scheduledTime: DateTime(2026, 11, 13, hour, minute),
  status: status,
);

/// The fixed "current time" for a test.
DateTime at(int hour, [int minute = 0]) => DateTime(2026, 11, 13, hour, minute);

void main() {
  const service = DoseStatusService(); // team defaults: 30 min / 4 h

  group('evaluate', () {
    test('stays scheduled before the 30-minute overdue point', () {
      expect(service.evaluate(dose(), at(8, 29)), isNull);
    });

    test('becomes overdue exactly 30 minutes after the scheduled time', () {
      expect(service.evaluate(dose(), at(8, 30)), DoseStatus.overdue);
    });

    test('an overdue dose stays overdue until 4 hours have passed', () {
      expect(
        service.evaluate(dose(status: DoseStatus.overdue), at(11, 59)),
        isNull,
      );
    });

    test('becomes missed 4 hours after the scheduled time', () {
      expect(
        service.evaluate(dose(status: DoseStatus.overdue), at(12)),
        DoseStatus.missed,
      );
      // App opened late: scheduled jumps straight to missed.
      expect(service.evaluate(dose(), at(15)), DoseStatus.missed);
    });

    test('a taken dose is never changed (P1-T12)', () {
      expect(service.evaluate(dose(status: DoseStatus.taken), at(23)), isNull);
    });

    test('a missed dose is final', () {
      expect(service.evaluate(dose(status: DoseStatus.missed), at(23)), isNull);
    });

    test('never moves backwards if the clock goes back', () {
      expect(
        service.evaluate(dose(status: DoseStatus.overdue), at(8, 10)),
        isNull,
      );
    });

    test('becomes missed when the next dose is due before 4 hours', () {
      // Doses at 08:00 and 10:00: at 10:00 the 08:00 dose is missed.
      expect(
        service.evaluate(dose(), at(10), nextDoseTime: at(10)),
        DoseStatus.missed,
      );
    });

    test('the next-dose rule can be switched off in the policy', () {
      const noNextDoseRule = DoseStatusService(
        DosePolicy(missWhenNextDoseDue: false),
      );
      expect(
        noNextDoseRule.evaluate(dose(), at(10), nextDoseTime: at(10)),
        DoseStatus.overdue,
      );
    });

    test('uses custom thresholds from the policy', () {
      const strict = DoseStatusService(
        DosePolicy(
          overdueAfter: Duration(minutes: 10),
          missedAfter: Duration(hours: 1),
        ),
      );
      expect(strict.evaluate(dose(), at(8, 10)), DoseStatus.overdue);
      expect(strict.evaluate(dose(), at(9)), DoseStatus.missed);
    });
  });

  group('changes', () {
    final doses = [
      dose(hour: 8), // will be missed at 13:00 (4 h + next dose rule)
      dose(hour: 12, minute: 0), // will be overdue at 13:00
      dose(hour: 20), // still in the future
      dose(hour: 9, status: DoseStatus.taken, medicationId: 'med-2'),
    ];

    test('returns only the doses that change, already updated', () {
      final changed = service.changes(doses, at(13));
      expect(
        {for (final d in changed) d.scheduledTime.hour: d.status},
        {8: DoseStatus.missed, 12: DoseStatus.overdue},
      );
    });

    test('running it twice changes nothing more (P1-T11)', () {
      final first = service.changes(doses, at(13));
      // Apply the first result, then evaluate again at the same time.
      final updated = [
        for (final d in doses)
          first.firstWhere((c) => c.id == d.id, orElse: () => d),
      ];
      expect(service.changes(updated, at(13)), isEmpty);
    });
  });
}
