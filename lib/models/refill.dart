class Refill {
  const Refill({
    required this.id,
    required this.medicationId,
    required this.currentStock,
    required this.refillThreshold,
    required this.lastUpdated,
  });

  final String id;
  final String medicationId;
  final int currentStock;
  final int refillThreshold;
  final DateTime lastUpdated;

  bool get refillNeeded => currentStock <= refillThreshold;
}
