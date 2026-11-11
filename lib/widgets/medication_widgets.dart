import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/medication.dart';
import '../state/medication_provider.dart';
import '../theme/app_theme.dart';
import 'status_chip.dart';

String doseLabel(Medication m) =>
    '${m.doseAmount.toString().replaceFirst(RegExp(r'\.0$'), '')} ${m.doseUnit}';

class MedicationCard extends StatelessWidget {
  const MedicationCard({required this.medication, this.onTap, super.key});
  final Medication medication;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = medication;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: onTap == null ? null : true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      backgroundColor: AppColors.tint,
                      child: Icon(
                        Icons.medication_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(doseLabel(m)),
                          Text(m.scheduledTimes.join(' • ')),
                        ],
                      ),
                    ),
                    if (onTap != null) const Icon(Icons.chevron_right),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${m.stockAmount} ${m.stockUnit} remaining'),
                StockStatus(medication: m),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StockStatus extends StatelessWidget {
  const StockStatus({required this.medication, super.key});
  final Medication medication;
  @override
  Widget build(BuildContext context) => StatusChip(
    label: medication.stockAmount == 0
        ? 'Out of stock'
        : medication.isLowStock
        ? 'Low supply'
        : 'Supply sufficient',
    color: medication.stockAmount == 0
        ? AppColors.red
        : medication.isLowStock
        ? AppColors.amber
        : AppColors.teal,
  );
}

class MessageCard extends StatelessWidget {
  const MessageCard({
    required this.message,
    this.title,
    this.warning = false,
    this.child,
    super.key,
  });
  final String message;
  final String? title;
  final bool warning;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Card(
    color: warning ? AppColors.cream : AppColors.tint,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                warning ? Icons.warning_amber_outlined : Icons.info_outline,
                color: warning ? AppColors.amber : AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(message),
                  ],
                ),
              ),
            ],
          ),
          if (child != null) child!,
        ],
      ),
    ),
  );
}

class MedicationLoadGuard extends StatelessWidget {
  const MedicationLoadGuard({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<MedicationProvider>();
    if (state.patientId == null) {
      return const Center(
        child: Text('Sign in as a patient to view medications.'),
      );
    }
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: MessageCard(
            message: state.errorMessage!,
            warning: true,
            child: TextButton(
              onPressed: state.retry,
              child: const Text('Retry'),
            ),
          ),
        ),
      );
    }
    return child;
  }
}

class ReminderSyncNotice extends StatelessWidget {
  const ReminderSyncNotice({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<MedicationProvider>();
    if (state.reminderError == null) return const SizedBox.shrink();
    return MessageCard(
      message: state.reminderError!,
      warning: true,
      child: TextButton(
        onPressed: state.retryReminderSync,
        child: const Text('Retry reminder sync'),
      ),
    );
  }
}
