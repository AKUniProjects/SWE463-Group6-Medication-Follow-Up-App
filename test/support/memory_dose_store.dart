import 'dart:async';

import 'package:medication_follow_up_app/models/dose_record.dart';
import 'package:medication_follow_up_app/services/dose_repository.dart';

/// Test double for Firestore's `doseRecords` collection. Records go through
/// toMap/fromMap like real documents. Transactions run one at a time, like
/// Firestore, so double-tap tests are meaningful.
class MemoryDoseStore implements DoseStore {
  final documents = <String, Map<String, dynamic>>{};
  final _changes = StreamController<void>.broadcast();
  Future<void> _tail = Future.value();

  /// Set to make the next operations fail like a network error.
  bool failReads = false;
  bool failWrites = false;

  /// Complete this to let a held transaction continue (tests pending UI).
  Completer<void>? holdWrites;

  int transactions = 0;
  int writes = 0;

  /// Puts a record straight into the store (test setup).
  void seed(DoseRecord record) => documents[record.id] = record.toMap();

  DoseRecord? record(String id) {
    final data = documents[id];
    return data == null ? null : DoseRecord.fromMap(id, data);
  }

  List<DoseRecord> _patientRecords(String patientId) => [
    for (final entry in documents.entries)
      if (entry.value['patientId'] == patientId)
        DoseRecord.fromMap(entry.key, entry.value),
  ];

  @override
  Stream<List<DoseRecord>> watchPatient(String patientId) {
    // Like Firestore snapshots(): send the current list when someone
    // listens, then a fresh list after every write.
    StreamSubscription<void>? changes;
    late final StreamController<List<DoseRecord>> controller;
    controller = StreamController<List<DoseRecord>>(
      onListen: () {
        if (failReads) {
          controller.addError(const DoseException(DoseError.unavailable));
          return;
        }
        controller.add(_patientRecords(patientId));
        changes = _changes.stream.listen(
          (_) => controller.add(_patientRecords(patientId)),
        );
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<T> transaction<T>(
    String doseId,
    Future<T> Function(DoseTransaction transaction) action,
  ) async {
    transactions++;
    // Wait for the previous transaction to finish (one at a time).
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await previous;
      final hold = holdWrites;
      if (hold != null) await hold.future;
      final tx = _MemoryTransaction(doseId, documents[doseId]);
      final result = await action(tx);
      final written = tx.written;
      if (written != null) {
        if (failWrites) throw StateError('simulated network failure');
        documents[doseId] = written.toMap();
        writes++;
        _changes.add(null);
      }
      return result;
    } finally {
      done.complete();
    }
  }
}

class _MemoryTransaction implements DoseTransaction {
  _MemoryTransaction(this.id, this.data);

  final String id;
  final Map<String, dynamic>? data;
  DoseRecord? written;

  @override
  Future<DoseRecord?> read() async =>
      data == null ? null : DoseRecord.fromMap(id, data!);

  @override
  void write(DoseRecord record) => written = record;
}
