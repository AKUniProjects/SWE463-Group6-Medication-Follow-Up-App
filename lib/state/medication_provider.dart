import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/medication.dart';
import '../services/medication_repository.dart';
import '../services/medication_reminders.dart';

class MedicationProvider extends ChangeNotifier {
  MedicationProvider(this.repository, {MedicationReminderGateway? reminders})
    : _reminders = MedicationReminderCoordinator(
        reminders ?? UnavailableMedicationReminders(),
      );

  final MedicationRepository repository;
  final MedicationReminderCoordinator _reminders;
  StreamSubscription<List<Medication>>? _subscription;
  List<Medication> _all = const [];
  String? _patientId;
  int _session = 0;
  int _read = 0;
  bool _disposed = false;
  bool isLoading = false;
  bool isBusy = false;
  String? errorMessage;
  String? writeError;
  String? reminderError;
  Future<void> _effects = Future.value();

  String? get patientId => _patientId;
  bool get remindersAvailable => _reminders.gateway.isAvailable;
  List<Medication> get activeMedications =>
      List.unmodifiable(_all.where((m) => m.isActive));
  List<Medication> get allMedications => List.unmodifiable(_all);

  Medication? find(String id) {
    for (final m in _all) {
      if (m.id == id && m.patientId == _patientId) return m;
    }
    return null;
  }

  /// Driven by AuthProvider's verified patient UID. Synchronously drops the
  /// previous account's records and defers IO outside ProxyProvider.build.
  void updateSession(String? patientId) {
    if (_patientId == patientId) return;
    final previous = _patientId;
    _patientId = patientId;
    final session = ++_session;
    _read++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _all = const [];
    isBusy = false;
    isLoading = patientId != null;
    errorMessage = writeError = reminderError = null;
    if (previous != null) {
      _effects = _effects
          .then((_) => _reminders.clear(previous))
          .catchError((Object _) {});
    }
    scheduleMicrotask(() {
      if (!_current(session)) return;
      if (patientId != null) {
        retry();
      } else {
        _notify();
      }
    });
  }

  bool _current(int session) => !_disposed && session == _session;

  void retry() {
    final uid = _patientId;
    if (uid == null || _disposed) return;
    final session = _session;
    final request = ++_read;
    unawaited(_subscription?.cancel());
    isLoading = true;
    errorMessage = null;
    _notify();
    _subscription = repository
        .watchPatient(uid)
        .listen(
          (records) {
            if (!_current(session) || request != _read) return;
            // Do not flash an older snapshot after a successful transaction.
            _all =
                records.where((m) => m.patientId == uid).map((m) {
                  final existing = find(m.id);
                  return existing != null && existing.revision > m.revision
                      ? existing
                      : m;
                }).toList()..sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );
            isLoading = false;
            errorMessage = null;
            _notify();
            _queueReminders(_all, session);
          },
          onError: (Object error) {
            if (!_current(session) || request != _read) return;
            _all = const [];
            isLoading = false;
            errorMessage = const MedicationException(
              MedicationError.unavailable,
            ).message;
            _notify();
          },
        );
  }

  void _queueReminders(List<Medication> records, int session) {
    _effects = _effects.then((_) async {
      if (!_current(session)) return;
      try {
        for (final record in records) {
          if (!_current(session)) return;
          await _reminders.reconcile(record);
        }
        if (_current(session)) reminderError = null;
      } catch (_) {
        if (_current(session)) {
          reminderError =
              'Your changes are saved, but reminder sync failed. Retry sync.';
        }
      }
      if (_current(session)) _notify();
    });
  }

  void retryReminderSync() => _queueReminders(_all, _session);

  Medication _acceptCommitted(Medication result) {
    // A later server commit may reach the live stream before this response.
    // Keep both displayed stock and reminder effects at the newest revision.
    final existing = find(result.id);
    final latest = existing != null && existing.revision > result.revision
        ? existing
        : result;
    _all = [..._all.where((m) => m.id != latest.id), latest]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return latest;
  }

  Future<Medication?> _write(Future<Medication> Function() action) async {
    if (isBusy || _patientId == null) return null;
    final session = _session;
    isBusy = true;
    writeError = null;
    _notify();
    try {
      final result = await action();
      if (!_current(session)) return null;
      _queueReminders([_acceptCommitted(result)], session);
      return result;
    } on MedicationException catch (error) {
      if (_current(session)) writeError = error.message;
    } catch (_) {
      if (_current(session)) {
        writeError = const MedicationException(MedicationError.unavailable)
            .message;
      }
    } finally {
      if (_current(session)) {
        isBusy = false;
        _notify();
      }
    }
    return null;
  }

  Future<Medication?> save(Medication medication, {required bool creating}) {
    if (medication.patientId != _patientId) return Future.value(null);
    return _write(
      () => creating
          ? repository.create(medication)
          : repository.update(medication),
    );
  }

  Future<Medication?> deactivate(Medication medication) =>
      _write(() => repository.deactivate(medication));

  Future<Medication?> updateSupply(Medication medication, int stock) =>
      _write(() => repository.updateSupply(medication, stock));

  /// Person 1 calls this using the SAME persisted scheduled-dose ID on retries.
  /// Dose-history persistence remains owned by Person 1.
  Future<ConsumptionResult> consumeStock({
    required String medicationId,
    required String doseRecordId,
  }) async {
    final uid = _patientId;
    if (uid == null) throw const MedicationException(MedicationError.signedOut);
    final session = _session;
    final result = await repository.consumeStock(
      patientId: uid,
      medicationId: medicationId,
      doseRecordId: doseRecordId,
    );
    if (!_current(session)) {
      throw const MedicationException(MedicationError.signedOut);
    }
    _queueReminders([_acceptCommitted(result.medication)], session);
    _notify();
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    unawaited(_subscription?.cancel());
    final uid = _patientId;
    if (uid != null) {
      _effects = _effects
          .then((_) => _reminders.clear(uid))
          .catchError((Object _) {});
    }
    super.dispose();
  }
}
