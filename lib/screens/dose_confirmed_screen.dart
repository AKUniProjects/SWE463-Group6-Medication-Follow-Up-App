import 'package:flutter/material.dart';

import '../state/dose_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/dose_widgets.dart';
import '../widgets/medication_widgets.dart';

/// 04b Dose Confirmed. Only opened AFTER the save succeeded, and it never
/// writes anything itself, so reopening it cannot confirm a dose twice.
class DoseConfirmedScreen extends StatelessWidget {
  const DoseConfirmedScreen({required this.confirmation, super.key});

  final DoseConfirmation confirmation;

  @override
  Widget build(BuildContext context) {
    final record = confirmation.record;
    final text = Theme.of(context).textTheme;
    final amount = doseAmountLabel(record);
    final confirmedAt = record.confirmedAt;

    return Scaffold(
      appBar: AppBar(title: const Text('Dose Confirmed')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.medium),
        children: [
          Card(
            color: AppColors.mint,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.medium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.teal,
                    size: 48,
                  ),
                  const SizedBox(height: AppSpacing.small),
                  Text(
                    confirmation.wasAlreadyTaken
                        ? 'Already recorded'
                        : 'Dose recorded!',
                    style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    amount.isEmpty
                        ? record.medicationName
                        : '${record.medicationName} · $amount',
                    style: text.titleMedium,
                  ),
                  if (confirmedAt != null)
                    Text(
                      'Confirmed at ${doseTimeLabel(context, confirmedAt)}',
                      style: text.titleSmall?.copyWith(color: AppColors.teal),
                    ),
                ],
              ),
            ),
          ),
          // The stock result arrives a moment after this screen opens.
          FutureBuilder<String?>(
            future: confirmation.stockWarning,
            builder: (context, snapshot) {
              final warning = snapshot.data;
              return warning == null
                  ? const SizedBox.shrink()
                  : MessageCard(warning: true, message: warning);
            },
          ),
          DoseProgressCard(progress: confirmation.progress),
          const SizedBox(height: AppSpacing.medium),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continue to Today'),
          ),
        ],
      ),
    );
  }
}
