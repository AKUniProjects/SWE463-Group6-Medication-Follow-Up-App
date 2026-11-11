import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/medication.dart';
import 'medication_repository.dart';

class FirestoreMedicationStore implements MedicationStore {
  FirestoreMedicationStore(this.firestore);
  final FirebaseFirestore firestore;
  CollectionReference<Map<String, dynamic>> get _medications =>
      firestore.collection('medications');

  @override
  String newId() => _medications.doc().id;

  @override
  Stream<List<Medication>> watchPatient(String patientId) => _medications
      .where('patientId', isEqualTo: patientId)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => Medication.fromMap(doc.id, doc.data()))
            .toList(),
      );

  @override
  Future<T> transaction<T>(
    String medicationId,
    Future<T> Function(MedicationTransaction transaction) action,
  ) async {
    final document = _medications.doc(medicationId);
    for (var retry = 0; retry < 5; retry++) {
      _FirestoreMedicationTransaction? attempt;
      MedicationException? domainFailure;
      try {
        return await firestore.runTransaction((tx) async {
          attempt = _FirestoreMedicationTransaction(tx, document);
          try {
            return await action(attempt!);
          } on MedicationException catch (error) {
            // Web/platform transaction bridges may wrap a callback exception.
            // Keep its actionable domain meaning (missing/conflict/session).
            domainFailure = error;
            rethrow;
          }
        });
      } catch (error) {
        if (domainFailure != null) throw domainFailure!;
        if (error is! FirebaseException) rethrow;
        // Rules may reject a competing revision/immutable-receipt write before
        // the SDK sees an ABORTED precondition and retries it. Recover ONLY
        // after an authorized server read proves our observed version changed.
        // The next transaction rechecks identity, revision and the dose receipt;
        // stale editor drafts still fail, and real permission denials stay denied.
        final before = attempt?.observed;
        if (error.code == 'permission-denied' && before != null && retry < 4) {
          try {
            final latest = await document.get(
              const GetOptions(source: Source.server),
            );
            if (latest.exists) {
              final current = Medication.fromMap(latest.id, latest.data()!);
              if (current.patientId == before.patientId &&
                  current.revision > before.revision) {
                continue;
              }
            }
          } on FirebaseException {
            // An inaccessible server document cannot authorize a retry.
          }
        }
        throw MedicationException(switch (error.code) {
          'permission-denied' => MedicationError.forbidden,
          'unauthenticated' => MedicationError.signedOut,
          'aborted' => MedicationError.conflict,
          _ => MedicationError.unavailable,
        });
      }
    }
    throw const MedicationException(MedicationError.conflict);
  }
}

class _FirestoreMedicationTransaction implements MedicationTransaction {
  _FirestoreMedicationTransaction(this.tx, this.document);
  final Transaction tx;
  final DocumentReference<Map<String, dynamic>> document;
  Medication? observed;

  DocumentReference<Map<String, dynamic>> _receipt(String doseId) =>
      document.collection('consumptions').doc(doseId);

  @override
  Future<Medication?> read() async {
    final snapshot = await tx.get(document);
    observed = snapshot.exists
        ? Medication.fromMap(snapshot.id, snapshot.data()!)
        : null;
    return observed;
  }

  @override
  Future<bool> hasConsumption(String doseRecordId) async =>
      (await tx.get(_receipt(doseRecordId))).exists;

  @override
  void write(Medication medication) => tx.set(document, medication.toMap());

  @override
  void recordConsumption(
    String doseRecordId,
    Medication medication,
    int units,
  ) {
    tx.set(_receipt(doseRecordId), {
      'patientId': medication.patientId,
      'doseRecordId': doseRecordId,
      'units': units,
      'revision': medication.revision,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
