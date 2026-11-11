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
    this.stockUnit = 'unit',
    this.unitsPerDose,
    this.revision = 0,
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

  /// Counted supply units, independent of the prescribed dosage unit.
  final String stockUnit;

  /// Whole stock units consumed per scheduled dose; null means unknown.
  final int? unitsPerDose;
  final int revision;

  bool get isLowStock => stockAmount <= refillThreshold;
  double? get estimatedDays =>
      unitsPerDose == null || unitsPerDose! <= 0 || scheduledTimes.isEmpty
      ? null
      : stockAmount / (unitsPerDose! * scheduledTimes.length);

  Medication copyWith({
    String? id,
    String? patientId,
    String? name,
    double? doseAmount,
    String? doseUnit,
    List<String>? scheduledTimes,
    int? stockAmount,
    int? refillThreshold,
    bool? isActive,
    String? stockUnit,
    int? unitsPerDose,
    bool clearUnitsPerDose = false,
    int? revision,
  }) => Medication(
    id: id ?? this.id,
    patientId: patientId ?? this.patientId,
    name: name ?? this.name,
    doseAmount: doseAmount ?? this.doseAmount,
    doseUnit: doseUnit ?? this.doseUnit,
    scheduledTimes: List.unmodifiable(scheduledTimes ?? this.scheduledTimes),
    stockAmount: stockAmount ?? this.stockAmount,
    refillThreshold: refillThreshold ?? this.refillThreshold,
    isActive: isActive ?? this.isActive,
    stockUnit: stockUnit ?? this.stockUnit,
    unitsPerDose: clearUnitsPerDose ? null : unitsPerDose ?? this.unitsPerDose,
    revision: revision ?? this.revision,
  );

  Map<String, dynamic> toMap() => {
    'patientId': patientId,
    'name': name,
    'doseAmount': doseAmount,
    'doseUnit': doseUnit,
    'scheduledTimes': scheduledTimes,
    'stockAmount': stockAmount,
    'refillThreshold': refillThreshold,
    'isActive': isActive,
    'stockUnit': stockUnit,
    'unitsPerDose': unitsPerDose,
    'revision': revision,
  };

  factory Medication.fromMap(String id, Map<String, dynamic> data) =>
      Medication(
        id: id,
        patientId: data['patientId'] as String,
        name: data['name'] as String,
        doseAmount: (data['doseAmount'] as num).toDouble(),
        doseUnit: data['doseUnit'] as String,
        scheduledTimes: List<String>.unmodifiable(
          data['scheduledTimes'] as List,
        ),
        stockAmount: data['stockAmount'] as int,
        refillThreshold: data['refillThreshold'] as int,
        isActive: data['isActive'] as bool,
        stockUnit: data['stockUnit'] as String? ?? 'unit',
        unitsPerDose: data['unitsPerDose'] as int?,
        revision: data['revision'] as int? ?? 0,
      );
}
