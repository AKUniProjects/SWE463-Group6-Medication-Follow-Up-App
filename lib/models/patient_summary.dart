import 'adherence_stats.dart';

class PatientSummary {
  const PatientSummary({
    required this.patientId,
    required this.patientName,
    required this.stats,
    required this.missedDoses,
    required this.overdueDoses,
    required this.requiresFollowUp,
  });

  final String patientId;
  final String patientName;
  final AdherenceStats stats;
  final int missedDoses;
  final int overdueDoses;
  final bool requiresFollowUp;
}
