import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/medication.dart';
import '../state/medication_provider.dart';
import '../widgets/medication_widgets.dart';

enum MedicationDeleteResult { keep, back, deleted }

class MedicationDeleteScreen extends StatefulWidget {
  const MedicationDeleteScreen({required this.medication, super.key});
  final Medication medication;
  @override
  State<MedicationDeleteScreen> createState() => _MedicationDeleteScreenState();
}

class _MedicationDeleteScreenState extends State<MedicationDeleteScreen> {
  bool _pending = false;
  String? _error;
  Future<void> _confirm() async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    final state = context.read<MedicationProvider>();
    final deleted = await state.deactivate(widget.medication);
    if (!mounted) return;
    if (deleted != null) {
      Navigator.pop(context, MedicationDeleteResult.deleted);
    } else {
      setState(() {
        _pending = false;
        _error = state.writeError ?? 'Could not delete. Retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_pending,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Delete confirmation'),
        leading: BackButton(
          onPressed: _pending
              ? null
              : () => Navigator.pop(context, MedicationDeleteResult.back),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          MessageCard(
            warning: true,
            message:
                'Remove ${widget.medication.name}?\n\n'
                'It will leave your active schedule. Past dose confirmations remain recorded. '
                'Future reminders stop when the device reminder service is connected.',
          ),
          if (_error != null) MessageCard(message: _error!, warning: true),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _pending ? null : _confirm,
            child: Text(_pending ? 'Deleting…' : 'Confirm delete'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _pending
                ? null
                : () => Navigator.pop(context, MedicationDeleteResult.keep),
            child: const Text('Keep medication'),
          ),
        ],
      ),
    ),
  );
}
