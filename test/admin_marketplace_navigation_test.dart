import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_marketplace_management_screen.dart';
import 'package:servicepay_app/admin/admin_marketplace_operations_api.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';

void main() {
  const headOffice = AdminAccess(role: 'HEAD_OFFICE', permissions: {});
  const viewer = AdminAccess(
      role: 'STAFF', permissions: {AdminPermissions.marketplaceView});

  test('actual production entrypoint registers every Marketplace route', () {
    final main = File('lib/admin/main.dart').readAsStringSync();
    expect(main, contains('for (final route in marketplaceAdminRoutes)'));
    expect(main, contains('AdminMarketplaceManagementScreen(destination: route)'));
    expect(main, contains('AdminSessionGate('));
    final dashboard =
        File('lib/admin/admin_dashboard_screen.dart').readAsStringSync();
    expect(dashboard, contains("Key('marketplace-management-entry')"));
    expect(dashboard, contains("title: 'Marketplace Management'"));
    expect(dashboard, contains('canViewMarketplace(_marketplaceAccess!)'));
  });

  test('Marketplace presentation permissions retain Head Office and explicit viewers', () {
    expect(canViewMarketplace(headOffice), isTrue);
    expect(canViewMarketplace(viewer), isTrue);
    expect(canViewMarketplace(
        const AdminAccess(role: 'STAFF', permissions: {})), isFalse);
  });

  testWidgets('hub links to real registered pages at phone width without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? opened;
    await tester.pumpWidget(MaterialApp(
      home: const AdminMarketplaceManagementScreen(initialAccess: headOffice),
      onGenerateRoute: (settings) {
        opened = settings.name;
        return MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Selected destination')));
      },
    ));
    await tester.pumpAndSettle();
    expect(find.text('Merchant Management'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('/marketplace/commissions')), 250);
    expect(tester.takeException(), isNull);
    expect(find.text('Commission Transaction History'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('/marketplace/commissions')));
    await tester.pumpAndSettle();
    expect(opened, '/marketplace/commissions');
  });

  testWidgets('forbidden deep link does not call the real API', (tester) async {
    var calls = 0;
    final api = AdminMarketplaceOperationsApi(
        tokenReader: () async => 'unit-only',
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 500);
        }));
    await tester.pumpWidget(MaterialApp(
        home: AdminMarketplaceManagementScreen(
            initialAccess: const AdminAccess(role: 'STAFF', permissions: {}),
            destination: '/marketplace/merchants',
            api: api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not have permission'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('merchant deep link renders the existing API-backed merchant screen',
      (tester) async {
    late Uri called;
    final api = AdminMarketplaceOperationsApi(
        baseUrl: 'https://test.invalid/api',
        tokenReader: () async => 'unit-only',
        client: MockClient((request) async {
          called = request.url;
          return http.Response(jsonEncode({
            'success': true, 'merchants': [],
            'pagination': {'page': 1, 'pages': 1, 'total': 0},
          }), 200);
        }));
    await tester.pumpWidget(MaterialApp(
        home: AdminMarketplaceManagementScreen(
            initialAccess: viewer,
            destination: '/marketplace/merchants',
            api: api)));
    await tester.pumpAndSettle();
    expect(called.path, '/api/admin/marketplace/merchants');
    expect(find.text('Marketplace Merchants'), findsOneWidget);
  });

  testWidgets('commission history uses existing settled-order API without writes',
      (tester) async {
    final requests = <http.Request>[];
    final api = AdminMarketplaceOperationsApi(
        baseUrl: 'https://test.invalid/api',
        tokenReader: () async => 'unit-only',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({
            'success': true, 'orders': [],
            'pagination': {'page': 1, 'pages': 1, 'total': 0},
          }), 200);
        }));
    await tester.pumpWidget(MaterialApp(
        home: AdminMarketplaceManagementScreen(
            initialAccess: viewer,
            destination: '/marketplace/commissions',
            api: api)));
    await tester.pumpAndSettle();
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/admin/marketplace/orders');
    expect(requests.single.url.queryParameters['fundsStatus'], 'SETTLED');
    expect(find.text('Commission Transaction History'), findsOneWidget);
    expect(find.textContaining('not an external bank payout'), findsOneWidget);
  });
}
