import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/user_profile.dart';
import 'package:medication_follow_up_app/screens/auth_screen.dart';
import 'package:medication_follow_up_app/screens/doctor_dashboard_screen.dart';
import 'package:medication_follow_up_app/screens/patient_home_screen.dart';
import 'package:medication_follow_up_app/services/auth_repository.dart';
import 'package:medication_follow_up_app/state/auth_provider.dart';

import 'support/app_providers.dart';
import 'support/controllable_auth_repository.dart';

void main() {
  late ControllableAuthRepository repo;
  late AuthProvider auth;

  setUp(() {
    repo = ControllableAuthRepository();
    auth = AuthProvider(repo)..start();
  });

  tearDown(() async {
    auth.dispose();
    await repo.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    // Listen inside the widget test's fake-async zone so profile loads
    // complete during pump().
    auth.dispose();
    auth = AuthProvider(repo)..start();
    await tester.pumpWidget(
      appWithProviders(auth),
    );
  }

  group('AuthProvider', () {
    test('registration race: early auth event does not mark failure', () async {
      final result = auth.signUp(
        displayName: 'Pat',
        email: 'pat@example.com',
        password: 'secret1',
        role: UserRole.patient,
      );
      expect(auth.isRegistering, isTrue);

      // Firebase reports the new user before the profile is written.
      repo.emit('patient-1');
      await Future<void>.delayed(Duration.zero);
      expect(auth.status, isNot(AuthStatus.missingProfile));

      repo.profiles['patient-1'] = patient;
      repo.pendingAction!.complete(patient);

      expect(await result, isTrue);
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.isPatient, isTrue);
      expect(auth.isRegistering, isFalse);
    });

    test('failed sign-up rolls back to signed out with safe message', () async {
      repo.emit(null);
      final result = auth.signUp(
        displayName: 'Pat',
        email: 'pat@example.com',
        password: 'secret1',
        role: UserRole.patient,
      );
      repo.emit('patient-1');
      repo.emit(null); // repository deleted the half-created user
      repo.pendingAction!.completeError(
          const AuthException(AuthErrorCode.profileCreationFailed));

      expect(await result, isFalse);
      expect(auth.status, AuthStatus.signedOut);
      expect(auth.actionErrorMessage,
          const AuthException(AuthErrorCode.profileCreationFailed).message);
    });

    test('sign-in error keeps user signed out', () async {
      repo.emit(null);
      final result = auth.signIn(email: 'a@b.com', password: 'x');
      repo.pendingAction!
          .completeError(const AuthException(AuthErrorCode.invalidCredentials));

      expect(await result, isFalse);
      expect(auth.status, AuthStatus.signedOut);
      expect(auth.actionErrorMessage, 'Incorrect email or password.');
    });

    test('stale profile load does not overwrite newer state', () async {
      repo.profiles['patient-1'] = patient;
      repo.emit('patient-1'); // starts async load
      repo.emit(null); // user signs out before it finishes
      await Future<void>.delayed(Duration.zero);

      expect(auth.status, AuthStatus.signedOut);
      expect(auth.userProfile, isNull);
    });

    test('profile load error becomes error state', () async {
      repo.profileLoadError = Exception('permission-denied');
      repo.emit('patient-1');
      await Future<void>.delayed(Duration.zero);

      expect(auth.status, AuthStatus.error);
    });
  });

  group('Routing', () {
    for (final recovery in [false, true]) {
      testWidgets('sign-out failure is visible and retry works, recovery=$recovery',
          (tester) async {
        repo.profiles[patient.id] = patient;
        await pumpApp(tester);
        repo.emit(recovery ? 'missing-profile' : patient.id);
        await tester.pumpAndSettle();
        repo.failSignOut = true;
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        expect(find.text('Could not sign out. Please try again.'), findsOneWidget);
        if (!recovery) expect(auth.isPatient, isTrue);
        repo.failSignOut = false;
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        expect(find.byType(AuthScreen), findsOneWidget);
        expect(find.text('Could not sign out. Please try again.'), findsNothing);
      });
    }

    testWidgets('initial loading, then signed out shows auth screen',
        (tester) async {
      await pumpApp(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repo.emit(null);
      await tester.pump();
      expect(find.byType(AuthScreen), findsOneWidget);
    });

    testWidgets('restored patient session routes to patient app',
        (tester) async {
      repo.profiles['patient-1'] = patient;
      await pumpApp(tester);
      repo.emit('patient-1');
      await tester.pumpAndSettle();

      expect(find.byType(PatientHomeScreen), findsOneWidget);
      expect(find.byType(DoctorDashboardScreen), findsNothing);
      expect(find.text('Doctor view'), findsNothing);
    });

    testWidgets('doctor routes to doctor dashboard', (tester) async {
      repo.profiles['doctor-1'] = doctor;
      await pumpApp(tester);
      repo.emit('doctor-1');
      await tester.pumpAndSettle();

      expect(find.byType(DoctorDashboardScreen), findsOneWidget);
      expect(find.byType(PatientHomeScreen), findsNothing);
    });

    testWidgets('logout returns to auth screen', (tester) async {
      repo.profiles['patient-1'] = patient;
      await pumpApp(tester);
      repo.emit('patient-1');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);
    });

    testWidgets('missing profile shows recovery view', (tester) async {
      await pumpApp(tester);
      repo.emit('ghost');
      await tester.pumpAndSettle();

      expect(find.text('Profile not found'), findsOneWidget);
      expect(find.byType(PatientHomeScreen), findsNothing);
      expect(find.byType(DoctorDashboardScreen), findsNothing);
    });

    testWidgets('auth stream error shows error view', (tester) async {
      await pumpApp(tester);
      repo.emitError();
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('unauthenticated named route cannot bypass gate',
        (tester) async {
      await pumpApp(tester);
      repo.emit(null);
      await tester.pump();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pushNamed('/app');
      await tester.pumpAndSettle();

      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.byType(PatientHomeScreen), findsNothing);
      expect(find.byType(DoctorDashboardScreen), findsNothing);
    });

    testWidgets('patient cannot reach doctor dashboard via route',
        (tester) async {
      repo.profiles['patient-1'] = patient;
      await pumpApp(tester);
      repo.emit('patient-1');
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pushNamed('/doctor');
      await tester.pumpAndSettle();

      expect(find.byType(DoctorDashboardScreen), findsNothing);
      expect(find.byType(PatientHomeScreen), findsOneWidget);
    });
  });
}
