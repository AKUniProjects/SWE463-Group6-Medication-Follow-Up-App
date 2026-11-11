import 'dart:async';
import 'dart:convert';

import 'package:medication_follow_up_app/models/medication.dart';
import 'package:medication_follow_up_app/services/medication_repository.dart';

/// Test double only. JSON round trips exercise the same serialized fields as
/// Firestore; actual authorization/persistence is tested with the emulator.
class MemoryMedicationStore implements MedicationStore {
  final documents = <String, Map<String, dynamic>>{};
  final receipts = <String, Set<String>>{};
  final _changes = StreamController<void>.broadcast();
  Future<void>? _tail;
  int _counter = 0;
  bool failReads = false;
  bool failWrites = false;
  Completer<void>? holdWrites;
  int transactions = 0;

  MemoryMedicationStore();
  MemoryMedicationStore.restore(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    for (final entry in (data['documents'] as Map<String, dynamic>).entries) {
      documents[entry.key] = Map<String, dynamic>.from(entry.value as Map);
    }
    for (final entry in (data['receipts'] as Map<String, dynamic>).entries) {
      receipts[entry.key] = (entry.value as List).cast<String>().toSet();
    }
    _counter = data['counter'] as int;
  }
  String export() => jsonEncode({
    'documents': documents,
    'receipts': receipts.map((key, value) => MapEntry(key, value.toList())),
    'counter': _counter,
  });
  @override
  String newId() => 'med-${++_counter}';

  List<Medication> records(String patientId) => documents.entries
      .map((e) => Medication.fromMap(e.key, e.value))
      .where((m) => m.patientId == patientId)
      .toList();

  void emit() => _changes.add(null);
  void emitError() => _changes.addError(StateError('controlled read failure'));

  @override
  Stream<List<Medication>> watchPatient(String patientId) async* {
    if (failReads) throw StateError('controlled read failure');
    yield records(patientId);
    await for (final _ in _changes.stream) {
      yield records(patientId);
    }
  }

  @override
  Future<T> transaction<T>(
    String medicationId,
    Future<T> Function(MedicationTransaction transaction) action,
  ) {
    transactions++;
    final result = (_tail ?? Future<void>.value()).then((_) async {
      await holdWrites?.future;
      if (failWrites) throw StateError('controlled write failure');
      final tx = _MemoryTransaction(this, medicationId);
      final result = await action(tx);
      if (tx.pending != null) {
        documents[medicationId] = tx.pending!.toMap();
        receipts.putIfAbsent(medicationId, () => {}).addAll(tx.newReceipts);
        emit();
      }
      return result;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> close() => _changes.close();
}

class _MemoryTransaction implements MedicationTransaction {
  _MemoryTransaction(this.store, this.id);
  final MemoryMedicationStore store;
  final String id;
  Medication? pending;
  final newReceipts = <String>{};
  @override
  Future<Medication?> read() async => store.documents[id] == null
      ? null
      : Medication.fromMap(id, store.documents[id]!);
  @override
  Future<bool> hasConsumption(String doseRecordId) async =>
      store.receipts[id]?.contains(doseRecordId) ?? false;
  @override
  void write(Medication medication) => pending = medication;
  @override
  void recordConsumption(
    String doseRecordId,
    Medication medication,
    int units,
  ) => newReceipts.add(doseRecordId);
}

Medication medicationDraft({
  String patientId = 'patient-1',
  String name = 'Fictional vitamin',
  double dose = 1,
  String doseUnit = 'tablet',
  int stock = 8,
  int? unitsPerDose = 1,
  List<String> times = const ['08:00', '20:00'],
}) => Medication(
  id: '',
  patientId: patientId,
  name: name,
  doseAmount: dose,
  doseUnit: doseUnit,
  scheduledTimes: times,
  stockAmount: stock,
  refillThreshold: 7,
  stockUnit: 'tablet',
  unitsPerDose: unitsPerDose,
);
