import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';
import 'auth_repository.dart';

import 'package:flutter/foundation.dart';

/// Thin wrapper around Firebase Authentication (replaceable in tests).
abstract class AuthGateway {
  Stream<String?> authStateChanges();
  String? get currentUid;

  /// Returns the signed-in UID. Throws [AuthException].
  Future<String> signIn(String email, String password);

  /// Returns the new user's UID. Throws [AuthException].
  Future<String> createUser(String email, String password);

  Future<void> deleteCurrentUser();
  Future<void> signOut();
}

/// Thin wrapper around the Firestore `users` collection.
abstract class ProfileStore {
  Future<Map<String, dynamic>?> read(String uid);
  Future<void> write(String uid, Map<String, dynamic> data);
}

/// Maps a FirebaseAuthException code to a safe [AuthErrorCode].
AuthErrorCode mapFirebaseAuthCode(String code) {
  switch (code) {
    case 'invalid-email':
    case 'missing-email':
    case 'missing-password':
      return AuthErrorCode.invalidInput;
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
    case 'INVALID_LOGIN_CREDENTIALS':
      return AuthErrorCode.invalidCredentials;
    case 'email-already-in-use':
      return AuthErrorCode.emailAlreadyInUse;
    case 'weak-password':
      return AuthErrorCode.weakPassword;
    case 'user-disabled':
      return AuthErrorCode.userDisabled;
    case 'too-many-requests':
      return AuthErrorCode.tooManyRequests;
    case 'network-request-failed':
      return AuthErrorCode.network;
    default:
      return AuthErrorCode.unknown;
  }
}

class FirebaseAuthGateway implements AuthGateway {
  FirebaseAuthGateway(this._auth);

  final FirebaseAuth _auth;

  @override
  Stream<String?> authStateChanges() =>
      _auth.authStateChanges().map((user) => user?.uid);

  @override
  String? get currentUid => _auth.currentUser?.uid;

  @override
  Future<String> signIn(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return _requireUid(result.user);
    } on FirebaseAuthException catch (e) {
      throw AuthException(mapFirebaseAuthCode(e.code));
    }
  }

  @override
  Future<String> createUser(String email, String password) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return _requireUid(result.user);
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint('SIGNUP ERROR CODE: ${e.code}');
        debugPrint('SIGNUP ERROR MESSAGE: ${e.message}');
      }
      throw AuthException(mapFirebaseAuthCode(e.code));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SIGNUP UNEXPECTED ERROR: $e');
      }
      rethrow;
    }
  }

  String _requireUid(User? user) {
    if (user == null) throw const AuthException(AuthErrorCode.unknown);
    return user.uid;
  }

  @override
  Future<void> deleteCurrentUser() async {
    await _auth.currentUser?.delete();
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

class FirestoreProfileStore implements ProfileStore {
  FirestoreProfileStore(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection('users').doc(uid);

  @override
  Future<Map<String, dynamic>?> read(String uid) async {
    final snapshot = await _doc(uid).get();
    return snapshot.exists ? snapshot.data() : null;
  }

  @override
  Future<void> write(String uid, Map<String, dynamic> data) =>
      _doc(uid).set(data);
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    AuthGateway? authGateway,
    ProfileStore? profileStore,
  }) : _auth =
           authGateway ?? FirebaseAuthGateway(auth ?? FirebaseAuth.instance),
       _profiles =
           profileStore ??
           FirestoreProfileStore(firestore ?? FirebaseFirestore.instance);

  final AuthGateway _auth;
  final ProfileStore _profiles;

  @override
  String? get currentUid => _auth.currentUid;

  // Listen for Firebase login/logout changes.
  @override
  Stream<String?> get authStateChanges => _auth.authStateChanges();

  // Load the authenticated user's profile.
  @override
  Future<UserProfile?> getCurrentUserProfile() async {
    final uid = _auth.currentUid;
    if (uid == null) return null;

    final data = await _profiles.read(uid);
    if (data == null) return null;

    return UserProfile.fromMap(uid, data);
  }

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || password.isEmpty) {
      throw const AuthException(AuthErrorCode.invalidInput);
    }

    final uid = await _guard(() => _auth.signIn(trimmedEmail, password));

    UserProfile? profile;
    try {
      final data = await _profiles.read(uid);
      if (data != null) profile = UserProfile.fromMap(uid, data);
    } catch (_) {
      await _safeSignOut(uid);
      throw const AuthException(AuthErrorCode.profileLoadFailed);
    }

    if (profile == null) {
      // Do not leave a session open without a usable profile.
      await _safeSignOut(uid);
      throw const AuthException(AuthErrorCode.profileNotFound);
    }
    return profile;
  }

  @override
  Future<UserProfile> signUp({
    required String displayName,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final trimmedName = displayName.trim();
    final trimmedEmail = email.trim();
    if (trimmedName.isEmpty || trimmedEmail.isEmpty || password.isEmpty) {
      throw const AuthException(AuthErrorCode.invalidInput);
    }

    final uid = await _guard(() => _auth.createUser(trimmedEmail, password));

    // New accounts never start with doctor links; links must be created
    // later through a verified linking flow.
    final profile = UserProfile(
      id: uid,
      displayName: trimmedName,
      email: trimmedEmail,
      role: role,
    );

    try {
      await _profiles.write(uid, profile.toMap());
    } catch (_) {
      // Roll back so a half-created account is never reported as
      // registered. If deletion fails, at least end the session.
      try {
        if (_auth.currentUid == uid) await _auth.deleteCurrentUser();
      } catch (_) {
        await _safeSignOut(uid);
      }
      throw const AuthException(AuthErrorCode.profileCreationFailed);
    }

    return profile;
  }

  @override
  Future<void> signOut() => _auth.signOut();

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(AuthErrorCode.unknown);
    }
  }

  Future<void> _safeSignOut(String expectedUid) async {
    // Cleanup belongs to the failed operation, never a replacement session.
    if (_auth.currentUid != expectedUid) return;
    try {
      await _auth.signOut();
    } catch (_) {
      // Sign-out failure is non-fatal here; the original error is reported.
    }
  }
}
