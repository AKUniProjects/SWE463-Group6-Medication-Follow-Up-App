# Medication Follow-up App - Flutter Starter

Starter Flutter project for SWE463 Group 6, Phase 2.

## Purpose

This project provides a runnable UI shell and placeholder navigation for the Medication Follow-up App. Full Firebase integration and notification implementation are planned for the implementation phase; this Phase 2 starter uses fictional in-memory sample data.

## Current navigation

1. Sign In screen
2. Patient Today screen
3. Medications screen
4. Medication editor screen
5. Doctor dashboard
6. Patient details screen

The bottom navigation switches between Today, Medications, and Doctor view. Tapping a medication opens its editor. Tapping a patient opens patient details.

## Project structure

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





## AI-use disclosure

AI assistance was used to draft the starter structure, sample models, and technical documentation.
