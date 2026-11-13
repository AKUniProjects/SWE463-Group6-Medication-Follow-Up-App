/// Team-agreed timing and counting rules for doses.
///
/// These are app rules, not medical advice: there is no single clinical
/// standard for when a late dose counts as missed. To change a rule for the
/// whole app, change its default value below. Tests can pass different
/// values to the constructor.
class DosePolicy {
  const DosePolicy({
    this.overdueAfter = const Duration(minutes: 30),
    this.missedAfter = const Duration(hours: 4),
    this.missWhenNextDoseDue = true,
    this.countFutureDosesInToday = true,
    this.overdueCountsAsMissed = false,
  });

  /// An unconfirmed dose becomes `overdue` this long after its scheduled
  /// time. The follow-up reminder is sent at this moment.
  final Duration overdueAfter;

  /// An unconfirmed dose becomes `missed` (final) this long after its
  /// scheduled time.
  final Duration missedAfter;

  /// If the next dose of the same medication is due before [missedAfter]
  /// has passed, the earlier dose becomes `missed` at that point instead.
  /// This follows the "never take a double dose" guidance.
  final bool missWhenNextDoseDue;

  /// Today's progress counts every dose of the day ("2 of 4"), including
  /// doses that are not due yet. False would count only due doses.
  final bool countFutureDosesInToday;

  /// Adherence statistics count `overdue` doses as missed. False means only
  /// `missed` doses count against adherence.
  final bool overdueCountsAsMissed;
}
