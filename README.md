# SWE463 Group 06 — Medication Follow-up App

Phase 3 Flutter prototype for Android and Chrome, using fictional medical data.

## Current implementation

- Firebase Authentication: Patient/Doctor registration, email/password login, validation, profile creation with rollback, session restoration, sign-out, and visible sign-out errors.
- Role routing through AuthGate and AppShell. Each authenticated session owns a navigator; switching identity or signing out disposes its details, editors, linking screens, and dialogs. Late auth-action results cannot restore a superseded session.
- Doctor Linking: secure 10-character codes, normalized lookup, doctor preview, explicit consent, duplicate prevention, link success/error views, and patient link management.
- Codes expire 30 days after server creation time. Doctors can generate, copy, replace, and deactivate codes. Replacement reports partial failures instead of hiding an older active code.
- Consent confirmation carries the previewed doctor UID. The repository rejects a changed identity; rules revalidate the written doctor UID against the code at commit time.
- Patients and doctors can revoke links through repository/provider operations. Patient revocation has UI; doctor-side Revoke UI remains pending.
- Firestore rules cover users, doctorCodes, doctorLinks, medications and immutable stock-consumption receipts. Other collections remain default-denied.
- Doctor Dashboard receives real active linked patients through LinkedPatientsDashboard. Pull-to-refresh works for empty, short, and longer lists. Provider request generations prevent older reads from overwriting newer mutation/refresh results.
- Patient Home cards retain status chips and Taken feedback in a growing action area. Buttons have a minimum 48px height without shrinking enlarged text. Regression tests cover 320/390px widths, text scales through 2x, and long names.

## Known unfinished Phase 3 work

Patient navigation contains Today, Medications and History, plus a Sign out action. The approved Insights destination is not integrated yet. Doctors have a separate dashboard and linking-code action.

Person 2's medication CRUD and supply tracking now use authenticated patient-scoped Firestore data through Provider/ChangeNotifier. Today displays the same saved medication plan and stock; it no longer presents sample doses or hardcoded refill warnings in the authenticated flow. Dose confirmation/history, Android reminders and missed-dose follow-up are connected (see Person 1 below). Real adherence statistics remain teammate-owned work.

The doctor adapter passes real Firebase patient UIDs, but statistics stay empty until the statistics owner reads doseRecords for linked patients. Zero records currently display as 0% adherence; this does not indicate measured nonadherence. Doctor-side revocation UI and real patient-history content remain pending.

## Shared architecture and contracts

- Models are in lib/models; repository interfaces and Firebase adapters are in lib/services; session-scoped ChangeNotifiers are in lib/state.
- AuthRepository.currentUid exposes the authoritative identity even while an operation is pending.
- DoctorLinkProvider follows AuthProvider through the ProxyProvider in main.dart.
- doctorLinks/{patientId}_{doctorId} is the authoritative relationship. UserProfile.linkedDoctorIds stays empty and never authorizes reads.
- New repositories/providers must use Firebase UIDs, clear session state, and reject stale results.
- Coordinate changes to main.dart, app_shell.dart, auth_gate.dart, shared models, firestore.rules, pubspec.yaml/lock, and this README.
- Medication serialization, stock units, stable dose IDs and reminder hooks are documented in [Person 2's handoff](docs/PERSON2_HANDOFF.md). Person 1's dose confirmation, reminders and follow-ups are documented in [Person 1's handoff](docs/PERSON1_HANDOFF.md).

### Person 1 — Doses, Reminders and Missed-Dose Follow-up

| Essential feature | Current status | Evidence |
|---|---|---|
| #4 Dose Confirmation & History | Implemented | Mark as Taken on Today, Dose Confirmed page, overdue/missed statuses, History tab (Week/Month), `doseRecords` Firestore rules and rule tests |
| #3 Medication Reminders | Implemented for Android | Daily dose reminders and low-stock refill reminders, permission prompt and denied state, bell overlay, Due Reminder page; checked on an Android emulator (API 37) |
| #6 Missed-Dose Follow-up | Implemented for Android | One follow-up notification 30 minutes after an unconfirmed dose, even with the app closed; cancelled on confirmation; Missed Follow-up page; checked on an Android emulator |

A dose becomes **Overdue** 30 minutes after its scheduled time (it can still be marked as taken) and **Missed** after 4 hours, or earlier when the next dose of the same medicine is due. Missed and Taken are final. These are team-agreed app rules, not medical advice; they live in `lib/services/dose_policy.dart`.

Dose IDs are `{medicationId}_{yyyyMMdd}_{HHmm}`, so one dose has one record and stock is deducted once. Notifications use flutter_local_notifications (BSD-3-Clause), timezone (BSD-2-Clause) and flutter_timezone (Apache-2.0). Android permissions: notifications, optional exact alarms, and restoring reminders after a restart. Notifications are Android only; on Chrome the dose features still work without them.

See the [handoff](docs/PERSON1_HANDOFF.md) for the demonstration steps, tests and known limitations.

### Person 2 — Medication Management and Refills

| Essential feature | Current status | Evidence |
|---|---|---|
| #2 Medication Management | Implemented for the owned CRUD flow | Validated multi-time Add/Edit, full-screen Keep/Confirm soft deletion, Firestore persistence, shared Today/list/refill refresh, patient isolation and error handling |
| #8 Medication Refill Reminder | In progress | Supply edits including zero, inclusive low-stock threshold, explicit consumption units, estimates and testable alert hooks work; Android notification delivery is not connected or verified |

Medications → Add medication / tap a saved card → Edit → Delete confirmation. Refills are reachable from Medications and Today. Editors opened from Today return to Medications. Cancellation does not write; revision checks reject stale drafts instead of overwriting newer stock.

Each medication owns its only stock balance. Low supply means stockAmount <= refillThreshold (default 7 counted stock units, editable). Estimated days = stockAmount / (unitsPerDose × unique daily times), shown to one decimal only when consumption is explicitly known. Prescribed mg/IU are never inferred to be tablets. Stock and per-dose consumption use whole counted units in this prototype.

New rules were checked locally, not deployed. Use emulators until the team reviews/deploys rules. See [handoff and verification](docs/PERSON2_HANDOFF.md) for limitations, interfaces, commands and actual screenshots.

### Doctor Linking data model

| Document | Fields and policy |
|---|---|
| users/{uid} | displayName, email, role, linkedDoctorIds. Owner creates their profile; only displayName can be updated. A linked doctor can read the patient's profile, never modify it. |
| doctorCodes/{code} | doctorId, doctorName, active, createdAt. Doctor creates their own code; 30-day expiry derives from immutable server createdAt. Owner may deactivate or delete. Signed-in users can get a known code; only its owner can list their codes. |
| doctorLinks/{patientId}_{doctorId} | patientId, doctorId, patientName, doctorName, linkCode, status, consentedAt; revokedAt/revokedBy when revoked. Patient creates/reactivates with a usable code and fresh consent. Either party may revoke. No deletes. |

Codes use the 32-symbol alphabet ABCDEFGHJKLMNPQRSTUVWXYZ23456789 (50 bits for 10 characters), generated with Random.secure(). Creation is transactional and retries collisions. Spaces/hyphens are removed and input is uppercased before lookup; grouped display is presentation only.

createdAt, consentedAt, and revokedAt use FieldValue.serverTimestamp(). Client-chosen timestamps are rejected.

After patient revocation, the same still-valid code may reactivate the link. After doctor revocation, the patient must use a code issued strictly after revokedAt. Code deactivation/replacement does not revoke existing links.

The repository's linkWithCode requires both consentGiven and expectedDoctorId from preview. Deleted codes fail lookup; a code recreated for another doctor fails the UID comparison. If it changes after lookup but before writing, existing rules reject the original doctorId/code pair. Rules cannot prove what a human read on screen; they enforce the patient-authenticated write and the code/doctor relationship.

### Authorized query contract

- Doctor links: doctorLinks.where('doctorId', isEqualTo: myUid), then filter active status in Dart (or add an active equality filter).
- Patient links: doctorLinks.where('patientId', isEqualTo: myUid).
- Linked patient profile: users.doc(patientId).get(), individually by ID.
- Do not issue unrestricted users or doctorLinks collection queries. Security Rules are not filters.
- Future doctor access to medication/dose records must also require an active patient-approved relationship; Doctor role alone is insufficient.

## Development setup — Windows PowerShell

### Tools and supported targets

| Tool | Recommended setup |
|---|---|
| Flutter / Dart | Verified locally with Flutter 3.47.9 stable / Dart 3.13.7. The lockfile requires Dart >=3.13.0; pubspec reflects that minimum. Prefer the verified toolchain for teammates. |
| Firebase CLI | 15.35.0 used for emulator verification; use an existing installation, or install separately during initial setup. |
| Java | JDK 21 or newer for the Firestore emulator. |
| Node.js | Node 24 used for CLI and built-in Node rule tests. |
| Chrome | Configured web target. Edge is also available as a development target. |
| Android Studio/device emulator | Android is the primary mobile target; check flutter devices for its actual ID. |

Firebase options are configured for Android and web only. Generated Windows/macOS/Linux/iOS folders do not mean Firebase is configured for those targets.

Initial setup (downloads Flutter dependencies):

~~~powershell
git clone https://github.com/AKUniProjects/SWE463-Group6-Medication-Follow-Up-App.git
cd SWE463-Group6-Medication-Follow-Up-App
flutter pub get
~~~

Firebase client configuration is committed for swe463-group06-medication-app. It is not a service-account credential. Do not commit passwords, private keys, or tokens.

### Run locally with emulators — recommended

Terminal 1:

~~~powershell
firebase emulators:start --only auth,firestore
# If the pinned CLI is not installed, initial setup may instead use:
# npx -y firebase-tools@15.35.0 emulators:start --only auth,firestore
~~~

Auth listens on 9099, Firestore on 8080, and Emulator UI on http://127.0.0.1:4000.

Terminal 2:

~~~powershell
flutter run --no-pub -d chrome --dart-define=USE_FIREBASE_EMULATORS=true
flutter run --no-pub -d emulator-5554 --dart-define=USE_FIREBASE_EMULATORS=true
~~~

Replace emulator-5554 with the Android ID from flutter devices. Web connects through localhost; Android Emulator uses 10.0.2.2.

Emulator mode is opt-in, refused in release builds, and does not silently fall back to live Firebase. Always include USE_FIREBASE_EMULATORS=true for fictional testing. Omitting it uses the configured live project, whose rules have not been deployed/verified as part of this prototype; do not use that as the default test path.

Emulators bind to 127.0.0.1. A physical phone cannot reach that listener merely by adding FIREBASE_EMULATOR_HOST=<PC LAN IP>. LAN testing requires deliberate emulator host/network configuration; prefer Chrome or Android Emulator for the documented local setup. Emulator data is temporary unless explicitly exported/imported.

### Fictional test accounts

Create accounts through the local app's Create an account screen:

| Role | Name | Email | Password |
|---|---|---|---|
| Patient | Test Patient | patient.test@example.com | Choose a fictional password, 6+ characters |
| Doctor | Test Doctor | doctor.test@example.com | Choose a fictional password, 6+ characters |

Use different accounts for account-switching checks. Do not enter real patient information.

## Tests

With dependencies already available:

~~~powershell
flutter analyze --no-pub
flutter test --no-pub
~~~

Rule tests use Node's built-in runner and the local emulator REST API; they need no npm test dependencies. Run files sequentially because each test resets its test-project database.

If port 8080 is free, the documented temporary-emulator command is:

~~~powershell
npx -y firebase-tools@15.35.0 emulators:exec --only firestore --project demo-medfollow "node --test --test-concurrency=1 firestore_rules_test/users_rules.test.mjs firestore_rules_test/doctor_linking_rules.test.mjs firestore_rules_test/medication_rules.test.mjs firestore_rules_test/dose_rules.test.mjs"
~~~

An installed CLI can replace the npx prefix with firebase. Do not download tools unnecessarily.

If this repository's emulator is already running with the current firestore.rules, reuse it in a separate fictional test-project namespace:

~~~powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:GCLOUD_PROJECT = 'demo-medfollow'
node --test --test-concurrency=1 firestore_rules_test/users_rules.test.mjs firestore_rules_test/doctor_linking_rules.test.mjs firestore_rules_test/medication_rules.test.mjs firestore_rules_test/dose_rules.test.mjs
~~~

First check the process/project/rules path. Do not kill unrelated processes. The tests reset demo-medfollow data; do not point GCLOUD_PROJECT at an emulator dataset you want to keep. With singleProjectMode enabled, the separate demo namespace may produce a project-ID warning; it still stays entirely local.

### Manual smoke checklist

1. Register Patient and Doctor accounts in emulator mode; verify the corresponding role screens.
2. Reload to check restoration; try incorrect credentials and an Auth-only account with a missing profile.
3. Doctor generates a code; patient previews the doctor and explicitly consents.
4. Doctor refreshes their dashboard, including with zero/one patient, then opens patient details.
5. Check Back, sign-out, and account switching. No old patient details or dialogs should remain.
6. Revoke from the patient, refresh the doctor dashboard, and confirm the patient disappears.
7. Add a medication with two daily times; confirm Today and Medications show the same record. Edit, update supply to zero, reload, then test Keep/Confirm deletion.
8. An unknown named route while signed out must show Login.
9. Mark a dose as taken on Today; check Dose Confirmed, the Taken chip and History (Week/Month). On Android, check a reminder and a follow-up notification (see [Person 1's handoff](docs/PERSON1_HANDOFF.md)).

## Security boundaries

- Doctors self-register and are not professionally verified.
- Doctor role alone never grants patient-record access; an active patient-approved link is required.
- Code guessing is not server-rate-limited in this Firestore-only prototype.
- Revocation blocks future server-authorized reads, but cannot recall data already received/cached.
- Medication reads require ownership or an active doctor link; only the patient may write. Soft deletion retains metadata and stock receipts are immutable. Dose-record permissions remain Person 1's unfinished integration.
- Local rules/tests are not live deployment. No Firebase deployment is part of this workflow.
- Fictional coursework data only; production healthcare readiness is outside the project scope.

## Project structure

~~~text
lib/
  main.dart
  firebase_options.dart
  firebase_emulators.dart
  models/       # profiles, links, medication/dose and summary models
  services/     # repository contracts, Firebase adapters, SampleData
  state/        # AuthProvider, DoctorLinkProvider, MedicationProvider
  theme/        # shared Material 3 colors, spacing and component styles
  screens/      # AuthGate/session navigator, AppShell, feature screens
  widgets/      # authentication fields/banners, medication/refill views
test/           # unit/widget regressions using controllable repositories
firestore_rules_test/  # sequential local-emulator authorization tests
firestore.rules
firebase.json, .firebaserc
~~~

Dependencies remain Firebase Core/Auth/Firestore and Provider, with flutter_test/flutter_lints for development. Notification dependencies and implementation remain future teammate work.

No application packages were added by Person 2. Existing package purposes/licenses:

| Package | Purpose | License |
|---|---|---|
| Flutter / Dart, flutter_test | Material 3 UI, runtime and widget tests | BSD-3-Clause |
| provider | Shared authentication/link/medication ChangeNotifier state | MIT |
| firebase_core | Initialize Firebase | BSD-3-Clause |
| firebase_auth | Patient/doctor sessions | BSD-3-Clause |
| cloud_firestore | Persistence, streams and stock transactions | BSD-3-Clause |
| flutter_lints | Static analysis rules | BSD-3-Clause |

Material icons are Flutter's bundled Material assets (Apache-2.0). Package license notices remain authoritative. No new font, image asset or application dependency was introduced.

## Design and Documentation Tools

- **Figma:** Used to create UI screen designs, interface states, and the interactive prototype.
- **draw.io (diagrams.net):** Used to create the master navigation diagram and eight detailed navigation flow diagrams. The editable source files are stored locally, and the diagrams are included in the Phase 2 PDF.
- **GitHub:** Used for the Flutter starter project, source code, and version control.

### Figma Design

[Full Figma Design](https://www.figma.com/design/hSyXUqyLPNyfsx5bOzb5tr/SWE463---Group-06---Medication-Follow-up-App--Phase-2-UI-Design?node-id=3-2)

### Interactive Prototype

[Figma Interactive Prototype](https://www.figma.com/proto/hSyXUqyLPNyfsx5bOzb5tr/SWE463---Group-06---Medication-Follow-up-App--Phase-2-UI-Design?node-id=4-435)

## Contribution Evidence

Phase 2 work was distributed among four group members:

- **Hashim Alramadhan:** Cover page, state management plan, contribution record, references, AI-use disclosure, and final PDF assembly.
- **Ali Aloryd:** Figma screen designs, interface states, and interactive prototype.
- **Abdulaziz Alwarthan:** Master navigation diagram, eight detailed navigation flow diagrams, and Flutter widget plan.
- **Khaled Mathbaq:** Data model, data source planning, Flutter starter project, repository structure, and running application screenshot.

Not all contributions are stored in GitHub. The final Phase 2 PDF includes the contribution record, with supporting work available through Figma, locally stored draw.io files, and the GitHub repository.

## AI-Use Disclosure

AI assistance was used to draft portions of the Flutter starter structure, sample data models, and technical documentation, and to support design inspiration, content revision, and language polishing.

The team reviewed and adapted AI-assisted material, remains responsible for the final work, and can explain the submitted design and implementation decisions.

For Person 1's Phase 3 contribution (Features #3, #4 and #6), Claude Code (Anthropic) was used as an AI assistant to plan the work, generate implementation code and tests, debug problems found during emulator testing, and draft this documentation. Person 1 reviewed the changes, ran the tests and the emulator checks, took the screenshots, and can explain the submitted code and design decisions.

For Person 2's Phase 3 contribution, Codex generated substantial implementation, tests, documentation and local verification assistance. This is an AI-assisted review draft; student/team review and the ability to explain it are still required before submission. The earlier Phase 2 disclosure does not establish that the team has already reviewed these changes. See the handoff for a code walkthrough and actual evidence.
