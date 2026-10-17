import 'package:flutter/material.dart';

import '../models/medication.dart';
import 'medication_editor_screen.dart';

class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({required this.medications, super.key});

  final List<Medication> medications;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Medications')),
      body: medications.isEmpty
          ? const Center(child: Text('No medications added yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: medications.length,
              itemBuilder: (context, index) {
                final medication = medications[index];
                final isLow = medication.stockAmount <= medication.refillThreshold;
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.medication_outlined),
                    ),
                    title: Text(medication.name),
                    subtitle: Text(
                      '${medication.doseAmount} ${medication.doseUnit} • '
                      '${medication.scheduledTimes.join(', ')}\n'
                      '${medication.stockAmount} remaining',
                    ),
                    isThreeLine: true,
                    trailing: Icon(
                      isLow ? Icons.warning_amber : Icons.check_circle_outline,
                      color: isLow ? Colors.orange : Colors.green,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => MedicationEditorScreen(
                          medication: medication,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const MedicationEditorScreen(),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add medication'),
      ),
    );
  }
}
