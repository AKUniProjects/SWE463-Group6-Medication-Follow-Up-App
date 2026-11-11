import '../models/medication.dart';
import 'medication_validation.dart';

enum MedicationError {
  signedOut,
  forbidden,
  missing,
  conflict,
  invalid,
  unavailable,
}

class MedicationException implements Exception {
  const MedicationException(this.code);
  final MedicationError code;
  String get message => switch (code) {
    MedicationError.signedOut => 'Sign in as a patient to manage medications.',
    MedicationError.forbidden => 'You cannot change this medication.',
    MedicationError.missing => 'This medication is no longer available.',
    MedicationError.conflict =>
      'This medication changed elsewhere. Reopen it to load the latest values.',
    MedicationError.invalid => 'Check the medication values and try again.',
    MedicationError.unavailable =>
      'Could not access medication data. Check your connection and retry.',
  };
  @override
  String toString() => message;
}

enum ConsumptionStatus {
  consumed,
  alreadyConsumed,
  unknownConsumption,
  insufficientStock,
}

class ConsumptionResult {
  const ConsumptionResult(this.status, this.medication);
  final ConsumptionStatus status;
  final Medication medication;
}

/// Storage transaction: implement once for Firestore, substitute in tests.
abstract class MedicationTransaction {
  Future<Medication?> read();
  Future<bool> hasConsumption(String doseRecordId);
  void write(Medication medication);
  void recordConsumption(String doseRecordId, Medication medication, int units);
}

abstract class MedicationStore {
  String newId();
  Stream<List<Medication>> watchPatient(String patientId);
  Future<T> transaction<T>(
    String medicationId,
    Future<T> Function(MedicationTransaction transaction) action,
  );
}

abstract class MedicationRepository {
  /// Includes inactive metadata for historical displays. Doctor reads are
  /// authorized by active DoctorLink rules, never by a UI-supplied ID alone.
  Stream<List<Medication>> watchPatient(String patientId);
  Future<Medication> create(Medication draft);
  Future<Medication> update(Medication medication);
  Future<Medication> deactivate(Medication medication);
  Future<Medication> updateSupply(Medication medication, int stock);
  Future<ConsumptionResult> consumeStock({
    required String patientId,
    required String medicationId,
    required String doseRecordId,
  });
}

/// Business rules independent of Firebase, exercised using a transactional fake.
class StoredMedicationRepository implements MedicationRepository {
  StoredMedicationRepository(this.store, {required this.currentPatientId});
  final MedicationStore store;

  /// Reads the trusted current patient session, not a value from the form.
  final String? Function() currentPatientId;

  void _requirePatient(String patientId) {
    final current = currentPatientId();
    if (current == null) {
      throw const MedicationException(MedicationError.signedOut);
    }
    if (patientId.isEmpty || current != patientId) {
      throw const MedicationException(MedicationError.forbidden);
    }
  }

  void _validate(Medication medication) {
    try {
      validateMedication(medication);
    } on ArgumentError {
      throw const MedicationException(MedicationError.invalid);
    }
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on MedicationException {
      rethrow;
    } catch (_) {
      throw const MedicationException(MedicationError.unavailable);
    }
  }

  @override
  Stream<List<Medication>> watchPatient(String patientId) =>
      store.watchPatient(patientId);

  @override
  Future<Medication> create(Medication draft) => _guard(() async {
    _requirePatient(draft.patientId);
    draft = draft.copyWith(name: draft.name.trim());
    _validate(draft);
    final medication = draft.copyWith(
      id: store.newId(),
      name: draft.name.trim(),
      isActive: true,
      revision: 1,
      scheduledTimes: [...draft.scheduledTimes]..sort(),
    );
    return store.transaction(medication.id, (tx) async {
      if (await tx.read() != null) {
        throw const MedicationException(MedicationError.conflict);
      }
      _requirePatient(medication.patientId);
      tx.write(medication);
      return medication;
    });
  });

  Future<Medication> _change(
    Medication expected,
    Medication Function(Medication current) change,
  ) => _guard(() async {
    _requirePatient(expected.patientId);
    return store.transaction(expected.id, (tx) async {
      final current = await tx.read();
      _requirePatient(expected.patientId);
      if (current == null || !current.isActive) {
        throw const MedicationException(MedicationError.missing);
      }
      if (current.patientId != expected.patientId) {
        throw const MedicationException(MedicationError.forbidden);
      }
      if (current.revision != expected.revision) {
        throw const MedicationException(MedicationError.conflict);
      }
      final next = change(current).copyWith(revision: current.revision + 1);
      _validate(next);
      tx.write(next);
      return next;
    });
  });

  @override
  Future<Medication> update(Medication medication) => _change(
    medication,
    (current) => medication.copyWith(
      id: current.id,
      patientId: current.patientId,
      isActive: true,
      scheduledTimes: [...medication.scheduledTimes]..sort(),
    ),
  );

  @override
  Future<Medication> deactivate(Medication medication) =>
      _change(medication, (current) => current.copyWith(isActive: false));

  @override
  Future<Medication> updateSupply(Medication medication, int stock) =>
      _change(medication, (current) => current.copyWith(stockAmount: stock));

  @override
  Future<ConsumptionResult> consumeStock({
    required String patientId,
    required String medicationId,
    required String doseRecordId,
  }) => _guard(() async {
    _requirePatient(patientId);
    if (!RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9_.:-]{0,299}$')
        .hasMatch(doseRecordId)) {
      throw const MedicationException(MedicationError.invalid);
    }
    return store.transaction(medicationId, (tx) async {
      final current = await tx.read();
      _requirePatient(patientId);
      if (current == null) {
        throw const MedicationException(MedicationError.missing);
      }
      if (current.patientId != patientId) {
        throw const MedicationException(MedicationError.forbidden);
      }
      // Read the immutable receipt before writing anything. Firestore may
      // retry the whole transaction when concurrent updates occur.
      if (await tx.hasConsumption(doseRecordId)) {
        return ConsumptionResult(ConsumptionStatus.alreadyConsumed, current);
      }
      if (!current.isActive) {
        throw const MedicationException(MedicationError.missing);
      }
      final units = current.unitsPerDose;
      if (units == null) {
        return ConsumptionResult(ConsumptionStatus.unknownConsumption, current);
      }
      if (current.stockAmount < units) {
        return ConsumptionResult(ConsumptionStatus.insufficientStock, current);
      }
      final next = current.copyWith(
        stockAmount: current.stockAmount - units,
        revision: current.revision + 1,
      );
      _validate(next);
      tx.write(next);
      tx.recordConsumption(doseRecordId, next, units);
      return ConsumptionResult(ConsumptionStatus.consumed, next);
    });
  });
}
