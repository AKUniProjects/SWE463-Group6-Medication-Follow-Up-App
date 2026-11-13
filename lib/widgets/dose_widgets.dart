import 'package:flutter/material.dart';

import '../models/dose_record.dart';
import '../state/dose_provider.dart';
import '../theme/app_theme.dart';
import 'status_chip.dart';

/// Pieces shared by Today, Dose Confirmed (04b) and History (07).

/// "1 tablet" or "2.5 ml". Empty if the record has no dose snapshot.
String doseAmountLabel(DoseRecord record) {
  final amount = record.doseAmount;
  final unit = record.doseUnit;
  if (amount == null || unit == null) return '';
  final number = amount == amount.roundToDouble()
      ? amount.toInt().toString()
      : amount.toString();
  return '$number $unit';
}

/// "8:00 AM" (or "08:00" when the phone uses 24-hour time).
String doseTimeLabel(BuildContext context, DateTime time) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(time),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    );

/// Design labels and colours: Upcoming (blue), Taken (teal),
/// Overdue (amber), Missed (red).
class DoseStatusChip extends StatelessWidget {
  const DoseStatusChip({required this.status, super.key});

  final DoseStatus status;

  static String labelFor(DoseStatus status) => switch (status) {
    DoseStatus.scheduled => 'Upcoming',
    DoseStatus.taken => 'Taken',
    DoseStatus.overdue => 'Overdue',
    DoseStatus.missed => 'Missed',
  };

  static Color colorFor(DoseStatus status) => switch (status) {
    DoseStatus.scheduled => AppColors.primary,
    DoseStatus.taken => AppColors.teal,
    DoseStatus.overdue => AppColors.amber,
    DoseStatus.missed => AppColors.red,
  };

  @override
  Widget build(BuildContext context) =>
      StatusChip(label: labelFor(status), color: colorFor(status));
}

/// "Today's progress  50%  2 of 4 doses taken" with a bar.
class DoseProgressCard extends StatelessWidget {
  const DoseProgressCard({required this.progress, super.key});

  final DoseProgress progress;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      color: AppColors.primary,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Today's progress",
              style: text.titleSmall?.copyWith(color: Colors.white),
            ),
            Text(
              '${progress.percent}%',
              style: text.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${progress.taken} of ${progress.total} doses taken',
              style: text.bodyMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.small),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 8,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
