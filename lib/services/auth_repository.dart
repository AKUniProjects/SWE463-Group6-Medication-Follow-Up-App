import '../models/user_profile.dart';

/// Defines authentication operations for the application.
///
/// Firebase implementation will be added in Task 3.
abstract class AuthRepository {
  /// Emits the signed-in user's UID, or null when signed out.
  Stream<String?> get authStateChanges;

  /// Returns the current user's profile, if authenticated.
  Future<UserProfile?> getCurrentUserProfile();

  /// Signs in an existing user.
  Future<UserProfile> signIn({
    required String email,
    required String password,
  });

  /// Registers a new patient or doctor.
  Future<UserProfile> signUp({
    required String displayName,
    required String email,
    required String password,
    required UserRole role,
  });

  /// Signs out the current user.
  Future<void> signOut();
}
