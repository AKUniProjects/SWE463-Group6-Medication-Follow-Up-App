# Medication Follow-up App

**Course:** SWE463  
**Phase:** 1 - Project Proposal  
**Group:** 6

## Team Members

| Name | Student ID |
| --- | --- |
| Abdulaziz Alwarthan | 202160310 |
| ALI ALORYD | 202322750 |
| HASHIM ALRAMADHAN | 202021320 |
| KHALED MATHBAQ | 202283100 |

## 1. Problem and Users

Adults who take prescribed medication daily may forget doses and struggle to recall their medication history during appointments. For example, a patient taking morning and evening medication may repeatedly overlook the evening dose without their doctor knowing until the next visit.

Our app targets patients managing regular medication at home and outpatient doctors following their treatment. Patients receive reminders and record doses, while linked doctors review these records and identify patients who may need follow-up. Optional in-app notes can provide a simple follow-up channel without exchanging personal phone numbers.

## 2. Scope and Features

The project contains **8 essential features** that form the required implementation scope. Two separate **optional enhancements** will be implemented only if time permits.

### Essential Features - Required Implementation Scope

| Priority | Feature | Purpose and functionality | Dependencies |
| --- | --- | --- | --- |
| 1 | Accounts and doctor linking | Patients sign in and link to a doctor using a code, with consent to share their records. This establishes access to the correct patient information. | Foundation for shared features. |
| 2 | Medication management | Patients add, edit, and remove prescribed medication details, including name, dose, and fixed daily times, to create their schedule. | Feature 1. |
| 3 | Medication reminders | Scheduled phone notifications remind patients when medication is due, helping them remember their routine. | Feature 2. |
| 4 | Dose confirmation and history | Patients tap **Taken** to record a dose and view past confirmations. Overdue or missed doses remain clearly identified. | Feature 2; integrated with Feature 3. |
| 5 | Doctor dashboard | Doctors review linked patients' weekly dose-confirmation rates, missed or overdue records, and patients requiring follow-up. | Features 1 and 4. |
| 6 | Missed dose follow-up | If a dose is not confirmed within a defined period, the app marks it as missed and sends an additional reminder. Missed doses are also reflected in the patient's history. | Features 3 and 4. |
| 7 | Adherence statistics | The app calculates medication adherence from dose history and displays weekly or monthly statistics, such as the percentage of scheduled doses taken. | Feature 4. |
| 8 | Medication refill reminder | Patients record the amount of medication available. The app estimates when the supply is running low and reminds them that a refill may be needed. | Features 2 and 4. |

### Optional Enhancements - If Time Permits

| Enhancement | Feature | Purpose and functionality | Dependencies |
| --- | --- | --- | --- |
| A | Follow-up notes | Doctors send short follow-up notes that linked patients can read inside the app, providing a simple follow-up channel. | Features 1 and 5. |
| B | Appointment reminders | Patients save upcoming doctor appointments and receive notifications before the appointment. | Feature 1. |

The semester prototype will focus on Android, fixed daily schedules, and demonstration accounts with fictional data. Dose history is self-reported. Diagnosis, prescription generation, and hospital integration are outside the scope.

## 3. Flutter Plan

### Proposed Screens and Widgets

| Screen | Main Flutter widgets |
| --- | --- |
| Login and doctor linking | `Form`, `TextFormField`, `ElevatedButton` |
| Patient home and dose history | `ListView.builder`, `Card`, `LinearProgressIndicator`, `ElevatedButton` |
| Medication editor and refill tracking | `Form`, `TextFormField`, `showTimePicker` |
| Doctor dashboard and patient details | `ListView.builder`, `ListTile`, `LinearProgressIndicator` |
| Optional notes and appointments | `ListView`, `TextField`, `IconButton`, `showDatePicker` |

### Proposed Architecture and Tools

**Structure and navigation:** Screens, data models, and service classes will be separated. `Navigator` will open detail screens, while `NavigationBar` will switch between each role's main views.

**State management:** We propose `setState` for simple screen changes and [Provider with ChangeNotifier](https://docs.flutter.dev/data-and-backend/state-mgmt/simple) for shared account and medication data.

**Backend and storage:** Firebase Authentication will handle login, while Cloud Firestore will store profiles, medications, dose records, refill data, appointments, and notes. [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/rules-conditions) will restrict access to each patient and linked doctor.

**Reminders:** [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) will support medication, missed-dose, refill, and optional appointment reminders on Android.

### Proposed Development Schedule

| Weeks | Deliverables |
| --- | --- |
| 1-2 | Screen designs, navigation, Firebase and account-linking prototype, and an early notification test. |
| 3-5 | Medication management, reminders, dose confirmation, history, and missed-dose follow-up. |
| 6-7 | Doctor dashboard, adherence statistics, refill reminders, and follow-up flags. |
| 8-10 | Integration, access-control and notification testing, usability improvements, optional enhancements if time permits, and fixes. |

**Contingencies:** If notification permissions are denied, due doses will remain visible on the patient's home screen. If development falls behind, the optional enhancements will be deferred first to protect the eight essential features.

## 4. Team Plan

**Group Number:** 6

### Work Distribution - Initial Responsibilities

| Team Member | Initial Responsibility |
| --- | --- |
| Abdulaziz Alwarthan | Authentication, accounts, and doctor-patient linking. |
| ALI ALORYD | Medication management, medication refill reminders, and related patient interface. |
| HASHIM ALRAMADHAN | Medication reminders, missed-dose follow-up, and notification behavior. |
| KHALED MATHBAQ | Doctor dashboard, adherence statistics, and patient dose-history views. |

### Team Rules and Shared Responsibilities

- Initial responsibilities may change as implementation progresses and integration needs become clearer.
- Every member will contribute to both source code and project documentation.
- All members will participate in integration, testing, Git/GitHub version control, and the final presentation.
- Work should be committed through the shared repository so contributions and changes remain traceable.

## 5. GitHub Repository

**Repository:** https://github.com/AKUniProjects/SWE463-Group6-Medication-Follow-Up-App  
**Visibility:** Public  
**Team Access:** All four team members have been added to the repository.

The repository will be used for the Flutter source code, documentation, and Git version history. Because it is public, the instructor can access the repository directly using the link above.

## AI Use Disclosure

AI tools were used for small suggestions, wording refinement, and learning support during project planning and documentation. All AI-assisted content was reviewed and understood by the team. During implementation, AI use will remain limited to learning, debugging, and small suggestions in accordance with the course rules. The team will not submit AI-generated code that members cannot explain.
