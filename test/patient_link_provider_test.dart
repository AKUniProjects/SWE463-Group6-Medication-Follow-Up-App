// Patient-side DoctorLinkProvider tests with a FAKE repository (no
// Firebase). Server enforcement is covered by firestore_rules_test/*.mjs.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/doctor_link.dart';
import 'package:medication_follow_up_app/services/doctor_link_repository.dart';
import 'package:medication_follow_up_app/state/doctor_link_provider.dart';

import 'support/fake_patient_link_repository.dart';

void main() {
  late FakeRepo repo;
  late DoctorLinkProvider provider;

  setUp(() {
    repo = FakeRepo();
    provider = DoctorLinkProvider(repo)
      ..updateSession(uid: 'pat', isDoctor: false, isPatient: true);
  });

  tearDown(() => provider.dispose());

  Future<void> linkOnce() async {
    await provider.lookupDoctor(validCode);
    await provider.linkToPreviewedDoctor(consentGiven: true);
  }

  test('initial state is idle with no links', () {
    expect(provider.linkStatus, PatientLinkStatus.idle);
    expect(provider.canLinkDoctors, isTrue);
    expect(provider.doctorPreview, isNull);
    expect(provider.patientLinks, isEmpty);
  });

  test('normalizes input and previews the doctor', () async {
    expect(await provider.lookupDoctor(' abcd-efgh-23 '), isTrue);
    expect(provider.codeInput, validCode);
    expect(provider.linkStatus, PatientLinkStatus.preview);
    expect(provider.doctorPreview!.doctorName, 'Dr Test');
  });

  test('format errors are caught before any repository call', () async {
    expect(DoctorLinkProvider.validateCodeInput('12'), isNotNull);
    expect(DoctorLinkProvider.validateCodeInput('abcd-efgh-23'), isNull);
    repo.gate = Completer<void>(); // would hang if called
    expect(await provider.lookupDoctor('12'), isFalse);
    expect(provider.linkStatus, PatientLinkStatus.invalidCode);
  });

  test('unknown, inactive and expired codes give invalidCode', () async {
    expect(await provider.lookupDoctor('ZZZZZZZZZZ'), isFalse);
    expect(provider.linkStatus, PatientLinkStatus.invalidCode);
    expect(provider.linkMessage, contains('not found'));

    repo.failNext = const DoctorLinkException(DoctorLinkErrorCode.codeExpired);
    expect(await provider.lookupDoctor(validCode), isFalse);
    expect(provider.linkStatus, PatientLinkStatus.invalidCode);
    expect(provider.linkMessage, contains('expired'));
    expect(provider.doctorPreview, isNull);
    expect(repo.links, isEmpty);
  });

  test('changing the input clears the preview', () async {
    await provider.lookupDoctor(validCode);
    provider.setCodeInput('JKLMNPQR45');
    expect(provider.doctorPreview, isNull);
    expect(provider.linkStatus, PatientLinkStatus.idle);
  });

  test('missing consent never reaches the repository', () async {
    await provider.lookupDoctor(validCode);
    expect(await provider.linkToPreviewedDoctor(consentGiven: false), isFalse);
    expect(provider.linkStatus, PatientLinkStatus.consentRequired);
    expect(repo.linkCalls, 0);
  });

  test('successful link passes real consent and refreshes links', () async {
    await linkOnce();
    expect(provider.linkStatus, PatientLinkStatus.linked);
    expect(repo.consentPassed, [true]);
    expect(provider.lastLinked!.doctorId, 'doc');
    expect(provider.activeDoctorLinks.single.doctorName, 'Dr Test');
  });

  test('already linked is reported, not shown as success', () async {
    await linkOnce();
    await provider.lookupDoctor(validCode);
    expect(await provider.linkToPreviewedDoctor(consentGiven: true), isFalse);
    expect(provider.linkStatus, PatientLinkStatus.alreadyLinked);
  });

  test('patient revoke, then reactivate with the same code', () async {
    await linkOnce();
    final link = provider.activeDoctorLinks.single;
    expect(await provider.revokeDoctorLink(link), isTrue);
    expect(provider.revokedDoctorLinks, hasLength(1));
    expect(provider.activeDoctorLinks, isEmpty);

    await provider.lookupDoctor(validCode);
    expect(await provider.linkToPreviewedDoctor(consentGiven: true), isTrue);
    expect(provider.activeDoctorLinks, hasLength(1));
  });

  test('doctor-revoked link requires a newer code', () async {
    await linkOnce();
    repo.revokeAsDoctor('pat_doc', DateTime.utc(2026, 11, 5));
    await provider.loadPatientLinks();
    expect(provider.revokedDoctorLinks.single.revokedBy, 'doc');

    await provider.lookupDoctor(validCode);
    expect(await provider.linkToPreviewedDoctor(consentGiven: true), isFalse);
    expect(provider.linkStatus, PatientLinkStatus.newCodeRequired);
    expect(provider.linkMessage, contains('new code'));

    repo.codes['NEWCDE5678'] = DoctorCode(
      code: 'NEWCDE5678',
      doctorId: 'doc',
      doctorName: 'Dr Test',
      active: true,
      createdAt: DateTime.utc(2026, 11, 6),
    );
    await provider.lookupDoctor('NEWCDE5678');
    expect(await provider.linkToPreviewedDoctor(consentGiven: true), isTrue);
  });

  test('failures are visible and retry works', () async {
    await provider.lookupDoctor(validCode);
    repo.failNext =
        const DoctorLinkException(DoctorLinkErrorCode.permissionDenied);
    expect(await provider.linkToPreviewedDoctor(consentGiven: true), isFalse);
    expect(provider.linkStatus, PatientLinkStatus.error);
    expect(provider.linkMessage, contains('permission'));
    expect(provider.doctorPreview, isNotNull); // retry keeps preview

    expect(await provider.linkToPreviewedDoctor(consentGiven: true), isTrue);

    repo.failNext = const DoctorLinkException(DoctorLinkErrorCode.network);
    expect(await provider.loadPatientLinks(), isFalse);
    expect(provider.patientLinksError, contains('Network'));
    expect(provider.patientLinks, isNotEmpty); // old list kept
    expect(await provider.loadPatientLinks(), isTrue);
    expect(provider.patientLinksError, isNull);
  });

  test('duplicate actions are blocked while pending', () async {
    final gate = repo.gate = Completer<void>();
    final first = provider.lookupDoctor(validCode);
    expect(provider.linkStatus, PatientLinkStatus.lookingUp);
    expect(await provider.lookupDoctor(validCode), isFalse);
    gate.complete();
    repo.gate = null;
    expect(await first, isTrue);
  });

  test('doctors and signed-out users cannot link', () async {
    provider.updateSession(uid: 'doc', isDoctor: true);
    expect(provider.canLinkDoctors, isFalse);
    expect(await provider.lookupDoctor(validCode), isFalse);
    expect(provider.linkMessage, contains('Only patient accounts'));
    expect(await provider.loadPatientLinks(), isFalse);

    provider.updateSession(uid: null, isDoctor: false);
    expect(await provider.lookupDoctor(validCode), isFalse);
    expect(repo.linkCalls, 0);
  });

  test('sign-out and account switch clear patient data', () async {
    await linkOnce();
    expect(provider.patientLinks, isNotEmpty);
    provider.updateSession(uid: 'pat2', isDoctor: false, isPatient: true);
    expect(provider.patientLinks, isEmpty);
    expect(provider.doctorPreview, isNull);
    expect(provider.linkStatus, PatientLinkStatus.idle);

    provider.updateSession(uid: null, isDoctor: false);
    expect(provider.canLinkDoctors, isFalse);
  });

  test('stale results after an account switch are ignored', () async {
    final gate = repo.gate = Completer<void>();
    final pending = provider.lookupDoctor(validCode);
    provider.updateSession(uid: 'pat2', isDoctor: false, isPatient: true);
    gate.complete();
    repo.gate = null;
    expect(await pending, isFalse);
    expect(provider.doctorPreview, isNull);
    expect(provider.linkStatus, PatientLinkStatus.idle);
  });

  test('doctor-code management still works for doctors', () async {
    provider.updateSession(uid: 'doc', isDoctor: true);
    expect(provider.canManageCodes, isTrue);
    expect(await provider.createCode(), isTrue);
    expect(provider.currentCode!.code, 'NEWCODE234');
  });

  // Regression (Task 3.5D emulator run): the "already linked" banner stayed
  // visible after the patient revoked that same doctor.
  test('revoking clears a stale already-linked message', () async {
    await linkOnce();
    await provider.lookupDoctor(validCode);
    await provider.linkToPreviewedDoctor(consentGiven: true);
    expect(provider.linkStatus, PatientLinkStatus.alreadyLinked);

    await provider.revokeDoctorLink(provider.activeDoctorLinks.single);
    expect(provider.linkStatus, PatientLinkStatus.idle);
    expect(provider.linkMessage, isNull);
    expect(provider.doctorPreview, isNotNull); // can re-link right away
  });
}
