import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/doctor_link.dart';
import 'doctor_link_repository.dart';

/// Thin Firestore wrapper (replaceable in tests). Fields listed in
/// `serverTimeFields` are written as `FieldValue.serverTimestamp()`.
/// Implementations throw [DoctorLinkException] for Firestore failures.
abstract class DoctorLinkStore {
  Future<Map<String, dynamic>?> readProfile(String uid);

  Future<Map<String, dynamic>?> readCode(String code);

  /// Writes the code only if no document exists; returns false on collision.
  Future<bool> createCodeIfAbsent(
    String code,
    Map<String, dynamic> fields,
    List<String> serverTimeFields,
  );

  Future<List<MapEntry<String, Map<String, dynamic>>>> codesWhereDoctor(
    String doctorId,
  );

  Future<void> updateCode(String code, Map<String, dynamic> fields);

  /// Equality-constrained link query: [field] is `patientId` or `doctorId`.
  Future<List<MapEntry<String, Map<String, dynamic>>>> linksWhere(
    String field,
    String uid,
  );

  /// Full replace (create or reactivate).
  Future<void> setLink(
    String linkId,
    Map<String, dynamic> fields,
    List<String> serverTimeFields,
  );

  /// Partial update of only the given fields.
  Future<void> updateLink(
    String linkId,
    Map<String, dynamic> fields,
    List<String> serverTimeFields,
  );
}

/// Maps a FirebaseException code to a safe [DoctorLinkErrorCode].
DoctorLinkErrorCode mapFirestoreErrorCode(String code) {
  switch (code) {
    case 'permission-denied':
    case 'unauthenticated':
      return DoctorLinkErrorCode.permissionDenied;
    case 'unavailable':
    case 'deadline-exceeded':
    case 'network-request-failed':
      return DoctorLinkErrorCode.network;
    default:
      return DoctorLinkErrorCode.unknown;
  }
}

class FirestoreDoctorLinkStore implements DoctorLinkStore {
  FirestoreDoctorLinkStore(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _codes =>
      _db.collection('doctorCodes');
  CollectionReference<Map<String, dynamic>> get _links =>
      _db.collection('doctorLinks');

  Map<String, dynamic> _withServerTime(
    Map<String, dynamic> fields,
    List<String> serverTimeFields,
  ) =>
      {
        ...fields,
        for (final f in serverTimeFields) f: FieldValue.serverTimestamp(),
      };

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      throw DoctorLinkException(mapFirestoreErrorCode(e.code));
    }
  }

  List<MapEntry<String, Map<String, dynamic>>> _entries(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) =>
      [for (final d in snap.docs) MapEntry(d.id, d.data())];

  @override
  Future<Map<String, dynamic>?> readProfile(String uid) => _guard(() async {
        final snap = await _db.collection('users').doc(uid).get();
        return snap.data();
      });

  @override
  Future<Map<String, dynamic>?> readCode(String code) => _guard(() async {
        final snap = await _codes.doc(code).get();
        return snap.data();
      });

  @override
  Future<bool> createCodeIfAbsent(
    String code,
    Map<String, dynamic> fields,
    List<String> serverTimeFields,
  ) =>
      _guard(() {
        // The Flutter SDK has no create-only write, so read and write in one
        // transaction; Security Rules also reject overwrites.
        final ref = _codes.doc(code);
        return _db.runTransaction<bool>((tx) async {
          final existing = await tx.get(ref);
          if (existing.exists) return false;
          tx.set(ref, _withServerTime(fields, serverTimeFields));
          return true;
        });
      });

  @override
  Future<List<MapEntry<String, Map<String, dynamic>>>> codesWhereDoctor(
    String doctorId,
  ) =>
      _guard(() async =>
          _entries(await _codes.where('doctorId', isEqualTo: doctorId).get()));

  @override
  Future<void> updateCode(String code, Map<String, dynamic> fields) =>
      _guard(() => _codes.doc(code).update(fields));

  @override
  Future<List<MapEntry<String, Map<String, dynamic>>>> linksWhere(
    String field,
    String uid,
  ) {
    assert(field == 'patientId' || field == 'doctorId');
    return _guard(
        () async => _entries(await _links.where(field, isEqualTo: uid).get()));
  }

  @override
  Future<void> setLink(
    String linkId,
    Map<String, dynamic> fields,
    List<String> serverTimeFields,
  ) =>
      _guard(() =>
          _links.doc(linkId).set(_withServerTime(fields, serverTimeFields)));

  @override
  Future<void> updateLink(
    String linkId,
    Map<String, dynamic> fields,
    List<String> serverTimeFields,
  ) =>
      _guard(() =>
          _links.doc(linkId).update(_withServerTime(fields, serverTimeFields)));
}

class FirebaseDoctorLinkRepository implements DoctorLinkRepository {
  FirebaseDoctorLinkRepository({
    DoctorLinkStore? store,
    String? Function()? currentUid,
    String Function()? generateCode,
    DateTime Function()? now,
    this.maxCodeAttempts = 5,
  })  : _store = store ?? FirestoreDoctorLinkStore(FirebaseFirestore.instance),
        _currentUid =
            currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
        _generateCode = generateCode ?? generateSecureDoctorCode,
        _now = now ?? DateTime.now;

  final DoctorLinkStore _store;
  final String? Function() _currentUid;
  final String Function() _generateCode;
  final DateTime Function() _now;
  final int maxCodeAttempts;

  String _requireUid() {
    final uid = _currentUid();
    if (uid == null) {
      throw const DoctorLinkException(DoctorLinkErrorCode.notSignedIn);
    }
    return uid;
  }

  Future<Map<String, dynamic>> _requireRole(String uid, String role) async {
    final profile = await _store.readProfile(uid);
    if (profile == null || profile['role'] != role) {
      throw DoctorLinkException(
        role == 'doctor'
            ? DoctorLinkErrorCode.notDoctor
            : DoctorLinkErrorCode.notPatient,
      );
    }
    return profile;
  }

  /// Wraps unexpected failures; [DoctorLinkException]s pass through.
  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DoctorLinkException {
      rethrow;
    } catch (_) {
      throw const DoctorLinkException(DoctorLinkErrorCode.unknown);
    }
  }

  // ------------------------------------------------------------ doctor

  @override
  Future<DoctorCode> createCode() => _run(() async {
        final uid = _requireUid();
        final profile = await _requireRole(uid, 'doctor');
        final name = profile['displayName'] as String;

        for (var attempt = 0; attempt < maxCodeAttempts; attempt++) {
          final code = _generateCode();
          final draft = DoctorCode(
            code: code,
            doctorId: uid,
            doctorName: name,
            active: true,
          );
          final created = await _store.createCodeIfAbsent(
            code,
            draft.toCreateFields(),
            DoctorCode.createServerTimeFields,
          );
          if (created) return draft;
        }
        throw const DoctorLinkException(
          DoctorLinkErrorCode.codeGenerationFailed,
        );
      });

  @override
  Future<List<DoctorCode>> myCodes() => _run(() async {
        final uid = _requireUid();
        final codes = [
          for (final e in await _store.codesWhereDoctor(uid))
            DoctorCode.fromMap(e.key, e.value),
        ];
        codes.sort((a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
        return codes;
      });

  @override
  Future<void> deactivateCode(String code) => _run(() async {
        _requireUid();
        final canonical = normalizeDoctorCode(code);
        if (!isValidDoctorCode(canonical)) {
          throw const DoctorLinkException(
            DoctorLinkErrorCode.invalidCodeFormat,
          );
        }
        await _store.updateCode(canonical, {'active': false});
      });

  @override
  Future<DoctorCode> replaceCode(String oldCode) => _run(() async {
        // Create first so the doctor is never left without a code.
        final fresh = await createCode();
        await deactivateCode(oldCode);
        return fresh;
      });

  @override
  Future<List<DoctorLink>> linksForDoctor({bool activeOnly = true}) =>
      _run(() async => _links('doctorId', _requireUid(), activeOnly));

  // ----------------------------------------------------------- patient

  @override
  Future<DoctorCode> lookupCode(String input) => _run(() async {
        _requireUid();
        final canonical = normalizeDoctorCode(input);
        if (!isValidDoctorCode(canonical)) {
          throw const DoctorLinkException(
            DoctorLinkErrorCode.invalidCodeFormat,
          );
        }
        final data = await _store.readCode(canonical);
        if (data == null) {
          throw const DoctorLinkException(DoctorLinkErrorCode.codeNotFound);
        }
        final code = DoctorCode.fromMap(canonical, data);
        if (!code.active) {
          throw const DoctorLinkException(DoctorLinkErrorCode.codeInactive);
        }
        if (!code.isUsableAt(_now())) {
          throw const DoctorLinkException(DoctorLinkErrorCode.codeExpired);
        }
        return code;
      });

  @override
  Future<DoctorLink> linkWithCode(
    String input, {
    required bool consentGiven,
  }) =>
      _run(() async {
        if (!consentGiven) {
          throw const DoctorLinkException(DoctorLinkErrorCode.consentRequired);
        }
        final uid = _requireUid();
        final profile = await _requireRole(uid, 'patient');
        final code = await lookupCode(input);
        if (code.doctorId == uid) {
          throw const DoctorLinkException(DoctorLinkErrorCode.ownCode);
        }

        final existing = (await _links('patientId', uid, false))
            .where((l) => l.doctorId == code.doctorId)
            .firstOrNull;
        if (existing != null) {
          if (existing.isActive) {
            throw const DoctorLinkException(DoctorLinkErrorCode.alreadyLinked);
          }
          // A doctor's revocation can only be undone with a newer code.
          final revokedAt = existing.revokedAt;
          final codeTime = code.createdAt;
          if (existing.revokedBy == existing.doctorId &&
              (revokedAt == null ||
                  codeTime == null ||
                  !codeTime.isAfter(revokedAt))) {
            throw const DoctorLinkException(
              DoctorLinkErrorCode.newCodeRequired,
            );
          }
        }

        final link = DoctorLink(
          id: doctorLinkId(uid, code.doctorId),
          patientId: uid,
          doctorId: code.doctorId,
          linkCode: code.code,
          status: LinkStatus.active,
          patientName: profile['displayName'] as String,
          doctorName: code.doctorName,
        );
        // Full replace: creates, or reactivates and clears revocation fields.
        await _store.setLink(
          link.id,
          link.toConsentFields(),
          DoctorLink.consentServerTimeFields,
        );
        return link;
      });

  @override
  Future<List<DoctorLink>> linksForPatient({bool activeOnly = false}) =>
      _run(() async => _links('patientId', _requireUid(), activeOnly));

  // ------------------------------------------------------------ shared

  @override
  Future<void> revokeLink(DoctorLink link) => _run(() async {
        final uid = _requireUid();
        if (uid != link.patientId && uid != link.doctorId) {
          throw const DoctorLinkException(
            DoctorLinkErrorCode.permissionDenied,
          );
        }
        if (!link.isActive) {
          throw const DoctorLinkException(DoctorLinkErrorCode.notLinked);
        }
        await _store.updateLink(
          doctorLinkId(link.patientId, link.doctorId),
          DoctorLink.revocationFields(uid),
          DoctorLink.revocationServerTimeFields,
        );
      });

  Future<List<DoctorLink>> _links(
    String field,
    String uid,
    bool activeOnly,
  ) async {
    final links = [
      for (final e in await _store.linksWhere(field, uid))
        DoctorLink.fromMap(e.key, e.value),
    ];
    return activeOnly ? links.where((l) => l.isActive).toList() : links;
  }
}
