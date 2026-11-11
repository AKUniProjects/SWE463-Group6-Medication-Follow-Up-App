import 'package:flutter/widgets.dart';
import 'package:medication_follow_up_app/main.dart';
import 'package:medication_follow_up_app/services/doctor_link_repository.dart';
import 'package:medication_follow_up_app/state/auth_provider.dart';
import 'package:medication_follow_up_app/state/doctor_link_provider.dart';
import 'package:provider/provider.dart';
import 'package:medication_follow_up_app/services/medication_repository.dart';
import 'package:medication_follow_up_app/state/medication_provider.dart';

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
