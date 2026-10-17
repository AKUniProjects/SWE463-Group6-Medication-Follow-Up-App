import 'package:flutter/material.dart';

import '../models/patient_summary.dart';

class PatientDetailsScreen extends StatelessWidget {
  const PatientDetailsScreen({required this.patient, super.key});

  final PatientSummary patient;

  @override
  Widget build(BuildContext context) {
    final stats = patient.stats;
    return Scaffold(
      appBar: AppBar(title: Text(patient.patientName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Adherence overview',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text(
                    '${(stats.percentage * 100).round()}%',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  Text(stats.periodLabel),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: stats.percentage),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Taken doses'),
                  trailing: Text('${stats.takenDoses}'),
                ),
                ListTile(
                  leading: const Icon(Icons.warning_amber_outlined),
                  title: const Text('Missed doses'),
                  trailing: Text('${patient.missedDoses}'),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Overdue doses'),
                  trailing: Text('${patient.overdueDoses}'),
                ),
              ],
            ),
          ),
          if (patient.requiresFollowUp) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const ListTile(
                leading: Icon(Icons.flag_outlined),
                title: Text('Follow-up recommended'),
                subtitle: Text('Review the patient\'s recent dose history.'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
