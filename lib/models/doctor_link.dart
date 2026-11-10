/// Doctor-patient relationship models (Task 3.2).
///
/// `doctorLinks/{patientId}_{doctorId}` is the authoritative relationship.
/// `UserProfile.linkedDoctorIds` is NOT used for authorization.
///
/// Repository write contract (Task 3.3). Security Rules reject
/// client-chosen times, so the `to...Fields()` maps are deliberately
/// INCOMPLETE: the repository must add every field listed in the matching
/// `...ServerTimeFields` constant as `FieldValue.serverTimestamp()`.
///
/// | Operation              | Model fields            | Server timestamp |
/// |------------------------|-------------------------|------------------|
/// | Create code            | `toCreateFields()`      | `createdAt`      |
/// | Deactivate code        | `{'active': false}`     | none             |
/// | Create / reactivate    | `toConsentFields()`     | `consentedAt`    |
/// | Revoke link            | `revocationFields(uid)` | `revokedAt`      |
library;

/// `pending` was removed: consent happens when the patient creates the link.
enum LinkStatus { active, revoked }

/// Codes are valid for exactly 30 days from their server `createdAt`.
/// There is no stored `expiresAt`; Firestore rules derive the same expiry.
const Duration doctorCodeValidity = Duration(days: 30);

/// 32 symbols (A-Z without I and O, digits 2-9): 5 bits each, so a
/// 10-character code carries 50 bits. Task 3.3 must pick characters with a
/// cryptographically secure RNG (`Random.secure()`); rules can check the
/// format but cannot prove randomness.
const String doctorCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const int doctorCodeLength = 10;

final RegExp _canonicalCode = RegExp(r'^[A-HJ-NP-Z2-9]{10}$');

/// Canonical stored form: uppercase, no spaces or hyphens.
/// `normalizeDoctorCode(' abcd-efgh-23 ')` -> `'ABCDEFGH23'`.
String normalizeDoctorCode(String input) =>
    input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

/// True when [code] is already in canonical stored form.
bool isValidDoctorCode(String code) => _canonicalCode.hasMatch(code);

/// Display-only grouping, e.g. `ABCD-EFGH-23`. Never stored.
String formatDoctorCodeForDisplay(String code) => code.length == 10
    ? '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8)}'
    : code;

/// Converts a persisted Firestore `Timestamp` (anything with `toDate()`) or
/// a `DateTime`, without importing cloud_firestore into the model layer.
/// Returns null when the field is absent (for example a pending server
/// timestamp in a local snapshot).
DateTime? _readTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  try {
    return (value as dynamic).toDate() as DateTime;
  } on NoSuchMethodError {
    throw FormatException('Unsupported timestamp type: ${value.runtimeType}');
  }
}

/// Deterministic link document ID; prevents duplicate links.
String doctorLinkId(String patientId, String doctorId) =>
    '${patientId}_$doctorId';

/// A doctor's shareable linking code, stored at `doctorCodes/{code}`.
class DoctorCode {
  const DoctorCode({
    required this.code,
    required this.doctorId,
    required this.doctorName,
    required this.active,
    this.createdAt,
  });

  final String code;
  final String doctorId;
  final String doctorName;
  final bool active;
  final DateTime? createdAt;

  DateTime? get expiresAt => createdAt?.add(doctorCodeValidity);

  bool isUsableAt(DateTime now) {
    final expiry = expiresAt;
    return active && expiry != null && now.isBefore(expiry);
  }

  /// Must be added by the repository as `FieldValue.serverTimestamp()`.
  static const List<String> createServerTimeFields = ['createdAt'];

  /// INCOMPLETE create payload: add [createServerTimeFields]. The document
  /// ID is the canonical [code]; create with a "must not exist" write and
  /// retry with a new code on collision.
  Map<String, dynamic> toCreateFields() => {
        'doctorId': doctorId,
        'doctorName': doctorName,
        'active': true,
      };

  factory DoctorCode.fromMap(String code, Map<String, dynamic> data) {
    return DoctorCode(
      code: code,
      doctorId: data['doctorId'] as String,
      doctorName: data['doctorName'] as String,
      active: data['active'] as bool,
      createdAt: _readTime(data['createdAt']),
    );
  }
}

class DoctorLink {
  const DoctorLink({
    required this.id,
    required this.patientId,
    required this.doctorId,
    required this.linkCode,
    required this.status,
    this.patientName = '',
    this.doctorName = '',
    this.consentedAt,
    this.revokedAt,
    this.revokedBy,
  });

  final String id;
  final String patientId;
  final String doctorId;
  final String linkCode;
  final LinkStatus status;
  final String patientName;
  final String doctorName;
  final DateTime? consentedAt;
  final DateTime? revokedAt;
  final String? revokedBy;

  bool get isActive => status == LinkStatus.active;

  /// Must be added by the repository as `FieldValue.serverTimestamp()`.
  static const List<String> consentServerTimeFields = ['consentedAt'];
  static const List<String> revocationServerTimeFields = ['revokedAt'];

  /// INCOMPLETE create/reactivate payload (always `active`): add
  /// [consentServerTimeFields]. Reactivation replaces the whole document so
  /// `revokedAt`/`revokedBy` are removed.
  Map<String, dynamic> toConsentFields() => {
        'patientId': patientId,
        'doctorId': doctorId,
        'patientName': patientName,
        'doctorName': doctorName,
        'linkCode': linkCode,
        'status': LinkStatus.active.name,
      };

  /// INCOMPLETE revocation update by [revokerUid] (must be the signed-in
  /// party): add [revocationServerTimeFields]; update only these fields.
  static Map<String, dynamic> revocationFields(String revokerUid) => {
        'status': LinkStatus.revoked.name,
        'revokedBy': revokerUid,
      };

  factory DoctorLink.fromMap(String id, Map<String, dynamic> data) {
    return DoctorLink(
      id: id,
      patientId: data['patientId'] as String,
      doctorId: data['doctorId'] as String,
      linkCode: data['linkCode'] as String,
      status: LinkStatus.values.byName(data['status'] as String),
      patientName: data['patientName'] as String? ?? '',
      doctorName: data['doctorName'] as String? ?? '',
      consentedAt: _readTime(data['consentedAt']),
      revokedAt: _readTime(data['revokedAt']),
      revokedBy: data['revokedBy'] as String?,
    );
  }
}
