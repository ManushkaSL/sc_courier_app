import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sc_courier/screens/dashboard_screen.dart';
import 'package:sc_courier/screens/login_screen.dart';
import 'package:sc_courier/screens/register_screen.dart';
import 'package:sc_courier/services/supabase_service.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await SupabaseService().initialize();
  });

  testWidgets('Shows login and navigates to register', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1080, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        initialRoute: LoginScreen.routeName,
        routes: {
          LoginScreen.routeName: (context) => const LoginScreen(),
          RegisterScreen.routeName: (context) => const RegisterScreen(),
          DashboardScreen.routeName: (context) => const DashboardScreen(),
        },
      ),
    );
    await tester.pump();

    expect(find.text('SC Courier Rider App'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);

    await tester.tap(find.text('Create an account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Back to login'), findsOneWidget);
  });
}
