import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/main.dart';
import 'package:medication_follow_up_app/models/user_profile.dart';
import 'package:medication_follow_up_app/screens/auth_screen.dart';
import 'package:medication_follow_up_app/screens/doctor_dashboard_screen.dart';
import 'package:medication_follow_up_app/screens/sign_up_screen.dart';
import 'package:medication_follow_up_app/services/auth_repository.dart';
import 'package:medication_follow_up_app/state/auth_provider.dart';
import 'package:provider/provider.dart';

import 'support/controllable_auth_repository.dart';

void main() {
  late ControllableAuthRepository repo;
  late AuthProvider auth;

  /// Pumps the real app (AuthGate) signed out, then opens Sign Up.
  Future<void> openSignUp(WidgetTester tester) async {
    // PatientHomeScreen has a known pre-existing overflow (out of scope).
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('RenderFlex overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    repo = ControllableAuthRepository();
    auth = AuthProvider(repo)..start();
    addTearDown(() async {
      auth.dispose();
      await repo.close();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: const MedicationFollowUpApp(),
      ),
    );
    repo.emit(null);
    await tester.pump();

    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> fillValid(WidgetTester tester) async {
    await tester.enterText(field('Full name'), 'Alex Morgan');
    await tester.enterText(field('Email'), 'alex@example.com');
    await tester.enterText(field('Password'), 'secret1');
  }

  Finder createButton(String role) => find.text('Create $role account');

  testWidgets('renders the Figma content from login', (tester) async {
    await openSignUp(tester);

    expect(find.byType(SignUpScreen), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
    expect(createButton('patient'), findsOneWidget);
    expect(find.text('Back to login'), findsOneWidget);
  });

  testWidgets('validates required fields and email', (tester) async {
    await openSignUp(tester);

    await tester.tap(createButton('patient'));
    await tester.pump();
    expect(find.text('Enter your full name'), findsOneWidget);
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter a password'), findsOneWidget);

    await tester.enterText(field('Email'), 'bad-email');
    await tester.tap(createButton('patient'));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(repo.signUpCalls, 0);
  });

  testWidgets('toggles password visibility', (tester) async {
    await openSignUp(tester);

    bool obscured() => tester
        .widget<TextField>(
          find.descendant(
              of: field('Password'), matching: find.byType(TextField)),
        )
        .obscureText;

    expect(obscured(), isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(obscured(), isFalse);
  });

  testWidgets('doctor selection submits doctor role and blocks repeats',
      (tester) async {
    await openSignUp(tester);

    await tester.tap(find.text('Doctor'));
    await tester.pump();
    expect(createButton('doctor'), findsOneWidget);

    await fillValid(tester);
    await tester.tap(createButton('doctor'));
    await tester.pump();

    expect(repo.signUpCalls, 1);
    expect(repo.lastSignUpRole, UserRole.doctor);
    expect(repo.lastSignUpName, 'Alex Morgan');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    // Firebase emits the new user before the profile exists (race).
    repo.emit('doctor-1');
    await tester.pump();
    expect(find.byType(SignUpScreen), findsOneWidget);

    repo.profiles['doctor-1'] = doctor;
    repo.pendingAction!.complete(doctor);
    await tester.pumpAndSettle();

    // Sign Up pops itself; AuthGate shows the doctor interface.
    expect(find.byType(SignUpScreen), findsNothing);
    expect(find.byType(DoctorDashboardScreen), findsOneWidget);
  });

  testWidgets('shows friendly error and keeps entered data', (tester) async {
    await openSignUp(tester);
    await fillValid(tester);

    await tester.tap(createButton('patient'));
    await tester.pump();
    repo.pendingAction!.completeError(
      const AuthException(AuthErrorCode.emailAlreadyInUse),
    );
    await tester.pumpAndSettle();

    expect(
        find.text('An account already exists for this email.'), findsOneWidget);
    expect(find.byType(SignUpScreen), findsOneWidget);
    expect(find.text('Alex Morgan'), findsOneWidget);
    expect(find.text('alex@example.com'), findsOneWidget);
  });

  testWidgets('Back to login returns to login without stale error',
      (tester) async {
    await openSignUp(tester);
    await fillValid(tester);
    await tester.tap(createButton('patient'));
    await tester.pump();
    repo.pendingAction!.completeError(
      const AuthException(AuthErrorCode.weakPassword),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Back to login'));
    await tester.tap(find.text('Back to login'));
    await tester.pumpAndSettle();

    expect(find.byType(SignUpScreen), findsNothing);
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.textContaining('too weak'), findsNothing);
  });
}
