import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/main.dart';
import 'package:medication_follow_up_app/state/auth_provider.dart';
import 'package:provider/provider.dart';

import 'support/controllable_auth_repository.dart';

void main() {
  testWidgets('shows the sign-in screen when signed out', (tester) async {
    final repo = ControllableAuthRepository();
    final auth = AuthProvider(repo)..start();

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: const MedicationFollowUpApp(),
      ),
    );
    repo.emit(null);
    await tester.pump();

    expect(find.text('Medication Follow-up'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);

    auth.dispose();
    await repo.close();
  });
}
