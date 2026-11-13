import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dose_record.dart';
import '../models/user_profile.dart';
import '../state/auth_provider.dart';
import '../state/dose_provider.dart';
import 'dose_confirmed_screen.dart';
import '../state/medication_provider.dart';
import '../widgets/auth_form_widgets.dart';
import 'doctor_code_dialog.dart';
import 'linked_patients_dashboard.dart';
import 'medications_screen.dart';
import 'patient_home_screen.dart';
import 'medication_editor_screen.dart';
import 'refill_tracking_screen.dart';

/// Role-specific navigation. Patients never get the doctor dashboard tab.
class AppShell extends StatefulWidget {
  const AppShell({required this.role, super.key});

  final UserRole role;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-check overdue/missed when the patient returns to the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.role == UserRole.patient) {
      context.read<DoseProvider>().evaluateStatuses();
    }
  }

  /// Mark as Taken: save first, then show 04b only if the save worked.
  Future<void> _confirmDose(DoseRecord dose) async {
    final doses = context.read<DoseProvider>();
    final confirmation = await doses.confirm(dose);
    if (!mounted) return;
    if (confirmation == null) {
      // Null without an error means a second tap while saving: ignore.
      final error = doses.confirmError;
      if (error == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _confirmDose(dose),
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DoseConfirmedScreen(confirmation: confirmation),
      ),
    );
  }

  Future<void> _editMedication(String id) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _selectedIndex = 1);
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MedicationEditorScreen(medicationId: id),
      ),
    );
    if (mounted && message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  late final List<NavigationDestination> _destinations =
      widget.role == UserRole.doctor
      ? const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
        ]
      : const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.medication_outlined),
            selectedIcon: Icon(Icons.medication),
            label: 'Medications',
          ),
        ];

  @override
  Widget build(BuildContext context) {
    final doses = widget.role == UserRole.patient
        ? context.watch<DoseProvider>()
        : null;
    final pages = doses == null
        ? [const LinkedPatientsDashboard()]
        : [
            PatientHomeScreen(
              medications: context
                  .watch<MedicationProvider>()
                  .activeMedications,
              doseRecords: doses.todayDoses,
              displayName:
                  context.watch<AuthProvider>().userProfile?.displayName ??
                  'Patient',
              progress: doses.progress,
              isLoadingDoses: doses.isLoading,
              doseError: doses.errorMessage,
              onRetryDoses: doses.retry,
              onTaken: _confirmDose,
              isPending: doses.isPending,
              isConfirming: doses.isConfirming,
              reviewCount: doses.needsReview.length,
              onMedicationTap: _editMedication,
              onRefills: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const RefillTrackingScreen()),
              ),
            ),
            const MedicationsScreen(),
          ];
    final error = context.watch<AuthProvider>().actionErrorMessage;
    return Scaffold(
      body: Column(
        children: [
          if (error != null)
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AuthErrorBanner(message: error),
              ),
            ),
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          // Destinations after the pages are actions, not pages.
          final isDoctor = widget.role == UserRole.doctor;
          if (isDoctor && index == pages.length) {
            showDoctorCodeDialog(context);
            return;
          }
          if (index == pages.length + (isDoctor ? 1 : 0)) {
            context.read<AuthProvider>().signOut();
            return;
          }
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: [
          ..._destinations,
          if (widget.role == UserRole.doctor)
            const NavigationDestination(
              icon: Icon(Icons.qr_code_2_outlined),
              label: 'Linking code',
            ),
          const NavigationDestination(
            icon: Icon(Icons.logout),
            label: 'Sign out',
          ),
        ],
      ),
    );
  }
}
