// Task 3.6: doctor dashboard integration (FAKE repository, no Firebase).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/doctor_link.dart';
import 'package:medication_follow_up_app/screens/doctor_dashboard_screen.dart';
import 'package:medication_follow_up_app/screens/linked_patients_dashboard.dart';
import 'package:medication_follow_up_app/screens/patient_details_screen.dart';
import 'package:medication_follow_up_app/services/doctor_link_repository.dart';
import 'package:medication_follow_up_app/state/doctor_link_provider.dart';
import 'package:provider/provider.dart';

LinkedPatient patient(String id, String name, {String doctor = 'doc'}) =>
    LinkedPatient(
      link: DoctorLink(
        id: '${id}_$doctor',
        patientId: id,
        doctorId: doctor,
        linkCode: 'ABCDEFGH23',
        status: LinkStatus.active,
        patientName: name,
      ),
      displayName: name,
      email: '$id@example.com',
    );

/// Per-doctor active links; revokeLink removes the patient (like a refresh
/// after the rules stop authorizing the profile).
class FakeRepo implements DoctorLinkRepository {
  final Map<String, List<LinkedPatient>> byDoctor = {};
  String currentDoctor = 'doc';
  Completer<void>? gate;
  DoctorLinkException? failNext;
  int loads = 0;
  final revoked = <String>[];

  @override
  Future<List<LinkedPatient>> linkedPatientsForDoctor() async {
    loads++;
    final g = gate;
    if (g != null) await g.future;
    final f = failNext;
    failNext = null;
    if (f != null) throw f;
    return List.of(byDoctor[currentDoctor] ?? const []);
  }

  @override
  Future<void> revokeLink(DoctorLink link) async {
    final f = failNext;
    failNext = null;
    if (f != null) throw f;
    revoked.add(link.id);
    byDoctor[link.doctorId]!.removeWhere((p) => p.link.id == link.id);
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late FakeRepo repo;
  late DoctorLinkProvider links;

  setUp(() {
    repo = FakeRepo()
      ..byDoctor['doc'] = [patient('p1', 'Patient One')]
      ..byDoctor['doc2'] = [
        patient('p9', 'Other Doctor Patient', doctor: 'doc2')
      ];
    links = DoctorLinkProvider(repo)..updateSession(uid: 'doc', isDoctor: true);
  });

  tearDown(() => links.dispose());

  for (final count in [0, 1, 3]) {
    testWidgets('pull refresh works with $count patients and updates links',
        (tester) async {
      repo.byDoctor['doc'] = [
        for (var i = 0; i < count; i++) patient('p$i', 'Patient $i'),
      ];
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: links,
        child: const MaterialApp(home: LinkedPatientsDashboard()),
      ));
      await tester.pumpAndSettle();
      final before = repo.loads;
      repo.byDoctor['doc'] = [patient('new', 'New linked patient')];
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(repo.loads, before + 1);
      expect(find.text('New linked patient'), findsOneWidget);
      // The next successful refresh removes the revoked relationship.
      repo.byDoctor['doc'] = [];
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('New linked patient'), findsNothing);
      expect(find.text('No linked patients yet.'), findsOneWidget);
    });
  }

  group('provider', () {
    test('loads active linked patients', () async {
      expect(await links.loadLinkedPatients(), isTrue);
      expect(links.linkedPatients.single.patientId, 'p1');
      expect(links.hasLoadedLinkedPatients, isTrue);
    });

    test('no linked patients', () async {
      repo.byDoctor['doc'] = [];
      expect(await links.loadLinkedPatients(), isTrue);
      expect(links.linkedPatients, isEmpty);
    });

    test('patients and signed-out users are refused without a read', () async {
      links.updateSession(uid: 'pat', isDoctor: false, isPatient: true);
      expect(await links.loadLinkedPatients(), isFalse);
      expect(links.linkedPatientsError, contains('Only doctor accounts'));
      links.updateSession(uid: null, isDoctor: false);
      expect(await links.loadLinkedPatients(), isFalse);
      expect(repo.loads, 0);
    });

    test('errors keep the previous list and retry works', () async {
      await links.loadLinkedPatients();
      repo.failNext =
          const DoctorLinkException(DoctorLinkErrorCode.permissionDenied);
      expect(await links.loadLinkedPatients(), isFalse);
      expect(links.linkedPatientsError, contains('permission'));
      expect(links.linkedPatients, hasLength(1));
      expect(await links.loadLinkedPatients(), isTrue);
      expect(links.linkedPatientsError, isNull);
    });

    test('switching doctors and signing out clear the list', () async {
      await links.loadLinkedPatients();
      links.updateSession(uid: 'doc2', isDoctor: true);
      expect(links.linkedPatients, isEmpty);
      repo.currentDoctor = 'doc2';
      await links.loadLinkedPatients();
      expect(links.linkedPatients.single.patientId, 'p9');

      links.updateSession(uid: null, isDoctor: false);
      expect(links.linkedPatients, isEmpty);
      expect(links.hasLoadedLinkedPatients, isFalse);
    });

    test('stale load from a previous doctor is ignored', () async {
      final gate = repo.gate = Completer<void>();
      final pending = links.loadLinkedPatients();
      links.updateSession(uid: 'doc2', isDoctor: true);
      gate.complete();
      repo.gate = null;
      expect(await pending, isFalse);
      expect(links.linkedPatients, isEmpty);
      expect(links.isLoadingLinkedPatients, isFalse);
    });

    test('doctor revocation removes the patient after refresh', () async {
      await links.loadLinkedPatients();
      expect(
          await links.revokePatientLink(links.linkedPatients.single), isTrue);
      expect(repo.revoked, ['p1_doc']);
      expect(links.linkedPatients, isEmpty);
    });

    test('failed revocation keeps the patient and shows an error', () async {
      await links.loadLinkedPatients();
      repo.failNext = const DoctorLinkException(DoctorLinkErrorCode.network);
      expect(
          await links.revokePatientLink(links.linkedPatients.single), isFalse);
      expect(links.linkedPatients, hasLength(1));
      expect(links.linkedPatientsError, contains('Network'));
    });
  });

  group('dashboard adapter', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<DoctorLinkProvider>.value(
          value: links,
          child: const MaterialApp(home: LinkedPatientsDashboard()),
        ),
      );
    }

    testWidgets('loading, then real patients in the teammate dashboard',
        (tester) async {
      final gate = repo.gate = Completer<void>();
      await pump(tester);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      repo.gate = null;
      await tester.pumpAndSettle();
      expect(find.byType(DoctorDashboardScreen), findsOneWidget);
      expect(find.text('Patient One'), findsOneWidget);
      expect(find.text('Demo Patient'), findsNothing); // no sample data
    });

    testWidgets('empty state comes from the dashboard', (tester) async {
      repo.byDoctor['doc'] = [];
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.text('No linked patients yet.'), findsOneWidget);
    });

    testWidgets('error before first load offers retry', (tester) async {
      repo.failNext = const DoctorLinkException(DoctorLinkErrorCode.network);
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Network error'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Patient One'), findsOneWidget);
    });

    testWidgets('tapping a patient opens details with the right identity',
        (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Patient One'));
      await tester.pumpAndSettle();

      final details = tester
          .widget<PatientDetailsScreen>(find.byType(PatientDetailsScreen));
      expect(details.patient.patientId, 'p1');
      expect(details.patient.patientName, 'Patient One');
    });

    test('summary mapping uses the Auth UID and empty stats', () {
      final summary = toPatientSummary(patient('p1', 'Patient One'));
      expect(summary.patientId, 'p1');
      expect(summary.stats.scheduledDoses, 0);
      expect(summary.requiresFollowUp, isFalse);
    });
  });
}
