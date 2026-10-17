import 'package:flutter/material.dart';

import '../services/sample_data.dart';
import 'doctor_dashboard_screen.dart';
import 'medications_screen.dart';
import 'patient_home_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  late final List<Widget> _pages = [
    PatientHomeScreen(
      medications: SampleData.medications,
      doseRecords: SampleData.doseRecords,
    ),
    MedicationsScreen(medications: SampleData.medications),
    DoctorDashboardScreen(patients: SampleData.patientSummaries),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
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
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Doctor view',
          ),
        ],
      ),
    );
  }
}
