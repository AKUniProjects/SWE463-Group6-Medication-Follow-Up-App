import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/dose_record.dart';
import '../models/medication.dart';
import '../services/dose_policy.dart';
import '../services/dose_repository.dart';
import '../services/dose_schedule.dart';
import '../services/dose_status_service.dart';
import '../services/medication_repository.dart'
    show ConsumptionStatus, MedicationException;

/// Person 2's stock deduction (`MedicationProvider.consumeStock`), passed in
/// so this provider does not depend on the whole MedicationProvider.
typedef ConsumeStock = Future<ConsumptionStatus> Function({
  required String medicationId,
  required String doseRecordId,
});

/// Week = last 7 days including today; Month = last 30 days.
enum HistoryPeriod { week, month }

/// "2 of 4 doses taken" for Today and 04b.
class DoseProgress {
  const DoseProgress({required this.taken, required this.total});

  final int taken;
  final int total;

  /// 0.0 to 1.0. No doses means 0 (no division by zero).
  double get fraction => total == 0 ? 0 : taken / total;
  int get percent => (fraction * 100).round();
}

/// Everything the Dose Confirmed screen (04b) shows. Built only AFTER the
/// save succeeded, so opening 04b never writes.
class DoseConfirmation {
  const DoseConfirmation({
    required this.record,
    required this.progress,
    this.wasAlreadyTaken = false,
    this.stockWarning,
  });

  final DoseRecord record;
  final DoseProgress progress;
  final bool wasAlreadyTaken;

  /// Completes with a warning when stock could not be deducted (the dose
  /// stays taken), or null. 04b opens BEFORE this finishes, so the patient
  /// does not wait for the second save.
  final Future<String?>? stockWarning;
}

/// Shared dose state for Today, History, 04b and notifications.
///
/// Session-scoped like the team's other providers: [updateSession] is
/// called by a ChangeNotifierProxyProvider whenever auth or medications
/// change. All reads and writes go through [DoseRepository].
class DoseProvider extends ChangeNotifier {
  DoseProvider(
    this.repository, {
    this.consumeStock,
    DateTime Function()? now,
    this.policy = const DosePolicy(),
    this.tickInterval = const Duration(minutes: 1),
  }) : _now = now ?? DateTime.now,
       _statusService = DoseStatusService(policy);

  final DoseRepository repository;
  final DosePolicy policy;

  /// Null in tests that do not check stock.
  final ConsumeStock? consumeStock;
  final DateTime Function() _now;

  /// How often statuses are re-checked while the app is open (null = never).
  final Duration? tickInterval;
  final DoseStatusService _statusService;

  String? _patientId;
  int _session = 0;
  bool _disposed = false;
  bool _evaluating = false;
  String _medicationsKey = '';
  List<Medication> _medications = const [];
  List<DoseRecord> _saved = const []; // last 30 days, from Firestore
  List<DoseRecord> _todayRaw = const []; // generated + saved statuses
  List<DoseRecord> _today = const []; // _todayRaw with current statuses
  StreamSubscription<List<DoseRecord>>? _subscription;
  DateTime? _subscribedDay;
  Timer? _ticker;
  final _pending = <String>{}; // dose IDs being confirmed
  final _stockRetry = <String, String>{}; // dose ID -> medication ID

  bool isLoading = false;

  /// Loading History/Today failed (shown with a Retry button).
  String? errorMessage;

  /// The last Taken attempt failed (the dose stays unconfirmed).
  String? confirmError;

  String? get patientId => _patientId;

  /// The provider's clock (fixed in tests), for "Today"/"Yesterday" labels.
  DateTime get now => _now();
  List<DoseRecord> get todayDoses => _today;

  /// Today's overdue doses ("1 unconfirmed dose needs your review").
  /// Only doses the patient can still fix with Mark as Taken: missed doses
  /// are final, so counting them would show a banner nobody can clear.
  List<DoseRecord> get needsReview => [
    for (final dose in _today)
      if (dose.status == DoseStatus.overdue) dose,
  ];

  bool isPending(String doseId) => _pending.contains(doseId);

  /// True while any dose is being saved: every Taken button is disabled,
  /// so a second 04b cannot open on top of the first.
  bool get isConfirming => _pending.isNotEmpty;

  DoseProgress get progress {
    final now = _now();
    final counted = policy.countFutureDosesInToday
        ? _today
        : _today.where((d) => !d.scheduledTime.isAfter(now)).toList();
    return DoseProgress(
      taken: counted.where((d) => d.status == DoseStatus.taken).length,
      total: counted.length,
    );
  }

  /// Saved records (taken, overdue, missed) in [period], newest first.
  List<DoseRecord> history(HistoryPeriod period) {
    final start = _dayOffset(_now(), period == HistoryPeriod.week ? -6 : -29);
    return _saved.where((r) => !r.scheduledTime.isBefore(start)).toList()
      ..sort((a, b) => b.scheduledTime.compareTo(a.scheduledTime));
  }

  /// Called by the ProxyProvider during build: never notifies directly.
  void updateSession({
    required String? patientId,
    required List<Medication> medications,
  }) {
    if (patientId != _patientId) {
      _startSession(patientId, medications);
      return;
    }
    final key = [
      for (final m in medications) '${m.id}:${m.revision}:${m.isActive}',
    ].join('|');
    if (key == _medicationsKey) return;
    _medicationsKey = key;
    _medications = medications;
    _rebuildToday();
    final session = _session;
    scheduleMicrotask(() {
      if (!_current(session)) return;
      _notify();
      // A new or edited medication may have doses that are already late:
      // save their status now instead of waiting for the next minute.
      unawaited(evaluateStatuses());
    });
  }

  void _startSession(String? patientId, List<Medication> medications) {
    _patientId = patientId;
    final session = ++_session; // ignore results from the old account
    unawaited(_subscription?.cancel());
    _subscription = null;
    _ticker?.cancel();
    _ticker = null;
    _medications = medications;
    _medicationsKey = '';
    _saved = const [];
    _todayRaw = const [];
    _today = const [];
    _pending.clear();
    _stockRetry.clear();
    errorMessage = null;
    confirmError = null;
    isLoading = patientId != null;
    scheduleMicrotask(() {
      if (!_current(session)) return;
      if (patientId == null) {
        _notify();
        return;
      }
      retry();
      _startTicker();
    });
  }

  /// (Re)loads the last 30 days of saved records and keeps listening.
  void retry() {
    final uid = _patientId;
    if (uid == null || _disposed) return;
    final session = _session;
    unawaited(_subscription?.cancel());
    final today = _dayOffset(_now(), 0);
    _subscribedDay = today;
    isLoading = true;
    errorMessage = null;
    _rebuildToday();
    _notify();
    _subscription = repository
        .watchRange(uid, _dayOffset(today, -29), _dayOffset(today, 1))
        .listen(
          (records) {
            if (!_current(session)) return;
            _saved = records;
            isLoading = false;
            errorMessage = null;
            _rebuildToday();
            _notify();
            unawaited(evaluateStatuses());
          },
          onError: (Object error) {
            if (!_current(session)) return;
            isLoading = false;
            errorMessage = error is DoseException
                ? error.message
                : 'Could not load your doses. Check your connection and retry.';
            _notify();
          },
        );
  }

  /// Marks [dose] as taken. Returns what 04b shows, or null if it failed
  /// (then [confirmError] explains why and the dose stays unconfirmed).
  /// A second call while the first is still saving is ignored.
  Future<DoseConfirmation?> confirm(DoseRecord dose) async {
    if (_patientId == null ||
        dose.patientId != _patientId ||
        _pending.isNotEmpty) {
      return null;
    }
    // Missed can no longer be confirmed, even if the screen was not
    // refreshed yet when the button was tapped.
    _rebuildToday();
    final shown = _today.where((d) => d.id == dose.id).firstOrNull;
    if (shown?.status == DoseStatus.missed) {
      confirmError = const DoseException(DoseError.alreadyMissed).message;
      _notify();
      return null;
    }
    final session = _session;
    _pending.add(dose.id);
    confirmError = null;
    _notify();
    try {
      final result = await repository.confirm(dose, _now());
      if (!_current(session)) return null;
      // Show it immediately; the live stream delivers the same record.
      _saved = [
        for (final r in _saved)
          if (r.id != result.record.id) r,
        result.record,
      ];
      _rebuildToday();
      // Not awaited: 04b shows the stock result when it arrives.
      final warning = _deductStock(result.record, session);
      return DoseConfirmation(
        record: result.record,
        progress: progress,
        wasAlreadyTaken: result.status == ConfirmStatus.alreadyTaken,
        stockWarning: warning,
      );
    } on DoseException catch (error) {
      if (_current(session)) confirmError = error.message;
      return null;
    } catch (_) {
      if (_current(session)) {
        confirmError = const DoseException(DoseError.unavailable).message;
      }
      return null;
    } finally {
      if (_current(session)) {
        _pending.remove(dose.id);
        _notify();
      }
    }
  }

  /// Moves late doses to overdue/missed and retries stock deductions.
  /// Safe to call often: on start, on resume, every minute, after loads.
  Future<void> evaluateStatuses() async {
    if (_patientId == null || _evaluating || isLoading) return;
    if (_subscribedDay != _dayOffset(_now(), 0)) {
      retry(); // a new day started: reload the 30-day window
      return;
    }
    final session = _session;
    _evaluating = true;
    try {
      final todayStart = _dayOffset(_now(), 0);
      // Raw statuses: _today already SHOWS the new status, so comparing
      // against it would find nothing to save.
      final candidates = [
        ..._todayRaw,
        // Earlier days: saved overdue doses can still become missed.
        ..._saved.where((r) => r.scheduledTime.isBefore(todayStart)),
      ];
      for (final change in _statusService.changes(candidates, _now())) {
        if (!_current(session)) return;
        try {
          // The repository re-reads the saved status, so a dose taken
          // meanwhile is never overwritten.
          await repository.markStatus(change, change.status);
        } on DoseException {
          // Not saved now; the next check tries again.
        }
      }
      await _retryStock(session);
    } finally {
      _evaluating = false;
    }
  }

  /// Returns a warning for 04b, or null if stock was deducted (or unknown
  /// to this provider in tests).
  Future<String?> _deductStock(DoseRecord record, int session) async {
    final consume = consumeStock;
    if (consume == null) return null;
    try {
      final status = await consume(
        medicationId: record.medicationId,
        doseRecordId: record.id,
      );
      _stockRetry.remove(record.id);
      return switch (status) {
        ConsumptionStatus.insufficientStock =>
          'Your supply looks empty. Update it in Refills.',
        ConsumptionStatus.unknownConsumption =>
          'Stock not updated: set units per dose for this medication.',
        ConsumptionStatus.consumed || ConsumptionStatus.alreadyConsumed => null,
      };
    } on MedicationException catch (error) {
      return error.message; // for example the medication was deleted
    } catch (_) {
      if (!_current(session)) return null; // signed out meanwhile
      _stockRetry[record.id] = record.medicationId; // e.g. offline
      return 'Dose saved. Stock will be updated when the connection returns.';
    }
  }

  Future<void> _retryStock(int session) async {
    final consume = consumeStock;
    if (consume == null) return;
    for (final entry in Map.of(_stockRetry).entries) {
      if (!_current(session)) return;
      try {
        // Same dose ID, so Person 2's receipt prevents a double deduction.
        await consume(medicationId: entry.value, doseRecordId: entry.key);
        _stockRetry.remove(entry.key);
      } on MedicationException {
        _stockRetry.remove(entry.key); // will never succeed
      } catch (_) {
        // Still offline: keep it for the next check.
      }
    }
  }

  void _rebuildToday() {
    final uid = _patientId;
    if (uid == null) {
      _todayRaw = const [];
      _today = const [];
      return;
    }
    final now = _now();
    final start = _dayOffset(now, 0);
    final end = _dayOffset(now, 1);
    final merged = mergeWithSaved(
      patientId: uid,
      generated: scheduledDosesForDay(
        patientId: uid,
        medications: _medications,
        day: now,
      ),
      saved: _saved
          .where(
            (r) =>
                !r.scheduledTime.isBefore(start) &&
                r.scheduledTime.isBefore(end),
          )
          .toList(),
    );
    // Show the status the rules give RIGHT NOW, even before it is saved,
    // so a late dose never shows "Upcoming" with a Taken button.
    _todayRaw = merged;
    final current = {
      for (final dose in _statusService.changes(merged, now)) dose.id: dose,
    };
    _today = [for (final dose in merged) current[dose.id] ?? dose];
  }

  void _startTicker() {
    final interval = tickInterval;
    if (interval == null) return; // tests call evaluateStatuses() directly
    _ticker = Timer.periodic(interval, (_) {
      _rebuildToday();
      _notify();
      unawaited(evaluateStatuses());
    });
  }

  /// Midnight of [day] plus [days] (DST-safe: built from the date parts).
  static DateTime _dayOffset(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);

  bool _current(int session) => !_disposed && session == _session;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _ticker?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
