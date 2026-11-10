import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/user_profile.dart';
import 'package:medication_follow_up_app/screens/auth_screen.dart';
import 'package:medication_follow_up_app/screens/sign_up_screen.dart';
import 'package:medication_follow_up_app/services/auth_repository.dart';
import 'package:medication_follow_up_app/state/auth_provider.dart';
import 'package:medication_follow_up_app/widgets/auth_form_widgets.dart';
import 'package:provider/provider.dart';

import 'support/controllable_auth_repository.dart';

void main() {
  late ControllableAuthRepository repo;
  late AuthProvider auth;

  Future<void> pump(WidgetTester tester, Widget screen) async {
    repo = ControllableAuthRepository();
    auth = AuthProvider(repo)..start();
    repo.emit(null);
    addTearDown(() async {
      auth.dispose();
      await repo.close();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(home: screen),
      ),
    );
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> failPending(AuthErrorCode code) async {
    repo.pendingAction!.completeError(AuthException(code));
  }

  group('validators', () {
    test('email is trimmed and permissive but rejects malformed', () {
      expect(validateAuthEmail(''), 'Enter your email');
      expect(validateAuthEmail('   '), 'Enter your email');
      expect(validateAuthEmail('a@b'), 'Enter a valid email address');
      expect(validateAuthEmail('a b@c.com'), 'Enter a valid email address');
      expect(validateAuthEmail('  first.last+tag@sub.example.co  '), isNull);
    });

    test('password uses the shared minimum length', () {
      expect(validateAuthPassword(''), 'Enter your password');
      expect(validateAuthPassword('12345'), 'Use at least 6 characters');
      expect(validateAuthPassword('123456'), isNull);
    });

    test('name rejects blank and overly long values', () {
      expect(validateAuthName('   '), 'Enter your full name');
      expect(validateAuthName('x' * 101), 'Use 100 characters or fewer');
      expect(validateAuthName('  Alex Morgan  '), isNull);
    });
  });

  group('Login', () {
    Future<void> fill(WidgetTester tester, String email, String pw) async {
      await tester.enterText(field('Email'), email);
      await tester.enterText(field('Password'), pw);
    }

    testWidgets('short password is rejected without submitting',
        (tester) async {
      await pump(tester, const AuthScreen());
      await fill(tester, 'pat@example.com', '123');
      await tapVisible(tester, find.text('Sign in'));

      expect(find.text('Use at least 6 characters'), findsOneWidget);
      expect(repo.signInCalls, 0);
    });

    testWidgets('trims email and blocks duplicate submissions', (tester) async {
      await pump(tester, const AuthScreen());
      await fill(tester, '  pat@example.com  ', 'secret1');
      await tapVisible(tester, find.text('Sign in'));
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();

      expect(repo.signInCalls, 1);
      expect(repo.lastSignInEmail, 'pat@example.com');
    });

    testWidgets('network failure shows subtle banner and keeps input',
        (tester) async {
      await pump(tester, const AuthScreen());
      await fill(tester, 'pat@example.com', 'secret1');
      await tapVisible(tester, find.text('Sign in'));
      await failPending(AuthErrorCode.network);
      await tester.pump();

      expect(
        find.text('Network error. Check your connection and try again.'),
        findsOneWidget,
      );
      expect(find.text('pat@example.com'), findsOneWidget);
      expect(find.text('secret1'), findsOneWidget);
      expect(auth.status, AuthStatus.signedOut);

      // Light-blue banner with navy text, not a red-filled box.
      final box = tester.widget<Container>(
        find.descendant(
          of: find.byType(AuthErrorBanner),
          matching: find.byType(Container),
        ),
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, AuthColors.tint);
      expect(find.bySemanticsLabel(RegExp('^Error:')), findsOneWidget);
    });

    testWidgets('editing a field clears an outdated error', (tester) async {
      await pump(tester, const AuthScreen());
      await fill(tester, 'pat@example.com', 'secret1');
      await tapVisible(tester, find.text('Sign in'));
      await failPending(AuthErrorCode.invalidCredentials);
      await tester.pump();
      expect(find.byType(AuthErrorBanner), findsOneWidget);

      await tester.enterText(field('Password'), 'secret2');
      await tester.pump();
      expect(find.byType(AuthErrorBanner), findsNothing);
    });
  });

  group('Sign Up', () {
    Future<void> fill(WidgetTester tester,
        {String name = 'Alex Morgan'}) async {
      await tester.enterText(field('Full name'), name);
      await tester.enterText(field('Email'), 'alex@example.com');
      await tester.enterText(field('Password'), 'secret1');
    }

    Finder create(String role) => find.text('Create $role account');

    testWidgets('whitespace-only and overly long names are rejected',
        (tester) async {
      await pump(tester, const SignUpScreen());
      await fill(tester, name: '    ');
      await tapVisible(tester, create('patient'));
      expect(find.text('Enter your full name'), findsOneWidget);

      await tester.enterText(field('Full name'), 'x' * 101);
      await tapVisible(tester, create('patient'));
      expect(find.text('Use 100 characters or fewer'), findsOneWidget);
      expect(repo.signUpCalls, 0);
    });

    testWidgets('short password is rejected', (tester) async {
      await pump(tester, const SignUpScreen());
      await fill(tester);
      await tester.enterText(field('Password'), '12');
      await tapVisible(tester, create('patient'));

      expect(find.text('Use at least 6 characters'), findsOneWidget);
      expect(repo.signUpCalls, 0);
    });

    testWidgets('trims name; doctor role and input survive weak-password error',
        (tester) async {
      await pump(tester, const SignUpScreen());
      await tester.tap(find.text('Doctor'));
      await tester.pump();
      await fill(tester, name: '  Alex Morgan  ');
      await tapVisible(tester, create('doctor'));
      expect(repo.lastSignUpName, 'Alex Morgan');
      expect(repo.lastSignUpRole, UserRole.doctor);

      await failPending(AuthErrorCode.weakPassword);
      await tester.pump();

      expect(find.textContaining('too weak'), findsOneWidget);
      expect(create('doctor'), findsOneWidget);
      expect(find.text('alex@example.com'), findsOneWidget);
    });

    testWidgets('retry clears the duplicate-email error', (tester) async {
      await pump(tester, const SignUpScreen());
      await fill(tester);
      await tapVisible(tester, create('patient'));
      await failPending(AuthErrorCode.emailAlreadyInUse);
      await tester.pump();
      expect(find.text('An account already exists for this email.'),
          findsOneWidget);

      await tapVisible(tester, create('patient'));
      expect(
          find.text('An account already exists for this email.'), findsNothing);
      expect(repo.signUpCalls, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  testWidgets('320px screens fit validation messages without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(tester, const SignUpScreen());
    await tapVisible(tester, create320());
    expect(find.text('Enter your full name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder create320() => find.text('Create patient account');
