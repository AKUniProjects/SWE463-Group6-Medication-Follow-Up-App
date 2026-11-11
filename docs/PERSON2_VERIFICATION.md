# Person 2 verification record

Verified locally on **11 November 2026**, against base **390da1d** on **phase3/medications-refills**. All application data used here was fictional and stayed in local Firebase emulators. No rules deployment, GitHub push, remote PR, merge or submission tag was performed.

## Final outcomes

| Check | Result | Evidence |
|---|---|---|
| Baseline static analysis | Passed, no issues | [baseline analysis](person2-evidence/baseline-analyze.txt) |
| Baseline Flutter tests | **193 passed** | [baseline tests](person2-evidence/baseline-flutter-tests.txt) |
| Dependency resolution | **Passed**, flutter pub get --offline; pubspec and lockfile unchanged | [pub get](person2-evidence/pub-get.txt) |
| Formatting | Passed, 26 changed/new Dart files processed | [formatter](person2-evidence/dart-format.txt) |
| Final static analysis | **Passed, no issues** | [analysis](person2-evidence/flutter-analyze.txt) |
| Final Flutter unit/widget tests | **222 passed**, including 29 new medication tests | [full test log](person2-evidence/flutter-tests.txt) |
| All Firestore rule tests | **40 passed, 0 failed**, including 6 new medication/receipt groups | [rule test log](person2-evidence/firestore-rules-tests.txt) |
| Real FlutterFire client adapter | **4/4 passed** in the running verification target | [actual result screenshot](person2-evidence/11-backend-checks-passed.jpg), [source](../tool/verify_medication_backend.dart) |
| Actual app browser review | Add/Edit, shared Today/list/refills, zero quantity, reload restoration, Keep and Confirm observed | [screenshot index](person2-evidence/README.md) |
| Android debug APK | **Blocked:** no Android SDK found | [actual build output](person2-evidence/android-build.txt) |
| Android device/reminder delivery | **Not run / not verified** | Feature #8 remains **In progress** |

The final source changes preserve newer live revisions when an older successful write response arrives late and refresh alert estimates when consumption/schedules change. The final 222-test run covers both. The browser screenshots precede these internal state/effect fixes; their visible screens are unchanged by them. The four real-adapter checks exercise the repository/store directly and remain applicable.

## What the checks cover

- **Repository, 11 tests:** trimmed names, sorted unique schedules, stable IDs, unchanged fields, JSON persistence/receipt restoration, soft deletion, unknown consumption, zero stock, inclusive threshold, unit-aware estimates, concurrent same-dose retries, overdraft prevention, stale revisions, cross-patient/sign-out rejection, failed writes and invalid values.
- **Provider, 9 tests:** loading/error/retry, duplicate-submit protection, shared live refresh, immediate account clearing and ignored old writes, delayed response ordering, reminder upsert/update/cancel, estimate refresh after consumption/schedule changes, deduplication and retry after notification failure.
- **Screens, 8 tests:** invalid draft and cancellation, real time-picker interaction with two times/duplicates/removal, Add/Edit/refill-zero/Keep/Confirm flow, failed writes retaining input, pending state, missing/read-retry states, and list/editor/refill at 320px with 2× text.
- **Navigation, 1 test:** opening an editor from Today and cancelling returns to Medications without writing.
- **Rules, 6 new groups:** owner CRUD, retained history, immutable identities/revisions, unauthorized reads/writes, scoped and linked-doctor queries, invalid fields including the last allowed schedule position, atomic receipt/deduction, immutable receipts, invalid deltas and overdraft.
- **Real adapter, 4 checks:** server-read CRUD/zero/soft deletion and a fresh repository read; four concurrent retries of one dose deduct once; four different concurrent doses each deduct once; stale edits cannot restore stock. Receipts use a server timestamp.

The remaining 193 Flutter tests and 34 rule tests exercise the inherited authentication/doctor-linking implementation. Account isolation is tested in repository/provider/rules tests; it is not presented as a second-patient manual browser run.

## Reproduction

Use the normal Flutter setup in README. Start Auth/Firestore emulators with the current rules, then run:

~~~powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:GCLOUD_PROJECT = 'demo-medfollow'
node --test --test-concurrency=1 firestore_rules_test/users_rules.test.mjs firestore_rules_test/doctor_linking_rules.test.mjs firestore_rules_test/medication_rules.test.mjs
flutter run --no-pub -d web-server --dart-define=USE_FIREBASE_EMULATORS=true --web-port 8767
~~~

Use the [handoff's demonstration steps](PERSON2_HANDOFF.md#reproducible-demonstration) in the printed local URL. Rule tests reset the disposable demo-medfollow namespace, so run them sequentially and never select a dataset to preserve.

For actual SDK transaction verification, run this separate development target and open its local URL:

~~~powershell
flutter run --no-pub -d web-server --target tool/verify_medication_backend.dart --web-port 8766
~~~

It always uses local emulators, creates disposable fictional Auth accounts and deletes those accounts afterward. Their document fixtures remain only in the temporary emulator database. It is not a user-facing route.

## Environment and resolved failures

This session used Windows, Flutter **3.47.1** / Dart **3.13.1**, Node **24.22.1**, Firebase CLI **15.35.0**, Firestore emulator **1.22.0**, and a portable Java **21.0.13** runtime. Auth ran on 127.0.0.1:9099 and Firestore on 127.0.0.1:8080. These are the versions used in this record; README's inherited tool recommendation is separate.

- The normal Flutter launcher could not inspect the SDK Git directory under this sandbox. Commands ran through the SDK's cached Flutter CLI snapshot with workspace-local package/cache/temp directories. Dart HTTPS package resolution also failed initially. Pinned package archives were restored from the official package host with lockfile SHA-256 checks; **offline pub get then succeeded**. No dependency version was changed. Windows plugin-symlink generation was disabled for the web/VM verification environment; generated desktop-file churn was excluded from the contribution.
- The initial baseline test launch hit a Windows temporary-path length limit. A shorter workspace TEMP/TMP allowed the unchanged baseline's **193 tests to pass**.
- A Chrome-platform Flutter test launch failed **before executing tests**, because this SDK snapshot referenced a missing build-machine host.dart.js asset. That attempted browser runner is not counted as passed. The replacement standalone Flutter web target executed the actual Firebase client adapter successfully; see its 4/4 screenshot.
- Real adapter checks initially exposed permission-denied races between revision-protected transactions and immutable receipts, and transaction-bridge wrapping of domain errors. The final store retries only after an authorized server read proves a newer revision, rechecks all invariants, and preserves actionable domain errors. All four real checks passed after these fixes; the rules were not weakened.
- A deterministic delayed-response test initially reproduced stock reverting from 6 to 7 despite a newer live revision. The provider now keeps the newest committed revision for both display and reminder effects. That test passes in the final suite.
- Static analysis caught an unnecessary import; it was removed. Actual UI review caught bottom controls covered by Firebase Auth's web emulator warning and an old snackbar covering Delete. The final layout reserves banner space and clears the prior snackbar when opening the editor.

Temporary verification tooling remains outside the repository. The committed logs are actual tool output; the test screenshot is from the running verification target, not an invented test report.

## Remaining limits

No Android SDK/device was available, so APK execution, Android permissions, actual notification delivery, tap routing and future-reminder cancellation on a device are unverified. The installed notification gateway explicitly reports unavailable. Person 1 must connect dose/history storage and Android scheduling, including time-zone/DST handling and stable dose IDs. Dose-history writes and stock receipts are not automatically one combined transaction.

Only whole counted stock units are supported. Emulator browser reload persistence was observed; emulator shutdown persistence requires an explicit export/import. Live Firebase deployment and cross-device persistence were not tested. Doctor/statistics screens and the shell's remaining History/Insights destinations stay with their assigned owners.
