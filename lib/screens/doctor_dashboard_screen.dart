import 'package:flutter/material.dart';

import '../models/patient_summary.dart';
import 'patient_details_screen.dart';

class DoctorDashboardScreen extends StatelessWidget {
  const DoctorDashboardScreen({required this.patients, super.key});

  final List<PatientSummary> patients;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Doctor dashboard')),
      body: patients.isEmpty
          ? const Center(child: Text('No linked patients yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: patients.length,
              itemBuilder: (context, index) {
                final patient = patients[index];
                final percentage = patient.stats.percentage;
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PatientDetailsScreen(patient: patient),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  patient.patientName,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              if (patient.requiresFollowUp)
                                const Chip(
                                  label: Text('Follow-up'),
                                  avatar: Icon(Icons.flag_outlined, size: 18),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(value: percentage),
                          const SizedBox(height: 8),
                          Text(
                            '${(percentage * 100).round()}% adherence • '
                            '${patient.missedDoses} missed • '
                            '${patient.overdueDoses} overdue',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
