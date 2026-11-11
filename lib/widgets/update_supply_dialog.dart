import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/medication.dart';
import '../services/medication_validation.dart';
import '../state/medication_provider.dart';
import 'medication_widgets.dart';

class UpdateSupplyDialog extends StatefulWidget {
  const UpdateSupplyDialog({required this.medication, super.key});
  final Medication medication;
  @override
  State<UpdateSupplyDialog> createState() => _UpdateSupplyDialogState();
}

class _UpdateSupplyDialogState extends State<UpdateSupplyDialog> {
  final _form = GlobalKey<FormState>();
  late final _quantity = TextEditingController(
    text: widget.medication.stockAmount.toString(),
  );
  bool _pending = false;
  String? _error;
  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_pending || !_form.currentState!.validate()) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    final state = context.read<MedicationProvider>();
    final result = await state.updateSupply(
      widget.medication,
      int.parse(_quantity.text.trim()),
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _pending = false;
        _error = state.writeError ?? 'Could not update supply. Retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_pending,
    child: AlertDialog(
      title: const Text('Update supply'),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.medication.name),
            const SizedBox(height: 8),
            Text(
              'Current supply: ${widget.medication.stockAmount} ${widget.medication.stockUnit}',
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('supply-quantity'),
              controller: _quantity,
              enabled: !_pending,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'New quantity'),
              validator: validateStock,
            ),
            if (_error != null) MessageCard(message: _error!, warning: true),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _pending ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _pending ? null : _save,
          child: Text(_pending ? 'Saving…' : 'Save quantity'),
        ),
      ],
    ),
  );
}
