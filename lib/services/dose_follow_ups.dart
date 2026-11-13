import '../models/dose_record.dart';

/// Feature #6: follow-up reminders for doses that were not confirmed.
///
/// `DoseProvider` decides WHICH doses need a follow-up and WHEN (using
/// `DosePolicy.overdueAfter`). The gateway only schedules and cancels, so
/// the provider can be tested with a fake and without Android.
class FollowUp {
  const FollowUp(this.dose, this.at);

  final DoseRecord dose;

  /// When the dose becomes overdue: the moment the reminder is shown.
  final DateTime at;
}

abstract class DoseFollowUpGateway {
  /// Makes the phone hold exactly [followUps] for [patientId]: each one is
  /// scheduled once, and any other pending follow-up of this patient (for
  /// example for a deleted medication) is cancelled.
  Future<void> syncFollowUps(String patientId, List<FollowUp> followUps);

  /// [dose] was confirmed: cancel its follow-up, and remove it from the
  /// notification tray if Android already showed it.
  Future<void> cancelFollowUp(DoseRecord dose);
}
