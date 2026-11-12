import '../models/dose_record.dart';
import 'dose_policy.dart';

/// Decides when unconfirmed doses become `overdue` or `missed` (Feature #6).
///
/// Pure logic: the caller passes the current time, so tests can use any
/// clock. It never reads or writes Firestore. Saving the result (and
/// re-checking that the dose was not taken meanwhile) is the repository's
/// job.
class DoseStatusService {
  const DoseStatusService([this.policy = const DosePolicy()]);

  final DosePolicy policy;

  /// The status [dose] should move to at [now], or null if it stays as it
  /// is. [nextDoseTime] is the next scheduled dose of the same medication,
  /// if known (used by `missWhenNextDoseDue`).
  DoseStatus? evaluate(
    DoseRecord dose,
    DateTime now, {
    DateTime? nextDoseTime,
  }) {
    // Taken and missed are final: never overwrite them.
    if (dose.status == DoseStatus.taken || dose.status == DoseStatus.missed) {
      return null;
    }

    final target = _statusAt(dose.scheduledTime, now, nextDoseTime);
    if (target == dose.status) return null;
    // Only move forward (for example if the phone clock is set back).
    if (dose.status == DoseStatus.overdue && target == DoseStatus.scheduled) {
      return null;
    }
    return target;
  }

  /// Checks every dose in [doses] and returns only the ones whose status
  /// changes, already updated. Running it again on updated doses returns
  /// nothing, so it is safe to call on every app start or resume.
  List<DoseRecord> changes(List<DoseRecord> doses, DateTime now) {
    final changed = <DoseRecord>[];
    for (final dose in doses) {
      final status = evaluate(
        dose,
        now,
        nextDoseTime: _nextDoseTime(dose, doses),
      );
      if (status != null) changed.add(dose.copyWith(status: status));
    }
    return changed;
  }

  DoseStatus _statusAt(DateTime scheduled, DateTime now, DateTime? next) {
    var missedAt = scheduled.add(policy.missedAfter);
    if (policy.missWhenNextDoseDue &&
        next != null &&
        next.isAfter(scheduled) &&
        next.isBefore(missedAt)) {
      missedAt = next;
    }
    if (!now.isBefore(missedAt)) return DoseStatus.missed;
    if (!now.isBefore(scheduled.add(policy.overdueAfter))) {
      return DoseStatus.overdue;
    }
    return DoseStatus.scheduled;
  }

  /// The earliest dose of the same medication scheduled after [dose].
  DateTime? _nextDoseTime(DoseRecord dose, List<DoseRecord> doses) {
    DateTime? next;
    for (final other in doses) {
      final isLaterSameMedication =
          other.medicationId == dose.medicationId &&
          other.scheduledTime.isAfter(dose.scheduledTime);
      if (isLaterSameMedication &&
          (next == null || other.scheduledTime.isBefore(next))) {
        next = other.scheduledTime;
      }
    }
    return next;
  }
}
