import '../models/dose_record.dart';
import '../models/medication.dart';

/// Stable ID for one scheduled dose: `{medicationId}_{yyyyMMdd}_{HHmm}`,
/// for example `abc123_20261113_0800`.
///
/// [day] is the local calendar day and [time] is the medication's "HH:mm"
/// schedule string. The same inputs always give the same ID. The ID is also
/// the stock receipt ID for `MedicationProvider.consumeStock`, so it must
/// match Person 2's pattern `[A-Za-z0-9_-][A-Za-z0-9_.:-]{0,299}`.
String doseIdFor(String medicationId, DateTime day, String time) {
  final date =
      '${day.year.toString().padLeft(4, '0')}'
      '${_twoDigits(day.month)}${_twoDigits(day.day)}';
  return '${medicationId}_${date}_${time.replaceAll(':', '')}';
}

/// The doses [patientId] should take on [day] (a local calendar day), built
/// from the schedules of their active medications.
///
/// Every dose returned is `scheduled`. Saved records (taken, overdue,
/// missed) are combined in afterwards by [mergeWithSaved]. Nothing here
/// reads Firestore or the clock, so the result depends only on the inputs.
List<DoseRecord> scheduledDosesForDay({
  required String patientId,
  required List<Medication> medications,
  required DateTime day,
}) {
  final doses = <DoseRecord>[];
  for (final medication in medications) {
    // Inactive (deleted) medications and other patients' data never
    // produce doses.
    if (!medication.isActive || medication.patientId != patientId) continue;

    for (final time in medication.scheduledTimes) {
      final parts = _parseTime(time);
      if (parts == null) continue; // Person 2 validates; skip bad data safely.

      doses.add(
        DoseRecord(
          id: doseIdFor(medication.id, day, time),
          medicationId: medication.id,
          patientId: patientId,
          medicationName: medication.name,
          scheduledTime: DateTime(
            day.year,
            day.month,
            day.day,
            parts.hour,
            parts.minute,
          ),
          status: DoseStatus.scheduled,
          doseAmount: medication.doseAmount,
          doseUnit: medication.doseUnit,
        ),
      );
    }
  }
  return doses;
}

/// Combines [generated] doses with [saved] records from the same period.
///
/// - A saved record replaces the generated dose with the same ID, for
///   example because it is already taken.
/// - A saved record with no generated match is kept, because it is history
///   (the medication was deleted or its time changed afterwards).
/// - Records that belong to another patient are dropped.
///
/// The result is sorted by scheduled time, then by medication name.
List<DoseRecord> mergeWithSaved({
  required String patientId,
  required List<DoseRecord> generated,
  required List<DoseRecord> saved,
}) {
  final byId = <String, DoseRecord>{
    for (final dose in generated)
      if (dose.patientId == patientId) dose.id: dose,
  };
  for (final record in saved) {
    if (record.patientId == patientId) byId[record.id] = record;
  }

  return byId.values.toList()..sort((a, b) {
    final byTime = a.scheduledTime.compareTo(b.scheduledTime);
    return byTime != 0 ? byTime : a.medicationName.compareTo(b.medicationName);
  });
}

/// Parses "HH:mm" into hour and minute, or returns null if malformed.
({int hour, int minute})? _parseTime(String time) {
  final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(time);
  if (match == null) return null;
  return (hour: int.parse(match.group(1)!), minute: int.parse(match.group(2)!));
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
