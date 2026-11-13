import 'package:medication_follow_up_app/services/notification_service.dart';

/// One reminder the fake "Android" is holding.
class FakeScheduled {
  FakeScheduled({
    required this.title,
    required this.body,
    required this.hour,
    required this.minute,
    required this.payload,
    required this.exact,
  });
  final String title;
  final String body;
  final int hour;
  final int minute;
  final String payload;
  final bool exact;

  ReminderPayload get decoded => ReminderPayload.decode(payload)!;
}

/// In-memory stand-in for the notification plugin. Like Android, it keeps
/// one entry per ID, so scheduling the same ID twice replaces it.
class FakeNotificationPlugin implements NotificationPlugin {
  FakeNotificationPlugin({this.enabled = true, this.exact = false});

  bool enabled;
  bool exact;

  /// What the "Allow notifications?" prompt answers in this test.
  bool grantOnRequest = true;
  final scheduled = <int, FakeScheduled>{};
  int initializeCalls = 0;
  void Function(String? payload)? _onTap;

  /// Simulates the patient tapping a shown notification.
  void tap(String? payload) => _onTap?.call(payload);

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    initializeCalls++;
    _onTap = onTap;
  }

  @override
  Future<bool> areNotificationsEnabled() async => enabled;

  @override
  Future<void> requestPermission() async => enabled = grantOnRequest;

  @override
  Future<bool> canScheduleExact() async => exact;

  @override
  Future<void> requestExactAlarms() async => exact = true;

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required String payload,
    required bool exact,
  }) async {
    scheduled[id] = FakeScheduled(
      title: title,
      body: body,
      hour: hour,
      minute: minute,
      payload: payload,
      exact: exact,
    );
  }

  @override
  Future<List<PendingReminder>> pending() async => [
    for (final e in scheduled.entries) PendingReminder(e.key, e.value.payload),
  ];

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);
}
