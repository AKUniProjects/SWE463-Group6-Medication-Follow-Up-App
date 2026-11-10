import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/adherence_stats.dart';
import '../models/patient_summary.dart';
import '../services/doctor_link_repository.dart';
import '../state/doctor_link_provider.dart';
import 'doctor_dashboard_screen.dart';

/// Integration adapter (Task 3.6): supplies the teammate-owned
/// [DoctorDashboardScreen] with the signed-in doctor's REAL linked patients
/// instead of sample data. The dashboard's UI and logic are unchanged.
///
/// Statistics are not available yet (no dose records), so each summary
/// carries empty stats; the dashboard owner will replace [toPatientSummary]
/// stats with real adherence data.
class LinkedPatientsDashboard extends StatefulWidget {
  const LinkedPatientsDashboard({super.key});

  @override
  State<LinkedPatientsDashboard> createState() =>
      _LinkedPatientsDashboardState();
}

/// Maps an authorized linked patient to the dashboard's existing model.
/// `patientId` is the patient's Firebase Auth UID (used by detail screens).
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

class _LinkedPatientsDashboardState extends State<LinkedPatientsDashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DoctorLinkProvider>().loadLinkedPatients();
    });
  }

  @override
  Widget build(BuildContext context) {
    final links = context.watch<DoctorLinkProvider>();

    if (!links.hasLoadedLinkedPatients) {
      final error = links.linkedPatientsError;
      return Scaffold(
        appBar: AppBar(title: const Text('Doctor dashboard')),
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: links.loadLinkedPatients,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }

    final dashboard = DoctorDashboardScreen(
      patients: links.linkedPatients.map(toPatientSummary).toList(),
    );
    return Stack(
      children: [
        // Pull-to-refresh re-checks links (revoked patients disappear).
        // Mouse/trackpad drags are enabled so it also works in Chrome.
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
          ),
          child: RefreshIndicator(
            onRefresh: links.loadLinkedPatients,
            notificationPredicate: (n) => n.depth <= 1,
            child: dashboard,
          ),
        ),
        if (links.linkedPatientsError != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                title: Text(links.linkedPatientsError!),
                trailing: TextButton(
                  onPressed: links.loadLinkedPatients,
                  child: const Text('Retry'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
