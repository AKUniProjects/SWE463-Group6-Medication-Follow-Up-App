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

  // Convert UserProfile into Firestore data.
  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'email': email,
      'role': role.name,
      'linkedDoctorIds': linkedDoctorIds,
    };
  }

  // Convert Firestore data into UserProfile.
  factory UserProfile.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    return UserProfile(
      id: id,
      displayName: data['displayName'] as String,
      email: data['email'] as String,
      role: UserRole.values.byName(
        data['role'] as String,
      ),
      linkedDoctorIds: List<String>.from(
        data['linkedDoctorIds'] as List<dynamic>? ?? [],
      ),
    );
  }
}
