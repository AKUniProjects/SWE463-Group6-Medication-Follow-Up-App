import 'package:flutter_test/flutter_test.dart';

import 'package:medication_follow_up_app/main.dart';

void main() {
  testWidgets('shows the sign-in screen', (tester) async {
    await tester.pumpWidget(const MedicationFollowUpApp());

    expect(find.text('Medication Follow-up'), findsOneWidget);
    expect(find.text('Sign in to demo'), findsOneWidget);
  });
}
