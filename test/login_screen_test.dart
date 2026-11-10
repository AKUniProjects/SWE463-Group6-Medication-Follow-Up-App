import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/screens/auth_screen.dart';
import 'package:medication_follow_up_app/services/auth_repository.dart';
import 'package:medication_follow_up_app/state/auth_provider.dart';
import 'package:provider/provider.dart';

import 'support/controllable_auth_repository.dart';

void main() {
  late ControllableAuthRepository repo;
  late AuthProvider auth;

  Future<void> pumpLogin(WidgetTester tester) async {
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
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> fillValid(WidgetTester tester) async {
    await tester.enterText(field('Email'), 'pat@example.com');
    await tester.enterText(field('Password'), 'secret1');
  }

  testWidgets('shows Figma content with a single sign-in button',
      (tester) async {
    await pumpLogin(tester);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('MedFollow'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('Sign in as doctor'), findsNothing);
  });

  testWidgets('validates empty and malformed input', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);

    await tester.enterText(field('Email'), 'not-an-email');
    await tester.enterText(field('Password'), '123');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Use at least 6 characters'), findsOneWidget);
    expect(repo.signInCalls, 0);
  });

  testWidgets('toggles password visibility', (tester) async {
    await pumpLogin(tester);

    TextField passwordField() => tester.widget<TextField>(
          find.descendant(
            of: field('Password'),
            matching: find.byType(TextField),
          ),
        );

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.text('Show password'));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
    expect(find.text('Hide password'), findsOneWidget);
  });

  testWidgets('submits through provider and disables button while busy',
      (tester) async {
    await pumpLogin(tester);
    await fillValid(tester);

    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(repo.signInCalls, 1);
    expect(repo.lastSignInEmail, 'pat@example.com');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    repo.pendingAction!.complete(patient);
    await tester.pump();
    expect(auth.isPatient, isTrue);
  });

  testWidgets('shows friendly error and clears it on retry', (tester) async {
    await pumpLogin(tester);
    await fillValid(tester);

    await tester.tap(find.text('Sign in'));
    await tester.pump();
    repo.pendingAction!.completeError(
      const AuthException(AuthErrorCode.invalidCredentials),
    );
    await tester.pump();

    expect(find.text('Incorrect email or password.'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Incorrect email or password.'), findsNothing);
  });

  testWidgets('fits a narrow phone screen without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpLogin(tester);
    expect(tester.takeException(), isNull);
  });
}
