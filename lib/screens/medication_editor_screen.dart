import 'package:flutter/material.dart';

import '../models/medication.dart';

class MedicationEditorScreen extends StatefulWidget {
  const MedicationEditorScreen({this.medication, super.key});

  final Medication? medication;

  @override
  State<MedicationEditorScreen> createState() => _MedicationEditorScreenState();
}

class _MedicationEditorScreenState extends State<MedicationEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _doseController;
  late final TextEditingController _stockController;
  String _unit = 'tablet';
  String _time = '08:00';

  @override
  void initState() {
    super.initState();
    final medication = widget.medication;
    _nameController = TextEditingController(text: medication?.name);
    _doseController = TextEditingController(
      text: medication == null ? '' : medication.doseAmount.toString(),
    );
    _stockController = TextEditingController(
      text: medication == null ? '' : medication.stockAmount.toString(),
    );
    _unit = medication?.doseUnit ?? _unit;
    _time = medication != null && medication.scheduledTimes.isNotEmpty
        ? medication.scheduledTimes.first
        : _time;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _doseController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Medication saved in demo mode')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.medication != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit medication' : 'Add medication')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Medication name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a medication name'
                  : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _doseController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Dose'),
                    validator: (value) => double.tryParse(value ?? '') == null
                        ? 'Enter a number'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    items: const [
                      DropdownMenuItem(value: 'tablet', child: Text('Tablet')),
                      DropdownMenuItem(value: 'mg', child: Text('mg')),
                      DropdownMenuItem(value: 'ml', child: Text('ml')),
                      DropdownMenuItem(value: 'IU', child: Text('IU')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _unit = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _time,
              decoration: const InputDecoration(labelText: 'Daily time'),
              items: const [
                DropdownMenuItem(value: '08:00', child: Text('08:00')),
                DropdownMenuItem(value: '12:00', child: Text('12:00')),
                DropdownMenuItem(value: '20:00', child: Text('20:00')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _time = value);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _stockController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Current supply'),
              validator: (value) => int.tryParse(value ?? '') == null
                  ? 'Enter a whole number'
                  : null,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save medication'),
            ),
          ],
        ),
      ),
    );
  }
}
