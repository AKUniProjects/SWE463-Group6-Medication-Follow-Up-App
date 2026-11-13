import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/dose_record.dart';
import 'dose_repository.dart';

/// Firestore storage for `doseRecords/{doseId}`. No business rules here:
/// they are in StoredDoseRepository and, on the server, firestore.rules.
class FirestoreDoseStore implements DoseStore {
  FirestoreDoseStore(this.firestore);

  final FirebaseFirestore firestore;

  CollectionReference<Map<String, dynamic>> get _doses =>
      firestore.collection('doseRecords');

  /// Query scoped to one patient (the rules reject unscoped queries).
  /// Date filtering is done in the repository, so no composite index is
  /// needed.
  @override
  Stream<List<DoseRecord>> watchPatient(String patientId) => _doses
      .where('patientId', isEqualTo: patientId)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (doc) => DoseRecord.fromMap(doc.id, _fromFirestore(doc.data())),
            )
            .toList(),
      );

  @override
  Future<T> transaction<T>(
    String doseId,
    Future<T> Function(DoseTransaction transaction) action,
  ) async {
    final document = _doses.doc(doseId);
    DoseException? domainFailure;
    try {
      return await firestore.runTransaction((tx) async {
        try {
          return await action(_FirestoreDoseTransaction(tx, document));
        } on DoseException catch (error) {
          // Some platforms wrap errors thrown inside a transaction. Keep the
          // original so the UI shows the right message.
          domainFailure = error;
          rethrow;
        }
      });
    } catch (error) {
      final failure = domainFailure;
      if (failure != null) throw failure;
      if (error is! FirebaseException) rethrow;
      throw DoseException(switch (error.code) {
        'permission-denied' => DoseError.forbidden,
        'unauthenticated' => DoseError.signedOut,
        _ => DoseError.unavailable,
      });
    }
  }
}

class _FirestoreDoseTransaction implements DoseTransaction {
  _FirestoreDoseTransaction(this.tx, this.document);

  final Transaction tx;
  final DocumentReference<Map<String, dynamic>> document;

  @override
  Future<DoseRecord?> read() async {
    final snapshot = await tx.get(document);
    final data = snapshot.data();
    return data == null
        ? null
        : DoseRecord.fromMap(snapshot.id, _fromFirestore(data));
  }

  /// Firestore turns `DateTime` values into `Timestamp`s automatically.
  @override
  void write(DoseRecord record) => tx.set(document, record.toMap());
}

/// Firestore returns dates as `Timestamp`; the model expects `DateTime`.
Map<String, dynamic> _fromFirestore(Map<String, dynamic> data) => {
  for (final entry in data.entries)
    entry.key: switch (entry.value) {
      final Timestamp time => time.toDate(),
      final value => value,
    },
};
