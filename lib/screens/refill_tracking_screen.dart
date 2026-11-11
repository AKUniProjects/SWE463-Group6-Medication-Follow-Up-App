import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/medication.dart';
import '../state/medication_provider.dart';
import '../widgets/medication_widgets.dart';
import '../widgets/refill_card.dart';
import '../widgets/update_supply_dialog.dart';
import 'medication_editor_screen.dart';

class RefillTrackingScreen extends StatelessWidget {
  const RefillTrackingScreen({super.key});
  Future<void> _update(BuildContext context, Medication medication) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateSupplyDialog(medication: medication),
    );
    if (context.mounted && result == true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Refill updated')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MedicationProvider>();
    final medications = state.activeMedications;
    return Scaffold(
      appBar: AppBar(title: const Text('Refill tracker')),
      body: MedicationLoadGuard(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const MessageCard(
              title: 'Stay prepared',
              message:
                  'Stock estimates use your entered '
                  'quantities and fixed schedules.',
            ),
            const SizedBox(height: 16),
            const ReminderSyncNotice(),
            if (!state.remindersAvailable)
              const MessageCard(
                message:
                    'Device refill notifications are not connected yet. '
                    'Low supply warnings remain available here.',
              ),
            if (medications.isEmpty) ...[
              const MessageCard(
                message: 'No active medications. Add a medication to track its supply.',
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const MedicationEditorScreen(),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add medication'),
              ),
            ],
            for (final m in medications)
              RefillCard(medication: m, onUpdate: () => _update(context, m)),
            const MessageCard(
              warning: true,
              message:
                  'Refill alerts use estimates, not pharmacy orders. '
                  'Days remaining are approximate and based on the supply and consumption you enter.',
            ),
          ],
        ),
      ),
    );
  }
}
