import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/login_screen.dart';
import 'package:servicepay_app/admin/main.dart' as admin;
import 'package:servicepay_app/login_screen.dart' as customer;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('production Admin entry starts Admin login, never Customer login',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    admin.main();
    await tester.pumpAndSettle();
    expect(find.byType(admin.ServicepayAdminApp), findsOneWidget);
    expect(find.byType(AdminLoginScreen), findsOneWidget);
    expect(find.byType(customer.LoginScreen), findsNothing);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'Servicepay Admin');
  });
}
