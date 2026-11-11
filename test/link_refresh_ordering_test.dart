import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/doctor_link.dart';
import 'package:medication_follow_up_app/services/doctor_link_repository.dart';
import 'package:medication_follow_up_app/state/doctor_link_provider.dart';

const active = DoctorLink(
  id: 'pat_doc',
  patientId: 'pat',
  doctorId: 'doc',
  linkCode: 'ABCDEFGH23',
  status: LinkStatus.active,
);
const revoked = DoctorLink(
  id: 'pat_doc',
  patientId: 'pat',
  doctorId: 'doc',
  linkCode: 'ABCDEFGH23',
  status: LinkStatus.revoked,
);
const patient = LinkedPatient(link: active, displayName: 'Patient', email: '');

class QueuedRepo implements DoctorLinkRepository {
  final patientReads = <Completer<List<DoctorLink>>>[];
  final doctorReads = <Completer<List<LinkedPatient>>>[];
  String? expectedUid;
  @override
  Future<List<DoctorLink>> linksForPatient({bool activeOnly = false}) {
    final read = Completer<List<DoctorLink>>();
    patientReads.add(read);
    return read.future;
  }

  @override
  Future<List<LinkedPatient>> linkedPatientsForDoctor() {
    final read = Completer<List<LinkedPatient>>();
    doctorReads.add(read);
    return read.future;
  }

  @override
  Future<void> revokeLink(DoctorLink link) async {}
  @override
  Future<DoctorCode> lookupCode(String input) async => DoctorCode(
    code: input,
    doctorId: 'doc',
    doctorName: 'Doctor',
    active: true,
    createdAt: DateTime.now(),
  );
  @override
  Future<DoctorLink> linkWithCode(
    String input, {
    required bool consentGiven,
    required String expectedDoctorId,
  }) async {
    expectedUid = expectedDoctorId;
    return active;
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late QueuedRepo repo;
  late DoctorLinkProvider links;
  setUp(() {
    repo = QueuedRepo();
    links = DoctorLinkProvider(repo)
      ..updateSession(uid: 'pat', isDoctor: false, isPatient: true);
  });
  tearDown(() => links.dispose());

  test(
    'patient refreshes finishing in reverse order keep newest result',
    () async {
      final old = links.loadPatientLinks();
      final newer = links.loadPatientLinks();
      repo.patientReads[1].complete([revoked]);
      expect(await newer, isTrue);
      repo.patientReads[0].complete([active]);
      expect(await old, isFalse);
      expect(links.activeDoctorLinks, isEmpty);
      expect(links.revokedDoctorLinks.single.id, active.id);
      expect(links.isLoadingPatientLinks, isFalse);
    },
  );

  test('link invalidates prior read and binds preview UID', () async {
    final old = links.loadPatientLinks();
    await links.lookupDoctor('ABCDEFGH23');
    final mutation = links.linkToPreviewedDoctor(consentGiven: true);
    await Future<void>.delayed(Duration.zero);
    repo.patientReads.last.complete([active]);
    expect(await mutation, isTrue);
    repo.patientReads.first.complete([]);
    expect(await old, isFalse);
    expect(links.activeDoctorLinks.single.id, active.id);
    expect(repo.expectedUid, 'doc');
  });

  test('revocation invalidates an older active snapshot', () async {
    final initial = links.loadPatientLinks();
    repo.patientReads.last.complete([active]);
    await initial;
    final old = links.loadPatientLinks();
    final mutation = links.revokeDoctorLink(active);
    await Future<void>.delayed(Duration.zero);
    repo.patientReads.last.complete([revoked]);
    expect(await mutation, isTrue);
    repo.patientReads[1].complete([active]);
    expect(await old, isFalse);
    expect(links.activeDoctorLinks, isEmpty);
  });

  test(
    'failed post-revoke refresh keeps acknowledged revocation and retries',
    () async {
      final initial = links.loadPatientLinks();
      repo.patientReads.last.complete([active]);
      await initial;
      final mutation = links.revokeDoctorLink(active);
      await Future<void>.delayed(Duration.zero);
      repo.patientReads.last.completeError(
        const DoctorLinkException(DoctorLinkErrorCode.network),
      );
      expect(await mutation, isTrue);
      expect(links.activeDoctorLinks, isEmpty);
      expect(links.patientLinksError, isNotNull);
      final retry = links.loadPatientLinks();
      repo.patientReads.last.complete([revoked]);
      expect(await retry, isTrue);
      expect(links.patientLinksError, isNull);
    },
  );

  test(
    'doctor refreshes finishing in reverse order keep newest result',
    () async {
      links.updateSession(uid: 'doc', isDoctor: true);
      final old = links.loadLinkedPatients();
      final newer = links.loadLinkedPatients();
      repo.doctorReads[1].complete([]);
      expect(await newer, isTrue);
      repo.doctorReads[0].complete([patient]);
      expect(await old, isFalse);
      expect(links.linkedPatients, isEmpty);
    },
  );

  test(
    'doctor revocation starts a fresh read despite a pending dashboard load',
    () async {
      links.updateSession(uid: 'doc', isDoctor: true);
      final old = links.loadLinkedPatients();
      final mutation = links.revokePatientLink(patient);
      await Future<void>.delayed(Duration.zero);
      expect(repo.doctorReads.length, 2);
      repo.doctorReads.last.complete([]);
      expect(await mutation, isTrue);
      repo.doctorReads.first.complete([patient]);
      expect(await old, isFalse);
      expect(links.linkedPatients, isEmpty);
      expect(links.isBusy, isFalse);
    },
  );

  test('old error cannot replace new success or new session', () async {
    final old = links.loadPatientLinks();
    final newer = links.loadPatientLinks();
    repo.patientReads[1].complete([active]);
    await newer;
    repo.patientReads[0].completeError(
      const DoctorLinkException(DoctorLinkErrorCode.network),
    );
    expect(await old, isFalse);
    expect(links.patientLinksError, isNull);
    final pending = links.loadPatientLinks();
    links.updateSession(uid: 'other', isDoctor: false, isPatient: true);
    repo.patientReads.last.complete([active]);
    expect(await pending, isFalse);
    expect(links.patientLinks, isEmpty);
  });
}
