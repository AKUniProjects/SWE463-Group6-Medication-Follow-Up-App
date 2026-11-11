import '../models/medication.dart';

class RefillAlert {
  const RefillAlert(this.medication);
  final Medication medication;
  String get patientId => medication.patientId;
  String get medicationId => medication.id;
}

/// Person 1 implements Android delivery and supplies this adapter at startup.
/// Calls must be idempotent upserts/cancellations keyed by patient + medication.
abstract class MedicationReminderGateway {
  bool get isAvailable;
  Future<void> syncSchedule(Medication medication);
  Future<void> syncRefill(RefillAlert alert);
  Future<void> cancelMedication(String patientId, String medicationId);
  Future<void> cancelRefill(String patientId, String medicationId);
  Future<void> clearPatient(String patientId);
}

/// Explicit unavailable dependency; never claims a notification was delivered.
class UnavailableMedicationReminders implements MedicationReminderGateway {
  @override
  bool get isAvailable => false;
  @override
  Future<void> syncSchedule(Medication medication) async {}
  @override
  Future<void> syncRefill(RefillAlert alert) async {}
  @override
  Future<void> cancelMedication(String patientId, String medicationId) async {}
  @override
  Future<void> cancelRefill(String patientId, String medicationId) async {}
  @override
  Future<void> clearPatient(String patientId) async {}
}

/// Fingerprints are recorded only after a successful adapter call. This runs
/// from shared state changes, never from a widget's build method.
class MedicationReminderCoordinator {
  MedicationReminderCoordinator(this.gateway);
  final MedicationReminderGateway gateway;
  final _schedules = <String, String>{};
  final _refills = <String, String>{};

  Future<void> reconcile(Medication m) async {
    if (!gateway.isAvailable) return;
    final key = '${m.patientId}/${m.id}';
    final schedule =
        '${m.isActive}|${m.name}|${m.doseAmount}|'
        '${m.doseUnit}|${m.scheduledTimes.join(',')}';
    if (_schedules[key] != schedule) {
      if (m.isActive) {
        await gateway.syncSchedule(m);
      } else {
        await gateway.cancelMedication(m.patientId, m.id);
      }
      _schedules[key] = schedule;
    }
    final refill = m.isActive && m.isLowStock
        ? '$schedule|${m.stockAmount}|${m.stockUnit}|'
              '${m.refillThreshold}|${m.unitsPerDose}'
        : 'cancel';
    if (_refills[key] != refill) {
      if (refill == 'cancel') {
        await gateway.cancelRefill(m.patientId, m.id);
      } else {
        await gateway.syncRefill(RefillAlert(m));
      }
      _refills[key] = refill;
    }
  }

  Future<void> clear(String patientId) async {
    _schedules.clear();
    _refills.clear();
    if (gateway.isAvailable) await gateway.clearPatient(patientId);
  }
}
