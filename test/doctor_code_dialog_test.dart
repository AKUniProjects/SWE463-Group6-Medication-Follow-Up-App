import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/doctor_link.dart';
import 'package:medication_follow_up_app/models/user_profile.dart';
import 'package:medication_follow_up_app/screens/app_shell.dart';
import 'package:medication_follow_up_app/screens/doctor_code_dialog.dart';
import 'package:medication_follow_up_app/services/doctor_link_repository.dart';
import 'package:medication_follow_up_app/state/doctor_link_provider.dart';
import 'package:provider/provider.dart';

DoctorCode code(String id, {bool active = true, DateTime? createdAt}) =>
    DoctorCode(
      code: id,
      doctorId: 'doc',
      doctorName: 'Dr Test',
      active: active,
      createdAt: createdAt ?? DateTime.now().subtract(const Duration(days: 1)),
    );

class FakeRepo implements DoctorLinkRepository {
  List<DoctorCode> stored = [];
  int loads = 0;
  Completer<void>? gate;
  DoctorLinkException? failLoad;
  int _n = 0;

  @override
  Future<List<DoctorCode>> myCodes() async {
    loads++;
    final g = gate;
    if (g != null) await g.future;
    final f = failLoad;
    if (f != null) throw f;
    return List.of(stored.reversed);
  }

  @override
  Future<DoctorCode> createCode() async {
    final c =
        code('NEWCODE${_n++}AB'.substring(0, 10), createdAt: DateTime.now());
    stored.add(c);
    return c;
  }

  @override
  Future<void> deactivateCode(String c) async {
    final i = stored.indexWhere((x) => x.code == c);
    stored[i] = code(c, active: false, createdAt: stored[i].createdAt);
  }

  @override
  Future<DoctorCode> replaceCode(String old) async {
    final fresh = await createCode();
    await deactivateCode(old);
    return fresh;
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late FakeRepo repo;
  late DoctorLinkProvider links;

  setUp(() {
    repo = FakeRepo();
    links = DoctorLinkProvider(repo)..updateSession(uid: 'doc', isDoctor: true);
  });

  tearDown(() => links.dispose());

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<DoctorLinkProvider>.value(
        value: links,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDoctorCodeDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(); // dialog + post-frame load starts
  }

  testWidgets('loading then empty state generates a code', (tester) async {
    final gate = repo.gate = Completer<void>();
    await openDialog(tester);
    await tester.pump();
    expect(find.text('Your linking code'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    repo.gate = null;
    await tester.pumpAndSettle();
    expect(find.text('No active code'), findsOneWidget);
    expect(repo.loads, 1); // one read per opening

    await tester.tap(find.text('Generate code'));
    await tester.pumpAndSettle();
    expect(find.text('NEWC-ODE0-AB'), findsOneWidget);
    expect(find.textContaining('Expires'), findsOneWidget);
    expect(find.text('Code created'), findsOneWidget);
  });

  testWidgets('shows active code with expiry and copies canonical value',
      (tester) async {
    repo.stored = [
      DoctorCode(
        code: 'ABCDEFGH23',
        doctorId: 'doc',
        doctorName: 'Dr Test',
        active: true,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ];
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await openDialog(tester);
    await tester.pumpAndSettle();
    expect(find.text('ABCD-EFGH-23'), findsOneWidget);
    expect(find.textContaining('Expires'), findsOneWidget);

    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();
    expect(copied, 'ABCDEFGH23');
    expect(find.text('Code copied'), findsOneWidget);
  });

  testWidgets('clipboard failure shows a fallback message', (tester) async {
    repo.stored = [code('ABCDEFGH23')];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'copy_fail');
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await openDialog(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not copy automatically'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive and expired codes are not shown as usable',
      (tester) async {
    repo.stored = [
      code('EXPIRED234',
          createdAt: DateTime.now().subtract(const Duration(days: 31))),
      code('INACTIVE23', active: false),
    ];
    await openDialog(tester);
    await tester.pumpAndSettle();
    expect(find.text('No active code'), findsOneWidget);
    expect(find.text('Generate code'), findsOneWidget);
  });

  testWidgets('replace and deactivate require confirmation', (tester) async {
    repo.stored = [code('OLDCODE234')];
    await openDialog(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(find.text('Replace code?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('OLDC-ODE2-34'), findsOneWidget);

    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
    await tester.pumpAndSettle();
    expect(find.text('New code created'), findsOneWidget);
    expect(find.text('OLDC-ODE2-34'), findsNothing);

    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    expect(find.text('Deactivate code?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();
    expect(find.text('Code deactivated'), findsOneWidget);
    expect(find.text('No active code'), findsOneWidget);
  });

  testWidgets('error shows banner and retry recovers', (tester) async {
    repo.failLoad = const DoctorLinkException(DoctorLinkErrorCode.network);
    await openDialog(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Network error'), findsOneWidget);
    expect(find.text('Generate code'), findsNothing); // unknown state

    repo.failLoad = null;
    await tester.tap(find.text('Retry loading'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Network error'), findsNothing);
    expect(find.text('Generate code'), findsOneWidget);
  });

  testWidgets('actions are disabled while busy', (tester) async {
    repo.stored = [code('OLDCODE234')];
    await openDialog(tester);
    await tester.pumpAndSettle();

    final gate = repo.gate = Completer<void>();
    unawaited(links.loadCodes());
    await tester.pump();
    final copy = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Copy code'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(copy.onPressed, isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    gate.complete();
    repo.gate = null;
    await tester.pumpAndSettle();
  });

  testWidgets('patients see a restriction and trigger no reads',
      (tester) async {
    links.updateSession(uid: 'pat', isDoctor: false);
    await openDialog(tester);
    await tester.pumpAndSettle();
    expect(find.text('Only doctor accounts can manage linking codes.'),
        findsOneWidget);
    expect(repo.loads, 0);
  });

  group('shell entry point', () {
    Future<void> pumpShell(WidgetTester tester, UserRole role) async {
      final original = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('RenderFlex overflowed')) return;
        original?.call(d);
      };
      addTearDown(() => FlutterError.onError = original);
      await tester.pumpWidget(
        ChangeNotifierProvider<DoctorLinkProvider>.value(
          value: links,
          child: MaterialApp(home: AppShell(role: role)),
        ),
      );
    }

    testWidgets('doctor opens and closes the overlay', (tester) async {
      await pumpShell(tester, UserRole.doctor);
      await tester.tap(find.text('Linking code'));
      await tester.pumpAndSettle();
      expect(find.byType(DoctorCodeDialog), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(DoctorCodeDialog), findsNothing);
      expect(find.text('Doctor dashboard'), findsOneWidget);
    });

    testWidgets('patient shell has no linking-code entry', (tester) async {
      await pumpShell(tester, UserRole.patient);
      expect(find.text('Linking code'), findsNothing);
    });
  });
}
