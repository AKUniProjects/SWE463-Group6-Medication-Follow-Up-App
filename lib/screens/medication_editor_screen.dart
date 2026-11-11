import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/medication.dart';
import '../services/medication_validation.dart';
import '../state/medication_provider.dart';
import '../widgets/medication_widgets.dart';
import 'medication_delete_screen.dart';

class MedicationEditorScreen extends StatefulWidget {
  const MedicationEditorScreen({this.medicationId, super.key});
  final String? medicationId;
  @override
  State<MedicationEditorScreen> createState() => _MedicationEditorScreenState();
}

class _MedicationEditorScreenState extends State<MedicationEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _dose = TextEditingController();
  final _stock = TextEditingController();
  final _threshold = TextEditingController();
  final _consumption = TextEditingController();
  final _times = <String>[];
  String _unit = 'tablet';
  String _stockUnit = 'tablet';
  String? _owner;
  String? _error;
  String? _timeError;
  Medication? _original;
  bool _initialized = false;
  bool _saving = false;
  bool get _editing => widget.medicationId != null;

  void _initialize(MedicationProvider state) {
    if (_initialized) return;
    _owner = state.patientId;
    _original = _editing ? state.find(widget.medicationId!) : null;
    final m = _original;
    if (_editing && m == null) return;
    _name.text = m?.name ?? '';
    _dose.text =
        m?.doseAmount.toString().replaceFirst(RegExp(r'\.0$'), '') ?? '';
    _stock.text = m?.stockAmount.toString() ?? '';
    _threshold.text = (m?.refillThreshold ?? defaultRefillThreshold).toString();
    _consumption.text = m?.unitsPerDose?.toString() ?? '';
    _unit = m?.doseUnit ?? 'tablet';
    _stockUnit = m?.stockUnit ?? 'tablet';
    _times.addAll(m?.scheduledTimes ?? []);
    _initialized = true;
  }

  @override
  void dispose() {
    for (final controller in [_name, _dose, _stock, _threshold, _consumption]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseTime(
    FormFieldState<List<String>> field, [
    int? index,
  ]) async {
    final current = index == null ? '08:00' : _times[index];
    final parts = current.split(':');
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (!mounted || selected == null) return;
    final time =
        '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
    if (_times.asMap().entries.any((e) => e.key != index && e.value == time)) {
      setState(() => _timeError = 'That daily time is already added');
      return;
    }
    setState(() {
      if (index == null) {
        _times.add(time);
      } else {
        _times[index] = time;
      }
      _times.sort();
      _timeError = null;
    });
    field.didChange(List.of(_times));
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final state = context.read<MedicationProvider>();
    if (state.patientId != _owner || _owner == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    // Keep the original ID/revision. Reopen concurrent changes instead of
    // silently overwriting newer supply or schedules.
    final draft = Medication(
      id: _original?.id ?? '',
      patientId: _owner!,
      name: _name.text.trim(),
      doseAmount: double.parse(_dose.text.trim()),
      doseUnit: _unit,
      scheduledTimes: List.unmodifiable(_times),
      stockAmount: int.parse(_stock.text.trim()),
      refillThreshold: int.parse(_threshold.text.trim()),
      stockUnit: _stockUnit,
      unitsPerDose: int.tryParse(_consumption.text.trim()),
      revision: _original?.revision ?? 0,
    );
    final saved = await state.save(draft, creating: !_editing);
    if (!mounted) return;
    if (saved != null) {
      Navigator.pop(
        context,
        _editing ? 'Medication updated' : 'Medication added',
      );
    } else {
      setState(() {
        _saving = false;
        _error = state.writeError ?? 'Could not save. Try again.';
      });
    }
  }

  Future<void> _delete() async {
    final result = await Navigator.of(context).push<MedicationDeleteResult>(
      MaterialPageRoute(
        builder: (_) => MedicationDeleteScreen(medication: _original!),
      ),
    );
    if (!mounted || result == null || result == MedicationDeleteResult.keep) {
      return;
    }
    Navigator.pop(
      context,
      result == MedicationDeleteResult.deleted ? 'Medication deleted' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MedicationProvider>();
    if (!state.isLoading) _initialize(state);
    final missing =
        _editing && (state.find(widget.medicationId!)?.isActive != true);
    final changedSession = _initialized && _owner != state.patientId;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editing ? 'Edit medication' : 'Add medication'),
        ),
        body: MedicationLoadGuard(
          child: missing || changedSession
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'This medication is no longer available. Go back to the list.',
                    ),
                  ),
                )
              : Form(
                  key: _form,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _editing ? 'Medication details' : 'New medication',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter your prescribed fixed daily schedule.',
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          key: const Key('medication-name'),
                          controller: _name,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Medication name',
                          ),
                          textCapitalization: TextCapitalization.words,
                          validator: validateMedicationName,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('medication-dose'),
                          controller: _dose,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(labelText: 'Dose'),
                          validator: validateDose,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _unit,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Dosage unit',
                          ),
                          items: doseUnits
                              .map(
                                (u) =>
                                    DropdownMenuItem(value: u, child: Text(u)),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (u) => setState(() => _unit = u!),
                          validator: (u) => doseUnits.contains(u)
                              ? null
                              : 'Choose a valid unit',
                        ),
                        const SizedBox(height: 16),
                        FormField<List<String>>(
                          initialValue: List.of(_times),
                          validator: (_) => validateTimes(_times),
                          builder: (field) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Daily times'),
                              Wrap(
                                spacing: 8,
                                children: _times
                                    .asMap()
                                    .entries
                                    .map(
                                      (e) => InputChip(
                                        label: Text(e.value),
                                        onPressed: _saving
                                            ? null
                                            : () => _chooseTime(field, e.key),
                                        onDeleted: _saving
                                            ? null
                                            : () {
                                                setState(() {
                                                  _times.removeAt(e.key);
                                                  _timeError = null;
                                                });
                                                field.didChange(
                                                  List.of(_times),
                                                );
                                              },
                                        deleteButtonTooltipMessage:
                                            'Remove ${e.value}',
                                      ),
                                    )
                                    .toList(),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed:
                                      _saving || _times.length >= maxDailyTimes
                                      ? null
                                      : () => _chooseTime(field),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add time'),
                                ),
                              ),
                              if (field.errorText != null || _timeError != null)
                                Text(
                                  _timeError ?? field.errorText!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('medication-stock'),
                          controller: _stock,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Remaining supply',
                          ),
                          validator: validateStock,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Supply details',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Count supply separately from the prescribed dose. '
                          'A dose in mg does not tell us how many tablets you use.',
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _stockUnit,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Counted stock unit',
                          ),
                          items: stockUnits
                              .map(
                                (u) =>
                                    DropdownMenuItem(value: u, child: Text(u)),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (u) => setState(() => _stockUnit = u!),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('medication-consumption'),
                          controller: _consumption,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Stock units per dose (optional)',
                            helperText: 'Leave blank if unknown; days remaining will be unavailable.',
                            helperMaxLines: 3,
                          ),
                          validator: validateConsumption,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('medication-threshold'),
                          controller: _threshold,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Low supply threshold',
                            helperText: 'Warn when remaining stock is at or below this quantity.',
                            helperMaxLines: 3,
                          ),
                          validator: validateStock,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          MessageCard(message: _error!, warning: true),
                        ],
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _saving || state.isBusy ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(
                            _saving
                                ? 'Saving…'
                                : _editing
                                ? 'Save changes'
                                : 'Save medication',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        if (_editing)
                          OutlinedButton.icon(
                            onPressed: _saving || state.isBusy ? null : _delete,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete medication'),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
