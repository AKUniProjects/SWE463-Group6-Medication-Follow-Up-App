enum ReminderStatus { scheduled, sent, cancelled }

class Reminder {
  const Reminder({
    required this.id,
    required this.doseRecordId,
    required this.reminderType,
    required this.scheduledTime,
    required this.status,
  });

  final String id;
  final String doseRecordId;
  final String reminderType;
  final DateTime scheduledTime;
  final ReminderStatus status;
}
