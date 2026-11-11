import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/user_profile.dart';
import 'package:medication_follow_up_app/services/auth_repository.dart';
import 'package:medication_follow_up_app/state/auth_provider.dart';

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<String?>.broadcast(
    sync: true,
  );

  UserProfile? profile;
  @override
  String? currentUid;

  @override
  Stream<String?> get authStateChanges => _controller.stream;

  void emitAuthChange(String? uid) {
    currentUid = uid;
    _controller.add(uid);
  }

  @override
  Future<UserProfile?> getCurrentUserProfile() async {
    return profile;
  }

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> signUp({
    required String displayName,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() async {
    emitAuthChange(null);
  }

  Future<void> close() async {
    await _controller.close();
  }
}

void main() {
  late FakeAuthRepository repository;
  late AuthProvider authProvider;

  setUp(() {
    repository = FakeAuthRepository();
    authProvider = AuthProvider(repository);
    authProvider.start();
  });

  tearDown(() async {
    authProvider.dispose();
    await repository.close();
  });

  test('User starts in loading state', () {
    expect(authProvider.status, AuthStatus.loading);
    expect(authProvider.isAuthenticated, false);
  });

  test('User becomes signed out', () {
    repository.emitAuthChange(null);

    expect(authProvider.status, AuthStatus.signedOut);
    expect(authProvider.isAuthenticated, false);
    expect(authProvider.userProfile, isNull);
  });

  test('Patient authentication loads correctly', () async {
    repository.profile = const UserProfile(
      id: 'patient-001',
      displayName: 'Demo Patient',
      email: 'patient@example.com',
      role: UserRole.patient,
    );

    repository.emitAuthChange('patient-001');

    await Future<void>.delayed(Duration.zero);

    expect(authProvider.status, AuthStatus.signedIn);
    expect(authProvider.isAuthenticated, true);
    expect(authProvider.isPatient, true);
    expect(authProvider.isDoctor, false);
    expect(authProvider.userId, 'patient-001');
  });

  test('Doctor authentication loads correctly', () async {
    repository.profile = const UserProfile(
      id: 'doctor-001',
      displayName: 'Demo Doctor',
      email: 'doctor@example.com',
      role: UserRole.doctor,
    );

    repository.emitAuthChange('doctor-001');

    await Future<void>.delayed(Duration.zero);

    expect(authProvider.status, AuthStatus.signedIn);
    expect(authProvider.isDoctor, true);
    expect(authProvider.isPatient, false);
  });

  test('Missing user profile is handled', () async {
    repository.profile = null;
    repository.emitAuthChange('unknown-user');

    await Future<void>.delayed(Duration.zero);

    expect(authProvider.status, AuthStatus.missingProfile);
    expect(authProvider.isAuthenticated, false);
  });

  test('Signing out clears authenticated state', () async {
    repository.profile = const UserProfile(
      id: 'patient-001',
      displayName: 'Demo Patient',
      email: 'patient@example.com',
      role: UserRole.patient,
    );

    repository.emitAuthChange('patient-001');
    await Future<void>.delayed(Duration.zero);

    expect(authProvider.isAuthenticated, true);

    await repository.signOut();

    expect(authProvider.status, AuthStatus.signedOut);
    expect(authProvider.userProfile, isNull);
    expect(authProvider.userId, isNull);
  });
}
