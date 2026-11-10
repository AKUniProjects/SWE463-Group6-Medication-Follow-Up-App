// Repository logic tests using an in-memory fake store (NOT the Firestore
// emulator). Server-side enforcement is covered separately by
// firestore_rules_test/*.mjs against the emulator.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/doctor_link.dart';
import 'package:medication_follow_up_app/services/doctor_link_repository.dart';
import 'package:medication_follow_up_app/services/firebase_doctor_link_repository.dart';

const serverTime = '<serverTimestamp>';

class FakeStore implements DoctorLinkStore {
  final profiles = <String, Map<String, dynamic>>{};
  final codes = <String, Map<String, dynamic>>{};
  final links = <String, Map<String, dynamic>>{};
  final queries = <String>[];
  DoctorLinkException? failNext;
  DateTime clock = DateTime.utc(2026, 11, 10, 12);

  void _maybeFail() {
    final e = failNext;
    failNext = null;
    if (e != null) throw e;
  }

  // Simulates FieldValue.serverTimestamp(): record a marker, then resolve.
  Map<String, dynamic> _stamp(Map<String, dynamic> f, List<String> times) {
    final out = {...f, for (final t in times) t: serverTime};
    lastWrite = Map.of(out);
    return {...f, for (final t in times) t: clock};
  }

  Map<String, dynamic>? lastWrite;

  final deniedProfiles = <String>{};

  @override
  Future<Map<String, dynamic>?> readProfile(String uid) async {
    _maybeFail();
    if (deniedProfiles.contains(uid)) {
      throw const DoctorLinkException(DoctorLinkErrorCode.permissionDenied);
    }
    return profiles[uid];
  }

  @override
  Future<Map<String, dynamic>?> readCode(String code) async {
    _maybeFail();
    return codes[code];
  }

  @override
  Future<bool> createCodeIfAbsent(
    String code,
    Map<String, dynamic> fields,
    List<String> serverTimeFields,
  ) async {
    _maybeFail();
    if (codes.containsKey(code)) return false;
    codes[code] = _stamp(fields, serverTimeFields);
    return true;
  }

  @override
  Future<List<MapEntry<String, Map<String, dynamic>>>> codesWhereDoctor(
    String doctorId,
  ) async {
    _maybeFail();
    queries.add('doctorCodes.doctorId==$doctorId');
    return [
      for (final e in codes.entries)
        if (e.value['doctorId'] == doctorId) MapEntry(e.key, e.value),
    ];
  }

  @override
  Future<void> updateCode(String code, Map<String, dynamic> fields) async {
    _maybeFail();
    codes[code] = {...codes[code]!, ...fields};
  }

  @override
  Future<List<MapEntry<String, Map<String, dynamic>>>> linksWhere(
    String field,
    String uid,
  ) async {
    _maybeFail();
    queries.add('doctorLinks.$field==$uid');
    return [
      for (final e in links.entries)
        if (e.value[field] == uid) MapEntry(e.key, e.value),
    ];
  }

  @override
  Future<void> setLink(
    String linkId,
    Map<String, dynamic> fields,
    List<String> serverTimeFields,
  ) async {
    _maybeFail();
    links[linkId] = _stamp(fields, serverTimeFields);
  }

  @override
  Future<void> updateLink(
    String linkId,
    Map<String, dynamic> fields,
    List<String> serverTimeFields,
  ) async {
    _maybeFail();
    links[linkId] = {...links[linkId]!, ..._stamp(fields, serverTimeFields)};
  }
}

Matcher throwsLink(DoctorLinkErrorCode code) => throwsA(
      isA<DoctorLinkException>().having((e) => e.code, 'code', code),
    );

void main() {
  late FakeStore store;
  String? uid;
  late List<String> generated;

  FirebaseDoctorLinkRepository repo() => FirebaseDoctorLinkRepository(
        store: store,
        currentUid: () => uid,
        generateCode: () => generated.removeAt(0),
        now: () => store.clock,
      );

  setUp(() {
    store = FakeStore()
      ..profiles['pat'] = {'displayName': 'Test Patient', 'role': 'patient'}
      ..profiles['doc'] = {'displayName': 'Dr Test', 'role': 'doctor'};
    generated = ['ABCDEFGH23', 'JKLMNPQR45', 'STUVWXYZ67'];
  });

  Future<DoctorCode> issueCode() async {
    uid = 'doc';
    return repo().createCode();
  }

  group('code generation', () {
    test('secure generator yields canonical 10-char codes', () {
      for (var i = 0; i < 200; i++) {
        expect(isValidDoctorCode(generateSecureDoctorCode()), isTrue);
      }
      // Deterministic RNG only to check the alphabet mapping.
      expect(generateSecureDoctorCode(Random(1)).length, 10);
    });

    test('creates code with server createdAt and retries collisions', () async {
      store.codes['ABCDEFGH23'] = {'doctorId': 'other'};
      final code = await issueCode();

      expect(code.code, 'JKLMNPQR45');
      expect(store.lastWrite, {
        'doctorId': 'doc',
        'doctorName': 'Dr Test',
        'active': true,
        'createdAt': serverTime,
      });
      expect(store.codes['ABCDEFGH23']!['doctorId'], 'other'); // untouched
    });

    test('gives up after max attempts', () async {
      for (final c in generated) {
        store.codes[c] = {'doctorId': 'x'};
      }
      generated.addAll(['A' * 10, 'B' * 10]);
      for (final c in ['A' * 10, 'B' * 10]) {
        store.codes[c] = {'doctorId': 'x'};
      }
      await expectLater(
        issueCode(),
        throwsLink(DoctorLinkErrorCode.codeGenerationFailed),
      );
    });

    test('patients cannot create codes', () async {
      uid = 'pat';
      expect(repo().createCode(), throwsLink(DoctorLinkErrorCode.notDoctor));
    });

    test('replace creates a new code then deactivates the old one', () async {
      final old = await issueCode();
      final fresh = await repo().replaceCode(old.code);
      expect(fresh.code, isNot(old.code));
      expect(store.codes[old.code]!['active'], isFalse);
      expect(store.codes[fresh.code]!['active'], isTrue);
    });

    test('myCodes queries by signed-in doctor only', () async {
      await issueCode();
      final codes = await repo().myCodes();
      expect(codes.single.doctorId, 'doc');
      expect(store.queries.last, 'doctorCodes.doctorId==doc');
    });
  });

  group('lookup', () {
    test('normalizes input and returns only doctor info', () async {
      await issueCode();
      uid = 'pat';
      final code = await repo().lookupCode(' abcd-efgh-23 ');
      expect(code.code, 'ABCDEFGH23');
      expect(code.doctorName, 'Dr Test');
    });

    test('rejects bad format, missing, inactive, expired codes', () async {
      await issueCode();
      uid = 'pat';
      expect(repo().lookupCode('12'),
          throwsLink(DoctorLinkErrorCode.invalidCodeFormat));
      expect(repo().lookupCode('ZZZZZZZZZZ'),
          throwsLink(DoctorLinkErrorCode.codeNotFound));

      store.clock = store.clock.add(const Duration(days: 30));
      await expectLater(repo().lookupCode('ABCDEFGH23'),
          throwsLink(DoctorLinkErrorCode.codeExpired));

      store.codes['ABCDEFGH23']!['active'] = false;
      await expectLater(repo().lookupCode('ABCDEFGH23'),
          throwsLink(DoctorLinkErrorCode.codeInactive));
    });
  });

  group('linking', () {
    test('requires explicit consent and patient role', () async {
      await issueCode();
      uid = 'pat';
      expect(repo().linkWithCode('ABCDEFGH23', consentGiven: false),
          throwsLink(DoctorLinkErrorCode.consentRequired));
      uid = 'doc';
      expect(repo().linkWithCode('ABCDEFGH23', consentGiven: true),
          throwsLink(DoctorLinkErrorCode.notPatient));
    });

    test('creates link from signed-in UID with server consentedAt', () async {
      await issueCode();
      uid = 'pat';
      final link = await repo().linkWithCode('abcdefgh23', consentGiven: true);

      expect(link.id, 'pat_doc');
      expect(store.lastWrite, {
        'patientId': 'pat',
        'doctorId': 'doc',
        'patientName': 'Test Patient',
        'doctorName': 'Dr Test',
        'linkCode': 'ABCDEFGH23',
        'status': 'active',
        'consentedAt': serverTime,
      });
      expect(store.queries.last, 'doctorLinks.patientId==pat');
    });

    test('prevents duplicate active link', () async {
      await issueCode();
      uid = 'pat';
      await repo().linkWithCode('ABCDEFGH23', consentGiven: true);
      expect(repo().linkWithCode('ABCDEFGH23', consentGiven: true),
          throwsLink(DoctorLinkErrorCode.alreadyLinked));
    });

    test('lists links with uid-constrained queries', () async {
      await issueCode();
      uid = 'pat';
      await repo().linkWithCode('ABCDEFGH23', consentGiven: true);

      expect((await repo().linksForPatient()).single.doctorId, 'doc');
      expect(store.queries.last, 'doctorLinks.patientId==pat');
      uid = 'doc';
      expect((await repo().linksForDoctor()).single.patientId, 'pat');
      expect(store.queries.last, 'doctorLinks.doctorId==doc');
    });
  });

  group('revocation and reactivation', () {
    Future<DoctorLink> linked() async {
      await issueCode();
      uid = 'pat';
      return repo().linkWithCode('ABCDEFGH23', consentGiven: true);
    }

    test('either party revokes with server revokedAt', () async {
      final link = await linked();
      uid = 'doc';
      await repo().revokeLink(link);
      expect(store.lastWrite, {
        'status': 'revoked',
        'revokedBy': 'doc',
        'revokedAt': serverTime,
      });
      expect(store.links['pat_doc']!['patientId'], 'pat'); // identity kept
    });

    test('outsiders and inactive links cannot be revoked', () async {
      final link = await linked();
      uid = 'stranger';
      expect(repo().revokeLink(link),
          throwsLink(DoctorLinkErrorCode.permissionDenied));
      uid = 'pat';
      await repo().revokeLink(link);
      final revoked = (await repo().linksForPatient()).single;
      expect(repo().revokeLink(revoked),
          throwsLink(DoctorLinkErrorCode.notLinked));
    });

    test('patient-revoked link reactivates with the same valid code', () async {
      final link = await linked();
      await repo().revokeLink(link); // uid = pat
      store.clock = store.clock.add(const Duration(hours: 1));

      final again = await repo().linkWithCode('ABCDEFGH23', consentGiven: true);
      expect(again.isActive, isTrue);
      expect(store.links['pat_doc']!.containsKey('revokedBy'), isFalse);
    });

    test('doctor-revoked link needs a code issued after revocation', () async {
      final link = await linked();
      store.clock = store.clock.add(const Duration(hours: 1));
      uid = 'doc';
      await repo().revokeLink(link);

      uid = 'pat';
      await expectLater(
        repo().linkWithCode('ABCDEFGH23', consentGiven: true),
        throwsLink(DoctorLinkErrorCode.newCodeRequired),
      );

      store.clock = store.clock.add(const Duration(hours: 1));
      final fresh = await issueCode(); // uid = doc
      uid = 'pat';
      final again = await repo().linkWithCode(fresh.code, consentGiven: true);
      expect(again.linkCode, fresh.code);
      expect(store.links['pat_doc']!['status'], 'active');
    });
  });

  group('errors', () {
    test('store permission and network errors pass through', () async {
      await issueCode();
      uid = 'pat';
      store.failNext =
          const DoctorLinkException(DoctorLinkErrorCode.permissionDenied);
      await expectLater(repo().lookupCode('ABCDEFGH23'),
          throwsLink(DoctorLinkErrorCode.permissionDenied));
      store.failNext = const DoctorLinkException(DoctorLinkErrorCode.network);
      await expectLater(
          repo().linksForPatient(), throwsLink(DoctorLinkErrorCode.network));
    });

    test('maps Firestore codes and requires sign-in', () async {
      expect(mapFirestoreErrorCode('permission-denied'),
          DoctorLinkErrorCode.permissionDenied);
      expect(mapFirestoreErrorCode('unavailable'), DoctorLinkErrorCode.network);
      expect(mapFirestoreErrorCode('internal'), DoctorLinkErrorCode.unknown);
      uid = null;
      expect(repo().linksForPatient(),
          throwsLink(DoctorLinkErrorCode.notSignedIn));
    });
  });

  group('doctor dashboard data (Task 3.6)', () {
    void seedLink(String patient, String status) {
      store.profiles[patient] = {
        'displayName': 'Name $patient',
        'email': '$patient@example.com',
        'role': 'patient',
      };
      store.links['${patient}_doc'] = {
        'patientId': patient,
        'doctorId': 'doc',
        'patientName': 'Name $patient',
        'doctorName': 'Dr Test',
        'linkCode': 'ABCDEFGH23',
        'status': status,
      };
    }

    test('returns only active links with readable profiles', () async {
      seedLink('p2', 'active');
      seedLink('p1', 'active');
      seedLink('p3', 'revoked');
      uid = 'doc';
      final patients = await repo().linkedPatientsForDoctor();

      expect(patients.map((p) => p.patientId), ['p1', 'p2']); // sorted
      expect(patients.first.displayName, 'Name p1');
      expect(store.queries, contains('doctorLinks.doctorId==doc'));
      expect(store.queries.where((q) => q.startsWith('users')), isEmpty);
    });

    test('skips profiles the rules deny (revoked meanwhile)', () async {
      seedLink('p1', 'active');
      seedLink('p2', 'active');
      store.deniedProfiles.add('p2');
      uid = 'doc';
      final patients = await repo().linkedPatientsForDoctor();
      expect(patients.single.patientId, 'p1');
    });

    test('empty, non-doctor and network failures', () async {
      uid = 'doc';
      expect(await repo().linkedPatientsForDoctor(), isEmpty);

      uid = 'pat';
      await expectLater(repo().linkedPatientsForDoctor(),
          throwsLink(DoctorLinkErrorCode.notDoctor));

      seedLink('p1', 'active');
      uid = 'doc';
      store.failNext = const DoctorLinkException(DoctorLinkErrorCode.network);
      await expectLater(repo().linkedPatientsForDoctor(),
          throwsLink(DoctorLinkErrorCode.network));
    });
  });
}
