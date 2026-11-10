import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_profile.dart';
import '../services/sample_data.dart';
import '../state/auth_provider.dart';
import 'doctor_code_dialog.dart';
import 'linked_patients_dashboard.dart';
import 'medications_screen.dart';
import 'patient_home_screen.dart';

/// Role-specific navigation. Patients never get the doctor dashboard tab.
class AppShell extends StatefulWidget {
  const AppShell({required this.role, super.key});

  final UserRole role;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  late final List<Widget> _pages = widget.role == UserRole.doctor
      ? [const LinkedPatientsDashboard()] // real linked patients (Task 3.6)
      : [
          PatientHomeScreen(
            medications: SampleData.medications,
            doseRecords: SampleData.doseRecords,
          ),
          MedicationsScreen(medications: SampleData.medications),
        ];

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
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          // Destinations after the pages are actions, not pages.
          final isDoctor = widget.role == UserRole.doctor;
          if (isDoctor && index == _pages.length) {
            showDoctorCodeDialog(context);
            return;
          }
          if (index == _pages.length + (isDoctor ? 1 : 0)) {
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
