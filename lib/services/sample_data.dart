import '../models/adherence_stats.dart';
import '../models/dose_record.dart';
import '../models/medication.dart';
import '../models/patient_summary.dart';

class SampleData {
  static final medications = <Medication>[
    const Medication(
      id: 'med-001',
      patientId: 'patient-001',
      name: 'Vitamin D',
      doseAmount: 1000,
      doseUnit: 'IU',
      scheduledTimes: ['08:00'],
      stockAmount: 18,
      refillThreshold: 7,
    ),
    const Medication(
      id: 'med-002',
      patientId: 'patient-001',
      name: 'Blood pressure tablet',
      doseAmount: 1,
      doseUnit: 'tablet',
      scheduledTimes: ['20:00'],
      stockAmount: 5,
      refillThreshold: 7,
    ),
  ];

  static final doseRecords = <DoseRecord>[
    DoseRecord(
      id: 'dose-001',
      medicationId: 'med-001',
      patientId: 'patient-001',
      medicationName: 'Vitamin D',
      scheduledTime: DateTime(2026, 10, 17, 8),
      status: DoseStatus.taken,
      confirmedAt: DateTime(2026, 10, 17, 8, 4),
    ),
    DoseRecord(
      id: 'dose-002',
      medicationId: 'med-002',
      patientId: 'patient-001',
      medicationName: 'Blood pressure tablet',
      scheduledTime: DateTime(2026, 10, 17, 20),
      status: DoseStatus.scheduled,
    ),
  ];

  static final patientSummaries = <PatientSummary>[
    const PatientSummary(
      patientId: 'patient-001',
      patientName: 'Demo Patient',
      stats: AdherenceStats(
        periodLabel: 'This week',
        scheduledDoses: 14,
        takenDoses: 12,
        missedDoses: 2,
      ),
      missedDoses: 2,
      overdueDoses: 1,
      requiresFollowUp: true,
    ),
    const PatientSummary(
      patientId: 'patient-002',
      patientName: 'Sample Patient',
      stats: AdherenceStats(
        periodLabel: 'This week',
        scheduledDoses: 14,
        takenDoses: 14,
        missedDoses: 0,
      ),
      missedDoses: 0,
      overdueDoses: 0,
      requiresFollowUp: false,
    ),
  ];
}
