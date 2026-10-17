# Medication Follow-up App - Flutter Starter

Starter Flutter project for SWE463 Group 6, Phase 2.

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

## Project Structure

```text
lib/
  main.dart
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
    app_shell.dart
    auth_screen.dart
    doctor_dashboard_screen.dart
    medication_editor_screen.dart
    medications_screen.dart
    patient_details_screen.dart
    patient_home_screen.dart
  services/
    sample_data.dart
  widgets/
    status_chip.dart
test/
  widget_test.dart
```

## Packages

The starter uses Flutter SDK widgets and `flutter_lints` only. No third-party runtime packages have been added yet.

Planned implementation-phase packages, subject to team approval and recording in this README before use:

- `firebase_core`: Initialize Firebase.
- `firebase_auth`: Account sign-in and authentication.
- `cloud_firestore`: Profiles, doctor links, medications, dose records, and refill data.
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
