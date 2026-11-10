import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/doctor_link.dart';
import 'package:medication_follow_up_app/services/doctor_link_repository.dart';
import 'package:medication_follow_up_app/state/doctor_link_provider.dart';

final now = DateTime.utc(2026, 11, 10, 12);

DoctorCode code(
  String id, {
  bool active = true,
  DateTime? createdAt,
}) =>
    DoctorCode(
      code: id,
      doctorId: 'doc',
      doctorName: 'Dr Test',
      active: active,
      createdAt: createdAt ?? now.subtract(const Duration(days: 1)),
    );

/// In-memory fake; set [gate] to hold the next myCodes() call open.
class FakeRepo implements DoctorLinkRepository {
  List<DoctorCode> stored = [];
  int myCodesCalls = 0;
  int createCalls = 0;
  Completer<void>? gate;
  DoctorLinkException? failMyCodes;
  DoctorLinkException? failCreate;
  DoctorLinkException? failDeactivate;
  bool ignoreDeactivate = false;
  int _next = 0;

  @override
  Future<List<DoctorCode>> myCodes() async {
    myCodesCalls++;
    final g = gate;
    if (g != null) {
      gate = null;
      await g.future;
    }
    final f = failMyCodes;
    if (f != null) throw f;
    return List.of(stored.reversed); // newest first
  }

  @override
  Future<DoctorCode> createCode() async {
    createCalls++;
    final f = failCreate;
    if (f != null) throw f;
    // Server assigns createdAt; the returned draft has none.
    final id = 'NEWCODE${_next++}AA'.substring(0, 10);
    stored.add(code(id, createdAt: now));
    return DoctorCode(
      code: id,
      doctorId: 'doc',
      doctorName: 'Dr Test',
      active: true,
    );
  }

  @override
  Future<void> deactivateCode(String c) async {
    final f = failDeactivate;
    if (f != null) throw f;
    if (ignoreDeactivate) return;
    final i = stored.indexWhere((x) => x.code == c);
    stored[i] = code(c, active: false, createdAt: stored[i].createdAt);
  }

  @override
  Future<DoctorCode> replaceCode(String oldCode) async {
    final fresh = await createCode();
    await deactivateCode(oldCode);
    return fresh;
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late FakeRepo repo;
  late DoctorLinkProvider provider;

  setUp(() {
    repo = FakeRepo();
    provider = DoctorLinkProvider(repo, now: () => now)
      ..updateSession(uid: 'doc', isDoctor: true);
  });

  tearDown(() => provider.dispose());

  test('initial state is empty and not loaded', () {
    final fresh = DoctorLinkProvider(repo);
    expect(fresh.codes, isEmpty);
    expect(fresh.hasLoaded, isFalse);
    expect(fresh.currentCode, isNull);
    expect(fresh.canManageCodes, isFalse);
    expect(repo.myCodesCalls, 0);
    fresh.dispose();
  });

  test('loads codes and selects newest usable code with expiry', () async {
    repo.stored = [code('OLDCODE234'), code('NEWERCD234')];
    expect(await provider.loadCodes(), isTrue);
    expect(provider.codes.length, 2);
    expect(provider.currentCode!.code, 'NEWERCD234');
    expect(provider.currentCodeExpiresAt,
        provider.currentCode!.createdAt!.add(doctorCodeValidity));
  });

  test('empty list loads with no current code', () async {
    expect(await provider.loadCodes(), isTrue);
    expect(provider.hasLoaded, isTrue);
    expect(provider.currentCode, isNull);
  });

  test('expired and inactive codes are never current', () async {
    repo.stored = [
      code('EXPIRED234', createdAt: now.subtract(const Duration(days: 31))),
      code('INACTIVE23', active: false),
    ];
    await provider.loadCodes();
    expect(provider.codes.length, 2);
    expect(provider.currentCode, isNull);
  });

  test('createCode refreshes to obtain server createdAt', () async {
    expect(await provider.createCode(), isTrue);
    expect(repo.myCodesCalls, 1);
    expect(provider.currentCode!.createdAt, now);
    expect(provider.currentCodeExpiresAt, now.add(doctorCodeValidity));
  });

  test('replace deactivates the old code', () async {
    repo.stored = [code('OLDCODE234')];
    await provider.loadCodes();
    expect(await provider.replaceCurrentCode(), isTrue);
    expect(provider.currentCode!.code, isNot('OLDCODE234'));
    expect(provider.codes.firstWhere((c) => c.code == 'OLDCODE234').active,
        isFalse);
    expect(provider.errorMessage, isNull);
  });

  test('replace reports partial failure when old code stays active', () async {
    repo.stored = [code('OLDCODE234')];
    await provider.loadCodes();
    repo.failDeactivate =
        const DoctorLinkException(DoctorLinkErrorCode.network);
    expect(await provider.replaceCurrentCode(), isFalse);
    expect(provider.errorMessage, contains('old code is still active'));
    expect(provider.isBusy, isFalse);

    // Recoverable: retry deactivation of the old code.
    repo.failDeactivate = null;
    expect(await provider.deactivateCode('OLDCODE234'), isTrue);
    expect(provider.errorMessage, isNull);
  });

  test('replace does not claim success if repository silently keeps old',
      () async {
    repo.stored = [code('OLDCODE234')];
    await provider.loadCodes();
    repo.ignoreDeactivate = true;
    expect(await provider.replaceCurrentCode(), isFalse);
    expect(provider.errorMessage, contains('still active'));
  });

  test('deactivate verifies and reports failures', () async {
    repo.stored = [code('OLDCODE234')];
    await provider.loadCodes();
    expect(await provider.deactivateCode('OLDCODE234'), isTrue);
    expect(provider.currentCode, isNull);
  });

  test('prevents duplicate actions while busy', () async {
    final gate = repo.gate = Completer<void>();
    final first = provider.createCode();
    expect(provider.isBusy, isTrue);
    expect(await provider.createCode(), isFalse);
    expect(await provider.loadCodes(), isFalse);
    gate.complete();
    expect(await first, isTrue);
    expect(repo.createCalls, 1);
  });

  test('failures show friendly errors and allow retry', () async {
    repo.failCreate = const DoctorLinkException(DoctorLinkErrorCode.network);
    expect(await provider.createCode(), isFalse);
    expect(provider.errorMessage, contains('Network error'));
    expect(provider.isBusy, isFalse);

    repo.failCreate = null;
    expect(await provider.createCode(), isTrue);
    expect(provider.errorMessage, isNull);

    repo.failMyCodes =
        const DoctorLinkException(DoctorLinkErrorCode.permissionDenied);
    expect(await provider.loadCodes(), isFalse);
    expect(provider.codes, isNotEmpty); // previous list kept
    expect(provider.isLoading, isFalse);
  });

  test('patients and signed-out users cannot act or read', () async {
    provider.updateSession(uid: 'pat', isDoctor: false);
    expect(await provider.loadCodes(), isFalse);
    expect(await provider.createCode(), isFalse);
    expect(provider.errorMessage, contains('Only doctor accounts'));

    provider.updateSession(uid: null, isDoctor: false);
    expect(provider.errorMessage, isNull);
    expect(await provider.loadCodes(), isFalse);
    expect(repo.myCodesCalls, 0);
    expect(repo.createCalls, 0);
  });

  test('sign-out and account switch clear cached codes', () async {
    repo.stored = [code('OLDCODE234')];
    await provider.loadCodes();
    provider.updateSession(uid: null, isDoctor: false);
    expect(provider.codes, isEmpty);
    expect(provider.hasLoaded, isFalse);

    provider.updateSession(uid: 'doc2', isDoctor: true);
    expect(provider.codes, isEmpty);
    expect(provider.canManageCodes, isTrue);
  });

  test('stale response from previous session is discarded', () async {
    repo.stored = [code('OLDCODE234')];
    final gate = repo.gate = Completer<void>();
    final pending = provider.loadCodes();
    expect(provider.isLoading, isTrue);

    provider.updateSession(uid: 'doc2', isDoctor: true); // switch account
    gate.complete();
    expect(await pending, isFalse);
    expect(provider.codes, isEmpty);
    expect(provider.isLoading, isFalse);
  });
}
