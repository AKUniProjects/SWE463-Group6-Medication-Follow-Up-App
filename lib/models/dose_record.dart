/// Status of one scheduled dose. The UI chooses the label and colour
/// (for example `scheduled` is shown as "Upcoming").
enum DoseStatus { scheduled, taken, overdue, missed }

/// One scheduled dose of one medication for one patient.
///
/// [id] is stable: the same medication, local date and time always give the
/// same ID (see `doseIdFor` in services/dose_schedule.dart), so one dose can
/// never be recorded twice.
///
/// [medicationName], [doseAmount] and [doseUnit] are copied from the
/// medication ("snapshot"), so History still shows them after the
/// medication is edited or deleted.
class DoseRecord {
  const DoseRecord({
    required this.id,
    required this.medicationId,
    required this.patientId,
    required this.medicationName,
    required this.scheduledTime,
    required this.status,
    this.confirmedAt,
    this.doseAmount,
    this.doseUnit,
  });

  final String id;
  final String medicationId;
  final String patientId;
  final String medicationName;
  final DateTime scheduledTime;
  final DoseStatus status;

  /// When the patient tapped Taken. Null until the dose is confirmed.
  final DateTime? confirmedAt;

  /// For example 1 and 'tablet'. Null in older demo data.
  final double? doseAmount;
  final String? doseUnit;

  /// A copy with a new [status] and, when taken, a [confirmedAt] time.
  /// Only these two fields ever change for a dose.
  DoseRecord copyWith({DoseStatus? status, DateTime? confirmedAt}) =>
      DoseRecord(
        id: id,
        medicationId: medicationId,
        patientId: patientId,
        medicationName: medicationName,
        scheduledTime: scheduledTime,
        status: status ?? this.status,
        confirmedAt: confirmedAt ?? this.confirmedAt,
        doseAmount: doseAmount,
        doseUnit: doseUnit,
      );

  /// Fields saved in Firestore (`doseRecords/{id}`). The ID is the document
  /// name, so it is not repeated inside. Dates stay `DateTime` here; the
  /// Firestore store converts them to and from Firestore `Timestamp`s.
  Map<String, dynamic> toMap() => {
    'patientId': patientId,
    'medicationId': medicationId,
    'medicationName': medicationName,
    'scheduledTime': scheduledTime,
    'status': status.name,
    'confirmedAt': confirmedAt,
    'doseAmount': doseAmount,
    'doseUnit': doseUnit,
  };

  factory DoseRecord.fromMap(String id, Map<String, dynamic> data) =>
      DoseRecord(
        id: id,
        patientId: data['patientId'] as String,
        medicationId: data['medicationId'] as String,
        medicationName: data['medicationName'] as String,
        scheduledTime: data['scheduledTime'] as DateTime,
        status: DoseStatus.values.byName(data['status'] as String),
        confirmedAt: data['confirmedAt'] as DateTime?,
        doseAmount: (data['doseAmount'] as num?)?.toDouble(),
        doseUnit: data['doseUnit'] as String?,
      );
}
