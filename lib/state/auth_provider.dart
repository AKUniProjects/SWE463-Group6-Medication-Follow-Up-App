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

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repository);

  final AuthRepository _repository;

  StreamSubscription<String?>? _subscription;
  int _changeId = 0;

  AuthStatus _status = AuthStatus.loading;
  UserProfile? _userProfile;
  String? _userId;
  String? _errorMessage;

  AuthStatus get status => _status;
  UserProfile? get userProfile => _userProfile;
  String? get userId => _userId;
  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _status == AuthStatus.signedIn;

  bool get isPatient =>
      isAuthenticated && _userProfile?.role == UserRole.patient;

  bool get isDoctor => isAuthenticated && _userProfile?.role == UserRole.doctor;

  // Start observing Firebase authentication changes.
  void start() {
    if (_subscription != null) return;

    _subscription = _repository.authStateChanges.listen(
      _onAuthChanged,
      onError: (Object error, StackTrace stackTrace) {
        _changeId++;
        _userProfile = null;
        _userId = null;
        _errorMessage = 'Authentication state error.';
        _status = AuthStatus.error;
        notifyListeners();
      },
    );
  }

  void _onAuthChanged(String? uid) {
    final requestId = ++_changeId;

    _userId = uid;
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
      if (requestId != _changeId) return;

      if (profile != null && profile.id != uid) {
        throw StateError('User profile ID mismatch.');
      }

      _userProfile = profile;
      _status =
          profile == null ? AuthStatus.missingProfile : AuthStatus.signedIn;
    } catch (_) {
      if (requestId != _changeId) return;

      _userProfile = null;
      _errorMessage = 'Could not load user profile.';
      _status = AuthStatus.error;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _changeId++;
    final subscription = _subscription;
    _subscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    super.dispose();
  }
}
