import 'dart:math';

import '../models/doctor_link.dart';

/// Doctor-patient linking operations (Task 3.3).
///
/// Identity always comes from the signed-in Firebase user; callers never
/// pass a patient or doctor ID for authorization. Firestore Security Rules
/// enforce every check again on the server.
///
/// Coursework prototype: doctors self-register and are not professionally
/// verified.
abstract class DoctorLinkRepository {
  // ----- Doctor -----

  /// Creates a new active code for the signed-in doctor.
  Future<DoctorCode> createCode();

  /// The signed-in doctor's codes, newest first.
  Future<List<DoctorCode>> myCodes();

  /// Deactivates one of the signed-in doctor's codes (one-way).
  Future<void> deactivateCode(String code);

  /// Issues a new code, then deactivates [oldCode].
  Future<DoctorCode> replaceCode(String oldCode);

  /// Links where the signed-in user is the doctor.
  Future<List<DoctorLink>> linksForDoctor({bool activeOnly = true});

  // ----- Patient -----

  /// Validates [input] (any case, spaces or hyphens) and returns the usable
  /// code with the doctor's name only. Never returns patient data.
  Future<DoctorCode> lookupCode(String input);

  /// Creates or reactivates the link to the code's doctor. Requires
  /// [consentGiven] to be true (explicit patient consent).
  Future<DoctorLink> linkWithCode(
    String input, {
    required bool consentGiven,
  });

  /// Links where the signed-in user is the patient.
  Future<List<DoctorLink>> linksForPatient({bool activeOnly = false});

  // ----- Either party -----

  /// Revokes an active link the signed-in user belongs to.
  Future<void> revokeLink(DoctorLink link);
}

enum DoctorLinkErrorCode {
  notSignedIn,
  notDoctor,
  notPatient,
  consentRequired,
  invalidCodeFormat,
  codeNotFound,
  codeInactive,
  codeExpired,
  ownCode,
  alreadyLinked,
  newCodeRequired,
  notLinked,
  codeGenerationFailed,
  permissionDenied,
  network,
  unknown,
}

/// User-safe, predictable Doctor Linking failure.
class DoctorLinkException implements Exception {
  const DoctorLinkException(this.code);

  final DoctorLinkErrorCode code;

  String get message {
    switch (code) {
      case DoctorLinkErrorCode.notSignedIn:
        return 'Please sign in again.';
      case DoctorLinkErrorCode.notDoctor:
        return 'Only doctor accounts can manage linking codes.';
      case DoctorLinkErrorCode.notPatient:
        return 'Only patient accounts can link to a doctor.';
      case DoctorLinkErrorCode.consentRequired:
        return 'Please confirm that you agree to share your records.';
      case DoctorLinkErrorCode.invalidCodeFormat:
        return 'Enter the 10-character code from your doctor.';
      case DoctorLinkErrorCode.codeNotFound:
        return 'This code was not found. Check it and try again.';
      case DoctorLinkErrorCode.codeInactive:
        return 'This code is no longer active. Ask your doctor for a new one.';
      case DoctorLinkErrorCode.codeExpired:
        return 'This code has expired. Ask your doctor for a new one.';
      case DoctorLinkErrorCode.ownCode:
        return 'You cannot link to your own account.';
      case DoctorLinkErrorCode.alreadyLinked:
        return 'You are already linked to this doctor.';
      case DoctorLinkErrorCode.newCodeRequired:
        return 'Your doctor ended this link. Ask them for a new code.';
      case DoctorLinkErrorCode.notLinked:
        return 'This link is no longer active.';
      case DoctorLinkErrorCode.codeGenerationFailed:
        return 'Could not create a code. Please try again.';
      case DoctorLinkErrorCode.permissionDenied:
        return 'You do not have permission to do this.';
      case DoctorLinkErrorCode.network:
        return 'Network error. Check your connection and try again.';
      case DoctorLinkErrorCode.unknown:
        return 'Something went wrong. Please try again.';
    }
  }

  @override
  String toString() => 'DoctorLinkException(${code.name})';
}

/// Generates a canonical code with a cryptographically secure RNG.
String generateSecureDoctorCode([Random? random]) {
  final rng = random ?? Random.secure();
  return List.generate(
    doctorCodeLength,
    (_) => doctorCodeAlphabet[rng.nextInt(doctorCodeAlphabet.length)],
  ).join();
}
