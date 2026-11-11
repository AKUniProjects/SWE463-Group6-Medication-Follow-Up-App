import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../services/auth_repository.dart';

enum AuthStatus {
  loading,
  signedOut,
  signedIn,
  missingProfile,
  error,
}

/// Single source of authentication state for the UI.
///
/// Screens call [signIn], [signUp], [signOut] and [retry]; they never talk
/// to the repository directly.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repository);

  final AuthRepository _repository;

  StreamSubscription<String?>? _subscription;
  int _changeId = 0;
  int _actionId = 0;
  String? _actionUid;
  bool _actionSuperseded = false;

  AuthStatus _status = AuthStatus.loading;
  UserProfile? _userProfile;
  String? _userId;
  String? _errorMessage;

  // Sign-in/sign-up in progress. While true, auth events are recorded but
  // not acted on, because the repository is still creating or loading the
  // profile (avoids the registration race from Task 2.1).
  bool _isSigningIn = false;
  bool _isRegistering = false;
  String? _actionErrorMessage;

  AuthStatus get status => _status;
  UserProfile? get userProfile => _userProfile;
  String? get userId => _userId;
  String? get errorMessage => _errorMessage;

  /// User-safe message from the last failed sign-in/sign-up, if any.
  String? get actionErrorMessage => _actionErrorMessage;
  bool get isRegistering => _isRegistering;
  bool get isBusy => _isSigningIn || _isRegistering;

  bool get isAuthenticated => _status == AuthStatus.signedIn;

  bool get isPatient =>
      isAuthenticated && _userProfile?.role == UserRole.patient;

  bool get isDoctor => isAuthenticated && _userProfile?.role == UserRole.doctor;

  // Start observing Firebase authentication changes (restores sessions).
  void start() {
    if (_subscription != null) return;

    _subscription = _repository.authStateChanges.listen(
      _onAuthChanged,
      onError: (Object error, StackTrace stackTrace) {
        _cancelAction();
        _changeId++;
        _userProfile = null;
        _userId = null;
        _errorMessage = 'Authentication state error.';
        _status = AuthStatus.error;
        notifyListeners();
      },
    );
  }

  Future<bool> signIn({required String email, required String password}) {
    return _runAction(
      registering: false,
      action: () => _repository.signIn(email: email, password: password),
    );
  }

  Future<bool> signUp({
    required String displayName,
    required String email,
    required String password,
    required UserRole role,
  }) {
    return _runAction(
      registering: true,
      action: () => _repository.signUp(
        displayName: displayName,
        email: email,
        password: password,
        role: role,
      ),
    );
  }

  Future<void> signOut() async {
    _cancelAction();
    final actionId = _actionId;
    _actionErrorMessage = null;
    notifyListeners();
    try {
      await _repository.signOut();
      if (actionId == _actionId && !_disposed) {
        _onAuthChanged(_repository.currentUid);
      }
    } catch (_) {
      if (actionId != _actionId || _disposed) return;
      _actionErrorMessage = 'Could not sign out. Please try again.';
      notifyListeners();
    }
  }

  /// Reloads the profile for the current session (missing/error states).
  void retry() => _onAuthChanged(_userId);

  void clearActionError() {
    if (_actionErrorMessage == null) return;
    _actionErrorMessage = null;
    notifyListeners();
  }

  Future<bool> _runAction({
    required bool registering,
    required Future<UserProfile> Function() action,
  }) async {
    if (isBusy) return false;

    final actionId = ++_actionId;
    _actionUid = null;
    _actionSuperseded = false;
    _isSigningIn = !registering;
    _isRegistering = registering;
    _actionErrorMessage = null;
    notifyListeners();

    UserProfile? profile;
    String? failure;
    try {
      profile = await action();
    } on AuthException catch (e) {
      failure = e.message;
    } catch (_) {
      failure = const AuthException(AuthErrorCode.unknown).message;
    }

    if (_disposed || actionId != _actionId) return false;
    _isSigningIn = false;
    _isRegistering = false;
    _actionErrorMessage = failure;

    if (profile != null &&
        !_actionSuperseded &&
        profile.id == _repository.currentUid) {
      _changeId++;
      _userId = profile.id;
      _userProfile = profile;
      _errorMessage = null;
      _status = AuthStatus.signedIn;
      notifyListeners();
      return true;
    }

    _onAuthChanged(_repository.currentUid);
    return false;
  }

  void _cancelAction() {
    _actionId++;
    _isSigningIn = false;
    _isRegistering = false;
    _actionUid = null;
  }

  void _onAuthChanged(String? uid) {
    final requestId = ++_changeId;

    // Duplicate event for a session we already resolved.
    if (uid != null &&
        uid == _userId &&
        _status == AuthStatus.signedIn &&
        _userProfile?.id == uid) {
      return;
    }

    _userId = uid;

    if (isBusy) {
      // The first event may precede the registration profile write.
      // A different non-null identity belongs to a replacement session.
      if (_actionUid != null && uid != _actionUid) {
        _actionSuperseded = true;
        if (uid != null) _cancelAction();
      }
      if (isBusy) {
        _actionUid ??= uid;
        _userProfile = null;
        _status = uid == null ? AuthStatus.signedOut : AuthStatus.loading;
        notifyListeners();
        return;
      }
    }

    _userProfile = null;
    _errorMessage = null;

    if (uid == null) {
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }

    _status = AuthStatus.loading;
    notifyListeners();

    unawaited(_loadProfile(requestId, uid));
  }

  Future<void> _loadProfile(
    int requestId,
    String uid,
  ) async {
    try {
      final profile = await _repository.getCurrentUserProfile();

      // Ignore a result from an outdated session.
      if (requestId != _changeId || _disposed) return;

      if (profile != null && profile.id != uid) {
        throw StateError('User profile ID mismatch.');
      }

      _userProfile = profile;
      _status =
          profile == null ? AuthStatus.missingProfile : AuthStatus.signedIn;
    } catch (_) {
      if (requestId != _changeId || _disposed) return;

      _userProfile = null;
      _errorMessage = 'Could not load user profile.';
      _status = AuthStatus.error;
    }

    notifyListeners();
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelAction();
    _changeId++;
    final subscription = _subscription;
    _subscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    super.dispose();
  }
}
