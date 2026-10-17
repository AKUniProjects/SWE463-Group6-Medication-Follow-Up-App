import 'package:flutter/material.dart';

import '../models/dose_record.dart';
import '../models/medication.dart';
import '../widgets/status_chip.dart';

class PatientHomeScreen extends StatelessWidget {
  const PatientHomeScreen({
    required this.medications,
    required this.doseRecords,
    super.key,
  });

  final List<Medication> medications;
  final List<DoseRecord> doseRecords;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
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
          Text('Good morning, Demo Patient',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Keep your medication record up to date.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Today\'s adherence'),
                        SizedBox(height: 4),
                        Text(
                          '1 of 2 doses confirmed',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: const ListTile(
              leading: Icon(Icons.warning_amber_outlined),
              title: Text('Refill reminder'),
              subtitle: Text('Blood pressure tablets are running low.'),
            ),
          ),
        ],
      ),
    );
  }

  double get _adherenceValue {
    if (doseRecords.isEmpty) return 0;
    final taken = doseRecords.where((record) => record.status == DoseStatus.taken).length;
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
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(isTaken ? Icons.check : Icons.medication_outlined),
        ),
        title: Text(record.medicationName),
        subtitle: Text(_timeLabel(record.scheduledTime)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusChip(label: _statusLabel(record.status), color: statusColor),
            if (!isTaken)
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${record.medicationName} marked taken')),
                  );
                },
                child: const Text('Taken'),
              ),
          ],
        ),
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
