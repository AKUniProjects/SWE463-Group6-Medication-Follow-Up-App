// Reproducible real-adapter checks without a browser-test launcher.
// Start Auth :9099 / Firestore :8080 emulators, then:
// flutter run -d web-server --target tool/verify_medication_backend.dart --web-port 8766
// Open the printed local URL. This target ALWAYS connects to local emulators.
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:medication_follow_up_app/firebase_options.dart';
import 'package:medication_follow_up_app/models/medication.dart';
import 'package:medication_follow_up_app/services/firestore_medication_store.dart';
import 'package:medication_follow_up_app/services/medication_repository.dart';
import 'package:medication_follow_up_app/theme/app_theme.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<List<String>> verifyBackend() async {
  if (!kIsWeb) throw StateError('Open this verification target in a browser.');
  final app = await Firebase.initializeApp(
    name: 'person2-backend-checks',
    options: DefaultFirebaseOptions.web,
  );
  final auth = FirebaseAuth.instanceFor(app: app);
  final firestore = FirebaseFirestore.instanceFor(app: app);
  firestore.useFirestoreEmulator('127.0.0.1', 8080);
  await auth.useAuthEmulator('127.0.0.1', 9099);
  final repo = StoredMedicationRepository(
    FirestoreMedicationStore(firestore),
    currentPatientId: () => auth.currentUser?.uid,
  );
  final passed = <String>[];
  Medication draft({int stock = 8}) => Medication(
    id: '',
    patientId: auth.currentUser!.uid,
    name: 'Fictional backend fixture',
    doseAmount: 500,
    doseUnit: 'mg',
    scheduledTimes: const ['08:00', '20:00'],
    stockAmount: stock,
    refillThreshold: 7,
    stockUnit: 'tablet',
    unitsPerDose: 1,
  );

  final checks = <String, Future<void> Function()>{
    'CRUD, zero supply, server persistence and soft deletion': () async {
      var m = await repo.create(draft());
      m = await repo.update(m.copyWith(name: 'Edited backend fixture'));
      m = await repo.updateSupply(m, 0);
      final server = await firestore
          .collection('medications')
          .doc(m.id)
          .get(const GetOptions(source: Source.server));
      require(
        server.data()!['stockAmount'] == 0,
        'Zero supply was not persisted',
      );
      require(
        (server.data()!['scheduledTimes'] as List).length == 2,
        'Lost schedule',
      );
      final cold = StoredMedicationRepository(
        FirestoreMedicationStore(firestore),
        currentPatientId: () => auth.currentUser?.uid,
      );
      final observed = await cold.watchPatient(m.patientId).first;
      require(
        observed.single.id == m.id,
        'Cold repository did not read the same ID',
      );
      m = await repo.deactivate(m);
      final retained = await firestore
          .collection('medications')
          .doc(m.id)
          .get(const GetOptions(source: Source.server));
      require(
        retained.exists && retained.data()!['isActive'] == false,
        'Soft deletion failed',
      );
    },
    'Four concurrent retries deduct once; overdraft is rejected': () async {
      final m = await repo.create(draft(stock: 1));
      final results = await Future.wait(
        List.generate(
          4,
          (_) => repo.consumeStock(
            patientId: m.patientId,
            medicationId: m.id,
            doseRecordId: 'same-dose-08:00',
          ),
        ),
      );
      require(
        results.where((r) => r.status == ConsumptionStatus.consumed).length ==
            1,
        'Expected exactly one deduction',
      );
      require(
        results
                .where((r) => r.status == ConsumptionStatus.alreadyConsumed)
                .length ==
            3,
        'Retries did not find the receipt',
      );
      final next = await repo.consumeStock(
        patientId: m.patientId,
        medicationId: m.id,
        doseRecordId: 'next-dose-20:00',
      );
      require(
        next.status == ConsumptionStatus.insufficientStock &&
            next.medication.stockAmount == 0,
        'Stock became negative',
      );
      final receipt = await firestore
          .collection('medications')
          .doc(m.id)
          .collection('consumptions')
          .doc('same-dose-08:00')
          .get(const GetOptions(source: Source.server));
      require(
        receipt.data()!['createdAt'] is Timestamp,
        'Missing server-stamped receipt',
      );
    },
    'Four distinct concurrent doses each deduct exactly once': () async {
      final m = await repo.create(draft(stock: 4));
      final results = await Future.wait(
        List.generate(
          4,
          (i) => repo.consumeStock(
            patientId: m.patientId,
            medicationId: m.id,
            doseRecordId: 'distinct-dose-$i',
          ),
        ),
      );
      require(
        results.every((r) => r.status == ConsumptionStatus.consumed),
        'A legitimate concurrent deduction failed',
      );
      final server = await firestore
          .collection('medications')
          .doc(m.id)
          .get(const GetOptions(source: Source.server));
      require(
        server.data()!['stockAmount'] == 0,
        'Distinct deductions were lost',
      );
    },
    'A stale edit cannot restore previously consumed stock': () async {
      final original = await repo.create(draft());
      await repo.consumeStock(
        patientId: original.patientId,
        medicationId: original.id,
        doseRecordId: 'dose-1',
      );
      var rejected = false;
      String? actualFailure;
      try {
        await repo.update(original.copyWith(name: 'Stale name'));
      } on MedicationException catch (e) {
        actualFailure = e.code.name;
        rejected = e.code == MedicationError.conflict;
      }
      final server = await firestore
          .collection('medications')
          .doc(original.id)
          .get(const GetOptions(source: Source.server));
      require(
        server.data()!['stockAmount'] == 7 &&
            server.data()!['name'] == original.name,
        'The stale draft overwrote server data',
      );
      require(rejected, 'Expected revision conflict, received $actualFailure');
    },
  };
  try {
    for (final check in checks.entries) {
      final unique = DateTime.now().microsecondsSinceEpoch;
      final random = Random.secure();
      final password = List.generate(
        24,
        (_) => random.nextInt(36).toRadixString(36),
      ).join();
      final user = (await auth.createUserWithEmailAndPassword(
        email: 'p2-$unique@example.test',
        password: password,
      )).user!;
      try {
        await firestore.collection('users').doc(user.uid).set({
          'displayName': 'Fictional backend patient',
          'email': user.email,
          'role': 'patient',
          'linkedDoctorIds': <String>[],
        });
        await check.value();
        passed.add(check.key);
        debugPrint('PASS: ${check.key}');
      } finally {
        await auth.currentUser?.delete();
      }
    }
  } finally {
    await app.delete();
  }
  return passed;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final verification = verifyBackend();
  runApp(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        appBar: AppBar(title: const Text('Person 2 backend verification')),
        body: FutureBuilder<List<String>>(
          future: verification,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText('FAILED: ${snapshot.error}'),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  '${snapshot.data!.length}/4 backend checks passed',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Text(
                  'Real Firebase adapter • local Auth and Firestore emulators',
                ),
                for (final name in snapshot.data!)
                  ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(name),
                  ),
                const Text(
                  'Fictional fixtures only. No live Firebase service was used.',
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
