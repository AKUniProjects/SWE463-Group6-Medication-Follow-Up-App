import 'package:flutter/material.dart';

import '../models/medication.dart';
import 'medication_widgets.dart';

class RefillCard extends StatelessWidget {
  const RefillCard({
    required this.medication,
    required this.onUpdate,
    super.key,
  });
  final Medication medication;
  final VoidCallback onUpdate;
  @override
  Widget build(BuildContext context) {
    final days = medication.estimatedDays;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              medication.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('${medication.stockAmount} ${medication.stockUnit} remaining'),
            Text(
              days == null
                  ? 'Days remaining unavailable: stock units per dose are unknown.'
                  : 'Approximately ${days.toStringAsFixed(1)} days remaining',
            ),
            Text(
              'Low supply threshold: ${medication.refillThreshold} ${medication.stockUnit}',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: StockStatus(medication: medication),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onUpdate,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Update quantity'),
            ),
          ],
        ),
      ),
    );
  }
}
