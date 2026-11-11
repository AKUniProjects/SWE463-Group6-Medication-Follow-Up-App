import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/medication_provider.dart';
import '../widgets/medication_widgets.dart';
import 'medication_editor_screen.dart';
import 'refill_tracking_screen.dart';

class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({super.key});

  Future<void> _edit(BuildContext context, [String? medicationId]) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MedicationEditorScreen(medicationId: medicationId),
      ),
    );
    if (context.mounted && result != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final medications = context.watch<MedicationProvider>().activeMedications;
    return Scaffold(
      appBar: AppBar(title: const Text('My medications')),
      body: MedicationLoadGuard(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: medications.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MessageCard(
                    title: medications.isEmpty
                        ? 'No medications yet'
                        : '${medications.length} active ${medications.length == 1 ? 'medication' : 'medications'}',
                    message: medications.isEmpty
                        ? 'Create your first fixed daily schedule.'
                        : 'Fixed daily schedules and refill status',
                  ),
                  const SizedBox(height: 16),
                  const ReminderSyncNotice(),
                ],
              );
            }
            if (index == medications.length + 1) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => _edit(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add medication'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RefillTrackingScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Refill tracking'),
                  ),
                ],
              );
            }
            final medication = medications[index - 1];
            return MedicationCard(
              medication: medication,
              onTap: () => _edit(context, medication.id),
            );
          },
        ),
      ),
    );
  }
}
