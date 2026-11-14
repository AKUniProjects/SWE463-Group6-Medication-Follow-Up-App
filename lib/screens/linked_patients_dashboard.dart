import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/adherence_stats.dart';
import '../models/patient_summary.dart';
import '../services/doctor_link_repository.dart';
import '../state/auth_provider.dart';
import '../state/doctor_dashboard_provider.dart';
import '../widgets/medication_widgets.dart';
import 'doctor_code_dialog.dart';
import 'doctor_dashboard_screen.dart';

PatientSummary toPatientSummary(LinkedPatient patient) => PatientSummary(
  patientId: patient.patientId,
  patientName: patient.displayName,
  stats: const AdherenceStats(
    periodLabel: 'No dose records yet',
    scheduledDoses: 0,
    takenDoses: 0,
    missedDoses: 0,
  ),
  missedDoses: 0,
  overdueDoses: 0,
  requiresFollowUp: false,
);

class LinkedPatientsDashboard extends StatelessWidget {
  const LinkedPatientsDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DoctorDashboardProvider>();
    final auth = context.watch<AuthProvider>();
    final patients = dashboard.patients;
    final ready = patients.where((patient) => patient.isReady).toList();
    final failed = patients
        .where((patient) => patient.errorMessage != null)
        .toList();
    final loading = patients.where((patient) => patient.isLoading).length;
    final name = auth.userProfile?.displayName.trim();

    Widget? status;

    if (dashboard.errorMessage != null) {
      status = MessageCard(
        title: 'Unable to load patients',
        message: dashboard.errorMessage!,
        warning: true,
        child: TextButton(
          onPressed: dashboard.retry,
          child: const Text('Try again'),
        ),
      );
    } else if (dashboard.isLoading) {
      status = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (failed.isNotEmpty || loading > 0) {
      status = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text('Loading records for $loading patient(s)…'),
                ],
              ),
            ),
          for (final patient in failed)
            MessageCard(
              title: patient.patientName,
              message: patient.errorMessage!,
              warning: true,
            ),
          if (failed.isNotEmpty)
            TextButton(
              onPressed: dashboard.retry,
              child: const Text('Retry loading records'),
            ),
        ],
      );
    }

    return DoctorDashboardScreen(
      patients: ready.map((patient) => patient.summary).toList(),
      displayName: name == null || name.isEmpty ? 'Doctor' : name,
      linkedPatientCount: dashboard.linkedPatientCount,
      status: status,
      onShowLinkingCode: () => showDoctorCodeDialog(context),
    );
  }
}
