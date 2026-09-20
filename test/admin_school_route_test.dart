import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/main.dart';
import 'package:servicepay_app/school/school_login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('/school remains a production admin entry route', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const ServicepayAdminApp());
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/school');
    for (var frame = 0; frame < 10; frame += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SchoolLoginScreen), findsOneWidget);
  });
}
