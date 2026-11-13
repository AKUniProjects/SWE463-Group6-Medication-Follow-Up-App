import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/dose_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/dose_widgets.dart';

/// "Due Reminder" state page (Phase 2 "State: Medication Due").
/// Lists the doses that are due right now, read live from DoseProvider.
class MedicationDueScreen extends StatelessWidget {
  const MedicationDueScreen({required this.onOpenToday, super.key});

  /// Switches the shell to the Today tab.
  final VoidCallback onOpenToday;

  @override
  Widget build(BuildContext context) {
    final due = context.watch<DoseProvider>().dueNow;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Due Reminder')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.medium),
        children: [
          if (due.isEmpty)
            const Text('Nothing is due right now.')
          else
            for (final dose in due)
              Card(
                color: AppColors.tint,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.medium),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dose.medicationName, style: text.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        [
                          doseAmountLabel(dose),
                          doseTimeLabel(context, dose.scheduledTime),
                        ].where((part) => part.isNotEmpty).join(' • '),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: AppSpacing.medium),
          FilledButton(
            onPressed: () {
              onOpenToday();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Open today'),
          ),
        ],
      ),
    );
  }
}
