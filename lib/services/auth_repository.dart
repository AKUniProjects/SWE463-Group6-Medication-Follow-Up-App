import '../models/user_profile.dart';

/// Defines authentication operations for the application.
///
/// Implementations throw [AuthException] on failure.
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

/// Categories of authentication failures exposed to the app.
enum AuthErrorCode {
  invalidInput,
  invalidCredentials,
  emailAlreadyInUse,
  weakPassword,
  userDisabled,
  tooManyRequests,
  network,
  profileNotFound,
  profileLoadFailed,
  profileCreationFailed,
  unknown,
}

/// A predictable, user-safe authentication failure.
///
/// [message] never contains raw exception details, passwords, or tokens.
class AuthException implements Exception {
  const AuthException(this.code);

  final AuthErrorCode code;

  String get message {
    switch (code) {
      case AuthErrorCode.invalidInput:
        return 'Please fill in all required fields correctly.';
      case AuthErrorCode.invalidCredentials:
        return 'Incorrect email or password.';
      case AuthErrorCode.emailAlreadyInUse:
        return 'An account already exists for this email.';
      case AuthErrorCode.weakPassword:
        return 'Password is too weak. Use at least 6 characters.';
      case AuthErrorCode.userDisabled:
        return 'This account has been disabled.';
      case AuthErrorCode.tooManyRequests:
        return 'Too many attempts. Please try again later.';
      case AuthErrorCode.network:
        return 'Network error. Check your connection and try again.';
      case AuthErrorCode.profileNotFound:
        return 'No user profile was found for this account.';
      case AuthErrorCode.profileLoadFailed:
        return 'Could not load your user profile.';
      case AuthErrorCode.profileCreationFailed:
        return 'Registration could not be completed. Please try again.';
      case AuthErrorCode.unknown:
        return 'Something went wrong. Please try again.';
    }
  }

  @override
  String toString() => 'AuthException(${code.name})';
}
