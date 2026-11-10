# Medication Follow-up App - Flutter Starter

Flutter project for SWE463 Group 6. Started in Phase 2; Phase 3 adds Firebase authentication (see "Phase 3 Status" below).

## Purpose

This project provides a runnable UI shell and placeholder navigation for the Medication Follow-up App. Full Firebase integration and notification implementation are planned for the implementation phase; this Phase 2 starter uses fictional in-memory sample data.

## Current Navigation

1. Sign In screen
2. Patient Today screen
3. Medications screen
4. Medication editor screen
5. Doctor dashboard
6. Patient details screen

The current starter application's bottom navigation switches between Today, Medications, and Doctor view. Tapping a medication opens its editor, while tapping a patient opens patient details.

The full Phase 2 Figma design includes four patient navigation destinations (Today, Meds, History, and Insights) and a separate doctor flow. These will be implemented in the next development phase.

> **Phase 3 update:** the starter navigation above has been replaced by authenticated, role-based navigation. See the Phase 3 sections below.

## Phase 3 Status — Authentication (Tasks 2.1–2.6)

Implemented and tested:

- Email/password **Sign In** and **Sign Up** (Patient or Doctor) using Firebase Authentication, matching the Figma Login and Sign Up screens.
- User profiles stored in Cloud Firestore at `users/{uid}` (`displayName`, `email`, `role`, `linkedDoctorIds`).
- `AuthProvider` (Provider/ChangeNotifier) manages loading, signed-out, signed-in, missing-profile, and error states, and handles the registration race condition.
- `AuthGate` routes by the stored role: patients see Today/Medications; doctors see the Doctor dashboard. Signed-out users always see Login; unknown routes (for example `/#/app`) cannot bypass it.
- Form validation and friendly error messages (wrong password, duplicate email, weak password, network, missing profile).
- Firestore Security Rules for user profiles, plus Firebase Local Emulator Suite support.

Current limitations:

- Patient and doctor screens still display **fictional sample data**, not the signed-in user's data.
- Doctor Linking, medications, reminders, dose history, and refill features are not yet connected to Firestore.
- Firestore rules currently allow **only** `users/{uid}`; every other collection is denied until its feature adds rules.
- A self-selected Doctor role is **not** professional verification and grants no access to patient records.
- `patient_home_screen.dart` has a known 40-pixel layout overflow.

## Doctor Linking Data Contract (Task 3.2 — rules only)

> Coursework prototype with fictional data. Doctor self-registration is allowed but is **not** professional verification, and this design is **not** production-ready for real medical data.

The authoritative relationship is `doctorLinks/{patientId}_{doctorId}`. `UserProfile.linkedDoctorIds` is not used for authorization and stays empty.

| Collection | Fields | Who can do what |
|---|---|---|
| `doctorCodes/{code}` | `doctorId`, `doctorName`, `active`, `createdAt` (server time) | Doctor creates own code (10 chars from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, name must match their profile); valid 30 days; owner may deactivate or delete. Signed-in users may `get` one code; only the owner may list (`where doctorId == myUid`). |
| `doctorLinks/{patientId}_{doctorId}` | `patientId`, `doctorId`, `patientName`, `doctorName`, `linkCode`, `status` (`active`/`revoked`), `consentedAt` (server time), `revokedAt`, `revokedBy` | Only the patient creates or reactivates, with a valid code and fresh consent. Either party revokes. Doctors cannot reactivate. After a patient revocation, any valid code from that doctor works; after a **doctor** revocation, the patient needs a code the doctor issued **after** the revocation. No deletes. |

Queries for teammates (other queries are denied):

- Doctor's patients: `doctorLinks.where('doctorId', isEqualTo: myUid).where('status', isEqualTo: 'active')` (or only the `doctorId` filter, then filter `status` in Dart). Every query **must** include `doctorId == myUid` or `patientId == myUid`; Security Rules are not filters, so queries without that constraint are rejected.
- Patient's doctors: `doctorLinks.where('patientId', isEqualTo: myUid)`.
- Patient profile for a linked doctor: `users.doc(patientId).get()` by ID only (no `users` queries). Access ends when the link is revoked.

All of the above were verified against the Firestore emulator (`firestore_rules_test/doctor_linking_rules.test.mjs`).

Code format: stored codes are exactly 10 characters from the 32-symbol alphabet above (50 bits), with no spaces or hyphens. The app may display them as `ABCD-EFGH-23`, and must normalize user input with `normalizeDoctorCode()` before lookup. Expiry is `createdAt + 30 days`; there is no stored `expiresAt`, and `createdAt` cannot be changed after creation.

Timestamps `createdAt`, `consentedAt`, and `revokedAt` must be written as `FieldValue.serverTimestamp()`; client-chosen times are rejected. See the write contract at the top of `lib/models/doctor_link.dart`.

Known limitations of this prototype:

- Doctors self-register and are not professionally verified; patient consent (creating the link) is required before any doctor access.
- Codes cannot be listed by patients, but guessing single codes is not server-rate-limited (Firestore-only design, no Cloud Functions).
- The rules record that the patient performed the link operation; they cannot prove the patient read an explanation. The consent screen is planned for Task 3.5.
- Revocation blocks later authorized reads, but data already received or cached on a device cannot be recalled.
- Doctor access to medications, dose history, and adherence needs future rules; those collections remain denied.
- These rules have only been tested on the local emulator and have **not** been deployed to the live Firebase project.

Requirements for Task 3.3 (repository): generate codes with `Random.secure()` over `doctorCodeAlphabet`; create codes with a "must not exist" write and retry on collision; use server timestamps as above; revoke with an update of `status`, `revokedBy`, and `revokedAt` only.

### Doctor Dashboard integration (Task 3.6)

The doctor shell now feeds the existing `DoctorDashboardScreen` (unchanged) with real linked patients through `lib/screens/linked_patients_dashboard.dart`:

- Data: `DoctorLinkProvider.loadLinkedPatients()` / `linkedPatients` (`List<LinkedPatient>`: `patientId`, `displayName`, `email`, `link`). Only active links and rule-authorized profiles are returned; sign-out or switching accounts clears the list.
- Mapping: `toPatientSummary(LinkedPatient)` sets `PatientSummary.patientId` to the patient's Firebase UID (used by `PatientDetailsScreen`). Statistics are empty ("No dose records yet") until the dashboard owner supplies real adherence data.
- Refresh: pull down on the patient list (touch or mouse) to re-check links; revoked patients disappear. When the list is empty the dashboard's empty state is not scrollable, so new links appear after reload or the next sign-in (the dashboard owner may add a refresh action).
- Doctor revocation: `DoctorLinkProvider.revokePatientLink(LinkedPatient)` is available but not yet shown in the dashboard UI (needs a confirmation dialog in the dashboard owner's design). After a doctor revokes, the patient needs a code issued after the revocation.
- Medications and dose records: future rules must use the same active-link check (`doctorLinks/{patientId}_{doctorId}` with `status == 'active'`), patient writes only.

## Development Setup (Windows PowerShell)

### Required tools

| Tool | Version used | Purpose |
|---|---|---|
| Flutter SDK | 3.47.9 (stable) | Build and run the app |
| Java (JDK) | 21 or newer | Firestore emulator |
| Node.js | 24 (LTS recommended) | Firebase CLI via `npx` and rule tests |
| Chrome or Edge | Current | Web target |
| Android Studio + Android Emulator | Current | Android target |

The Firebase CLI does not need a global install; commands below use `npx -y firebase-tools@15.35.0`.

### Initial setup

```powershell
git clone https://github.com/AKUniProjects/SWE463-Group6-Medication-Follow-Up-App.git
cd SWE463-Group6-Medication-Follow-Up-App
flutter pub get
```

Firebase configuration (`lib/firebase_options.dart`, `android/app/google-services.json`, `firebase.json`, `.firebaserc`) is already committed for project `swe463-group06-medication-app`. Only re-run `flutterfire configure` if the Firebase project changes.

### Run against the live Firebase project

```powershell
flutter run -d chrome          # or: flutter run -d edge
flutter run -d emulator-5554   # Android Emulator (see: flutter devices)
```

### Run against local Firebase emulators (recommended for development)

Terminal 1 — start the Auth (9099) and Firestore (8080) emulators. Emulator UI: http://127.0.0.1:4000

```powershell
npx -y firebase-tools@15.35.0 emulators:start --only auth,firestore
```

Terminal 2 — run the app in emulator mode:

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true
flutter run -d emulator-5554 --dart-define=USE_FIREBASE_EMULATORS=true
```

- Chrome/Edge connect to `localhost`; the Android Emulator connects to `10.0.2.2` automatically.
- For a physical phone, add `--dart-define=FIREBASE_EMULATOR_HOST=<your PC's LAN IP>`.
- Emulator mode is opt-in, refused in release builds, and never falls back to the live project. The browser console prints `Using Firebase emulators at ...` and Firebase shows an "emulator mode" banner.
- Emulator data is temporary and is cleared when the emulators stop.

### Test accounts

Use fictional data only, and only in emulator mode. Create accounts through the app's **Create an account** screen, for example:

| Role | Name | Email | Password |
|---|---|---|---|
| Patient | Test Patient | `patient.test@example.com` | any 6+ characters |
| Doctor | Test Doctor | `doctor.test@example.com` | any 6+ characters |

Never commit real credentials, tokens, or service-account keys.

### Running tests

```powershell
flutter analyze
flutter test
```

Firestore Security Rules tests (run inside a temporary Firestore emulator; no npm install needed):

```powershell
npx -y firebase-tools@15.35.0 emulators:exec --only firestore --project demo-medfollow "node --test --test-concurrency=1 firestore_rules_test/users_rules.test.mjs firestore_rules_test/doctor_linking_rules.test.mjs"
```

### Manual emulator test checklist

With the emulators and the app running in emulator mode:

1. Sign up as a Patient → the Patient interface opens; Emulator UI shows the Auth user and `users/{uid}` with `role: patient` and empty `linkedDoctorIds`.
2. Reload the page → the session is restored. Sign out → Login appears.
3. Sign in with a wrong password → "Incorrect email or password." and no access.
4. Sign up as a Doctor → the Doctor dashboard opens; reload restores it; sign out returns to Login.
5. Sign up again with an existing email → "An account already exists for this email."
6. Create an Auth-only user in the Emulator UI (no profile) and sign in → "No user profile was found for this account." and the user stays signed out.
7. While signed out, open `http://localhost:<port>/#/app` → Login is shown.

### Before live deployment (Firebase Console)

1. **Authentication → Sign-in method:** enable **Email/Password**.
2. **Firestore Database:** create the database (production mode) if it does not exist.
3. Review and publish `firestore.rules` (for example `npx -y firebase-tools@15.35.0 deploy --only firestore:rules`) — only after team approval.
4. Add rules for each new collection (doctor links, medications, dose records, refills) before those features write data.

## Project Structure

```text
lib/
  main.dart
  firebase_options.dart        # FlutterFire configuration
  firebase_emulators.dart      # opt-in local emulator connection
  models/
    adherence_stats.dart
    doctor_link.dart
    dose_record.dart
    medication.dart
    patient_summary.dart
    refill.dart
    reminder.dart
    user_profile.dart
  screens/
    app_shell.dart               # role-specific navigation
    auth_gate.dart               # chooses screen from auth state and role
    auth_screen.dart             # Login
    sign_up_screen.dart          # Sign Up
    doctor_dashboard_screen.dart
    medication_editor_screen.dart
    medications_screen.dart
    patient_details_screen.dart
    patient_home_screen.dart
  services/
    auth_repository.dart         # interface + AuthException
    firebase_auth_repository.dart
    sample_data.dart
  state/
    auth_provider.dart
  widgets/
    auth_form_widgets.dart       # shared Login/Sign Up widgets and validators
    status_chip.dart
test/                            # Flutter unit and widget tests (fake repositories)
firestore_rules_test/            # Firestore Security Rules tests (emulator)
firestore.rules                  # Firestore Security Rules
firebase.json, .firebaserc       # Firebase project and emulator configuration
```

## Packages

Packages in use (see `pubspec.yaml`):

- `firebase_core` ^5.1.0: Initialize Firebase.
- `firebase_auth` ^7.0.1: Account sign-in and authentication.
- `cloud_firestore` ^7.1.0: User profiles (later: doctor links, medications, dose records, refill data).
- `provider` ^6.1.5+1: App-wide authentication state.
- `flutter_test`, `flutter_lints` (development).

Still planned, subject to team approval:

- `flutter_local_notifications`: Android medication, missed-dose, and refill notifications.

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
