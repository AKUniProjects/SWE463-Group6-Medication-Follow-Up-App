import 'package:flutter/material.dart';

import '../models/dose_record.dart';
import '../models/medication.dart';
import '../state/dose_provider.dart';
import '../widgets/dose_widgets.dart';
import '../widgets/medication_widgets.dart';
import 'doctor_linking_screen.dart';

/// 04 Patient Home (Today). Shows data it is given; AppShell connects it to
/// DoseProvider and MedicationProvider. It holds no shared state itself.
class PatientHomeScreen extends StatelessWidget {
  const PatientHomeScreen({
    required this.medications,
    required this.doseRecords,
    this.displayName = 'Demo Patient',
    this.doseTrackingAvailable = true,
    this.progress,
    this.isLoadingDoses = false,
    this.doseError,
    this.onRetryDoses,
    this.onTaken,
    this.isPending,
    this.isConfirming = false,
    this.reviewCount = 0,
    this.onReview,
    this.onMedicationTap,
    this.onRefills,
    super.key,
  });

  final List<Medication> medications;

  /// Today's doses, already sorted by time.
  final List<DoseRecord> doseRecords;
  final String displayName;
  final bool doseTrackingAvailable;

  /// From DoseProvider (applies the policy). Null: count [doseRecords].
  final DoseProgress? progress;
  final bool isLoadingDoses;
  final String? doseError;
  final VoidCallback? onRetryDoses;

  /// Called when "Mark as Taken" is tapped. Null disables the button.
  final ValueChanged<DoseRecord>? onTaken;

  /// True while that dose is being saved (button shows a spinner).
  final bool Function(String doseId)? isPending;

  /// True while ANY dose is saving: all Taken buttons are disabled.
  final bool isConfirming;

  /// Overdue/missed doses today, for the "needs your review" banner.
  final int reviewCount;
  final VoidCallback? onReview;
  final ValueChanged<String>? onMedicationTap;
  final VoidCallback? onRefills;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final shownProgress =
        progress ??
        DoseProgress(
          taken: doseRecords.where((r) => r.status == DoseStatus.taken).length,
          total: doseRecords.length,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          // Doctor Linking shortcut (Task 3.5B).
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DoctorLinkingScreen(),
              ),
            ),
            tooltip: 'Link a doctor',
            icon: const Icon(Icons.people_alt_outlined),
          ),
          IconButton(
            onPressed: () {},
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Hello, $displayName', style: theme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Keep your medication record up to date.',
            style: theme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (doseTrackingAvailable) ...[
            DoseProgressCard(progress: shownProgress),
            const SizedBox(height: 20),
            Text("Today's medications", style: theme.titleLarge),
            const SizedBox(height: 8),
            if (isLoadingDoses && doseRecords.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (doseError != null)
              MessageCard(
                warning: true,
                message: doseError!,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onRetryDoses,
                    child: const Text('Retry'),
                  ),
                ),
              )
            else if (doseRecords.isEmpty)
              const MessageCard(message: 'No doses scheduled today.'),
            ...doseRecords.map(
              (record) => _DoseCard(
                record: record,
                pending: isPending?.call(record.id) ?? false,
                enabled: !isConfirming,
                onTaken: onTaken == null ? null : () => onTaken!(record),
              ),
            ),
            if (reviewCount > 0)
              InkWell(
                onTap: onReview,
                child: MessageCard(
                  warning: true,
                  message: reviewCount == 1
                      ? '1 unconfirmed dose needs your review'
                      : '$reviewCount unconfirmed doses need your review',
                ),
              ),
          ] else
            const MessageCard(
              message:
                  'Dose confirmation and history are not connected yet. '
                  'Your saved medication plan is shown below.',
            ),
          const SizedBox(height: 16),
          Text('Medication plan', style: theme.titleLarge),
          const SizedBox(height: 8),
          if (medications.isEmpty)
            const Text(
              'No active medications yet. Open Medications to add one.',
            ),
          for (final m in medications)
            MedicationCard(
              medication: m,
              onTap: onMedicationTap == null
                  ? null
                  : () => onMedicationTap!(m.id),
            ),
          if (onRefills != null)
            OutlinedButton.icon(
              onPressed: onRefills,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Refill tracking'),
            ),
          const SizedBox(height: 16),
          if (medications.any((m) => m.isLowStock))
            const MessageCard(
              warning: true,
              message: 'One or more medications have low supply. Review refill tracking.',
            ),
        ],
      ),
    );
  }
}

/// One dose: name, "1 tablet • 8:00 AM", status chip, Mark as Taken.
class _DoseCard extends StatelessWidget {
  const _DoseCard({
    required this.record,
    required this.pending,
    this.enabled = true,
    this.onTaken,
  });

  final DoseRecord record;
  final bool pending;
  final bool enabled;
  final VoidCallback? onTaken;

  @override
  Widget build(BuildContext context) {
    // Taken is final; missed can no longer be confirmed (team decision).
    final canConfirm =
        record.status == DoseStatus.scheduled ||
        record.status == DoseStatus.overdue;
    final amount = doseAmountLabel(record);
    final time = doseTimeLabel(context, record.scheduledTime);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.medication_outlined, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.medicationName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(amount.isEmpty ? time : '$amount • $time'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DoseStatusChip(status: record.status),
            if (canConfirm) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  // Disabled while saving, so a second tap does nothing.
                  onPressed: pending || !enabled ? null : onTaken,
                  icon: pending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(pending ? 'Saving…' : 'Mark as Taken'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
