import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notification_service.dart';
import '../theme/app_theme.dart';

/// "Notification Permissions" page (Phase 2 "State: Permission Denied").
/// Shows the real Android state: on, blocked, or not available here.
/// The patient can always continue: tracking works without notifications.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<NotificationService?>()?.refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The patient may have changed the permission in Android settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<NotificationService?>()?.refreshStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<NotificationService?>();
    final permission = service?.permission ?? ReminderPermission.unsupported;
    final close = FilledButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(
        permission == ReminderPermission.granted
            ? 'Done'
            : 'Continue without notifications',
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Notification Permissions')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.medium),
        children: [
          ...switch (permission) {
            ReminderPermission.granted => [
              const _Banner(
                icon: Icons.notifications_active_outlined,
                color: AppColors.teal,
                background: AppColors.mint,
                text: 'Notifications are on.',
              ),
              const SizedBox(height: AppSpacing.small),
              // Scheduled is not "delivered": say exactly what we know.
              Text(
                '${service!.scheduledCount} reminders are scheduled on this '
                'phone. Android shows each one at its time.',
              ),
              const SizedBox(height: AppSpacing.small),
              Text(
                service.exactAlarms
                    ? 'Timing: exact.'
                    : 'Timing: approximate. Android may show reminders a '
                          'few minutes late to save battery.',
              ),
              if (!service.exactAlarms)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: service.requestExactAlarms,
                    child: const Text('Allow exact timing'),
                  ),
                ),
            ],
            ReminderPermission.denied => [
              const _Banner(
                icon: Icons.warning_amber_outlined,
                color: AppColors.amber,
                background: AppColors.cream,
                text: 'Notifications disabled in Android settings.',
              ),
              const SizedBox(height: AppSpacing.small),
              const Text(
                'You will not get dose reminders. You can still mark doses '
                'as taken and see your history.',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: service!.openSettings,
                  child: const Text('Open Android settings'),
                ),
              ),
            ],
            ReminderPermission.unknown => [
              const Center(child: CircularProgressIndicator()),
            ],
            ReminderPermission.unsupported => [
              const _Banner(
                icon: Icons.info_outline,
                color: AppColors.muted,
                background: AppColors.tint,
                text: 'Reminders work in the Android app only.',
              ),
            ],
          },
          const SizedBox(height: AppSpacing.medium),
          close,
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.medium),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: AppSpacing.small),
        Expanded(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    ),
  );
}
