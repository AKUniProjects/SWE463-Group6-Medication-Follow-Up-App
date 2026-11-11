import 'package:flutter/material.dart';

import '../models/dose_record.dart';
import '../models/medication.dart';
import '../widgets/status_chip.dart';
import '../widgets/medication_widgets.dart';
import 'doctor_linking_screen.dart';

class PatientHomeScreen extends StatelessWidget {
  const PatientHomeScreen({
    required this.medications,
    required this.doseRecords,
    this.displayName = 'Demo Patient',
    this.doseTrackingAvailable = true,
    this.onMedicationTap,
    this.onRefills,
    super.key,
  });

  final List<Medication> medications;
  final List<DoseRecord> doseRecords;
  final String displayName;
  final bool doseTrackingAvailable;
  final ValueChanged<String>? onMedicationTap;
  final VoidCallback? onRefills;

  @override
  Widget build(BuildContext context) {
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
          Text(
            'Hello, $displayName',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Keep your medication record up to date.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (doseTrackingAvailable)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: _adherenceValue,
                        strokeWidth: 8,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Today\'s adherence'),
                          const SizedBox(height: 4),
                          Text(
                            '${doseRecords.where((r) => r.status == DoseStatus.taken).length} of '
                            '${doseRecords.length} doses confirmed',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text('Dose schedule', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...doseRecords.map((record) => _DoseCard(record: record)),
          if (!doseTrackingAvailable)
            const MessageCard(
              message:
                  'Dose confirmation and history are not connected yet. '
                  'Your saved medication plan is shown below.',
            ),
          const SizedBox(height: 16),
          Text(
            'Medication plan',
            style: Theme.of(context).textTheme.titleLarge,
          ),
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

  double get _adherenceValue {
    if (doseRecords.isEmpty) return 0;
    final taken = doseRecords
        .where((record) => record.status == DoseStatus.taken)
        .length;
    return taken / doseRecords.length;
  }
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({required this.record});

  final DoseRecord record;

  @override
  Widget build(BuildContext context) {
    final isTaken = record.status == DoseStatus.taken;
    final statusColor = switch (record.status) {
      DoseStatus.taken => Colors.green,
      DoseStatus.overdue || DoseStatus.missed => Colors.red,
      DoseStatus.scheduled => Colors.indigo,
    };

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: CircleAvatar(
              child: Icon(isTaken ? Icons.check : Icons.medication_outlined),
            ),
            title: Text(record.medicationName),
            subtitle: Text(_timeLabel(record.scheduledTime)),
          ),
          // Actions have their own growing area instead of ListTile.trailing's
          // fixed height. Wrap preserves text scaling on narrow screens.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                StatusChip(
                  label: _statusLabel(record.status),
                  color: statusColor,
                ),
                if (!isTaken)
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(64, 48),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${record.medicationName} marked taken',
                          ),
                        ),
                      );
                    },
                    child: const Text('Taken'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(DoseStatus status) {
    return switch (status) {
      DoseStatus.taken => 'Taken',
      DoseStatus.scheduled => 'Scheduled',
      DoseStatus.overdue => 'Overdue',
      DoseStatus.missed => 'Missed',
    };
  }

  String _timeLabel(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return 'Scheduled at $hour:$minute';
  }
}
