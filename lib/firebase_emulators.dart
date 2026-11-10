import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Opt-in local emulator mode for development only.
///
/// Enable with:
///   flutter run --dart-define=USE_FIREBASE_EMULATORS=true
/// Optional host override (for example a physical device on the LAN):
///   --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.20
const bool kUseFirebaseEmulators = bool.fromEnvironment(
  'USE_FIREBASE_EMULATORS',
);
const String _hostOverride = String.fromEnvironment('FIREBASE_EMULATOR_HOST');

const int authEmulatorPort = 9099;
const int firestoreEmulatorPort = 8080;

/// Host that reaches the developer machine from the running app.
///
/// The Android Emulator sees the host machine as 10.0.2.2; Chrome/Edge and
/// desktop use localhost.
String emulatorHost() {
  if (_hostOverride.isNotEmpty) return _hostOverride;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return '10.0.2.2';
  }
  return 'localhost';
}

/// Points Firebase Auth and Firestore at the local emulators.
///
/// Must run after `Firebase.initializeApp` and before any repository uses
/// Firebase. Any failure is rethrown so the app never silently falls back
/// to the live project. Release builds refuse emulator mode entirely.
Future<void> connectToFirebaseEmulators() async {
  if (kReleaseMode) {
    throw StateError('Firebase emulators cannot be used in release builds.');
  }

  final host = emulatorHost();
  FirebaseFirestore.instance.useFirestoreEmulator(host, firestoreEmulatorPort);
  await FirebaseAuth.instance.useAuthEmulator(host, authEmulatorPort);
  debugPrint('Using Firebase emulators at $host '
      '(auth:$authEmulatorPort, firestore:$firestoreEmulatorPort).');
}
