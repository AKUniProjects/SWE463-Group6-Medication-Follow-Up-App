import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import 'firebase_emulators.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/firebase_auth_repository.dart';
import 'services/firebase_doctor_link_repository.dart';
import 'state/auth_provider.dart';
import 'state/doctor_link_provider.dart';
import 'state/medication_provider.dart';
import 'services/medication_repository.dart';
import 'services/firestore_medication_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Development-only: connect to local emulators when explicitly enabled.
  if (kUseFirebaseEmulators) {
    await connectToFirebaseEmulators();
  }

  // Provide shared authentication state to the application.
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          lazy: false,
          create: (_) => AuthProvider(FirebaseAuthRepository())..start(),
        ),
        // Doctor-code state follows the signed-in user: it is cleared on
        // sign-out or account switch. Only verified-profile doctors may act.
        ChangeNotifierProxyProvider<AuthProvider, DoctorLinkProvider>(
          create: (_) => DoctorLinkProvider(FirebaseDoctorLinkRepository()),
          update: (_, auth, links) => links!
            ..updateSession(
              uid: auth.isAuthenticated ? auth.userId : null,
              isDoctor: auth.isDoctor,
              isPatient: auth.isPatient,
            ),
        ),
        ChangeNotifierProxyProvider<AuthProvider, MedicationProvider>(
          create: (context) => MedicationProvider(
            StoredMedicationRepository(
              FirestoreMedicationStore(FirebaseFirestore.instance),
              currentPatientId: () {
                final auth = context.read<AuthProvider>();
                return auth.isPatient ? auth.userId : null;
              },
            ),
          ),
          update: (_, auth, medications) =>
              medications!..updateSession(auth.isPatient ? auth.userId : null),
        ),
      ],
      child: const MedicationFollowUpApp(),
    ),
  );
}

class MedicationFollowUpApp extends StatelessWidget {
  const MedicationFollowUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medication Follow-up',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Firebase Auth injects a fixed warning banner in web emulator mode.
      // Reserve its space so it cannot cover navigation or the last action.
      builder: (context, child) => Padding(
        padding: const EdgeInsets.only(
          bottom: kIsWeb && kUseFirebaseEmulators ? 48 : 0,
        ),
        child: child,
      ),
      // Every route goes through the gate, so no URL or named route can
      // bypass authentication or role checks.
      home: const AuthGate(),
      onGenerateRoute: (_) =>
          MaterialPageRoute<void>(builder: (_) => const AuthGate()),
    );
  }
}
