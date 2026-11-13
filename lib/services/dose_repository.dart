import '../models/dose_record.dart';

/// Why a dose operation failed. The UI shows [DoseException.message].
enum DoseError { signedOut, forbidden, alreadyMissed, invalid, unavailable }

class DoseException implements Exception {
  const DoseException(this.code);

  final DoseError code;

  String get message => switch (code) {
    DoseError.signedOut => 'Sign in as a patient to record doses.',
    DoseError.forbidden => 'You cannot change this dose.',
    DoseError.alreadyMissed =>
      'This dose is already recorded as missed and cannot be confirmed.',
    DoseError.invalid => 'This dose change is not allowed.',
    DoseError.unavailable =>
      'Could not save the dose. Check your connection and try again.',
  };

  @override
  String toString() => 'DoseException(${code.name})';
}

/// Result of [DoseRepository.confirm]. A repeated confirm is not an error:
/// it returns [alreadyTaken] with the record saved the first time.
enum ConfirmStatus { confirmed, alreadyTaken }

class ConfirmResult {
  const ConfirmResult(this.status, this.record);

  final ConfirmStatus status;
  final DoseRecord record;
}

/// One dose document inside a transaction (read first, then write).
abstract class DoseTransaction {
  /// The saved record, or null if this dose was never saved (scheduled).
  Future<DoseRecord?> read();

  void write(DoseRecord record);
}

/// Storage only: Firestore in the app, an in-memory fake in tests.
/// Business rules live in [StoredDoseRepository], so tests cover them.
abstract class DoseStore {
  Stream<List<DoseRecord>> watchPatient(String patientId);

  Future<T> transaction<T>(
    String doseId,
    Future<T> Function(DoseTransaction transaction) action,
  );
}

/// What the rest of the app (DoseProvider) uses to read and change doses.
abstract class DoseRepository {
  /// Saved records of [patientId] scheduled from [from] (inclusive) to [to]
  /// (exclusive). Emits again whenever a record changes.
  Stream<List<DoseRecord>> watchRange(
    String patientId,
    DateTime from,
    DateTime to,
  );

  /// Marks [dose] as taken at [at]. Safe to repeat: a dose that is already
  /// taken is returned unchanged with [ConfirmStatus.alreadyTaken].
  Future<ConfirmResult> confirm(DoseRecord dose, DateTime at);

  /// Moves [dose] forward to `overdue` or `missed`. Returns the saved
  /// record, or null if the saved status no longer allows it (for example
  /// it was taken in the meantime).
  Future<DoseRecord?> markStatus(DoseRecord dose, DoseStatus status);
}

/// The dose rules, independent of Firebase.
class StoredDoseRepository implements DoseRepository {
  StoredDoseRepository(this.store, {required this.currentPatientId});

  final DoseStore store;

  /// The signed-in patient's UID from the trusted session (AuthProvider),
  /// never a value typed into a form.
  final String? Function() currentPatientId;

  @override
  Stream<List<DoseRecord>> watchRange(
    String patientId,
    DateTime from,
    DateTime to,
  ) {
    final error = _sessionError(patientId);
    if (error != null) return Stream.error(error);
    return store
        .watchPatient(patientId)
        .map(
          (records) => records
              .where(
                (r) =>
                    r.patientId == patientId &&
                    !r.scheduledTime.isBefore(from) &&
                    r.scheduledTime.isBefore(to),
              )
              .toList(),
        );
  }

  @override
  Future<ConfirmResult> confirm(DoseRecord dose, DateTime at) =>
      _guard(() async {
        _requirePatient(dose.patientId);
        return store.transaction(dose.id, (tx) async {
          final saved = await tx.read();
          if (saved != null && saved.patientId != dose.patientId) {
            throw const DoseException(DoseError.forbidden);
          }
          final current = saved ?? dose;
          // Checked against the SAVED status, not the screen's copy.
          switch (saved?.status) {
            case DoseStatus.taken:
              return ConfirmResult(ConfirmStatus.alreadyTaken, current);
            case DoseStatus.missed:
              throw const DoseException(DoseError.alreadyMissed);
            case null || DoseStatus.scheduled || DoseStatus.overdue:
              final taken = current.copyWith(
                status: DoseStatus.taken,
                confirmedAt: at,
              );
              tx.write(taken);
              return ConfirmResult(ConfirmStatus.confirmed, taken);
          }
        });
      });

  @override
  Future<DoseRecord?> markStatus(DoseRecord dose, DoseStatus status) =>
      _guard(() async {
        if (status != DoseStatus.overdue && status != DoseStatus.missed) {
          throw const DoseException(DoseError.invalid);
        }
        _requirePatient(dose.patientId);
        return store.transaction(dose.id, (tx) async {
          final saved = await tx.read();
          if (saved != null && saved.patientId != dose.patientId) {
            throw const DoseException(DoseError.forbidden);
          }
          // Not saved yet means it is still scheduled.
          final from = saved?.status ?? DoseStatus.scheduled;
          if (!_canMove(from, status)) return null;
          final updated = (saved ?? dose).copyWith(status: status);
          tx.write(updated);
          return updated;
        });
      });

  /// Allowed automatic moves: scheduled -> overdue/missed, overdue -> missed.
  /// taken and missed are final.
  bool _canMove(DoseStatus from, DoseStatus to) => switch (from) {
    DoseStatus.scheduled => true,
    DoseStatus.overdue => to == DoseStatus.missed,
    DoseStatus.taken || DoseStatus.missed => false,
  };

  DoseException? _sessionError(String patientId) {
    final current = currentPatientId();
    if (current == null) return const DoseException(DoseError.signedOut);
    if (patientId.isEmpty || current != patientId) {
      return const DoseException(DoseError.forbidden);
    }
    return null;
  }

  void _requirePatient(String patientId) {
    final error = _sessionError(patientId);
    if (error != null) throw error;
  }

  /// Turns unexpected errors into [DoseError.unavailable], so the UI always
  /// gets a [DoseException] with a friendly message.
  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on DoseException {
      rethrow;
    } catch (_) {
      throw const DoseException(DoseError.unavailable);
    }
  }
}
