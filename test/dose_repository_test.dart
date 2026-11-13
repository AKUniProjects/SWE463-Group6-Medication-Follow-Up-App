// Repository rule tests using an in-memory store (NOT the Firestore
// emulator). Server-side enforcement is tested separately in
// firestore_rules_test/dose_rules.test.mjs.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/dose_record.dart';
import 'package:medication_follow_up_app/services/dose_repository.dart';

import 'support/memory_dose_store.dart';

/// A fictional dose of patient-1 on 13 Nov 2026 at 08:00.
DoseRecord dose({
  String id = 'med1_20261113_0800',
  String patientId = 'patient-1',
  DoseStatus status = DoseStatus.scheduled,
  DateTime? scheduledTime,
}) => DoseRecord(
  id: id,
  medicationId: 'med1',
  patientId: patientId,
  medicationName: 'Vitamin D',
  scheduledTime: scheduledTime ?? DateTime(2026, 11, 13, 8),
  status: status,
  doseAmount: 1,
  doseUnit: 'tablet',
);

final tappedAt = DateTime(2026, 11, 13, 8, 4);

void main() {
  late MemoryDoseStore store;
  late String? signedInPatient;
  late StoredDoseRepository repository;

  // setUp runs before EVERY test, so each test starts with an empty store.
  setUp(() {
    store = MemoryDoseStore();
    signedInPatient = 'patient-1';
    repository = StoredDoseRepository(
      store,
      currentPatientId: () => signedInPatient,
    );
  });

  test('toMap/fromMap keeps every field', () {
    final original = dose().copyWith(
      status: DoseStatus.taken,
      confirmedAt: tappedAt,
    );
    final copy = DoseRecord.fromMap(original.id, original.toMap());
    expect(copy.toMap(), original.toMap());
  });

  group('confirm', () {
    test('saves exactly one taken record with confirmedAt (P1-T01)', () async {
      final result = await repository.confirm(dose(), tappedAt);

      expect(result.status, ConfirmStatus.confirmed);
      expect(result.record.status, DoseStatus.taken);
      expect(result.record.confirmedAt, tappedAt); // tap time, not 08:00
      expect(store.documents, hasLength(1));
      expect(store.record(dose().id)!.status, DoseStatus.taken);
    });

    test('a second confirm does not write again (P1-T02)', () async {
      await repository.confirm(dose(), tappedAt);
      final again = await repository.confirm(dose(), DateTime(2026, 11, 13, 9));

      expect(again.status, ConfirmStatus.alreadyTaken);
      expect(again.record.confirmedAt, tappedAt); // first time is kept
      expect(store.writes, 1);
    });

    test('two rapid taps at the same time write once (P1-T02)', () async {
      final results = await Future.wait([
        repository.confirm(dose(), tappedAt),
        repository.confirm(dose(), tappedAt),
      ]);

      expect(results.map((r) => r.status).toSet(), {
        ConfirmStatus.confirmed,
        ConfirmStatus.alreadyTaken,
      });
      expect(store.writes, 1);
    });

    test('an overdue dose can still be confirmed', () async {
      store.seed(dose(status: DoseStatus.overdue));
      final result = await repository.confirm(dose(), tappedAt);
      expect(result.record.status, DoseStatus.taken);
    });

    test('a missed dose cannot be confirmed', () async {
      store.seed(dose(status: DoseStatus.missed));
      await expectLater(
        repository.confirm(dose(), tappedAt),
        throwsA(
          isA<DoseException>().having(
            (e) => e.code,
            'code',
            DoseError.alreadyMissed,
          ),
        ),
      );
      expect(store.record(dose().id)!.status, DoseStatus.missed);
    });

    test('a failed save leaves the dose unconfirmed (P1-T03)', () async {
      store.failWrites = true;
      await expectLater(
        repository.confirm(dose(), tappedAt),
        throwsA(
          isA<DoseException>().having(
            (e) => e.code,
            'code',
            DoseError.unavailable,
          ),
        ),
      );
      expect(store.documents, isEmpty);
    });

    test('signed out or another patient is rejected (P1-T15)', () async {
      signedInPatient = null;
      await expectLater(
        repository.confirm(dose(), tappedAt),
        throwsA(
          isA<DoseException>().having(
            (e) => e.code,
            'code',
            DoseError.signedOut,
          ),
        ),
      );

      signedInPatient = 'patient-2';
      await expectLater(
        repository.confirm(dose(), tappedAt),
        throwsA(
          isA<DoseException>().having(
            (e) => e.code,
            'code',
            DoseError.forbidden,
          ),
        ),
      );
      expect(store.documents, isEmpty);
    });
  });

  group('markStatus', () {
    test('moves scheduled -> overdue -> missed', () async {
      final overdue = await repository.markStatus(dose(), DoseStatus.overdue);
      expect(overdue!.status, DoseStatus.overdue);

      final missed = await repository.markStatus(dose(), DoseStatus.missed);
      expect(missed!.status, DoseStatus.missed);
      expect(store.record(dose().id)!.status, DoseStatus.missed);
    });

    test('never overwrites a taken dose (P1-T12)', () async {
      await repository.confirm(dose(), tappedAt);
      // The screen still has the old "scheduled" copy of the dose.
      final result = await repository.markStatus(dose(), DoseStatus.missed);

      expect(result, isNull);
      expect(store.record(dose().id)!.status, DoseStatus.taken);
    });

    test('repeating the same change writes once (P1-T11)', () async {
      await repository.markStatus(dose(), DoseStatus.overdue);
      final second = await repository.markStatus(dose(), DoseStatus.overdue);

      expect(second, isNull);
      expect(store.writes, 1);
    });

    test('only overdue and missed can be set this way', () async {
      for (final status in [DoseStatus.taken, DoseStatus.scheduled]) {
        await expectLater(
          repository.markStatus(dose(), status),
          throwsA(
            isA<DoseException>().having(
              (e) => e.code,
              'code',
              DoseError.invalid,
            ),
          ),
        );
      }
    });
  });

  group('watchRange', () {
    test('shows only this patient within the period, and updates', () async {
      store.seed(
        dose(
          id: 'med1_20261101_0800',
          status: DoseStatus.missed,
          scheduledTime: DateTime(2026, 11, 1, 8),
        ),
      ); // outside the week
      store.seed(
        dose(
          id: 'other_20261113_0800',
          patientId: 'patient-2',
          status: DoseStatus.missed,
        ),
      ); // another patient

      final emissions = <List<DoseRecord>>[];
      final subscription = repository
          .watchRange(
            'patient-1',
            DateTime(2026, 11, 9),
            DateTime(2026, 11, 16),
          )
          .listen(emissions.add);
      await pumpEventQueue(); // let the stream deliver its first list

      expect(emissions.last, isEmpty);

      await repository.confirm(dose(), tappedAt);
      await pumpEventQueue();
      expect(emissions.last.map((d) => d.id), [dose().id]); // read-after-write

      await subscription.cancel();
    });

    test("another patient's history is refused", () async {
      await expectLater(
        repository.watchRange(
          'patient-2',
          DateTime(2026, 11, 9),
          DateTime(2026, 11, 16),
        ),
        emitsError(isA<DoseException>()),
      );
    });
  });

  test('a held save can be observed as pending', () async {
    store.holdWrites = Completer<void>();
    var finished = false;
    final pending = repository
        .confirm(dose(), tappedAt)
        .then((_) => finished = true);
    await pumpEventQueue();
    expect(finished, isFalse); // the provider can show a spinner here

    store.holdWrites!.complete();
    await pending;
    expect(finished, isTrue);
  });
}
