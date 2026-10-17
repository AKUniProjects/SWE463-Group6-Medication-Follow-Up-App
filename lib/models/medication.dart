class Medication {
  const Medication({
    required this.id,
    required this.patientId,
    required this.name,
    required this.doseAmount,
    required this.doseUnit,
    required this.scheduledTimes,
    required this.stockAmount,
    required this.refillThreshold,
    this.isActive = true,
  });

  final String id;
  final String patientId;
  final String name;
  final double doseAmount;
  final String doseUnit;
  final List<String> scheduledTimes;
  final int stockAmount;
  final int refillThreshold;
  final bool isActive;
}
