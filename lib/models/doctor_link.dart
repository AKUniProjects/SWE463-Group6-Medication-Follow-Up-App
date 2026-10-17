enum LinkStatus { pending, active, revoked }

class DoctorLink {
  const DoctorLink({
    required this.id,
    required this.patientId,
    required this.doctorId,
    required this.linkCode,
    required this.status,
  });

  final String id;
  final String patientId;
  final String doctorId;
  final String linkCode;
  final LinkStatus status;
}
