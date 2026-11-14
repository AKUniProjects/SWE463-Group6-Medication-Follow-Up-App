import 'package:flutter/material.dart';

import '../models/adherence_stats.dart';
import '../theme/app_theme.dart';

class AdherenceProgressCard extends StatelessWidget {
  const AdherenceProgressCard({
    required this.title,
    required this.stats,
    super.key,
  });

  final String title;
  final AdherenceStats stats;

  @override
  Widget build(BuildContext context) {
    final available = stats.hasAdherenceData;
    final text = Theme.of(context).textTheme;

    final caption = available
        ? '${stats.takenDoses} of '
              '${stats.adherenceDenominator} evaluated doses confirmed'
        : stats.hasRecords
        ? 'Waiting for confirmed or missed doses'
        : 'No dose records available';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF147BA8), Color(0xFF3DB5B5)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyMedium?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      available ? '${stats.percentageRounded}%' : '—',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 34,
                backgroundColor: const Color(0xFFF2FBFC),
                child: Icon(
                  available ? Icons.check : Icons.schedule,
                  color: AppColors.teal,
                  size: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(caption, style: text.bodySmall?.copyWith(color: Colors.white)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: stats.percentage,
              minHeight: 7,
              color: Colors.white,
              backgroundColor: const Color(0xFF9DE0E2),
              semanticsLabel: 'Dose confirmation rate',
              semanticsValue: available
                  ? '${stats.percentageRounded}%'
                  : 'No data',
            ),
          ),
        ],
      ),
    );
  }
}

class AdherenceTrendChart extends StatelessWidget {
  const AdherenceTrendChart({
    required this.days,
    required this.period,
    super.key,
  });

  final List<AdherenceDay> days;
  final AdherencePeriod period;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('No trend data available.'),
        ),
      );
    }

    // Weekly: seven daily bars. Monthly: five six-day groups.
    final size = period == AdherencePeriod.week ? 1 : 6;
    final groups = <List<AdherenceDay>>[];

    for (var i = 0; i < days.length; i += size) {
      final end = i + size < days.length ? i + size : days.length;
      groups.add(days.sublist(i, end));
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: groups.map(_bar).toList(),
            ),
            if (period == AdherencePeriod.month) ...[
              const SizedBox(height: 12),
              const Text(
                'Six-day groups, labelled by starting date.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bar(List<AdherenceDay> group) {
    final taken = group.fold<int>(0, (sum, day) => sum + day.takenDoses);
    final total = group.fold<int>(0, (sum, day) => sum + day.evaluatedDoses);
    final fraction = total == 0
        ? 0.0
        : (taken / total).clamp(0.0, 1.0).toDouble();

    final first = group.first.date;
    final last = group.last.date;
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    final label = period == AdherencePeriod.week
        ? weekdays[first.weekday - 1]
        : '${first.day}/${first.month}';

    final dateLabel = group.length == 1
        ? '${first.day}/${first.month}/${first.year}'
        : '${first.day}/${first.month}–${last.day}/${last.month}';

    final description = total == 0
        ? '$dateLabel: no evaluated doses'
        : '$dateLabel: $taken of $total confirmed';

    return Expanded(
      child: Tooltip(
        message: description,
        child: Semantics(
          label: description,
          child: ExcludeSemantics(
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 120,
                  alignment: Alignment.bottomCenter,
                  decoration: BoxDecoration(
                    color: AppColors.tint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    height: 120 * fraction,
                    decoration: BoxDecoration(
                      color: AppColors.teal,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
