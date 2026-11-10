import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/doctor_link.dart';
import 'package:medication_follow_up_app/screens/doctor_linking_screen.dart';
import 'package:medication_follow_up_app/services/doctor_link_repository.dart';
import 'package:medication_follow_up_app/state/doctor_link_provider.dart';
import 'package:provider/provider.dart';

import 'support/fake_patient_link_repository.dart';

void main() {
  late FakeRepo repo;
  late DoctorLinkProvider links;

  setUp(() {
    repo = FakeRepo();
    links = DoctorLinkProvider(repo)
      ..updateSession(uid: 'pat', isDoctor: false, isPatient: true);
  });

  tearDown(() => links.dispose());

  /// Pumps a "Patient Today" stand-in with a button that opens the screen.
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<DoctorLinkProvider>.value(
        value: links,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DoctorLinkingScreen(),
                    ),
                  ),
                  child: const Text('Patient Today'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Patient Today'));
    await tester.pumpAndSettle();
  }

  Finder codeField() => find.byType(TextFormField);

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> findDoctor(WidgetTester tester, String code) async {
    await tester.enterText(codeField(), code);
    await tapVisible(tester, find.text('Find doctor'));
  }

  bool consentValue(WidgetTester tester) =>
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value!;

  testWidgets('renders the Figma content', (tester) async {
    await open(tester);
    expect(find.text('Doctor Linking'), findsOneWidget);
    expect(find.text('Connect your doctor'), findsOneWidget);
    expect(find.text('Secure sharing'), findsOneWidget);
    expect(find.text('Doctor linking code'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('Try an invalid code'), findsNothing); // prototype only
  });

  testWidgets('validates empty and malformed codes without lookup',
      (tester) async {
    await open(tester);
    await tapVisible(tester, find.text('Find doctor'));
    expect(find.text('Enter the code from your doctor'), findsOneWidget);

    await findDoctor(tester, 'DR-48291');
    expect(find.textContaining('10-character code'), findsWidgets);
    expect(links.doctorPreview, isNull);
  });

  testWidgets('accepts separators and shows the real doctor preview',
      (tester) async {
    await open(tester);
    await findDoctor(tester, 'abcd-efgh-23');
    expect(find.text('Dr Test'), findsOneWidget);
    expect(find.textContaining('not professionally verified'), findsOneWidget);
    expect(consentValue(tester), isFalse); // unchecked by default
    expect(find.text('Enable consent to continue'), findsOneWidget);
  });

  testWidgets('unknown and expired codes show feedback', (tester) async {
    await open(tester);
    await findDoctor(tester, 'ZZZZZZZZZZ');
    expect(find.textContaining('not found'), findsOneWidget);

    repo.failNext = const DoctorLinkException(DoctorLinkErrorCode.codeExpired);
    await tapVisible(tester, find.text('Find doctor'));
    expect(find.textContaining('expired'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('linking is blocked until consent, then passes true',
      (tester) async {
    await open(tester);
    await findDoctor(tester, validCode);

    final blocked = tester.widget<TextButton>(find.ancestor(
      of: find.text('Enable consent to continue'),
      matching: find.byType(TextButton),
    ));
    expect(blocked.onPressed, isNull);
    expect(repo.linkCalls, 0);

    await tapVisible(tester, find.byType(CheckboxListTile));
    expect(consentValue(tester), isTrue);
    await tapVisible(tester, find.text('Link doctor'));

    expect(repo.consentPassed, [true]);
    expect(find.text('Doctor linked successfully'), findsOneWidget);
    expect(find.text('Continue to Today'), findsOneWidget);
    expect(links.activeDoctorLinks, hasLength(1));
  });

  testWidgets('changing the code resets consent and preview', (tester) async {
    await open(tester);
    await findDoctor(tester, validCode);
    await tapVisible(tester, find.byType(CheckboxListTile));
    await tester.enterText(codeField(), 'JKLMNPQR45');
    await tester.pump();
    expect(links.doctorPreview, isNull);
    expect(find.byType(CheckboxListTile), findsNothing);

    await tester.enterText(codeField(), validCode);
    await tapVisible(tester, find.text('Find doctor'));
    expect(consentValue(tester), isFalse);
  });

  testWidgets('shows loading and blocks duplicate submits', (tester) async {
    await open(tester);
    await tester.enterText(codeField(), validCode);
    final gate = repo.gate = Completer<void>();
    await tester.ensureVisible(find.text('Find doctor'));
    await tester.tap(find.text('Find doctor'));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    gate.complete();
    repo.gate = null;
    await tester.pumpAndSettle();
    expect(find.text('Dr Test'), findsOneWidget);
  });

  testWidgets('already-linked and newer-code-required errors', (tester) async {
    await open(tester);
    await findDoctor(tester, validCode);
    await tapVisible(tester, find.byType(CheckboxListTile));
    await tapVisible(tester, find.text('Link doctor'));

    // Second attempt with the same doctor.
    await tapVisible(tester, find.text('Continue to Today'));
    await tapVisible(tester, find.text('Patient Today'));
    await findDoctor(tester, validCode);
    await tapVisible(tester, find.byType(CheckboxListTile));
    await tapVisible(tester, find.text('Link doctor'));
    expect(find.text('You are already linked to this doctor.'), findsOneWidget);

    repo.revokeAsDoctor('pat_doc', DateTime.utc(2026, 11, 5));
    await tapVisible(tester, find.text('Link doctor'));
    expect(find.textContaining('Ask them for a new code'), findsOneWidget);
    expect(find.text('Dr Test'), findsWidgets); // preview kept
  });

  testWidgets('errors can be retried', (tester) async {
    await open(tester);
    await findDoctor(tester, validCode);
    await tapVisible(tester, find.byType(CheckboxListTile));
    repo.failNext = const DoctorLinkException(DoctorLinkErrorCode.network);
    await tapVisible(tester, find.text('Link doctor'));
    expect(find.textContaining('Network error'), findsOneWidget);

    await tapVisible(tester, find.text('Link doctor'));
    expect(find.text('Doctor linked successfully'), findsOneWidget);
  });

  testWidgets('Not now and Back return without linking', (tester) async {
    await open(tester);
    await findDoctor(tester, validCode);
    await tapVisible(tester, find.text('Not now'));
    expect(find.text('Patient Today'), findsOneWidget);

    await tapVisible(tester, find.text('Patient Today'));
    await tapVisible(tester, find.byTooltip('Back'));
    expect(find.text('Patient Today'), findsOneWidget);
    expect(repo.linkCalls, 0);
    expect(repo.links, isEmpty);
  });

  testWidgets('non-patients cannot use the form', (tester) async {
    links.updateSession(uid: 'doc', isDoctor: true);
    await open(tester);
    expect(find.text('Only patient accounts can link to a doctor.'),
        findsOneWidget);
    expect(codeField(), findsNothing);
    expect(find.text('Your doctors'), findsNothing);
  });

  // ---------------------------------------------------- Task 3.5C

  void seedLink({bool active = true, String? revokedBy}) {
    repo.links['pat_doc'] = DoctorLink(
      id: 'pat_doc',
      patientId: 'pat',
      doctorId: 'doc',
      linkCode: validCode,
      status: active ? LinkStatus.active : LinkStatus.revoked,
      doctorName: 'Dr Test',
      revokedBy: revokedBy,
      revokedAt: active ? null : DateTime.utc(2026, 11, 5),
    );
  }

  Future<void> linkWithConsent(WidgetTester tester) async {
    await findDoctor(tester, validCode);
    await tapVisible(tester, find.byType(CheckboxListTile));
    await tapVisible(tester, find.text('Link doctor'));
  }

  testWidgets('success screen shows the persisted doctor and continues',
      (tester) async {
    await open(tester);
    await linkWithConsent(tester);

    expect(find.text('Link Success'), findsOneWidget);
    expect(
      find.text('You have approved medication record sharing with Dr Test.'),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('Continue to Today'));
    expect(find.text('Patient Today'), findsOneWidget);

    // Reopening starts fresh and does not link again.
    await tapVisible(tester, find.text('Patient Today'));
    expect(find.text('Connect your doctor'), findsOneWidget);
    expect(repo.linkCalls, 1);
  });

  testWidgets('success header back returns to Today', (tester) async {
    await open(tester);
    await linkWithConsent(tester);
    await tapVisible(tester, find.byTooltip('Back'));
    expect(find.text('Patient Today'), findsOneWidget);
  });

  testWidgets('no false success when the link is missing after refresh',
      (tester) async {
    await open(tester);
    await findDoctor(tester, validCode);
    await tapVisible(tester, find.byType(CheckboxListTile));
    // Link call succeeds, but the follow-up list read fails.
    repo.failListAfterLink = true;
    await tapVisible(tester, find.text('Link doctor'));
    expect(find.text('Doctor linked successfully'), findsNothing);
    expect(find.textContaining('could not confirm the link'), findsOneWidget);
  });

  testWidgets('invalid code shows the Link Error design', (tester) async {
    await open(tester);
    await findDoctor(tester, 'ZZZZZZZZZZ');
    expect(find.text('Link Error'), findsOneWidget);
    expect(find.textContaining('not found'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('Try again'), findsNothing); // fix the code instead
  });

  testWidgets('network error is distinct and Try again retries',
      (tester) async {
    await open(tester);
    await tester.enterText(codeField(), validCode);
    repo.failNext = const DoctorLinkException(DoctorLinkErrorCode.network);
    await tapVisible(tester, find.text('Find doctor'));
    expect(find.text('Link Error'), findsOneWidget);
    expect(find.textContaining('Network error'), findsOneWidget);

    await tapVisible(tester, find.text('Try again'));
    expect(find.text('Dr Test'), findsOneWidget);
    expect(find.text('Doctor Linking'), findsOneWidget);
  });

  testWidgets('empty and active linked-doctor lists', (tester) async {
    await open(tester);
    expect(find.text('Your doctors'), findsOneWidget);
    expect(find.text('No linked doctors yet.'), findsOneWidget);

    seedLink();
    await links.loadPatientLinks();
    await tester.pumpAndSettle();
    expect(find.text('Can view your records'), findsOneWidget);
    expect(find.text('Revoke'), findsOneWidget);
  });

  testWidgets('revoke needs confirmation; cancel keeps the link',
      (tester) async {
    seedLink();
    await open(tester);
    await tapVisible(tester, find.text('Revoke'));
    expect(find.text('Stop sharing?'), findsOneWidget);
    await tapVisible(tester, find.text('Cancel'));
    expect(repo.links['pat_doc']!.isActive, isTrue);

    await tapVisible(tester, find.text('Revoke'));
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Revoke'));
    expect(repo.links['pat_doc']!.isActive, isFalse);
    expect(find.textContaining('Access ended. Enter a valid code'),
        findsOneWidget);
    expect(find.text('Revoke'), findsNothing);
  });

  testWidgets('failed revoke keeps the doctor listed', (tester) async {
    seedLink();
    await open(tester);
    await tapVisible(tester, find.text('Revoke'));
    repo.failNext =
        const DoctorLinkException(DoctorLinkErrorCode.permissionDenied);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Revoke'));
    expect(find.text('Can view your records'), findsOneWidget);
    expect(find.textContaining('permission'), findsOneWidget);
  });

  testWidgets('doctor-revoked link explains a new code is needed',
      (tester) async {
    seedLink(active: false, revokedBy: 'doc');
    await open(tester);
    expect(find.textContaining('Ask for a new code'), findsOneWidget);
    await linkWithConsent(tester);
    expect(find.text('Link Error'), findsOneWidget);
    expect(find.textContaining('Ask them for a new code'), findsOneWidget);
    expect(find.text('Doctor linked successfully'), findsNothing);
  });
}
