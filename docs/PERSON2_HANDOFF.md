# Person 2 Phase 3 handoff

**Branch:** phase3/medications-refills. **Base:** origin/main at 390da1d, including Person 3's merged PRs #1–#3 and later fixes. The initial checkout was clean. No push, remote PR, merge, deployment or phase-3 tag is included.

| Scope | Status |
|---|---|
| #2 Medication Management | Implemented for the owned CRUD flow: persistent, validated multi-time Add/Edit, Keep/Confirm soft deletion, shared Today/list/refill refresh and patient isolation |
| #8 Medication Refill Reminder | In progress: stock editing, estimates, warnings and alert hooks work; Android delivery and Person 1's confirmation integration remain unfinished |
| Shared UI | Material 3 theme/tokens, medication/refill cards, semantic status labels, reusable form and loading/error/message views |

Person 3's authentication, linking, session navigator and role handling are preserved. The current shell still has Today/Medications plus Sign out; its approved History/Insights destinations remain with their owners. No dose-status logic, history implementation or doctor analytics was taken over.

## Reproducible demonstration

1. Run flutter pub get and start Auth/Firestore emulators as described in README. Launch with USE_FIREBASE_EMULATORS=true. Create/sign in to a fictional patient.
2. Medications → Add medication. Try invalid input first. Enter a trimmed name, positive finite dose, valid unit, two different picker times and non-negative integer supply. Save.
3. Verify the new record in Medications and Today. Edit one field; the ID and unchanged times remain. Cancel/Back on a second draft must not write.
4. Refills → Update quantity → save zero. Verify Out of stock and shared stock changes. Cancel a second update to preserve the saved value.
5. Reload. The session, medication, times and stock remain while the backend retains its database.
6. Edit → Delete → Keep. Reopen and Confirm. The medication leaves active lists but its metadata remains for historical references.
7. Switch to a second fictional patient. The first patient's records and drafts must not appear. Doctor access requires an active link and is read-only.

The runtime flow uses the real Firebase adapter and local emulators. Genuine screenshots are in person2-evidence/. There is no fabricated Android notification evidence.

## Data policy

Canonical document: **medications/{id}**. Existing Medication is extended with stockUnit, nullable unitsPerDose and revision; existing constructor callers remain compatible.

| Rule | Implementation |
|---|---|
| Patient scope | Verified AuthProvider patient UID; repository guards and Firestore rules reinforce ownership |
| Schedule | Unique local HH:mm strings, sorted on writes; 1–24 daily times. Person 1 owns date/time-zone/DST scheduling |
| Dose units | tablet, capsule, mg, ml, IU |
| Counted stock units | tablet, capsule, ml, IU, package, unit; independent of prescribed dose |
| Consumption | Optional positive **whole stock units per dose**. Unknown stays null; mg/IU never imply tablets |
| Low supply | stockAmount <= refillThreshold; default threshold 7 **stock units**, editable; zero is Out of stock |
| Days estimate | stockAmount / (unitsPerDose × unique daily-time count), one decimal; unavailable if consumption is unknown |
| Bounds | Name ≤100 characters; dose/stock/threshold/consumption ≤1,000,000,000; positive dose, non-negative integer stock |
| Edits | Transactions increment revision; stale drafts are rejected with instructions to reopen |
| Deletion | isActive=false only. No DoseRecord is changed/deleted; inactive metadata remains readable |

Firestore is the actual persistent backend. The JSON-round-trip in-memory store is a **test double only**. Emulator data survives app/browser reloads while the emulator runs. Preserving it across emulator shutdown requires explicit Firebase --export-on-exit/--import configuration. Live deployment and cross-device behavior are unverified.

Rules allow owner-patient writes and owner/actively-linked-doctor reads. Queries must include patientId equality. Hard medication deletes and receipt updates/deletes are forbidden. Other collections remain closed until their owner adds rules.

## Integration contracts

**Person 1**

- Read MedicationRepository.watchPatient(patientId); filter isActive for current schedules. All stable medication IDs and daily times are available.
- Call MedicationProvider.consumeStock(medicationId: ..., doseRecordId: ...) using the **same persisted scheduled-dose ID** on retries. IDs match [A-Za-z0-9_-][A-Za-z0-9_.:-]{0,299}; do not generate a fresh ID on every tap.
- The operation atomically writes the deduction and immutable medications/{id}/consumptions/{doseId} receipt with a server timestamp.
- Outcomes: consumed, alreadyConsumed, unknownConsumption, insufficientStock. Unknown/insufficient supply produces no negative stock or receipt.
- A future separate DoseRecord write is **not automatically atomic with stock**. The confirmation orchestrator must reconcile/retry stock with the stable dose ID after an interruption and explicitly decide how unknown/insufficient stock affects confirmation.
- Implement MedicationReminderGateway and inject it into MedicationProvider at startup: syncSchedule, syncRefill, cancelRefill, cancelMedication, clearPatient.
- Gateway operations must be idempotent and keyed by patient + medication. The coordinator serializes events and deduplicates unchanged fingerprints outside widget builds. A failed notification sync does not undo a saved medication; Retry sync is available.
- The installed gateway reports unavailable. Android permissions, actual delivery, restoration, tap-to-Refills and real future-reminder cancellation remain unverified.

**Person 3**

- main.dart registers one MedicationProvider through ChangeNotifierProxyProvider. It receives auth.userId only when auth.isPatient; logout/account changes clear scoped data and ignore late results.
- AppShell passes the shared medication list to Today, adds Refills entry points and returns Today-initiated edits to Medications. It supplies no fabricated DoseRecords while Person 1's repository is absent.
- Web emulator mode reserves space for Firebase Auth's fixed warning banner so it cannot cover bottom controls. Android/live layouts are unaffected.
- New rules are tested local source, **not deployed**.

**Person 4**

- The read interface is available through context.read<MedicationProvider>().repository.watchPatient(selectedPatientId). In doctor context, Firestore enforces the active-link check; mutation methods still require the patient.
- Streams include inactive metadata for historical references. Filter active records for current treatments.
- Reuse AppTheme/AppColors, MedicationCard, RefillCard, StatusChip and MessageCard. Dispose subscriptions and clear caches on logout/link revocation.

## Code walkthrough

| Area | What to explain in review |
|---|---|
| medication_validation.dart | UI and repository invariants; the same rules are enforced server-side |
| StoredMedicationRepository | Identity/revision checks, soft deletion, one-time stock receipts and consumption outcomes |
| FirestoreMedicationStore | Real transactions; reads precede writes; bounded recovery rechecks an authorized server revision after competing commits; domain errors survive platform wrapping |
| MedicationProvider | One shared list, explicit async states, stale-session rejection, newest-revision response merging and serialized reminder effects |
| MedicationEditorScreen | One local Add/Edit draft; all fields remain mounted in a scrollable Form, so off-screen fields validate |
| Delete screen / supply dialog | Explicit decisions, pending protection, failures retain input, success only after persistence |

## Verification and limits

See [PERSON2_VERIFICATION.md](PERSON2_VERIFICATION.md) for actual command outcomes, evidence and environment limits. Standard checks:

~~~powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
node --test --test-concurrency=1 firestore_rules_test/users_rules.test.mjs firestore_rules_test/doctor_linking_rules.test.mjs firestore_rules_test/medication_rules.test.mjs
~~~

Rule tests use FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 and GCLOUD_PROJECT=demo-medfollow, and reset that disposable local namespace. Do not point them at data to preserve.

Real client-adapter verification:

~~~powershell
flutter run -d web-server --target tool/verify_medication_backend.dart --web-port 8766
~~~

Open its local URL. This development-only target always uses local emulators and checks CRUD/server persistence, concurrent duplicate and distinct doses, overdraft and stale edits. It is not an application route.

## Design, licenses and AI disclosure

The inline Add action, shared Add/Edit, full-screen Keep/Confirm deletion and supply dialog follow Phase 2. Explicit stock/consumption controls and editable thresholds avoid unsupported dose-to-stock assumptions. System Material typography replaces the unbundled Inter font; amber text is darker for contrast. The existing incomplete navigation shell was preserved for Person 3 to finish.

No application dependency was added. Flutter/Dart/test/lints and FlutterFire packages are BSD-3-Clause; Provider is MIT; bundled Material icons are Apache-2.0. README lists purposes and the package notices remain authoritative. Temporary verification tooling is outside the repository.

Codex generated substantial implementation, tests, documentation and verification assistance. This is a review draft. The student/team are not represented as having already reviewed or authored the new changes unaided; review, understand and adapt the contribution under the course rules and retain an accurate AI disclosure before submission. All screenshot/test claims must remain tied to the actual evidence.
