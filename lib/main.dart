import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_emulators.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/firebase_auth_repository.dart';
import 'services/firebase_doctor_link_repository.dart';
import 'state/auth_provider.dart';
import 'state/doctor_link_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
          create: (_) => AuthProvider(
            FirebaseAuthRepository(),
          )..start(),
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      // Every route goes through the gate, so no URL or named route can
      // bypass authentication or role checks.
      home: const AuthGate(),
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => const AuthGate(),
      ),
    );
  }
}
