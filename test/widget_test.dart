import 'package:flutter_test/flutter_test.dart';

import 'package:sc_courier/main.dart';

void main() {
  testWidgets('Shows login and navigates to register', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('SC Courier Rider App'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);

    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Back to login'), findsOneWidget);
  });
}
