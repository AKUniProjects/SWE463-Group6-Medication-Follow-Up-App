import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';
import 'auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  // Listen for Firebase login/logout changes.
  @override
  Stream<String?> get authStateChanges =>
      _auth.authStateChanges().map((user) => user?.uid);

  // Load the authenticated user's profile.
  @override
  Future<UserProfile?> getCurrentUserProfile() async {
    final user = _auth.currentUser;

    if (user == null) return null;

    final document = await _firestore.collection('users').doc(user.uid).get();

    if (!document.exists) return null;

    final data = document.data();
    if (data == null) return null;

    return UserProfile.fromMap(document.id, data);
  }

  // Actual login implementation belongs to Task 3.
  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) {
    throw UnimplementedError('Sign-in is planned for Task 3.');
  }

  // Actual registration implementation belongs to Task 3.
  @override
  Future<UserProfile> signUp({
    required String displayName,
    required String email,
    required String password,
    required UserRole role,
  }) {
    throw UnimplementedError('Sign-up is planned for Task 3.');
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
