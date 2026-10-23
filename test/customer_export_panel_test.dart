import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/customer_export_api.dart';
import 'package:servicepay_app/admin/customer_export_panel.dart';

void main() {
  test('customer export policy allows Head Office or explicit grant only', () {
    expect(
      const AdminAccess(role: 'HEAD_OFFICE', permissions: <String>{})
          .canExportCustomers,
      isTrue,
    );
    expect(
      const AdminAccess(
        role: 'BRANCH_MANAGER',
        permissions: <String>{AdminPermissions.customersExport},
      ).canExportCustomers,
      isTrue,
    );
    expect(
      const AdminAccess(role: 'BRANCH_MANAGER', permissions: <String>{'*'})
          .canExportCustomers,
      isFalse,
    );
    expect(
      const AdminAccess(role: 'BRANCH_MANAGER', permissions: <String>{})
          .canExportCustomers,
      isFalse,
    );
  });

  testWidgets('unsupported share offers an explicit download fallback',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final List<http.Request> requests = <http.Request>[];
    final CustomerExportApi api = CustomerExportApi(
      tokenLoader: () async => 'test-token',
      client: MockClient((http.Request request) async {
        requests.add(request);
        return http.Response.bytes(
          utf8.encode('"Full Name","Phone Number","Email Address"\r\n'),
          200,
          headers: <String, String>{'content-type': 'text/csv'},
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerExportPanel(api: api, searchQuery: 'Amina'),
        ),
      ),
    );

    await tester.tap(find.text('Share Customers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(requests, hasLength(1));
    expect(jsonDecode(requests.single.body)['action'], 'share');
    expect(
        find.text(
            'Sharing is unavailable here. Download the prepared file instead.'),
        findsOneWidget);
    expect(find.text('Download file'), findsOneWidget);

    await tester.tap(find.text('Download file'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Download started.'), findsOneWidget);
  });
}
