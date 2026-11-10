import 'dart:async';

import 'package:medication_follow_up_app/models/user_profile.dart';
import 'package:medication_follow_up_app/services/auth_repository.dart';

const patient = UserProfile(
  id: 'patient-1',
  displayName: 'Pat',
  email: 'pat@example.com',
  role: UserRole.patient,
);

const doctor = UserProfile(
  id: 'doctor-1',
  displayName: 'Dr. Lee',
  email: 'lee@example.com',
  role: UserRole.doctor,
);

/// Fake repository whose auth events and async results are test-controlled.
class ControllableAuthRepository implements AuthRepository {
  final _controller = StreamController<String?>.broadcast(sync: true);

  /// Profiles stored "in Firestore", keyed by uid.
  final Map<String, UserProfile> profiles = {};
  String? currentUid;
  Object? profileLoadError;

  Completer<UserProfile>? pendingAction;

  void emit(String? uid) {
    currentUid = uid;
    _controller.add(uid);
  }

  void emitError() => _controller.addError(Exception('stream failure'));

  @override
  Stream<String?> get authStateChanges => _controller.stream;

  @override
  Future<UserProfile?> getCurrentUserProfile() async {
    if (profileLoadError != null) throw profileLoadError!;
    return currentUid == null ? null : profiles[currentUid];
  }

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) {
    signInCalls++;
    lastSignInEmail = email;
    pendingAction = Completer<UserProfile>();
    return pendingAction!.future;
  }

  int signInCalls = 0;
  String? lastSignInEmail;

  @override
  Future<UserProfile> signUp({
    required String displayName,
    required String email,
    required String password,
    required UserRole role,
  }) {
    pendingAction = Completer<UserProfile>();
    return pendingAction!.future;
  }

  @override
  Future<void> signOut() async => emit(null);

  Future<void> close() => _controller.close();
}
