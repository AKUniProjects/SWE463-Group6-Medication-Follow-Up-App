import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/app_shell.dart';
import 'screens/auth_screen.dart';
import 'services/firebase_auth_repository.dart';
import 'state/auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Provide shared authentication state to the application.
  runApp(
    ChangeNotifierProvider<AuthProvider>(
      lazy: false,
      create: (_) => AuthProvider(
        FirebaseAuthRepository(),
      )..start(),
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
      home: const AuthScreen(),
      routes: {
        '/app': (_) => const AppShell(),
      },
    );
  }
}
