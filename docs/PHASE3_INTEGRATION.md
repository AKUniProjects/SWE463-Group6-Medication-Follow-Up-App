# Phase 3 integration — 14 November 2026

Combined sources:

- Person 2: phase3/medications-refills at b8ebe4c (persistent medications/refills).
- Person 1: phase3/doses-reminders at 70e14ee, stacked on Person 2 (doses/history, Android reminders and follow-ups).
- Person 4: main at ea22725 (linked-patient records, doctor dashboard and adherence).
- Person 3's authentication, role checks and consent/linking foundation remain included.

The source branches combined without text conflicts. The combined baseline had 310 passing and 15 failing Flutter tests, caused by dashboard/provider integration and stale fixtures. These were fixed before merging.

## Integration fixes

- Preserve all providers in main.dart. Dose confirmation uses the shared medication provider with a stable scheduled-dose ID, while the notification service implements the existing medication reminder gateway.
- Refill notification taps now open Refill Tracking rather than Today. Running-app and cold-start taps share routing. Invalid or other-patient payloads cannot navigate the current patient's session.
- Transient stock failures from the real repository are MedicationException(unavailable/conflict). Those now enter the retry queue and stay queued across repeated temporary errors; permanent ownership/missing-record failures are not retried. Successful attempts use the original receipt ID to prevent double deduction.
- Restore pull-to-refresh for the doctor's dashboard, including an empty list.
- Fix the doctor progress bar's accessibility semantics: the missing-data caption is not used as a numeric progress value. This avoids Flutter semantics assertions and does not present missing data as measured adherence.
- Update the app and direct-shell test fixtures to include the actual doctor dashboard provider. Existing authentication, linked-patient and session-isolation assertions remain exercised through the new screens and explicit View patient action.
- Add integration regressions for stock retries, refill routing, another-patient notification rejection, live doctor statistics, revocation and read-failure clearing.

## Verification

| Check | Result |
|---|---|
| Dependency resolution | Offline pub get passed with the branch's pinned lockfile |
| Static analysis | No issues |
| Flutter unit/widget tests | 330 passed |
| Firestore emulator rule tests | 47 passed, 0 failed |
| Web debug build | Passed; Wasm dry run also succeeded |
| Android debug APK | Blocked: no Android SDK in this environment |

Actual logs are in [integration-evidence](integration-evidence/). The unchanged rule tests include linked-doctor read permissions, patient isolation, stock receipts and dose-record mutations. New doctor-provider tests use controlled streams to verify live confirmation statistics and immediate clearing on revocation, read failure and session change.

Commands, using Auth/Firestore emulators on localhost :9099/:8080:

~~~powershell
flutter pub get --offline
flutter analyze --no-pub
flutter test --no-pub
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:GCLOUD_PROJECT = 'demo-medfollow'
node --test --test-concurrency=1 firestore_rules_test/users_rules.test.mjs firestore_rules_test/doctor_linking_rules.test.mjs firestore_rules_test/medication_rules.test.mjs firestore_rules_test/dose_rules.test.mjs
flutter build web --debug --no-pub
flutter build apk --debug --no-pub
~~~

Session toolchain: Flutter 3.47.1 / Dart 3.13.1, Node 24, Firebase CLI 15.35.0, Java 21. The SDK's cached CLI snapshot was used with a workspace package cache. Missing pinned package archives were fetched from pub.dev and checked against lockfile SHA-256 hashes. FLUTTER_WINDOWS=false and FLUTTER_LINUX=false disabled unrelated desktop plugin-symlink generation in this Windows sandbox; the desktop project sources were preserved. No system Developer Mode or global Git configuration was changed. Analyzer log terminal padding is trimmed; result content is unchanged.

## Remaining limits

Android delivery was not rerun in this environment. Person 1 supplied earlier emulator screenshots and a handoff describing dose/follow-up delivery; those are teammate evidence, not new verification of this combined build. Recheck dose and refill delivery, permissions, restart restoration, and notification taps on Android before submission.

Existing prototype limits remain: stock retries are in memory (a shutdown can lose a pending deduction), dose and stock writes are separate transactions, newly added medication schedules can include earlier times on their creation day because no createdAt is stored, and follow-ups are scheduled for today/tomorrow. Patient Details is a summary snapshot. See the individual handoffs for the complete limitations.

This integration does not deploy Firebase rules, create a release build, or add a submission tag. Codex assisted with integration review, fixes, tests and this record; student/team review is still required under the course's AI-use policy.
