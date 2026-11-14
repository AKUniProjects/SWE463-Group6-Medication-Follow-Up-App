# MedFollow — Medication Follow-up App

**SWE463 · Mobile Application Development | Group 06 | Phase 3 — Working Flutter Prototype**

MedFollow is a Flutter application for patients managing daily medications and doctors monitoring patients who have agreed to share their records. Patients can manage medication schedules, confirm doses, review history and stock levels, and receive reminders. Doctors can link to patients through consent-based codes and view adherence summaries. **The prototype uses fictional medical data only.**

**Repository:** https://github.com/AKUniProjects/SWE463-Group6-Medication-Follow-Up-App

## Team and responsibilities

| Person | Team member | Student ID | Phase 3 contribution |
|---|---|---|---|
| 1 | Hashim Alramadhan | 202021320 | Medication reminders, dose confirmation/history, and missed-dose follow-up |
| 2 | Khaled Mathbaq | 202283100 | Medication management, refill tracking, and feature integration |
| 3 | Ali Kamal Aloryd | 202322750 | Authentication, doctor linking, Firebase security, and role navigation |
| 4 | Abdulaziz Alwarthan | 202160310 | Doctor dashboard, linked-patient records, and adherence calculations |

## Implemented Phase 3 features

| Essential feature | Status | Working prototype scope |
|---|---|---|
| 1. Accounts and Doctor Linking | **IMPLEMENTED** | Patient/Doctor sign-up and sign-in, secure linking codes, doctor preview, patient consent, and link management |
| 2. Medication Management | **IMPLEMENTED** | Firestore-backed add, edit, soft-delete, and daily medication schedules |
| 3. Medication Reminders | **IMPLEMENTED** | Scheduled Android notifications, notification permissions, and in-app reminders |
| 4. Dose Confirmation and History | **IMPLEMENTED** | Mark as Taken, saved dose records, and Week/Month history |
| 5. Doctor Dashboard | **IMPLEMENTED** | Linked-patient list, weekly adherence summaries, and follow-up indicators |
| 6. Missed-Dose Follow-up | **IMPLEMENTED** | Overdue/missed status handling, reminder notifications, and follow-up screen |
| 7. Adherence Statistics | **IMPLEMENTED** | Seven-day adherence calculations and doctor-facing statistics; patient Insights screen remains planned |
| 8. Medication Refill Reminder | **IMPLEMENTED** | Stock tracking, low-stock warnings, supply updates, and Android refill reminders |

These statuses describe the **Phase 3 prototype scope**; outstanding screens and edge cases are listed below.

## Technology and project structure

- **UI:** Flutter, Dart, and Material 3.
- **State management:** Provider / ChangeNotifier for authentication, doctor links, medications, doses, and the doctor dashboard.
- **Data:** Firebase Authentication and Cloud Firestore, accessed through repositories and tested using local Firebase emulators.
- **Notifications:** Android local notifications with timezone-aware scheduling.
- **Security:** Firestore rules restrict patient data to its owner and doctors with an active, consented link.

The main application code is organized in `lib/screens/` (pages), `lib/widgets/` (reusable UI), `lib/models/` (data), `lib/state/` (providers), and `lib/services/` (repositories and business logic). Automated Flutter tests are in `test/`; Firestore authorization tests are in `firestore_rules_test/`.

## Setup and run

**Prerequisites:** Flutter with Dart **3.13+** (team-used Flutter 3.47.9), Android Studio/emulator or Chrome, Node.js (team-used Node 24), Java JDK 21+, and Git. The team used Firebase CLI **15.35.0**. A Firebase Console account or cloud database is **not required** for local testing.

Clone the repository and install dependencies:

```powershell
git clone https://github.com/AKUniProjects/SWE463-Group6-Medication-Follow-Up-App.git
cd SWE463-Group6-Medication-Follow-Up-App
flutter pub get
```

**Terminal 1 — Start Firebase Authentication and Firestore emulators:**

```powershell
npx -y firebase-tools@15.35.0 emulators:start --only auth,firestore
```

Keep this terminal running. The Authentication emulator uses **9099**, Firestore **8080**, and the Emulator UI is at http://127.0.0.1:4000. The configured project ID is `swe463-group06-medication-app`.

**Terminal 2 — Run the app in Chrome:**

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true
```

**Or run on an Android emulator:**

```powershell
flutter devices
flutter run -d emulator-5554 --dart-define=USE_FIREBASE_EMULATORS=true
```

Replace `emulator-5554` with the device ID reported by `flutter devices`. Android emulators connect to the host at `10.0.2.2`; Chrome uses `localhost`. Always include `USE_FIREBASE_EMULATORS=true` when testing fictional accounts. Emulator data is temporary unless explicitly exported.

## Demonstration flow

1. On **Create an account**, register a fictional **Doctor**, open **Linking code**, and generate a code.
2. In another browser session, register a fictional **Patient**. Open **Link with Doctor**, preview the doctor, accept the consent checkbox, and confirm the link.
3. As the patient, open **Medications**, add a medication and schedule, and confirm a dose from **Today**. Check the **History** tab and updated stock/refill indicators.
4. Return to the doctor session. On the **Dashboard**, verify the linked patient and their adherence summary; open **Patient Details**.

Do not enter real patient information or use production credentials.

## Testing and evidence

```powershell
flutter analyze
flutter test
```

To run the Firestore security-rule tests, **stop the running Firestore emulator first** (or use a separate compatible local test namespace), then run:

```powershell
npx -y firebase-tools@15.35.0 emulators:exec --only firestore --project demo-medfollow "node --test --test-concurrency=1 firestore_rules_test/users_rules.test.mjs firestore_rules_test/doctor_linking_rules.test.mjs firestore_rules_test/medication_rules.test.mjs firestore_rules_test/dose_rules.test.mjs"
```

The final integration logs report **330 passing Flutter tests**, **47 passing Firestore-rule tests**, and **no analyzer issues**. The team also completed a final merged Android run. Saved integration logs are in [`docs/integration-evidence/`](docs/integration-evidence/); feature screenshots and handoffs are in `docs/`.

## Known limitations and planned improvements

- The patient **Insights** tab and 30-day trend visualization are not yet connected to navigation; adherence statistics are available on the doctor side.
- **Patient Details** shows aggregate adherence rather than a detailed medication/dose timeline. Doctor-side link revocation exists in the data layer but has no dashboard button yet.
- Notifications are native to **Android**; Chrome uses in-app reminders. Missed-dose records are not backfilled for every day the app was closed, and some pending stock retries are in memory.
- The team tested Firestore security rules **locally**; the cloud rules/database were not deployed as part of Phase 3. Doctors are self-registered for this coursework prototype, not professionally verified.

## Main packages

| Package(s) | Purpose | License |
|---|---|---|
| `firebase_core`, `firebase_auth`, `cloud_firestore` | Firebase initialization, login, and database persistence | BSD-3-Clause |
| `provider` | Shared application state | MIT |
| `flutter_local_notifications` | Android medication and refill notifications | BSD-3-Clause |
| `timezone` | Timezone-aware notification scheduling | BSD-2-Clause |
| `flutter_timezone` | Device timezone detection | Apache-2.0 |
| `flutter_test`, `flutter_lints` | Widget/unit testing and static analysis | Flutter/Dart SDK and package licenses |

Package license files remain the authoritative source for exact license terms.

## Design and supporting documentation

- [Phase 2 Figma design](https://www.figma.com/design/hSyXUqyLPNyfsx5bOzb5tr/SWE463---Group-06---Medication-Follow-up-App--Phase-2-UI-Design?node-id=3-2)
- [Phase 3 integration and test evidence](docs/PHASE3_INTEGRATION.md)
- [Doses and reminders handoff](docs/PERSON1_HANDOFF.md) · [Medication and refills handoff](docs/PERSON2_HANDOFF.md)
- [Phase 3 report screenshots](docs/phase3-screenshots/)

## AI-use disclosure

The team used AI-assisted tools during Phase 3 to **generate portions of application code and tests**, inspect errors, help fix widget overflows, review code, and assist with the report and README preparation. Team members reviewed and tested the resulting work and remain responsible for understanding and explaining the submitted implementation. AI-assisted work is disclosed here in accordance with the course requirements.
