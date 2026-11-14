enum AdherencePeriod { week, month }

class AdherenceDay {
  const AdherenceDay({
    required this.date,
    required this.scheduledDoses,
    required this.takenDoses,
    required this.missedDoses,
    required this.overdueDoses,
    required this.evaluatedDoses,
  });

  final DateTime date;
  final int scheduledDoses;
  final int takenDoses;
  final int missedDoses;
  final int overdueDoses;
  final int evaluatedDoses;

  bool get hasAdherenceData => evaluatedDoses > 0;

  double get percentage {
    if (!hasAdherenceData) return 0;

    return (takenDoses / evaluatedDoses).clamp(0.0, 1.0).toDouble();
  }
}

class AdherenceStats {
  const AdherenceStats({
    required this.periodLabel,
    required this.scheduledDoses,
    required this.takenDoses,
    required this.missedDoses,
    this.overdueDoses = 0,
    this.pendingDoses = 0,
    this.evaluatedDoses,
    this.days = const [],
  });

  final String periodLabel;

  /// Number of available dose records included in the period.
  /// Missing historical records are not invented.
  final int scheduledDoses;

  final int takenDoses;
  final int missedDoses;
  final int overdueDoses;
  final int pendingDoses;

  /// Doses included in the adherence denominator.
  /// Nullable to preserve compatibility with existing constructor calls.
  final int? evaluatedDoses;

  final List<AdherenceDay> days;

  int get adherenceDenominator => evaluatedDoses ?? scheduledDoses;

  bool get hasRecords => scheduledDoses > 0;

  bool get hasAdherenceData => adherenceDenominator > 0;

  /// Fraction from 0.0 to 1.0 for progress indicators.
  double get percentage {
    if (!hasAdherenceData) return 0;

    return (takenDoses / adherenceDenominator).clamp(0.0, 1.0).toDouble();
  }

  int get percentageRounded => (percentage * 100).round();

  /// An application review flag, not a medical assessment.
  bool get requiresFollowUp => missedDoses > 0 || overdueDoses > 0;
}
