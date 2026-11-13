import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dose_record.dart';
import '../state/dose_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/dose_widgets.dart';
import '../widgets/medication_widgets.dart';

/// 07 Dose History: the patient's saved doses (taken, overdue, missed).
///
/// Week/Month switch the SAME screen in place (local `setState`), so no
/// duplicate History routes are pushed. Data comes from DoseProvider, so a
/// dose confirmed on Today appears here without restarting.
class DoseHistoryScreen extends StatefulWidget {
  const DoseHistoryScreen({this.onBackToToday, super.key});

  /// Switches the shell back to the Today tab.
  final VoidCallback? onBackToToday;

  @override
  State<DoseHistoryScreen> createState() => _DoseHistoryScreenState();
}

class _DoseHistoryScreenState extends State<DoseHistoryScreen> {
  HistoryPeriod _period = HistoryPeriod.week; // UI-only state

  void _show(HistoryPeriod period) => setState(() => _period = period);

  @override
  Widget build(BuildContext context) {
    final doses = context.watch<DoseProvider>();
    final records = doses.history(_period);
    final isWeek = _period == HistoryPeriod.week;

    return Scaffold(
      appBar: AppBar(
        leading: widget.onBackToToday == null
            ? null
            : IconButton(
                tooltip: 'Back to Today',
                onPressed: widget.onBackToToday,
                icon: const Icon(Icons.arrow_back),
              ),
        title: const Text('Dose history'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.medium),
        children: [
          Text(
            'Your medication timeline',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.medium),
          SegmentedButton<HistoryPeriod>(
            segments: const [
              ButtonSegment(value: HistoryPeriod.week, label: Text('Week')),
              ButtonSegment(value: HistoryPeriod.month, label: Text('Month')),
            ],
            selected: {_period},
            onSelectionChanged: (selection) => _show(selection.first),
          ),
          const SizedBox(height: AppSpacing.medium),
          if (doses.errorMessage != null)
            MessageCard(
              warning: true,
              message: doses.errorMessage!,
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: doses.retry,
                  child: const Text('Retry'),
                ),
              ),
            ),
          if (doses.isLoading && records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.large),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (records.isEmpty && doses.errorMessage == null)
            _EmptyHistory(onBackToToday: widget.onBackToToday)
          else if (records.isNotEmpty) ...[
            if (isWeek)
              for (final day in _groupByDay(records))
                _HistoryCard(
                  title: _dayTitle(context, day.first.scheduledTime, doses.now),
                  records: day,
                  showDate: false,
                )
            else
              _HistoryCard(
                title: records.length == 1
                    ? '1 scheduled dose recorded'
                    : '${records.length} scheduled doses recorded',
                records: records,
                showDate: true,
              ),
            const SizedBox(height: AppSpacing.small),
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () =>
                  _show(isWeek ? HistoryPeriod.month : HistoryPeriod.week),
              child: Text(
                isWeek ? 'View monthly records' : 'View weekly records',
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Splits newest-first records into one list per calendar day.
  List<List<DoseRecord>> _groupByDay(List<DoseRecord> records) {
    final days = <List<DoseRecord>>[];
    for (final record in records) {
      final last = days.isEmpty ? null : days.last.first.scheduledTime;
      if (last != null && DateUtils.isSameDay(last, record.scheduledTime)) {
        days.last.add(record);
      } else {
        days.add([record]);
      }
    }
    return days;
  }

  /// "Today's doses", "Yesterday", or a date like "Sun, Nov 9".
  String _dayTitle(BuildContext context, DateTime day, DateTime now) {
    if (DateUtils.isSameDay(day, now)) return "Today's doses";
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    if (DateUtils.isSameDay(day, yesterday)) return 'Yesterday';
    return MaterialLocalizations.of(context).formatMediumDate(day);
  }
}

/// One card: a title and its dose rows.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.title,
    required this.records,
    required this.showDate,
  });

  final String title;
  final List<DoseRecord> records;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            for (final record in records)
              _HistoryRow(record: record, showDate: showDate),
          ],
        ),
      ),
    );
  }
}

/// "Vitamin D / 8:04 AM · Confirmed • Taken" (Week) or
/// "Vitamin D / Nov 9, 8:00 AM • Missed" (Month).
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record, required this.showDate});

  final DoseRecord record;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final taken = record.status == DoseStatus.taken;
    // Taken shows WHEN it was confirmed; others show when it was due.
    final time = taken
        ? record.confirmedAt ?? record.scheduledTime
        : record.scheduledTime;
    final clock = doseTimeLabel(context, time);
    final label = DoseStatusChip.labelFor(record.status);
    final detail = showDate
        ? '${MaterialLocalizations.of(context).formatShortMonthDay(time)}, '
              '$clock • $label'
        : '$clock · ${taken ? 'Confirmed' : 'Not confirmed'} • $label';

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.small),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            taken ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            color: DoseStatusChip.colorFor(record.status),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.medicationName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Phase 2 "Empty History" state.
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({this.onBackToToday});

  final VoidCallback? onBackToToday;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MessageCard(
          title: 'No history yet',
          message: 'Taken and missed dose records will appear here.',
        ),
        const SizedBox(height: AppSpacing.small),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: onBackToToday,
          child: const Text('Back to Today'),
        ),
      ],
    );
  }
}
