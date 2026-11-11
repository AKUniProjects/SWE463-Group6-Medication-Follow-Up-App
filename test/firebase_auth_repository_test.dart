import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/user_profile.dart';
import 'package:medication_follow_up_app/services/auth_repository.dart';
import 'package:medication_follow_up_app/services/firebase_auth_repository.dart';

class FakeAuthGateway implements AuthGateway {
  String? currentUidValue;
  AuthException? signInError;
  AuthException? createError;
  bool failDelete = false;
  bool deleted = false;
  int signOutCalls = 0;

  @override
  Stream<String?> authStateChanges() => const Stream.empty();

  @override
  String? get currentUid => currentUidValue;

  @override
  Future<String> signIn(String email, String password) async {
    if (signInError != null) throw signInError!;
    return currentUidValue = 'uid-1';
  }

  @override
  Future<String> createUser(String email, String password) async {
    if (createError != null) throw createError!;
    return currentUidValue = 'new-uid';
  }

  @override
  Future<void> deleteCurrentUser() async {
    if (failDelete) throw Exception('delete failed');
    deleted = true;
    currentUidValue = null;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    currentUidValue = null;
  }
}

class FakeProfileStore implements ProfileStore {
  final Map<String, Map<String, dynamic>> docs = {};
  bool failWrite = false;
  bool failRead = false;
  Completer<void>? pending;

  @override
  Future<Map<String, dynamic>?> read(String uid) async {
    if (pending != null) await pending!.future;
    if (failRead) throw Exception('read failed');
    return docs[uid];
  }

  @override
  Future<void> write(String uid, Map<String, dynamic> data) async {
    if (pending != null) await pending!.future;
    if (failWrite) throw Exception('permission-denied');
    docs[uid] = data;
  }
}

Matcher throwsAuth(AuthErrorCode code) => throwsA(
      isA<AuthException>().having((e) => e.code, 'code', code),
    );

void main() {
  late FakeAuthGateway gateway;
  late FakeProfileStore store;
  late FirebaseAuthRepository repository;

  setUp(() {
    gateway = FakeAuthGateway();
    store = FakeProfileStore();
    repository = FirebaseAuthRepository(
      authGateway: gateway,
      profileStore: store,
    );
  });

  for (final registering in [false, true]) {
    test('failed old auth operation leaves replacement user intact: $registering',
        () async {
      store.pending = Completer<void>();
      store.failRead = true;
      store.failWrite = true;
      final operation = registering
          ? repository.signUp(displayName: 'A', email: 'a@example.com',
              password: 'secret1', role: UserRole.patient)
          : repository.signIn(email: 'a@example.com', password: 'secret1');
      final assertion = expectLater(operation, throwsAuth(registering
          ? AuthErrorCode.profileCreationFailed : AuthErrorCode.profileLoadFailed));
      await Future<void>.delayed(Duration.zero);
      gateway.currentUidValue = 'replacement-user';
      store.pending!.complete();
      await assertion;
      expect(gateway.currentUid, 'replacement-user');
      expect(gateway.deleted, isFalse);
      expect(gateway.signOutCalls, 0);
    });
  }

  group('signIn', () {
    test('returns the stored profile', () async {
      store.docs['uid-1'] = {
        'displayName': 'Pat',
        'email': 'pat@example.com',
        'role': 'patient',
        'linkedDoctorIds': ['doc-1'],
      };

      final profile = await repository.signIn(
        email: ' pat@example.com ',
        password: 'secret1',
      );

      expect(profile.id, 'uid-1');
      expect(profile.role, UserRole.patient);
      expect(profile.linkedDoctorIds, ['doc-1']);
    });

    test('rejects empty input without calling Firebase', () {
      expect(
        repository.signIn(email: ' ', password: ''),
        throwsAuth(AuthErrorCode.invalidInput),
      );
    });

    test('propagates mapped credential errors', () {
      gateway.signInError =
          const AuthException(AuthErrorCode.invalidCredentials);
      expect(
        repository.signIn(email: 'a@b.com', password: 'x'),
        throwsAuth(AuthErrorCode.invalidCredentials),
      );
    });

    test('missing profile signs out and fails', () async {
      await expectLater(
        repository.signIn(email: 'a@b.com', password: 'x'),
        throwsAuth(AuthErrorCode.profileNotFound),
      );
      expect(gateway.signOutCalls, 1);
    });

    test('profile read failure signs out and fails', () async {
      store.failRead = true;
      await expectLater(
        repository.signIn(email: 'a@b.com', password: 'x'),
        throwsAuth(AuthErrorCode.profileLoadFailed),
      );
      expect(gateway.signOutCalls, 1);
    });
  });

  group('signUp', () {
    test('creates users/{uid} with role and no doctor links', () async {
      final profile = await repository.signUp(
        displayName: ' Dr. Lee ',
        email: 'lee@example.com',
        password: 'secret1',
        role: UserRole.doctor,
      );

      expect(profile.id, 'new-uid');
      expect(profile.role, UserRole.doctor);
      expect(store.docs['new-uid'], {
        'displayName': 'Dr. Lee',
        'email': 'lee@example.com',
        'role': 'doctor',
        'linkedDoctorIds': <String>[],
      });
    });

    test('propagates email-already-in-use', () {
      gateway.createError =
          const AuthException(AuthErrorCode.emailAlreadyInUse);
      expect(
        repository.signUp(
          displayName: 'A',
          email: 'a@b.com',
          password: 'secret1',
          role: UserRole.patient,
        ),
        throwsAuth(AuthErrorCode.emailAlreadyInUse),
      );
    });

    test('profile write failure deletes the auth user', () async {
      store.failWrite = true;
      await expectLater(
        repository.signUp(
          displayName: 'A',
          email: 'a@b.com',
          password: 'secret1',
          role: UserRole.patient,
        ),
        throwsAuth(AuthErrorCode.profileCreationFailed),
      );
      expect(gateway.deleted, isTrue);
      expect(store.docs, isEmpty);
    });

    test('falls back to sign-out when rollback delete fails', () async {
      store.failWrite = true;
      gateway.failDelete = true;
      await expectLater(
        repository.signUp(
          displayName: 'A',
          email: 'a@b.com',
          password: 'secret1',
          role: UserRole.patient,
        ),
        throwsAuth(AuthErrorCode.profileCreationFailed),
      );
      expect(gateway.signOutCalls, 1);
    });
  });

  test('getCurrentUserProfile returns null when signed out', () async {
    expect(await repository.getCurrentUserProfile(), isNull);
  });

  test('maps Firebase error codes safely', () {
    expect(mapFirebaseAuthCode('invalid-credential'),
        AuthErrorCode.invalidCredentials);
    expect(mapFirebaseAuthCode('weak-password'), AuthErrorCode.weakPassword);
    expect(
        mapFirebaseAuthCode('network-request-failed'), AuthErrorCode.network);
    expect(mapFirebaseAuthCode('something-new'), AuthErrorCode.unknown);
    expect(const AuthException(AuthErrorCode.unknown).message,
        isNot(contains('Exception')));
  });
}
