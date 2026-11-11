import '../models/medication.dart';

const doseUnits = ['tablet', 'capsule', 'mg', 'ml', 'IU'];
const stockUnits = ['tablet', 'capsule', 'ml', 'IU', 'package', 'unit'];
const defaultRefillThreshold = 7;
// Keep integer stock and consumption arithmetic exact on Flutter web as well.
const maxStock = 1000000000;
const maxDailyTimes = 24;

String? validateMedicationName(String? input) {
  final name = input?.trim() ?? '';
  if (name.isEmpty) return 'Enter a medication name';
  if (name.length > 100) return 'Use 100 characters or fewer';
  return null;
}

String? validateDose(String? input) {
  final value = double.tryParse(input?.trim() ?? '');
  return value == null || !value.isFinite || value <= 0 || value > maxStock
      ? 'Enter a positive finite dose, up to 1,000,000,000'
      : null;
}

String? validateStock(String? input) {
  final text = input?.trim() ?? '';
  final value = int.tryParse(text);
  return !RegExp(r'^\d+$').hasMatch(text) ||
          value == null ||
          value < 0 ||
          value > maxStock
      ? 'Enter a whole number from 0 to 1,000,000,000'
      : null;
}

String? validateConsumption(String? input) {
  if (input == null || input.trim().isEmpty) return null;
  if (validateStock(input) != null || int.parse(input.trim()) == 0) {
    return 'Enter a positive whole number, or leave blank';
  }
  return null;
}

String? validateTimes(List<String> times) {
  if (times.isEmpty) return 'Choose at least one daily time';
  if (times.length > maxDailyTimes) return 'Use at most 24 daily times';
  if (times.any((t) => !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(t))) {
    return 'Choose valid daily times';
  }
  if (times.toSet().length != times.length) return 'Daily times must be unique';
  return null;
}

/// Also validate at the repository boundary: forms are not the only callers.
void validateMedication(Medication m) {
  final error =
      validateMedicationName(m.name) ??
      validateDose(m.doseAmount.toString()) ??
      validateStock(m.stockAmount.toString()) ??
      validateStock(m.refillThreshold.toString()) ??
      validateTimes(m.scheduledTimes) ??
      validateConsumption(m.unitsPerDose?.toString());
  if (error != null ||
      !doseUnits.contains(m.doseUnit) ||
      !stockUnits.contains(m.stockUnit) ||
      m.name != m.name.trim()) {
    throw ArgumentError(error ?? 'Invalid medication units or name');
  }
}
