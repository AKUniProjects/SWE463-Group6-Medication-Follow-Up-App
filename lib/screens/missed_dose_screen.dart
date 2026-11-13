import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dose_record.dart';
import '../state/dose_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/dose_widgets.dart';
import '../widgets/medication_widgets.dart' show MessageCard;

/// "Missed Follow-up" state page (Phase 2 "State: Missed Dose Follow-up").
/// Lists today's overdue and missed doses, read live from DoseProvider,
/// so a dose confirmed meanwhile disappears from it.
class MissedDoseScreen extends StatelessWidget {
  const MissedDoseScreen({
    required this.onOpenToday,
    required this.onOpenHistory,
    super.key,
  });

  /// Switch the shell to the Today / History tab.
  final VoidCallback onOpenToday;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final doses = context.watch<DoseProvider>().needsFollowUp;
    final text = Theme.of(context).textTheme;

    // Close this page (and anything under it) and show [openTab].
    void leaveTo(VoidCallback openTab) {
      openTab();
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Missed Follow-up')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.medium),
        children: [
          if (doses.isEmpty)
            const MessageCard(message: 'No doses need follow-up right now.')
          else
            for (final dose in doses) ...[
              MessageCard(
                warning: true,
                message: '${dose.medicationName} has no recorded confirmation.',
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.medium),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${dose.medicationName} • '
                              '${doseTimeLabel(context, dose.scheduledTime)}',
                              style: text.titleMedium,
                            ),
                          ),
                          DoseStatusChip(status: dose.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Overdue can still be confirmed; missed is final.
                      if (dose.status == DoseStatus.overdue)
                        const Text('You can still mark it as taken on Today.'),
                      Text(
                        'This is a follow-up reminder, not medical advice.',
                        style: text.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.small),
            ],
          const SizedBox(height: AppSpacing.medium),
          FilledButton(
            onPressed: () => leaveTo(onOpenHistory),
            child: const Text('Review dose history'),
          ),
          const SizedBox(height: AppSpacing.small),
          OutlinedButton(
            onPressed: () => leaveTo(onOpenToday),
            child: const Text('Back to Today'),
          ),
        ],
      ),
    );
  }
}
