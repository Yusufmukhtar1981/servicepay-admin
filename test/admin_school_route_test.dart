import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/main.dart';
import 'package:servicepay_app/school/school_login_screen.dart';

void main() {
  testWidgets('/school remains a production admin entry route', (tester) async {
    await tester.pumpWidget(const ServicepayAdminApp());
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/school');
    await tester.pumpAndSettle();
    expect(find.byType(SchoolLoginScreen), findsOneWidget);
  });
}