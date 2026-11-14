import 'package:flutter/material.dart';

import '../models/patient_summary.dart';
import '../theme/app_theme.dart';
import '../widgets/adherence_widgets.dart';
import '../widgets/medication_widgets.dart';
import 'patient_details_screen.dart';

class DoctorDashboardScreen extends StatelessWidget {
  const DoctorDashboardScreen({
    required this.patients,
    this.displayName = 'Doctor',
    this.linkedPatientCount,
    this.status,
    this.onShowLinkingCode,
    super.key,
  });

  final List<PatientSummary> patients;
  final String displayName;
  final int? linkedPatientCount;
  final Widget? status;
  final VoidCallback? onShowLinkingCode;

  @override
  Widget build(BuildContext context) {
    final followUp = patients.where((p) => p.requiresFollowUp).toList();
    final others = patients.where((p) => !p.requiresFollowUp).toList();
    final count = linkedPatientCount ?? patients.length;
    final highlighted = followUp.isNotEmpty
        ? followUp.first
        : patients.isNotEmpty
        ? patients.first
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hello, $displayName',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Your patients at a glance',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const CircleAvatar(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  child: Icon(Icons.people_outline),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (status != null) ...[status!, const SizedBox(height: 16)],
            if (count == 0 && status == null)
              const MessageCard(
                title: 'No patient records are shared yet.',
                message:
                    'Give patients your linking code. '
                    'They decide whether to consent.',
              ),
            if (highlighted != null) ...[
              AdherenceProgressCard(
                title: '${highlighted.patientName} • this week',
                stats: highlighted.stats,
              ),
              const SizedBox(height: 16),
            ],
            if (count > 0) ...[
              Row(
                children: [
                  Expanded(child: _countCard('Linked patients', count)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _countCard('Needs follow-up', followUp.length),
                  ),
                ],
              ),
              if (patients.length < count)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Follow-up count includes loaded records only.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 20),
            ],
            if (followUp.isNotEmpty) ...[
              _heading('Patients needing follow-up'),
              for (final patient in followUp) _patientCard(context, patient),
            ],
            if (others.isNotEmpty) ...[
              _heading('Your patients'),
              for (final patient in others) _patientCard(context, patient),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onShowLinkingCode,
              icon: const Icon(Icons.link),
              label: const Text('Show linking code'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.navy,
      ),
    ),
  );

  Widget _countCard(String label, int count) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count.toString().padLeft(2, '0'),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    ),
  );

  Widget _patientCard(BuildContext context, PatientSummary patient) {
    final stats = patient.stats;
    final warning = patient.requiresFollowUp;
    final adherence = stats.hasAdherenceData
        ? '${stats.percentageRounded}% confirmed'
        : 'No evaluated doses yet';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people_outline, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient.patientName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'This week • $adherence',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: warning ? AppColors.cream : AppColors.mint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                warning
                    ? '${patient.missedDoses} missed · '
                          '${patient.overdueDoses} overdue'
                    : stats.hasAdherenceData
                    ? 'On track'
                    : 'Awaiting confirmations',
                style: TextStyle(
                  fontSize: 12,
                  color: warning ? AppColors.amber : AppColors.teal,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.tint,
                  foregroundColor: AppColors.primary,
                ),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => PatientDetailsScreen(patient: patient),
                  ),
                ),
                child: const Text('View patient'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
