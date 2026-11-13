# Person 1 Phase 3 handoff

**Branch:** phase3/doses-reminders. **Base:** origin/phase3/medications-refills (Person 2's branch, not merged yet). Merge this branch after Person 2's PR, then rebase onto main.

| Scope | Status |
|---|---|
| #4 Dose Confirmation & History | Implemented: Mark as Taken on Today, Dose Confirmed page, overdue/missed statuses, History tab with Week and Month views, Firestore `doseRecords` with rules |
| #3 Medication Reminders | Implemented for Android: daily dose reminders, refill reminders, notification permission handling, bell overlay, Due Reminder page. Checked on an Android emulator (API 37) |
| #6 Missed-Dose Follow-up | Implemented: one follow-up notification when a dose becomes overdue, cancelled on confirmation, Missed Follow-up page. Checked on an Android emulator |

## How it works

### Doses (#4)
- Doses are not stored in advance. Today's doses are built from each active medication's `scheduledTimes`. A `doseRecords/{doseId}` document is written only when the status changes (taken, missed).
- **Dose ID:** `{medicationId}_{yyyyMMdd}_{HHmm}` in local time. The same dose always gets the same ID, so a second tap or a retry cannot create a second record, and Person 2's `consumeStock(doseId)` deducts stock only once.
- **Order on confirm:** the dose record is saved first, then stock is deducted. A stock problem only shows a warning on the Dose Confirmed page; the dose stays Taken.

### Status rules (`lib/services/dose_policy.dart`)
The approved Phase 1/2 documents did not give a number for the "defined period", so the team agreed these values. They are app rules, not medical advice.

| Status | Rule |
|---|---|
| Upcoming | Before the scheduled time + 30 minutes |
| Overdue | 30 minutes after the scheduled time, still not confirmed. Can still be marked as taken |
| Missed | 4 hours after the scheduled time, or when the next dose of the same medicine is due (whichever comes first). Final |
| Taken | Confirmed by the patient. Final |

Today's progress counts all of today's doses ("2 of 9"). Overdue doses do not count against adherence until they become missed. Both choices are flags in `DosePolicy` for the statistics owner.

### Reminders (#3)
- `NotificationService` (`lib/services/notification_service.dart`) implements Person 2's `MedicationReminderGateway`. It schedules one daily notification per medication time, and a daily refill reminder at 09:00 while stock is low (this connects #8's Android delivery).
- Notification IDs come from an FNV-1a hash of a text key, so they are the same on every run: restarting the app replaces reminders instead of duplicating them.
- Exact timing is used only if the patient allows it ("Alarms & reminders"); otherwise Android may deliver a few minutes late. The Notification Permissions page shows which one is active.
- Reminders belong to one patient per phone. Signing out, or signing in as another patient, removes the previous patient's reminders.
- Tapping a dose reminder opens Today. The Due Reminder page opens from the bell overlay.

### Follow-ups (#6)
- A one-time follow-up notification is scheduled **in advance** at scheduled time + 30 minutes for today's and tomorrow's unconfirmed doses, so it fires even when the app is closed.
- Confirming the dose cancels its follow-up and removes it from the notification tray. Each follow-up is scheduled only once.
- Tapping a follow-up opens the Missed Follow-up page, including when the tap starts a closed app. "Review dose history" opens the History tab.

## Packages and Android permissions

| Package | Purpose | License |
|---|---|---|
| flutter_local_notifications ^23.0.1 | Schedule and show Android notifications | BSD-3-Clause |
| timezone ^0.11.2 | Schedule at local wall-clock times | BSD-2-Clause |
| flutter_timezone ^5.1.1 | Read the phone's time zone | Apache-2.0 |

| Permission | Why |
|---|---|
| POST_NOTIFICATIONS (added by the plugin) | Android 13+ asks the patient to allow notifications |
| SCHEDULE_EXACT_ALARM | Optional exact timing, granted by the patient |
| RECEIVE_BOOT_COMPLETED | Restore scheduled reminders after the phone restarts |

`android/app/build.gradle.kts` enables core library desugaring, which the notification plugin requires.

## Reproducible demonstration

1. Start the Auth/Firestore emulators as described in the README and run the app on an Android emulator (API 33 or higher) with `--dart-define=USE_FIREBASE_EMULATORS=true`. Sign in as a fictional patient and allow notifications.
2. Bell → Notification settings → Allow exact timing.
3. Add a medication with a time 3 minutes from now. The reminder arrives at that time; the bell shows "Medication due".
4. Do not confirm it. Swipe the app away. A "Missed dose follow-up" notification arrives 30 minutes after the dose time; tapping it opens Missed Follow-up.
5. Add another medication and confirm it before it is 30 minutes late: no follow-up arrives, and the count on Notification settings drops by one.
6. Confirm a dose on Today: Dose Confirmed shows the dose, the stock result and the progress. History shows it under Week and Month.
7. Turn notifications off in Android settings: Notification settings shows the denied state, and doses can still be confirmed.

To test without waiting 30 minutes, temporarily set `overdueAfter` to 2 minutes in `dose_policy.dart`, and undo it afterwards with `git restore lib/services/dose_policy.dart`. Four automated tests fail while it is changed.

## Tests

- Flutter: `test/dose_*_test.dart`, `test/notification_service_test.dart`, `test/notifications_ui_test.dart`, `test/dose_follow_up_test.dart`, `test/missed_follow_up_ui_test.dart`. Fakes: `test/support/memory_dose_store.dart`, `test/support/fake_notification_plugin.dart`.
- Firestore rules: `firestore_rules_test/dose_rules.test.mjs`.
- The real notification plugin cannot run in unit tests, so it sits behind the `NotificationPlugin` interface and the tests use a fake. Android delivery was checked by hand on an emulator.

## Known limitations

1. **`Medication` has no `createdAt`.** A dose scheduled earlier on the day a medication was added can show as overdue or missed. Fix: Person 2 adds a `createdAt` server timestamp, and `scheduledDosesForDay` skips earlier doses.
2. **Taken is final, with no undo.** This follows the design, but an accidental tap cannot be corrected. Options: a confirmation dialog before saving, a short undo window (with stock deducted only after it closes), or both.
3. **Statuses update only while the app is open** (on load, every minute, and on returning to the app). The follow-up notification covers the closed case.
4. **Only today's doses are generated.** A past day when the app was never opened has no missed records in History.
5. **Follow-ups are scheduled only for today and tomorrow.** If the app is not opened for longer, later follow-ups are not scheduled. A dose that is already late when the app first opens that day gets no follow-up notification, but it appears in the bell and on the Missed Follow-up page.
6. **Stock-deduction retries are kept in memory.** If the app closes while offline before a retry succeeds, that deduction is lost; the patient can correct stock in Refills.
7. **History periods are rolling:** Week is the last 7 days and Month the last 30 days, including today.
8. **Android only.** Notifications are turned off on web and desktop; dose confirmation and History still work there.
9. **The cold-start tap fix** (a follow-up tapped while the app was closed) is covered by automated tests, but was not re-checked by hand on the emulator after the fix.
10. **The `doseRecords` rules are not deployed.** Deploy them (`firebase deploy --only firestore:rules`) before testing against the live project.
11. **No doctor read path for doses yet.** The repository reads only the signed-in patient's records. The rules already allow linked doctors to read, so the statistics owner needs to add the doctor query.

## Notes for teammates

- **Changed shared files:** `main.dart` (DoseProvider and NotificationService providers), `app_shell.dart` (History tab, bell, notification taps), `pubspec.yaml`, `firestore.rules` (`doseRecords`), the Android manifest and `build.gradle.kts`.
- **Teammates' tests I updated:** `patient_home_overflow_test.dart`, `medication_navigation_test.dart`, `doctor_code_dialog_test.dart` and `test/support/app_providers.dart`, for the new dose provider and buttons.
- **Statistics owner:** use `DosePolicy.countFutureDosesInToday` and `overdueCountsAsMissed` so statistics match Today.
