import 'dart:async';

import 'package:medication_follow_up_app/models/doctor_link.dart';
import 'package:medication_follow_up_app/services/doctor_link_repository.dart';

// Shared fake for patient-linking tests (no Firebase).
const validCode = 'ABCDEFGH23';

DoctorCode doctorCode(String code) => DoctorCode(
      code: code,
      doctorId: 'doc',
      doctorName: 'Dr Test',
      active: true,
      createdAt: DateTime.utc(2026, 11, 1),
    );

/// Simulates repository behaviour, including the revocation policy.
class FakeRepo implements DoctorLinkRepository {
  final Map<String, DoctorCode> codes = {validCode: doctorCode(validCode)};
  final Map<String, DoctorLink> links = {};
  final List<bool> consentPassed = [];
  int linkCalls = 0;
  Completer<void>? gate;
  DoctorLinkException? failNext;
  String patientId = 'pat';

  Future<void> _step() async {
    final g = gate;
    if (g != null) await g.future;
    final f = failNext;
    failNext = null;
    if (f != null) throw f;
  }

  @override
  Future<DoctorCode> lookupCode(String input) async {
    await _step();
    final c = normalizeDoctorCode(input);
    if (!isValidDoctorCode(c)) {
      throw const DoctorLinkException(DoctorLinkErrorCode.invalidCodeFormat);
    }
    final code = codes[c];
    if (code == null) {
      throw const DoctorLinkException(DoctorLinkErrorCode.codeNotFound);
    }
    if (!code.active) {
      throw const DoctorLinkException(DoctorLinkErrorCode.codeInactive);
    }
    return code;
  }

  @override
  Future<DoctorLink> linkWithCode(
    String input, {
    required bool consentGiven,
    required String expectedDoctorId,
  }) async {
    linkCalls++;
    consentPassed.add(consentGiven);
    final code = await lookupCode(input);
    if (code.doctorId != expectedDoctorId) {
      throw const DoctorLinkException(DoctorLinkErrorCode.doctorChanged);
    }
    final id = doctorLinkId(patientId, code.doctorId);
    final existing = links[id];
    if (existing != null && existing.isActive) {
      throw const DoctorLinkException(DoctorLinkErrorCode.alreadyLinked);
    }
    if (existing != null &&
        existing.revokedBy == existing.doctorId &&
        !code.createdAt!.isAfter(existing.revokedAt!)) {
      throw const DoctorLinkException(DoctorLinkErrorCode.newCodeRequired);
    }
    final created = DoctorLink(
      id: id,
      patientId: patientId,
      doctorId: code.doctorId,
      linkCode: code.code,
      status: LinkStatus.active,
      doctorName: code.doctorName,
    );
    if (failListAfterLink) {
      // Simulate the write "succeeding" but not being readable afterwards.
      failListAfterLink = false;
      _failNextList = true;
      return created;
    }
    return links[id] = created;
  }

  /// When true, the next successful link is followed by a failed list read.
  bool failListAfterLink = false;
  bool _failNextList = false;

  @override
  Future<List<DoctorLink>> linksForPatient({bool activeOnly = false}) async {
    await _step();
    if (_failNextList) {
      _failNextList = false;
      throw const DoctorLinkException(DoctorLinkErrorCode.network);
    }
    return links.values.where((l) => l.patientId == patientId).toList();
  }

  @override
  Future<void> revokeLink(DoctorLink link) async {
    await _step();
    links[link.id] = DoctorLink(
      id: link.id,
      patientId: link.patientId,
      doctorId: link.doctorId,
      linkCode: link.linkCode,
      status: LinkStatus.revoked,
      revokedBy: patientId,
      revokedAt: DateTime.utc(2026, 11, 5),
    );
  }

  void revokeAsDoctor(String id, DateTime at) {
    final l = links[id]!;
    links[id] = DoctorLink(
      id: id,
      patientId: l.patientId,
      doctorId: l.doctorId,
      linkCode: l.linkCode,
      status: LinkStatus.revoked,
      revokedBy: l.doctorId,
      revokedAt: at,
    );
  }

  // Doctor side, for the preservation test.
  final List<DoctorCode> doctorCodes = [];

  @override
  Future<List<DoctorCode>> myCodes() async => List.of(doctorCodes);

  @override
  Future<DoctorCode> createCode() async {
    final c = DoctorCode(
      code: 'NEWCODE234',
      doctorId: 'doc',
      doctorName: 'Dr Test',
      active: true,
      createdAt: DateTime.now(),
    );
    doctorCodes.add(c);
    return c;
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
