import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/adherence_stats.dart';
import '../models/doctor_link.dart';
import '../models/dose_record.dart';
import '../models/medication.dart';
import '../models/patient_summary.dart';
import '../services/adherence_calculator.dart';
import '../services/doctor_records_repository.dart';
import '../services/dose_policy.dart';
import '../services/dose_schedule.dart';
import '../services/dose_status_service.dart';

/// Read-only data used by the doctor's screens.
class DoctorPatientData {
  const DoctorPatientData({
    required this.patientId,
    required this.patientName,
    required this.medications,
    required this.doseRecords,
    required this.weeklyStats,
    required this.monthlyStats,
    required this.isLoading,
    this.errorMessage,
  });

  final String patientId;
  final String patientName;
  final List<Medication> medications;
  final List<DoseRecord> doseRecords;

  final AdherenceStats weeklyStats;
  final AdherenceStats monthlyStats;

  final bool isLoading;
  final String? errorMessage;

  bool get isReady => !isLoading && errorMessage == null;

  List<Medication> get activeMedications =>
      medications.where((medication) => medication.isActive).toList();

  AdherenceStats statsFor(AdherencePeriod period) {
    return period == AdherencePeriod.week ? weeklyStats : monthlyStats;
  }

  PatientSummary get summary => PatientSummary(
    patientId: patientId,
    patientName: patientName,
    stats: weeklyStats,
    missedDoses: weeklyStats.missedDoses,
    overdueDoses: weeklyStats.overdueDoses,
    requiresFollowUp: weeklyStats.requiresFollowUp,
  );
}

/// Internal subscriptions and loading state for one linked patient.
class _PatientWatch {
  _PatientWatch(this.link);

  DoctorLink link;

  List<DoseRecord> doses = const [];
  List<Medication> medications = const [];

  bool dosesLoaded = false;
  bool medicationsLoaded = false;

  String? errorMessage;

  StreamSubscription<List<DoseRecord>>? doseSubscription;
  StreamSubscription<List<Medication>>? medicationSubscription;

  bool get isLoading =>
      errorMessage == null && (!dosesLoaded || !medicationsLoaded);

  void cancel() {
    unawaited(doseSubscription?.cancel());
    unawaited(medicationSubscription?.cancel());

    doseSubscription = null;
    medicationSubscription = null;
  }
}

class DoctorDashboardProvider extends ChangeNotifier {
  DoctorDashboardProvider(
    this.repository, {
    this.policy = const DosePolicy(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final DoctorRecordsRepository repository;
  final DosePolicy policy;
  final DateTime Function() _now;

  final Map<String, _PatientWatch> _patients = {};

  StreamSubscription<List<DoctorLink>>? _linksSubscription;
  Timer? _timer;

  String? _doctorId;
  int _generation = 0;
  bool _disposed = false;

  bool isLoading = false;
  String? errorMessage;

  String? get doctorId => _doctorId;

  int get linkedPatientCount => _patients.length;

  /// Counts only patients whose records loaded successfully.
  int get followUpCount => patients
      .where(
        (patient) => patient.isReady && patient.weeklyStats.requiresFollowUp,
      )
      .length;

  List<DoctorPatientData> get patients {
    final now = _now();

    final result = _patients.values
        .map((watch) => _buildPatient(watch, now))
        .toList();

    result.sort(
      (first, second) => first.patientName.toLowerCase().compareTo(
        second.patientName.toLowerCase(),
      ),
    );

    return List<DoctorPatientData>.unmodifiable(result);
  }

  /// Returns null if the patient is no longer linked.
  DoctorPatientData? patientById(String patientId) {
    final watch = _patients[patientId];

    if (watch == null) return null;

    return _buildPatient(watch, _now());
  }

  /// Called by ChangeNotifierProxyProvider when authentication changes.
  /// A null ID means signed out or signed in as a patient.
  void updateSession(String? doctorId) {
    if (_disposed || doctorId == _doctorId) return;

    _doctorId = doctorId;
    final generation = ++_generation;

    _cancelSubscriptions();

    errorMessage = null;
    isLoading = doctorId != null;

    // ProxyProvider calls this during build, so notify afterwards.
    scheduleMicrotask(() {
      if (!_isCurrent(generation)) return;

      if (_doctorId == null) {
        _notify();
        return;
      }

      _startListening(generation);
    });
  }

  /// Reloads links and all patient subscriptions.
  void retry() {
    if (_disposed || _doctorId == null) return;

    final generation = ++_generation;

    _cancelSubscriptions();

    errorMessage = null;
    isLoading = true;

    _startListening(generation);
  }

  void _startListening(int generation) {
    if (!_isCurrent(generation) || _doctorId == null) return;

    _notify();

    try {
      _linksSubscription = repository.watchActiveLinks().listen(
        (links) {
          if (!_isCurrent(generation)) return;

          _updatePatients(links, generation);

          isLoading = false;
          errorMessage = null;

          _notify();
        },
        onError: (Object error) {
          if (!_isCurrent(generation)) return;

          _handleLinksError();
        },
      );

      // Refresh derived timing and rolling periods without writing doses.
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (_isCurrent(generation)) {
          _notify();
        }
      });
    } catch (_) {
      if (_isCurrent(generation)) {
        _handleLinksError();
      }
    }
  }

  void _updatePatients(List<DoctorLink> links, int generation) {
    final activeLinks = {
      for (final link in links)
        if (link.isActive && link.doctorId == _doctorId) link.patientId: link,
    };

    // Remove subscriptions and cached records immediately on revocation.
    final removedIds = _patients.keys
        .where((patientId) => !activeLinks.containsKey(patientId))
        .toList();

    for (final patientId in removedIds) {
      _patients.remove(patientId)?.cancel();
    }

    for (final entry in activeLinks.entries) {
      final existing = _patients[entry.key];

      if (existing != null) {
        existing.link = entry.value;
        continue;
      }

      final watch = _PatientWatch(entry.value);
      _patients[entry.key] = watch;

      _listenToPatient(entry.key, watch, generation);
    }
  }

  void _listenToPatient(String patientId, _PatientWatch watch, int generation) {
    bool isCurrentPatient() {
      return _isCurrent(generation) &&
          identical(_patients[patientId], watch) &&
          watch.errorMessage == null;
    }

    void fail(Object error) {
      if (!isCurrentPatient()) return;

      watch.cancel();

      // Never display stale records as successful data after a failure.
      watch.doses = const [];
      watch.medications = const [];
      watch.dosesLoaded = false;
      watch.medicationsLoaded = false;

      watch.errorMessage =
          'Could not load this patient’s records. '
          'Access may have changed, or the connection failed. Retry.';

      _notify();
    }

    try {
      watch.doseSubscription = repository.watchPatientDoses(patientId).listen((
        records,
      ) {
        if (!isCurrentPatient()) return;

        watch.doses = records;
        watch.dosesLoaded = true;

        _notify();
      }, onError: fail);

      watch.medicationSubscription = repository
          .watchPatientMedications(patientId)
          .listen((medications) {
            if (!isCurrentPatient()) return;

            watch.medications = medications;
            watch.medicationsLoaded = true;

            _notify();
          }, onError: fail);
    } catch (error) {
      fail(error);
    }
  }

  DoctorPatientData _buildPatient(_PatientWatch watch, DateTime now) {
    final ready =
        watch.dosesLoaded &&
        watch.medicationsLoaded &&
        watch.errorMessage == null;

    final records = ready ? _currentRecords(watch, now) : const <DoseRecord>[];

    final calculator = AdherenceCalculator(policy: policy);
    final patientId = watch.link.patientId;

    return DoctorPatientData(
      patientId: patientId,
      patientName: watch.link.patientName,
      medications: ready
          ? List<Medication>.unmodifiable(watch.medications)
          : const [],
      doseRecords: List<DoseRecord>.unmodifiable(records),
      weeklyStats: calculator.calculate(
        patientId: patientId,
        records: records,
        period: AdherencePeriod.week,
        now: now,
      ),
      monthlyStats: calculator.calculate(
        patientId: patientId,
        records: records,
        period: AdherencePeriod.month,
        now: now,
      ),
      isLoading: watch.isLoading,
      errorMessage: watch.errorMessage,
    );
  }

  List<DoseRecord> _currentRecords(_PatientWatch watch, DateTime now) {
    final local = now.toLocal();

    final today = DateTime(local.year, local.month, local.day);

    final tomorrow = DateTime(local.year, local.month, local.day + 1);

    final start = AdherenceCalculator.periodStart(now, AdherencePeriod.month);

    final saved = watch.doses.where((dose) {
      final time = dose.scheduledTime.toLocal();

      return !time.isBefore(start) && time.isBefore(tomorrow);
    }).toList();

    // Reuse Person 1's schedule generator for TODAY only.
    // Do not fabricate historical schedules from current medication times.
    final generatedToday = scheduledDosesForDay(
      patientId: watch.link.patientId,
      medications: watch.medications
          .where((medication) => medication.isActive)
          .toList(),
      day: now,
    );

    final todayRecords = mergeWithSaved(
      patientId: watch.link.patientId,
      generated: generatedToday,
      saved: saved.where((dose) {
        return !dose.scheduledTime.toLocal().isBefore(today);
      }).toList(),
    );

    final combined = <DoseRecord>[
      ...saved.where((dose) {
        return dose.scheduledTime.toLocal().isBefore(today);
      }),
      ...todayRecords,
    ];

    // Derive current statuses for display using the team's policy.
    // The doctor never persists these changes.
    final changes = {
      for (final dose in DoseStatusService(policy).changes(combined, now))
        dose.id: dose,
    };

    final result = [for (final dose in combined) changes[dose.id] ?? dose];

    result.sort(
      (first, second) => second.scheduledTime.compareTo(first.scheduledTime),
    );

    return result;
  }

  void _handleLinksError() {
    // Invalidate callbacks already queued by the old subscriptions.
    _generation++;
    _cancelSubscriptions();

    isLoading = false;
    errorMessage =
        'Could not load linked patients. '
        'Check your connection and account access, then retry.';

    _notify();
  }

  void _cancelSubscriptions() {
    unawaited(_linksSubscription?.cancel());
    _linksSubscription = null;

    _timer?.cancel();
    _timer = null;

    for (final watch in _patients.values) {
      watch.cancel();
    }

    _patients.clear();
  }

  bool _isCurrent(int generation) {
    return !_disposed && generation == _generation;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;

    _cancelSubscriptions();

    super.dispose();
  }
}
