import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/admin_announcements_api.dart';
import 'package:servicepay_app/admin/admin_dashboard_screen.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';

void main() {
  testWidgets('Delivery & Logistics opens the dedicated Delivery Pricing page',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final AdminAnnouncementsApi promoApi = AdminAnnouncementsApi(
      client: MockClient((http.Request _) async => http.Response('{}', 200)),
      baseUrl: 'https://preview.servicepay.test/api',
    );

    await tester.pumpWidget(MaterialApp(
      home: AdminDashboardScreen(
        initialAccess: const AdminAccess(
          role: 'HEAD_OFFICE',
          permissions: <String>{},
        ),
        dashboardLoader: (String _) async => <String, dynamic>{},
        promoApi: promoApi,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fintech Control Center'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Delivery Pricing');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delivery Pricing').last);
    await tester.pumpAndSettle();

    expect(find.text('Delivery Pricing'), findsOneWidget);
    expect(find.text('Pricing could not be loaded'), findsOneWidget);
  });
}
