import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/medication.dart';
import '../screens/medication_due_screen.dart';
import '../screens/missed_dose_screen.dart';
import '../screens/notification_settings_screen.dart';
import '../state/dose_provider.dart';
import '../state/medication_provider.dart';
import '../theme/app_theme.dart';
import 'dose_widgets.dart';

/// Active medications at or below their refill threshold. Person 2 owns
/// the rule (`isLowStock`); this only reads it.
List<Medication> lowStockMedications(List<Medication> medications) => [
  for (final m in medications)
    if (m.isLowStock) m,
];

/// Opens the Notifications overlay from the bell on Today (Diagram 7).
/// Rows come from live state, so it never shows a reminder that is not real.
Future<void> showNotificationsOverlay(
  BuildContext context, {
  required VoidCallback onOpenToday,
  required VoidCallback onOpenHistory,
  required VoidCallback onRefills,
}) {
  // The shell's navigator: pages open on top of Today, not in the dialog.
  final navigator = Navigator.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      void openPage(Widget page) {
        Navigator.of(dialogContext).pop();
        navigator.push(MaterialPageRoute<void>(builder: (_) => page));
      }

      return _NotificationsDialog(
        onDue: () => openPage(MedicationDueScreen(onOpenToday: onOpenToday)),
        onMissed: () => openPage(
          MissedDoseScreen(
            onOpenToday: onOpenToday,
            onOpenHistory: onOpenHistory,
          ),
        ),
        onRefill: () {
          Navigator.of(dialogContext).pop();
          onRefills();
        },
        onSettings: () => openPage(const NotificationSettingsScreen()),
      );
    },
  );
}

class _NotificationsDialog extends StatelessWidget {
  const _NotificationsDialog({
    required this.onDue,
    required this.onMissed,
    required this.onRefill,
    required this.onSettings,
  });

  final VoidCallback onDue;
  final VoidCallback onMissed;
  final VoidCallback onRefill;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final doses = context.watch<DoseProvider>();
    final due = doses.dueNow;
    final lateDoses = doses.needsFollowUp;
    final lowStock = lowStockMedications(
      context.watch<MedicationProvider>().activeMedications,
    );
    final text = Theme.of(context).textTheme;

    return Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Notifications', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Your latest medication reminders',
              style: text.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.medium),
            if (due.isNotEmpty)
              _Row(
                title: 'Medication due',
                subtitle: [
                  '${due.first.medicationName} • '
                      '${doseTimeLabel(context, due.first.scheduledTime)}',
                  if (due.length > 1) '+${due.length - 1} more',
                ].join('  '),
                background: AppColors.tint,
                onTap: onDue,
              ),
            if (lateDoses.isNotEmpty)
              _Row(
                title: 'Missed follow-up',
                subtitle: [
                  '${lateDoses.first.medicationName} • '
                      '${doseTimeLabel(context, lateDoses.first.scheduledTime)}',
                  if (lateDoses.length > 1) '+${lateDoses.length - 1} more',
                ].join('  '),
                background: AppColors.cream,
                onTap: onMissed,
              ),
            for (final m in lowStock)
              _Row(
                title: 'Refill reminder',
                subtitle:
                    '${m.name} • ${m.stockAmount} ${m.stockUnit} '
                    'remaining',
                background: AppColors.mint,
                onTap: onRefill,
              ),
            if (due.isEmpty && lateDoses.isEmpty && lowStock.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.small),
                child: Text('No reminders right now.'),
              ),
            _Row(
              title: 'Notification settings',
              subtitle: 'Manage Android reminder permissions',
              background: AppColors.divider,
              onTap: onSettings,
            ),
            const SizedBox(height: AppSpacing.small),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.background,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.small),
    child: Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    ),
  );
}
