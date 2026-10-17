# Data Model and Data Source

## Data source plan

The application will use Firebase Authentication for account sign-in and Cloud Firestore for shared application data. The Phase 2 starter uses fictional in-memory sample data so the UI can run before backend integration. In the implementation phase, Firestore Security Rules will restrict patient records to the patient and the linked doctor.

## Main entities

| Entity | Important fields and Dart types | Source and persistence |
|---|---|---|
| UserProfile | `id: String`, `displayName: String`, `email: String`, `role: UserRole`, `linkedDoctorIds: List<String>` | Firebase Authentication supplies the account identity. The profile is stored in the `users` Firestore collection. |
| DoctorLink | `id: String`, `patientId: String`, `doctorId: String`, `linkCode: String`, `status: LinkStatus` | Created when a patient enters a doctor code. Stored in the `doctorLinks` collection. |
| Medication | `id: String`, `patientId: String`, `name: String`, `doseAmount: double`, `doseUnit: String`, `scheduledTimes: List<String>`, `stockAmount: int`, `refillThreshold: int`, `isActive: bool` | Entered and edited by the patient. Stored in the `medications` collection. |
| DoseRecord | `id: String`, `medicationId: String`, `patientId: String`, `scheduledTime: DateTime`, `status: DoseStatus`, `confirmedAt: DateTime?` | Created from the medication schedule. Stored in the `doseRecords` collection when a dose is scheduled, taken, overdue, or missed. |
| Reminder | `id: String`, `doseRecordId: String`, `reminderType: String`, `scheduledTime: DateTime`, `status: ReminderStatus` | Generated from dose schedules. The notification is scheduled locally on Android; reminder status can be stored with the dose record when needed. |
| Refill | `id: String`, `medicationId: String`, `currentStock: int`, `refillThreshold: int`, `lastUpdated: DateTime` | Stock is entered or updated by the patient. Stored with medication/refill data in Firestore. |
| PatientSummary | `patientId: String`, `patientName: String`, `stats: AdherenceStats`, `missedDoses: int`, `overdueDoses: int`, `requiresFollowUp: bool` | Derived for the doctor dashboard from linked patient profiles and dose records. It can be calculated at read time rather than stored as a separate source of truth. |
| AdherenceStats | `periodLabel: String`, `scheduledDoses: int`, `takenDoses: int`, `missedDoses: int`, `percentage: double` | Calculated from dose records for a selected week or month. The percentage is derived rather than manually entered. |

## Example Dart model

```dart
class Medication {
  const Medication({
    required this.id,
    required this.patientId,
    required this.name,
    required this.doseAmount,
    required this.doseUnit,
    required this.scheduledTimes,
    required this.stockAmount,
    required this.refillThreshold,
    this.isActive = true,
  });

  final String id;
  final String patientId;
  final String name;
  final double doseAmount;
  final String doseUnit;
  final List<String> scheduledTimes;
  final int stockAmount;
  final int refillThreshold;
  final bool isActive;
}
```

## How data enters and changes the app

1. The user signs in through Firebase Authentication. The app then reads the matching `UserProfile` document.
2. A patient enters a doctor code. The app validates the code and creates an active `DoctorLink` after consent.
3. The patient submits the medication form. The app writes the medication name, dose, daily times, stock amount, and refill threshold.
4. The medication schedule produces dose records and schedules local Android notifications.
5. When the patient taps **Taken**, the app updates the dose status to `taken`, records `confirmedAt`, and decreases the available stock.
6. If the dose is not confirmed within the defined period, the app changes its status to `overdue` or `missed` and schedules the additional reminder.
7. When stock reaches the refill threshold, the app displays a refill warning and can store the updated stock in Firestore.
8. The doctor dashboard reads linked patient records and calculates weekly or monthly adherence, missed doses, overdue doses, and follow-up flags.

## Persistence decisions

- Authentication identity: Firebase Authentication.
- Shared patient, doctor-link, medication, dose, and refill data: Cloud Firestore.
- Android reminder scheduling: `flutter_local_notifications` during implementation.
- Temporary form values and display-only UI state: local widget state with `setState`.
- Phase 2 demo data: the local `SampleData` service in the starter project.
