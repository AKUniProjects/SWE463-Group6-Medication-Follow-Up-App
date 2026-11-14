import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/doctor_link.dart';
import 'package:medication_follow_up_app/models/dose_record.dart';
import 'package:medication_follow_up_app/models/medication.dart';
import 'package:medication_follow_up_app/services/doctor_records_repository.dart';
import 'package:medication_follow_up_app/state/doctor_dashboard_provider.dart';

class LiveDoctorRecords implements DoctorRecordsRepository {
  final links = StreamController<List<DoctorLink>>.broadcast();
  final doses = StreamController<List<DoseRecord>>.broadcast();
  final medications = StreamController<List<Medication>>.broadcast();
  @override
  String? Function() get currentDoctorId => _doctorId;
  String? _doctorId() => 'doctor';
  @override
  Stream<List<DoctorLink>> watchActiveLinks() => links.stream;
  @override
  Stream<List<DoseRecord>> watchPatientDoses(String patientId) => doses.stream;
  @override
  Stream<List<Medication>> watchPatientMedications(String patientId) =>
      medications.stream;
  Future<void> close() async {
    await links.close();
    await doses.close();
    await medications.close();
  }
}

void main() {
  late LiveDoctorRecords repository;
  late DoctorDashboardProvider dashboard;
  final now = DateTime(2026, 11, 14, 8, 5);
  const link = DoctorLink(
    id: 'patient_doctor',
    patientId: 'patient',
    doctorId: 'doctor',
    patientName: 'Fictional patient',
    linkCode: 'ABCDEFGH23',
    status: LinkStatus.active,
  );
  const medication = Medication(
    id: 'medication',
    patientId: 'patient',
    name: 'Fictional medicine',
    doseAmount: 1,
    doseUnit: 'tablet',
    scheduledTimes: ['08:00'],
    stockAmount: 5,
    refillThreshold: 7,
  );
  setUp(() {
    repository = LiveDoctorRecords();
    dashboard = DoctorDashboardProvider(repository, now: () => now);
  });
  tearDown(() async {
    dashboard.dispose();
    await repository.close();
  });
  Future<void> load() async {
    dashboard.updateSession('doctor');
    await pumpEventQueue();
    repository.links.add([link]);
    await pumpEventQueue();
    repository.doses.add([]);
    repository.medications.add([medication]);
    await pumpEventQueue();
  }

  test('live saved confirmation updates doctor statistics; revocation clears records', () async {
    await load();
    expect(dashboard.patients.single.weeklyStats.hasAdherenceData, isFalse);
    repository.doses.add([
      DoseRecord(
        id: 'medication_20261114_0800',
        medicationId: 'medication',
        patientId: 'patient',
        medicationName: medication.name,
        scheduledTime: DateTime(2026, 11, 14, 8),
        status: DoseStatus.taken,
        confirmedAt: now,
      ),
    ]);
    await pumpEventQueue();
    expect(dashboard.patients.single.weeklyStats.takenDoses, 1);
    expect(dashboard.patients.single.weeklyStats.percentage, 1);
    repository.links.add([]);
    await pumpEventQueue();
    expect(dashboard.patients, isEmpty);
    repository.medications.add([medication]);
    await pumpEventQueue();
    expect(dashboard.patientById('patient'), isNull);
  });

  test(
    'session changes and patient read failures clear private cached records',
    () async {
      await load();
      repository.doses.addError(StateError('permission revoked'));
      await pumpEventQueue();
      expect(dashboard.patients.single.errorMessage, isNotNull);
      expect(dashboard.patients.single.medications, isEmpty);
      expect(dashboard.patients.single.doseRecords, isEmpty);
      dashboard.updateSession(null);
      expect(dashboard.patients, isEmpty);
      repository.links.add([link]);
      await pumpEventQueue();
      expect(dashboard.patients, isEmpty);
    },
  );
}
