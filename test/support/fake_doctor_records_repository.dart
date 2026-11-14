import 'package:medication_follow_up_app/models/doctor_link.dart';
import 'package:medication_follow_up_app/models/dose_record.dart';
import 'package:medication_follow_up_app/models/medication.dart';
import 'package:medication_follow_up_app/services/doctor_link_repository.dart';
import 'package:medication_follow_up_app/services/doctor_records_repository.dart';

/// Adapts existing controllable link fixtures to the new read-only dashboard.
/// No Firebase instance or sample production data is needed in widget tests.
class FakeDoctorRecordsRepository implements DoctorRecordsRepository {
  FakeDoctorRecordsRepository(this.links);
  final DoctorLinkRepository links;

  @override
  String? Function() get currentDoctorId => _doctorId;
  String? _doctorId() => 'doc';

  @override
  Stream<List<DoctorLink>> watchActiveLinks() async* {
    final patients = await links.linkedPatientsForDoctor();
    yield [
      for (final patient in patients)
        DoctorLink(
          id: patient.link.id,
          patientId: patient.patientId,
          doctorId: patient.link.doctorId,
          linkCode: patient.link.linkCode,
          status: patient.link.status,
          patientName: patient.displayName,
          doctorName: patient.link.doctorName,
        ),
    ];
  }

  @override
  Stream<List<DoseRecord>> watchPatientDoses(String patientId) =>
      Stream.value(const []);

  @override
  Stream<List<Medication>> watchPatientMedications(String patientId) =>
      Stream.value(const []);
}
