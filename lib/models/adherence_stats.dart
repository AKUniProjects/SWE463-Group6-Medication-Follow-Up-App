class AdherenceStats {
  const AdherenceStats({
    required this.periodLabel,
    required this.scheduledDoses,
    required this.takenDoses,
    required this.missedDoses,
  });

  final String periodLabel;
  final int scheduledDoses;
  final int takenDoses;
  final int missedDoses;

  double get percentage {
    if (scheduledDoses == 0) return 0;
    return takenDoses / scheduledDoses;
  }
}
