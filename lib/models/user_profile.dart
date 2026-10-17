enum UserRole { patient, doctor }

class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.email,
    required this.role,
    this.linkedDoctorIds = const <String>[],
  });

  final String id;
  final String displayName;
  final String email;
  final UserRole role;
  final List<String> linkedDoctorIds;
}
