import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_profile.dart';
import '../services/sample_data.dart';
import '../state/auth_provider.dart';
import 'doctor_dashboard_screen.dart';
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
      ? [DoctorDashboardScreen(patients: SampleData.patientSummaries)]
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
          // Last destination is sign out, not a page.
          if (index == _pages.length) {
            context.read<AuthProvider>().signOut();
            return;
          }
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: [
          ..._destinations,
          const NavigationDestination(
            icon: Icon(Icons.logout),
            label: 'Sign out',
          ),
        ],
      ),
    );
  }
}
