import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/doctor_link.dart';
import 'package:medication_follow_up_app/models/user_profile.dart';
import 'package:medication_follow_up_app/screens/doctor_dashboard_screen.dart';
import 'package:medication_follow_up_app/screens/patient_details_screen.dart';
import 'package:medication_follow_up_app/screens/doctor_linking_screen.dart';
import 'package:medication_follow_up_app/screens/medication_editor_screen.dart';
import 'package:medication_follow_up_app/screens/doctor_code_dialog.dart';
import 'package:medication_follow_up_app/services/doctor_link_repository.dart';
import 'package:medication_follow_up_app/state/auth_provider.dart';

import 'support/app_providers.dart';
import 'support/controllable_auth_repository.dart';

class PatientsRepo extends NoPatientsRepo {
  PatientsRepo(this.currentUid);
  final String? Function() currentUid;
  @override
  Future<List<DoctorLink>> linksForPatient({bool activeOnly = false}) async =>
      [];
  @override
  Future<List<DoctorCode>> myCodes() async => [
    DoctorCode(
      code: 'ABCDEFGH23',
      doctorId: doctor.id,
      doctorName: doctor.displayName,
      active: true,
      createdAt: DateTime.now(),
    ),
  ];
  @override
  Future<List<LinkedPatient>> linkedPatientsForDoctor() async =>
      currentUid() != doctor.id
      ? []
      : [
          const LinkedPatient(
            link: DoctorLink(
              id: 'pat_doctor-1',
              patientId: 'pat',
              doctorId: 'doctor-1',
              linkCode: 'ABCDEFGH23',
              status: LinkStatus.active,
            ),
            displayName: 'Private patient A',
            email: 'fictional@example.com',
          ),
        ];
}

void main() {
  late ControllableAuthRepository repo;
  late AuthProvider auth;
  setUp(() {
    repo = ControllableAuthRepository();
    auth = AuthProvider(repo)..start();
  });
  tearDown(() async {
    auth.dispose();
    await repo.close();
  });

  test('sign-in cannot complete after explicit sign-out', () async {
    final result = auth.signIn(email: patient.email, password: 'secret1');
    repo.emit(patient.id);
    await auth.signOut();
    repo.pendingAction!.complete(patient);
    expect(await result, isFalse);
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.userProfile, isNull);
  });

  test('sign-in cannot complete after a newer null auth event', () async {
    final result = auth.signIn(email: patient.email, password: 'secret1');
    repo.emit(patient.id);
    repo.emit(null);
    repo.pendingAction!.complete(patient);
    expect(await result, isFalse);
    expect(auth.status, AuthStatus.signedOut);
  });

  test('sign-in A cannot replace restored B', () async {
    final result = auth.signIn(email: patient.email, password: 'secret1');
    repo.emit(patient.id);
    repo.profiles[doctor.id] = doctor;
    repo.emit(doctor.id);
    await Future<void>.delayed(Duration.zero);
    repo.pendingAction!.complete(patient);
    expect(await result, isFalse);
    expect(auth.userProfile, doctor);
  });

  test('older completion cannot clear newer action busy state', () async {
    final old = auth.signIn(email: patient.email, password: 'secret1');
    final pendingOld = repo.pendingAction!;
    await auth.signOut();
    final newer = auth.signIn(email: doctor.email, password: 'secret1');
    pendingOld.complete(patient);
    expect(await old, isFalse);
    expect(auth.isBusy, isTrue);
    repo.emit(doctor.id);
    repo.pendingAction!.complete(doctor);
    expect(await newer, isTrue);
    expect(auth.userProfile, doctor);
  });

  test(
    'returned profile must match authoritative identity without an event',
    () async {
      final result = auth.signIn(email: patient.email, password: 'secret1');
      repo.currentUid = null;
      repo.pendingAction!.complete(patient);
      expect(await result, isFalse);
      expect(auth.isAuthenticated, isFalse);
    },
  );

  for (final target in [null, 'doctor-2', patient.id]) {
    testWidgets('details routes are disposed on session change to $target', (
      tester,
    ) async {
      repo.profiles[doctor.id] = doctor;
      repo.profiles[patient.id] = patient;
      repo.profiles['doctor-2'] = const UserProfile(
        id: 'doctor-2',
        displayName: 'Second doctor',
        email: 'second@example.com',
        role: UserRole.doctor,
      );
      auth.dispose();
      auth = AuthProvider(repo)..start();
      await tester.pumpWidget(
        appWithProviders(auth, links: PatientsRepo(() => repo.currentUid)),
      );
      repo.emit(doctor.id);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Private patient A'));
      await tester.pumpAndSettle();
      expect(find.byType(PatientDetailsScreen), findsOneWidget);
      final oldNavigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      if (target == null) {
        await auth.signOut();
      } else {
        repo.emit(target);
      }
      await tester.pumpAndSettle();
      expect(
        find.byType(PatientDetailsScreen, skipOffstage: false),
        findsNothing,
      );
      expect(oldNavigator.mounted, isFalse);
      expect(find.text('Private patient A', skipOffstage: false), findsNothing);
      // The old route cannot be recovered by Back in the replacement session.
      if (target != null) {
        expect(
          tester.state<NavigatorState>(find.byType(Navigator).last).canPop(),
          isFalse,
        );
      }
    });
  }

  for (final screen in ['linking', 'editor', 'code dialog']) {
    testWidgets('session removal disposes protected $screen', (tester) async {
      repo.profiles[doctor.id] = doctor;
      repo.profiles[patient.id] = patient;
      auth.dispose();
      auth = AuthProvider(repo)..start();
      await tester.pumpWidget(
        appWithProviders(auth, links: PatientsRepo(() => repo.currentUid)),
      );
      repo.emit(screen == 'code dialog' ? doctor.id : patient.id);
      await tester.pumpAndSettle();
      if (screen == 'linking') {
        await tester.tap(find.byTooltip('Link a doctor'));
      } else if (screen == 'editor') {
        await tester.tap(find.text('Medications'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add medication'));
      } else {
        await tester.tap(find.text('Linking code'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Replace'));
      }
      await tester.pumpAndSettle();
      final oldNavigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(oldNavigator.mounted, isFalse);
      expect(
        find.byType(DoctorLinkingScreen, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byType(MedicationEditorScreen, skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(DoctorCodeDialog, skipOffstage: false), findsNothing);
      expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
    });
  }

  testWidgets('details back returns to the same authenticated dashboard', (
    tester,
  ) async {
    repo.profiles[doctor.id] = doctor;
    auth.dispose();
    auth = AuthProvider(repo)..start();
    await tester.pumpWidget(
      appWithProviders(auth, links: PatientsRepo(() => repo.currentUid)),
    );
    repo.emit(doctor.id);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Private patient A'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PatientDetailsScreen), findsNothing);
    expect(find.byType(DoctorDashboardScreen), findsOneWidget);
    expect(auth.userProfile, doctor);
  });
}
