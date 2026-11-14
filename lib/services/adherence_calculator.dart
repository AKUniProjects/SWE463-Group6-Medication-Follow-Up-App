import '../models/adherence_stats.dart';
import '../models/dose_record.dart';
import 'dose_policy.dart';

class AdherenceCalculator {
  const AdherenceCalculator({this.policy = const DosePolicy()});

  final DosePolicy policy;

  /// Rolling period, matching Person 1's History:
  /// Week = today and the previous 6 days.
  /// Month = today and the previous 29 days.
  static DateTime periodStart(DateTime now, AdherencePeriod period) {
    final local = now.toLocal();
    final days = period == AdherencePeriod.week ? 7 : 30;

    return DateTime(local.year, local.month, local.day - days + 1);
  }

  static DateTime periodEnd(DateTime now) {
    final local = now.toLocal();

    return DateTime(local.year, local.month, local.day + 1);
  }

  /// Accepts records from the shared data layer.
  ///
  /// If a dose occurs more than once, the last supplied copy wins.
  /// Therefore, pass saved history first and current todayDoses last.
  ///
  /// This method does not read or write Firestore and does not change
  /// statuses. Person 1's status service owns those transitions.
  AdherenceStats calculate({
    required String patientId,
    required Iterable<DoseRecord> records,
    required AdherencePeriod period,
    required DateTime now,
  }) {
    if (patientId.trim().isEmpty) {
      throw ArgumentError.value(
        patientId,
        'patientId',
        'A patient ID is required.',
      );
    }

    final start = periodStart(now, period);
    final end = periodEnd(now);
    final unique = <String, DoseRecord>{};

    for (final record in records) {
      if (record.patientId != patientId) continue;

      unique[record.id] = record;
    }

    final included = unique.values.where((record) {
      final scheduled = record.scheduledTime.toLocal();

      if (scheduled.isBefore(start) || !scheduled.isBefore(end)) {
        return false;
      }

      if (!policy.countFutureDosesInToday && scheduled.isAfter(now)) {
        return false;
      }

      return true;
    }).toList();

    final dayCount = period == AdherencePeriod.week ? 7 : 30;
    final days = <AdherenceDay>[];

    for (var index = 0; index < dayCount; index++) {
      final date = DateTime(start.year, start.month, start.day + index);

      final nextDate = DateTime(date.year, date.month, date.day + 1);

      final dailyRecords = included.where((record) {
        final scheduled = record.scheduledTime.toLocal();

        return !scheduled.isBefore(date) && scheduled.isBefore(nextDate);
      }).toList();

      days.add(_summarizeDay(date, dailyRecords));
    }

    return AdherenceStats(
      periodLabel: period == AdherencePeriod.week
          ? 'Last 7 days'
          : 'Last 30 days',
      scheduledDoses: included.length,
      takenDoses: _count(included, DoseStatus.taken),
      missedDoses: _count(included, DoseStatus.missed),
      overdueDoses: _count(included, DoseStatus.overdue),
      pendingDoses: _count(included, DoseStatus.scheduled),
      evaluatedDoses: _evaluatedCount(included),
      days: List.unmodifiable(days),
    );
  }

  AdherenceDay _summarizeDay(DateTime date, List<DoseRecord> records) {
    return AdherenceDay(
      date: date,
      scheduledDoses: records.length,
      takenDoses: _count(records, DoseStatus.taken),
      missedDoses: _count(records, DoseStatus.missed),
      overdueDoses: _count(records, DoseStatus.overdue),
      evaluatedDoses: _evaluatedCount(records),
    );
  }

  int _evaluatedCount(List<DoseRecord> records) {
    final taken = _count(records, DoseStatus.taken);
    final missed = _count(records, DoseStatus.missed);

    final overdue = policy.overdueCountsAsMissed
        ? _count(records, DoseStatus.overdue)
        : 0;

    return taken + missed + overdue;
  }

  int _count(Iterable<DoseRecord> records, DoseStatus status) {
    return records.where((record) => record.status == status).length;
  }
}
