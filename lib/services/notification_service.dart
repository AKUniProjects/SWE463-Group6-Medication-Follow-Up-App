import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/medication.dart';
import 'dose_schedule.dart' show parseDoseTime;
import 'medication_reminders.dart';

/// Feature #3: Android medication reminders.
///
/// [NotificationService] implements Person 2's [MedicationReminderGateway],
/// so `MedicationProvider` tells it when a medication is added, edited,
/// disabled or deleted. It never stores schedules itself: every reminder is
/// built from the [Medication] it is given.
///
/// The real plugin sits behind [NotificationPlugin] so tests use a fake.

/// Refill reminders repeat daily at this local time while stock is low.
const refillReminderTime = '09:00';

enum ReminderKind { dose, refill }

/// Android notification permission, as last checked.
enum ReminderPermission { unknown, granted, denied, unsupported }

/// Stored inside each notification so we can find it again later:
/// whose reminder it is, for which medication and at what time.
class ReminderPayload {
  const ReminderPayload({
    required this.kind,
    required this.patientId,
    required this.medicationId,
    required this.time,
  });

  final ReminderKind kind;
  final String patientId;
  final String medicationId;
  final String time; // "HH:mm"

  String encode() => jsonEncode({
    'kind': kind.name,
    'patientId': patientId,
    'medicationId': medicationId,
    'time': time,
  });

  /// Null if [text] is not one of our payloads.
  static ReminderPayload? decode(String? text) {
    if (text == null) return null;
    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      return ReminderPayload(
        kind: ReminderKind.values.byName(map['kind'] as String),
        patientId: map['patientId'] as String,
        medicationId: map['medicationId'] as String,
        time: map['time'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A notification Android has scheduled but not shown yet.
class PendingReminder {
  const PendingReminder(this.id, this.payload);
  final int id;
  final String? payload;
}

/// The few plugin calls the service needs.
abstract class NotificationPlugin {
  Future<void> initialize({required void Function(String? payload) onTap});
  Future<bool> areNotificationsEnabled();
  Future<void> requestPermission();
  Future<bool> canScheduleExact();
  Future<void> requestExactAlarms();
  Future<void> openSettings();

  /// Repeats every day at [hour]:[minute] local time. Scheduling the same
  /// [id] again replaces the old one, so it never duplicates.
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required String payload,
    required bool exact,
  });
  Future<List<PendingReminder>> pending();
  Future<void> cancel(int id);
}

/// Stable notification ID (Android needs an int) from a text key, using
/// the FNV-1a hash. Unlike `String.hashCode`, it is the same on every run,
/// so restarting the app replaces reminders instead of duplicating them.
int notificationId(String key) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(key)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff; // positive 31-bit int
}

class NotificationService extends ChangeNotifier
    implements MedicationReminderGateway {
  NotificationService(this.plugin, {required this.supported})
    : permission = supported
          ? ReminderPermission.unknown
          : ReminderPermission.unsupported;

  final NotificationPlugin plugin;

  /// False on web/desktop: local reminders only work in the Android app.
  final bool supported;

  ReminderPermission permission;

  /// True if Android allows exact timing ("Alarms & reminders").
  bool exactAlarms = false;

  /// Reminders scheduled on this phone. Scheduled is not "delivered":
  /// Android shows them later, and only if notifications stay allowed.
  int scheduledCount = 0;

  final _taps = StreamController<ReminderPayload?>.broadcast();
  Future<void>? _started;
  String? _patientId; // whose reminders this device currently holds
  bool _disposed = false;

  /// A notification was tapped while the app was running.
  Stream<ReminderPayload?> get taps => _taps.stream;

  @override
  bool get isAvailable => supported;

  /// Sets up the plugin once. Every other method awaits it, so calls made
  /// while the app is still starting are not lost.
  Future<void> start() => _started ??= _start();

  Future<void> _start() async {
    if (!supported) return;
    await plugin.initialize(
      onTap: (payload) => _taps.add(ReminderPayload.decode(payload)),
    );
    await refreshStatus();
  }

  /// Re-reads the permission state, e.g. after returning from settings.
  Future<void> refreshStatus() async {
    if (!supported) return;
    final enabled = await plugin.areNotificationsEnabled();
    permission = enabled
        ? ReminderPermission.granted
        : ReminderPermission.denied;
    exactAlarms = await plugin.canScheduleExact();
    scheduledCount = (await plugin.pending()).length;
    _notify();
  }

  /// Shows Android's "Allow notifications?" prompt (Android 13+).
  Future<void> requestPermission() async {
    await start();
    if (!supported || permission == ReminderPermission.granted) return;
    await plugin.requestPermission();
    await refreshStatus();
  }

  /// Opens Android's "Alarms & reminders" page. Applies to reminders
  /// scheduled after it is granted (or on the next app start).
  Future<void> requestExactAlarms() async {
    await start();
    if (!supported) return;
    await plugin.requestExactAlarms();
    await refreshStatus();
  }

  Future<void> openSettings() async {
    if (supported) await plugin.openSettings();
  }

  @override
  Future<void> syncSchedule(Medication medication) async {
    await _prepare(medication.patientId);
    final wanted = <int, ReminderPayload>{};
    for (final time in medication.scheduledTimes) {
      final payload = ReminderPayload(
        kind: ReminderKind.dose,
        patientId: medication.patientId,
        medicationId: medication.id,
        time: time,
      );
      wanted[_idFor(payload)] = payload;
    }
    // A changed time has a new ID: cancel this medication's old ones.
    await _cancelWhere(
      (id, p) =>
          p.kind == ReminderKind.dose &&
          p.patientId == medication.patientId &&
          p.medicationId == medication.id &&
          !wanted.containsKey(id),
    );
    for (final MapEntry(key: id, value: payload) in wanted.entries) {
      final parts = parseDoseTime(payload.time);
      if (parts == null) continue; // Person 2 validates; skip bad data
      await plugin.scheduleDaily(
        id: id,
        title: 'Time for ${medication.name}',
        body:
            '${_amount(medication)} at ${payload.time}. '
            'Open the app to mark it as taken.',
        hour: parts.hour,
        minute: parts.minute,
        payload: payload.encode(),
        exact: exactAlarms,
      );
    }
    await _updateCount();
  }

  @override
  Future<void> syncRefill(RefillAlert alert) async {
    final m = alert.medication;
    await _prepare(m.patientId);
    final payload = ReminderPayload(
      kind: ReminderKind.refill,
      patientId: m.patientId,
      medicationId: m.id,
      time: refillReminderTime,
    );
    final parts = parseDoseTime(refillReminderTime)!;
    await plugin.scheduleDaily(
      id: _idFor(payload),
      title: 'Refill reminder',
      body:
          '${m.name}: ${m.stockAmount} ${m.stockUnit} remaining. '
          'Update your supply in Refills.',
      hour: parts.hour,
      minute: parts.minute,
      payload: payload.encode(),
      exact: exactAlarms,
    );
    await _updateCount();
  }

  @override
  Future<void> cancelMedication(String patientId, String medicationId) =>
      _cancelFor(patientId, medicationId, ReminderKind.dose);

  @override
  Future<void> cancelRefill(String patientId, String medicationId) =>
      _cancelFor(patientId, medicationId, ReminderKind.refill);

  /// Sign-out: remove every reminder of this patient from the phone.
  @override
  Future<void> clearPatient(String patientId) async {
    await start();
    if (!supported) return;
    await _cancelWhere((_, p) => p.patientId == patientId);
    if (_patientId == patientId) _patientId = null;
    await _updateCount();
  }

  Future<void> _cancelFor(
    String patientId,
    String medicationId,
    ReminderKind kind,
  ) async {
    await start();
    if (!supported) return;
    await _cancelWhere(
      (_, p) =>
          p.kind == kind &&
          p.patientId == patientId &&
          p.medicationId == medicationId,
    );
    await _updateCount();
  }

  /// One patient's reminders per phone: the first call for a new patient
  /// removes any left over from another account (for example if the app
  /// was closed without signing out).
  Future<void> _prepare(String patientId) async {
    await start();
    if (_patientId == patientId) return;
    await _cancelWhere((_, p) => p.patientId != patientId);
    _patientId = patientId;
  }

  Future<void> _cancelWhere(
    bool Function(int id, ReminderPayload payload) test,
  ) async {
    for (final reminder in await plugin.pending()) {
      final payload = ReminderPayload.decode(reminder.payload);
      if (payload != null && test(reminder.id, payload)) {
        await plugin.cancel(reminder.id);
      }
    }
  }

  Future<void> _updateCount() async {
    scheduledCount = (await plugin.pending()).length;
    _notify();
  }

  int _idFor(ReminderPayload p) => notificationId(
    '${p.kind.name}/${p.patientId}/${p.medicationId}/${p.time}',
  );

  /// "1 tablet" or "2.5 ml".
  static String _amount(Medication m) {
    final amount = m.doseAmount == m.doseAmount.roundToDouble()
        ? m.doseAmount.toInt().toString()
        : m.doseAmount.toString();
    return '$amount ${m.doseUnit}';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_taps.close());
    super.dispose();
  }
}

/// The real plugin (Android). Not unit-tested: checked on an emulator.
class LocalNotificationsPlugin implements NotificationPlugin {
  final _plugin = FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  // "private": the lock screen hides the medication name unless the user
  // allows sensitive content in Android settings.
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'medication_reminders',
      'Medication reminders',
      channelDescription: 'Reminders when a dose or a refill is due',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.private,
    ),
  );

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    // Medication times are local wall-clock times ("08:00" means 08:00
    // wherever the phone is), so load the phone's time zone.
    tz_data.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
  }

  @override
  Future<bool> areNotificationsEnabled() async =>
      await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<void> requestPermission() async =>
      _android?.requestNotificationsPermission();

  @override
  Future<bool> canScheduleExact() async =>
      await _android?.canScheduleExactNotifications() ?? false;

  @override
  Future<void> requestExactAlarms() async =>
      _android?.requestExactAlarmsPermission();

  @override
  Future<void> openSettings() async => _plugin.openAppNotificationSettings();

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
    final now = tz.TZDateTime.now(tz.local);
    var first = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!first.isAfter(now)) {
      // Built from the date parts (not +24h) so DST cannot shift the hour.
      first = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        hour,
        minute,
      );
    }
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: first,
      notificationDetails: _details,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      // Repeat every day at the same time.
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  @override
  Future<List<PendingReminder>> pending() async => [
    for (final r in await _plugin.pendingNotificationRequests())
      PendingReminder(r.id, r.payload),
  ];

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}
