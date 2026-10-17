import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'screens/auth_screen.dart';

void main() {
  runApp(const MedicationFollowUpApp());
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
