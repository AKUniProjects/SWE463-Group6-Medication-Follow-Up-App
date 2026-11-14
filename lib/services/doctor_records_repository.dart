import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/doctor_link.dart';
import '../models/dose_record.dart';
import '../models/medication.dart';
import 'firestore_dose_store.dart';
import 'firestore_medication_store.dart';

class DoctorRecordsRepository {
  DoctorRecordsRepository({
    required FirebaseFirestore firestore,
    required this.currentDoctorId,
  }) : _firestore = firestore,
       _doseStore = FirestoreDoseStore(firestore),
       _medicationStore = FirestoreMedicationStore(firestore);

  final FirebaseFirestore _firestore;
  final FirestoreDoseStore _doseStore;
  final FirestoreMedicationStore _medicationStore;

  /// Must return the current user's UID only when AuthProvider
  /// confirms that the signed-in user is a doctor.
  final String? Function() currentDoctorId;

  /// Live links belonging to the signed-in doctor.
  ///
  /// Revoked links disappear from the returned list.
  /// The provider will use this to cancel patient subscriptions
  /// and clear records when access is revoked.
  Stream<List<DoctorLink>> watchActiveLinks() {
    final doctorId = _requireDoctor();

    return _firestore
        .collection('doctorLinks')
        .where('doctorId', isEqualTo: doctorId)
        .snapshots()
        .map((snapshot) {
          _checkSession(doctorId);

          final links = snapshot.docs
              .map((document) {
                return DoctorLink.fromMap(document.id, document.data());
              })
              .where((link) {
                return link.doctorId == doctorId && link.isActive;
              })
              .toList();

          links.sort(
            (first, second) => first.patientName.toLowerCase().compareTo(
              second.patientName.toLowerCase(),
            ),
          );

          return List<DoctorLink>.unmodifiable(links);
        });
  }

  /// Live saved dose records for one patient.
  ///
  /// Reuses the team's Firestore store, including Timestamp conversion.
  /// Firestore rules must authorize the doctor's active patient link.
  ///
  /// This does not call the patient-only StoredDoseRepository because
  /// that repository intentionally rejects other patients' IDs.
  Stream<List<DoseRecord>> watchPatientDoses(String patientId) {
    final doctorId = _requireDoctor();
    _validatePatientId(patientId);

    return _doseStore.watchPatient(patientId).map((records) {
      _checkSession(doctorId);

      final patientRecords = records
          .where((record) => record.patientId == patientId)
          .toList();

      patientRecords.sort(
        (first, second) => second.scheduledTime.compareTo(first.scheduledTime),
      );

      return List<DoseRecord>.unmodifiable(patientRecords);
    });
  }

  /// Live medications for one patient.
  ///
  /// Includes inactive medications so historical records can retain
  /// their medication information. The current schedule screen
  /// will display only medications whose isActive value is true.
  Stream<List<Medication>> watchPatientMedications(String patientId) {
    final doctorId = _requireDoctor();
    _validatePatientId(patientId);

    return _medicationStore.watchPatient(patientId).map((medications) {
      _checkSession(doctorId);

      final patientMedications = medications
          .where((medication) => medication.patientId == patientId)
          .toList();

      patientMedications.sort(
        (first, second) =>
            first.name.toLowerCase().compareTo(second.name.toLowerCase()),
      );

      return List<Medication>.unmodifiable(patientMedications);
    });
  }

  String _requireDoctor() {
    final doctorId = currentDoctorId();

    if (doctorId == null || doctorId.isEmpty) {
      throw StateError('Sign in as a doctor to view patient records.');
    }

    return doctorId;
  }

  void _checkSession(String expectedDoctorId) {
    if (currentDoctorId() != expectedDoctorId) {
      throw StateError(
        'Your session changed. Patient records must be reloaded.',
      );
    }
  }

  void _validatePatientId(String patientId) {
    if (patientId.trim().isEmpty) {
      throw ArgumentError.value(
        patientId,
        'patientId',
        'A patient ID is required.',
      );
    }
  }
}
