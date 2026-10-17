enum DoseStatus { scheduled, taken, overdue, missed }

class DoseRecord {
  const DoseRecord({
    required this.id,
    required this.medicationId,
    required this.patientId,
    required this.medicationName,
    required this.scheduledTime,
    required this.status,
    this.confirmedAt,
  });

  final String id;
  final String medicationId;
  final String patientId;
  final String medicationName;
  final DateTime scheduledTime;
  final DoseStatus status;
  final DateTime? confirmedAt;
}
