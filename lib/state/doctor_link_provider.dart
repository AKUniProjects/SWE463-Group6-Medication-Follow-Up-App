import 'package:flutter/foundation.dart';

import '../models/doctor_link.dart';
import '../services/doctor_link_repository.dart';

/// Patient linking flow states (Task 3.5A).
enum PatientLinkStatus {
  idle,
  lookingUp,
  preview,
  invalidCode,
  consentRequired,
  linking,
  linked,
  alreadyLinked,
  newCodeRequired,
  error,
}

/// Doctor Linking UI state (Task 3.4A: doctor code management only).
///
/// Session-scoped: [updateSession] is driven by [AuthProvider] (see
/// main.dart). Codes, errors and in-flight results from a previous session
/// are discarded when the user signs out or switches accounts.
///
/// All Firestore access goes through [DoctorLinkRepository]; code
/// generation and expiry logic stay in the repository/model.
class DoctorLinkProvider extends ChangeNotifier {
  DoctorLinkProvider(this._repository, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final DoctorLinkRepository _repository;
  final DateTime Function() _now;

  String? _uid;
  bool _isDoctor = false;
  int _session = 0;
  bool _disposed = false;
  int _patientLoad = 0;
  int _doctorLoad = 0;

  List<DoctorCode> _codes = const [];
  bool _hasLoaded = false;
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;

  /// Newest first, as returned by the repository.
  List<DoctorCode> get codes => _codes;
  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _isLoading;

  /// True while create/replace/deactivate is running.
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;

  /// Only a signed-in doctor may manage codes.
  bool get canManageCodes => _uid != null && _isDoctor;

  /// Newest code that is active and unexpired (per the 30-day model rule),
  /// or null when the doctor must create one.
  DoctorCode? get currentCode {
    final now = _now();
    for (final code in _codes) {
      if (code.isUsableAt(now)) return code;
    }
    return null;
  }

  DateTime? get currentCodeExpiresAt => currentCode?.expiresAt;

  /// Called by the ProxyProvider whenever auth state changes. Does not read
  /// Firestore and does not notify (it runs during the provider's build).
  void updateSession({
    required String? uid,
    required bool isDoctor,
    bool isPatient = false,
  }) {
    if (uid == _uid && isDoctor == _isDoctor && isPatient == _isPatient) {
      return;
    }
    _uid = uid;
    _isDoctor = isDoctor;
    _isPatient = isPatient;
    _session++; // invalidates in-flight work from the previous session
    _codes = const [];
    _hasLoaded = false;
    _isLoading = false;
    _isBusy = false;
    _errorMessage = null;
    _clearPatientState();
    _clearLinkedPatients();
  }

  // ============================================ doctor: linked patients
  //
  // Data source for the Doctor Dashboard (Task 3.6). Only ACTIVE links and
  // rule-authorized profiles are returned by the repository.

  List<LinkedPatient> _linkedPatients = const [];
  bool _hasLoadedLinkedPatients = false;
  bool _isLoadingLinkedPatients = false;
  String? _linkedPatientsError;

  List<LinkedPatient> get linkedPatients => _linkedPatients;
  bool get hasLoadedLinkedPatients => _hasLoadedLinkedPatients;
  bool get isLoadingLinkedPatients => _isLoadingLinkedPatients;
  String? get linkedPatientsError => _linkedPatientsError;

  /// Loads (or refreshes) the signed-in doctor's linked patients.
  Future<bool> loadLinkedPatients() async {
    if (_isBusy) return false;
    return _loadLinkedPatients();
  }

  Future<bool> _loadLinkedPatients() async {
    if (!canManageCodes) {
      _linkedPatientsError =
          const DoctorLinkException(DoctorLinkErrorCode.notDoctor).message;
      _notify();
      return false;
    }
    final session = _session;
    final request = ++_doctorLoad;
    _isLoadingLinkedPatients = true;
    _linkedPatientsError = null;
    _notify();
    try {
      final patients = await _repository.linkedPatientsForDoctor();
      if (session != _session || request != _doctorLoad) return false;
      _linkedPatients = List.unmodifiable(patients);
      _hasLoadedLinkedPatients = true;
      return true;
    } catch (e) {
      if (session != _session || request != _doctorLoad) return false;
      _linkedPatientsError = _messageFor(e); // previous list is kept
      return false;
    } finally {
      if (session == _session && request == _doctorLoad) {
        _isLoadingLinkedPatients = false;
        _notify();
      }
    }
  }

  /// Doctor-side revocation (interface for the dashboard owner). After a
  /// doctor revokes, the patient needs a code issued after the revocation.
  Future<bool> revokePatientLink(LinkedPatient patient) async {
    if (!canManageCodes || _isBusy) return false;
    final session = _session;
    _isBusy = true;
    _linkedPatientsError = null;
    ++_doctorLoad; // invalidate every pre-mutation snapshot
    _isLoadingLinkedPatients = false;
    _notify();
    try {
      await _repository.revokeLink(patient.link);
      if (session != _session) return false;
      _linkedPatients = List.unmodifiable(
        _linkedPatients.where((p) => p.link.id != patient.link.id),
      );
      _notify();
      await _loadLinkedPatients();
      if (session != _session) return false;
      _isBusy = false;
      _notify();
      return true;
    } catch (e) {
      if (session != _session) return false;
      _isBusy = false;
      _linkedPatientsError = _messageFor(e);
      _notify();
      return false;
    }
  }

  void _clearLinkedPatients() {
    _linkedPatients = const [];
    _hasLoadedLinkedPatients = false;
    _isLoadingLinkedPatients = false;
    _linkedPatientsError = null;
  }

  // ===================================================== patient linking
  //
  // Flow (Task 3.5B UI): enter code -> lookupDoctor() -> preview ->
  // explicit consent -> linkToPreviewedDoctor(consentGiven: ...) -> linked.
  // Reactivating a revoked link uses the same flow; the repository decides
  // create vs. reactivate and enforces the revocation policy.

  bool _isPatient = false;
  PatientLinkStatus _linkStatus = PatientLinkStatus.idle;
  String _codeInput = '';
  DoctorCode? _preview;
  DoctorLink? _lastLinked;
  String? _linkMessage;
  List<DoctorLink> _patientLinks = const [];
  bool _hasLoadedPatientLinks = false;
  bool _isLoadingPatientLinks = false;
  String? _patientLinksError;

  /// Only a signed-in patient may link to doctors.
  bool get canLinkDoctors => _uid != null && _isPatient;
  PatientLinkStatus get linkStatus => _linkStatus;

  /// Canonical (normalized) form of the last entered code.
  String get codeInput => _codeInput;
  DoctorCode? get doctorPreview => _preview;
  DoctorLink? get lastLinked => _lastLinked;

  /// Friendly message for the current [linkStatus], if any.
  String? get linkMessage => _linkMessage;
  List<DoctorLink> get patientLinks => _patientLinks;
  List<DoctorLink> get activeDoctorLinks =>
      _patientLinks.where((l) => l.isActive).toList();
  List<DoctorLink> get revokedDoctorLinks =>
      _patientLinks.where((l) => !l.isActive).toList();
  bool get hasLoadedPatientLinks => _hasLoadedPatientLinks;
  bool get isLoadingPatientLinks => _isLoadingPatientLinks;
  String? get patientLinksError => _patientLinksError;

  /// Format-only validation for form fields; null when well-formed.
  static String? validateCodeInput(String raw) =>
      isValidDoctorCode(normalizeDoctorCode(raw))
          ? null
          : const DoctorLinkException(DoctorLinkErrorCode.invalidCodeFormat)
              .message;

  /// Records the typed code; a different code clears the old preview.
  void setCodeInput(String raw) {
    final canonical = normalizeDoctorCode(raw);
    if (canonical == _codeInput) return;
    _codeInput = canonical;
    if (_preview != null || _linkStatus != PatientLinkStatus.idle) {
      if (_isBusy) return; // a pending action owns the state
      _preview = null;
      _lastLinked = null;
      _linkStatus = PatientLinkStatus.idle;
      _linkMessage = null;
      _notify();
    }
  }

  /// Looks up [raw] (or the stored input) and stores the doctor preview.
  Future<bool> lookupDoctor([String? raw]) async {
    if (raw != null) setCodeInput(raw);
    if (!_checkPatient() || _isBusy) return false;
    final formatError = validateCodeInput(_codeInput);
    if (formatError != null) {
      _setLink(PatientLinkStatus.invalidCode, formatError);
      return false;
    }

    final session = _session;
    _isBusy = true;
    _preview = null;
    _setLink(PatientLinkStatus.lookingUp, null);
    try {
      final code = await _repository.lookupCode(_codeInput);
      if (session != _session) return false;
      _preview = code;
      _isBusy = false;
      _setLink(PatientLinkStatus.preview, null);
      return true;
    } catch (e) {
      if (session != _session) return false;
      _isBusy = false;
      _setLinkFailure(e);
      return false;
    }
  }

  /// Links to the previewed doctor. [consentGiven] must come from the
  /// patient's explicit choice in the UI; false never reaches Firestore.
  Future<bool> linkToPreviewedDoctor({required bool consentGiven}) async {
    if (!_checkPatient() || _isBusy) return false;
    final preview = _preview;
    if (preview == null) {
      _setLink(
        PatientLinkStatus.invalidCode,
        const DoctorLinkException(DoctorLinkErrorCode.invalidCodeFormat)
            .message,
      );
      return false;
    }
    if (!consentGiven) {
      _setLink(
        PatientLinkStatus.consentRequired,
        const DoctorLinkException(DoctorLinkErrorCode.consentRequired).message,
      );
      return false;
    }

    final session = _session;
    _isBusy = true;
    ++_patientLoad;
    _isLoadingPatientLinks = false;
    _setLink(PatientLinkStatus.linking, null);
    try {
      final link = await _repository.linkWithCode(
        preview.code,
        consentGiven: consentGiven,
        expectedDoctorId: preview.doctorId,
      );
      if (session != _session) return false;
      _lastLinked = link;
      // The write was acknowledged. Keep it even if the follow-up read fails.
      _patientLinks = List.unmodifiable([
        ..._patientLinks.where((l) => l.id != link.id),
        link,
      ]);
      _hasLoadedPatientLinks = true;
      await _refreshPatientLinks(session);
      if (session != _session) return false;
      _isBusy = false;
      _setLink(PatientLinkStatus.linked, null);
      return true;
    } catch (e) {
      if (session != _session) return false;
      _isBusy = false;
      _setLinkFailure(e);
      return false;
    }
  }

  /// Loads the signed-in patient's links (active and revoked).
  Future<bool> loadPatientLinks() async {
    if (!_checkPatient() || _isBusy) return false;
    return _refreshPatientLinks(_session);
  }

  /// Revokes an active link (patient side), then refreshes the list.
  Future<bool> revokeDoctorLink(DoctorLink link) async {
    if (!_checkPatient() || _isBusy) return false;
    final session = _session;
    _isBusy = true;
    _patientLinksError = null;
    ++_patientLoad;
    _isLoadingPatientLinks = false;
    _notify();
    try {
      await _repository.revokeLink(link);
      if (session != _session) return false;
      _patientLinks = List.unmodifiable([
        for (final l in _patientLinks)
          if (l.id != link.id)
            l
          else
            DoctorLink(
              id: l.id,
              patientId: l.patientId,
              doctorId: l.doctorId,
              linkCode: l.linkCode,
              status: LinkStatus.revoked,
              patientName: l.patientName,
              doctorName: l.doctorName,
              consentedAt: l.consentedAt,
              revokedBy: _uid,
            ),
      ]);
      await _refreshPatientLinks(session);
      if (session != _session) return false;
      _isBusy = false;
      // An "already linked" result is no longer true after revocation.
      if (_linkStatus == PatientLinkStatus.alreadyLinked) {
        _linkStatus = PatientLinkStatus.idle;
        _linkMessage = null;
      }
      _notify();
      return true;
    } catch (e) {
      if (session != _session) return false;
      _isBusy = false;
      _patientLinksError = _messageFor(e);
      _notify();
      return false;
    }
  }

  /// Returns the linking flow to its initial state (keeps the link list).
  void resetLinkFlow() {
    if (_isBusy) return;
    _codeInput = '';
    _preview = null;
    _lastLinked = null;
    _linkStatus = PatientLinkStatus.idle;
    _linkMessage = null;
    _notify();
  }

  bool _checkPatient() {
    if (canLinkDoctors) return true;
    _setLink(
      PatientLinkStatus.error,
      const DoctorLinkException(DoctorLinkErrorCode.notPatient).message,
    );
    return false;
  }

  void _setLink(PatientLinkStatus status, String? message) {
    _linkStatus = status;
    _linkMessage = message;
    _notify();
  }

  void _setLinkFailure(Object error) {
    final code = error is DoctorLinkException ? error.code : null;
    if (code == DoctorLinkErrorCode.doctorChanged) _preview = null;
    final status = switch (code) {
      DoctorLinkErrorCode.invalidCodeFormat ||
      DoctorLinkErrorCode.codeNotFound ||
      DoctorLinkErrorCode.codeInactive ||
      DoctorLinkErrorCode.codeExpired ||
      DoctorLinkErrorCode.ownCode =>
        PatientLinkStatus.invalidCode,
      DoctorLinkErrorCode.consentRequired => PatientLinkStatus.consentRequired,
      DoctorLinkErrorCode.alreadyLinked => PatientLinkStatus.alreadyLinked,
      DoctorLinkErrorCode.newCodeRequired => PatientLinkStatus.newCodeRequired,
      _ => PatientLinkStatus.error,
    };
    _setLink(status, _messageFor(error));
  }

  String _messageFor(Object error) => error is DoctorLinkException
      ? error.message
      : const DoctorLinkException(DoctorLinkErrorCode.unknown).message;

  /// Re-reads the patient's links; keeps the old list on failure.
  Future<bool> _refreshPatientLinks(int session) async {
    final request = ++_patientLoad;
    _isLoadingPatientLinks = true;
    _patientLinksError = null;
    _notify();
    try {
      final links = await _repository.linksForPatient();
      if (session != _session || request != _patientLoad) return false;
      _patientLinks = List.unmodifiable(links);
      _hasLoadedPatientLinks = true;
      return true;
    } catch (e) {
      if (session == _session && request == _patientLoad) {
        _patientLinksError = _messageFor(e);
      }
      return false;
    } finally {
      if (session == _session && request == _patientLoad) {
        _isLoadingPatientLinks = false;
        _notify();
      }
    }
  }

  void _clearPatientState() {
    _linkStatus = PatientLinkStatus.idle;
    _codeInput = '';
    _preview = null;
    _lastLinked = null;
    _linkMessage = null;
    _patientLinks = const [];
    _hasLoadedPatientLinks = false;
    _isLoadingPatientLinks = false;
    _patientLinksError = null;
  }

  /// Loads the signed-in doctor's codes. Returns false if not allowed,
  /// already running, failed, or superseded by a new session.
  Future<bool> loadCodes() async {
    if (!_checkAllowed() || _isLoading || _isBusy) return false;
    final session = _session;
    _isLoading = true;
    _errorMessage = null;
    _notify();

    final ok = await _refresh(session);
    if (session != _session) return false;
    _isLoading = false;
    _notify();
    return ok;
  }

  /// Issues a new code, then re-reads codes to obtain the server
  /// `createdAt` (and therefore the expiry date).
  Future<bool> createCode() => _action((session) async {
        await _repository.createCode();
        return _refresh(session);
      });

  /// Replaces the current code. Verifies afterwards that the old code is no
  /// longer active and reports a partial failure if it still is.
  Future<bool> replaceCurrentCode() {
    final old = currentCode;
    if (old == null) return createCode();
    return _action((session) async {
      DoctorLinkException? failure;
      try {
        await _repository.replaceCode(old.code);
      } on DoctorLinkException catch (e) {
        failure = e;
      }
      final refreshed = await _refresh(session);
      if (session != _session) return false;
      if (!refreshed) return false;

      final oldStillActive = _codes.any((c) => c.code == old.code && c.active);
      final hasNewCode = _codes.any(
        (c) => c.code != old.code && c.isUsableAt(_now()),
      );
      if (oldStillActive && hasNewCode) {
        _errorMessage = 'A new code was created, but the old code is still '
            'active. Deactivate it to stop new links.';
        return false;
      }
      if (failure != null || oldStillActive || !hasNewCode) {
        _errorMessage = failure?.message ??
            const DoctorLinkException(DoctorLinkErrorCode.unknown).message;
        return false;
      }
      return true;
    });
  }

  /// Deactivates [code] (one-way) and verifies it after refreshing.
  Future<bool> deactivateCode(String code) => _action((session) async {
        DoctorLinkException? failure;
        try {
          await _repository.deactivateCode(code);
        } on DoctorLinkException catch (e) {
          failure = e;
        }
        final refreshed = await _refresh(session);
        if (session != _session || !refreshed) return false;
        final stillActive = _codes.any((c) => c.code == code && c.active);
        if (failure != null || stillActive) {
          _errorMessage = failure?.message ??
              const DoctorLinkException(DoctorLinkErrorCode.unknown).message;
          return false;
        }
        return true;
      });

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _notify();
  }

  // ------------------------------------------------------------ helpers

  bool _checkAllowed() {
    if (canManageCodes) return true;
    _errorMessage =
        const DoctorLinkException(DoctorLinkErrorCode.notDoctor).message;
    _notify();
    return false;
  }

  /// Runs one mutating action at a time for the current session.
  Future<bool> _action(Future<bool> Function(int session) body) async {
    if (!_checkAllowed() || _isBusy || _isLoading) return false;
    final session = _session;
    _isBusy = true;
    _errorMessage = null;
    _notify();

    bool ok;
    try {
      ok = await body(session);
    } on DoctorLinkException catch (e) {
      if (session == _session) _errorMessage = e.message;
      ok = false;
    } catch (_) {
      if (session == _session) {
        _errorMessage =
            const DoctorLinkException(DoctorLinkErrorCode.unknown).message;
      }
      ok = false;
    }

    if (session != _session) return false; // stale: discard silently
    _isBusy = false;
    _notify();
    return ok;
  }

  /// Re-reads codes; keeps the previous list if the read fails.
  Future<bool> _refresh(int session) async {
    try {
      final codes = await _repository.myCodes();
      if (session != _session) return false;
      _codes = List.unmodifiable(codes);
      _hasLoaded = true;
      return true;
    } on DoctorLinkException catch (e) {
      if (session == _session) _errorMessage = e.message;
      return false;
    } catch (_) {
      if (session == _session) {
        _errorMessage =
            const DoctorLinkException(DoctorLinkErrorCode.unknown).message;
      }
      return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    super.dispose();
  }
}
