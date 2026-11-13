import 'package:flutter/widgets.dart';
import 'package:medication_follow_up_app/main.dart';
import 'package:medication_follow_up_app/services/doctor_link_repository.dart';
import 'package:medication_follow_up_app/state/auth_provider.dart';
import 'package:medication_follow_up_app/state/doctor_link_provider.dart';
import 'package:provider/provider.dart';
import 'package:medication_follow_up_app/services/medication_repository.dart';
import 'package:medication_follow_up_app/state/medication_provider.dart';

import 'package:medication_follow_up_app/services/dose_repository.dart';
import 'package:medication_follow_up_app/state/dose_provider.dart';

import 'memory_dose_store.dart';
import 'memory_medication_store.dart';

/// Doctor-link repository with no linked patients (app-level tests).
class NoPatientsRepo implements DoctorLinkRepository {
  @override
  Future<List<LinkedPatient>> linkedPatientsForDoctor() async => const [];

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// The real app with the same provider wiring as main.dart, using fakes.
Widget appWithProviders(
  AuthProvider auth, {
  DoctorLinkRepository? links,
  MedicationRepository? medications,
  MemoryDoseStore? doseStore,
  DateTime Function()? doseClock,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProxyProvider<AuthProvider, MedicationProvider>(
        create: (_) => MedicationProvider(
          medications ??
              StoredMedicationRepository(
                MemoryMedicationStore(),
                currentPatientId: () => auth.isPatient ? auth.userId : null,
              ),
        ),
        update: (_, a, medications) =>
            medications!..updateSession(a.isPatient ? a.userId : null),
      ),
      // Same as main.dart, with an in-memory dose store and no ticker
      // (widget tests fail if a periodic timer is still running).
      ChangeNotifierProxyProvider2<
        AuthProvider,
        MedicationProvider,
        DoseProvider
      >(
        create: (context) => DoseProvider(
          StoredDoseRepository(
            doseStore ?? MemoryDoseStore(),
            currentPatientId: () => auth.isPatient ? auth.userId : null,
          ),
          now: doseClock,
          tickInterval: null,
          consumeStock:
              ({required medicationId, required doseRecordId}) async =>
                  (await context.read<MedicationProvider>().consumeStock(
                    medicationId: medicationId,
                    doseRecordId: doseRecordId,
                  )).status,
        ),
        update: (_, a, medications, doses) => doses!
          ..updateSession(
            patientId: a.isPatient ? a.userId : null,
            medications: medications.activeMedications,
          ),
      ),
      ChangeNotifierProxyProvider<AuthProvider, DoctorLinkProvider>(
        create: (_) => DoctorLinkProvider(links ?? NoPatientsRepo()),
        update: (_, a, provider) => provider!
          ..updateSession(
            uid: a.isAuthenticated ? a.userId : null,
            isDoctor: a.isDoctor,
            isPatient: a.isPatient,
          ),
      ),
    ],
    child: const MedicationFollowUpApp(),
  );
}
