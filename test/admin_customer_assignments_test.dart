import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/hierarchy_management_screen.dart';
import 'package:servicepay_app/admin/phase1_operations_api.dart';

void main() {
  testWidgets(
      'Customer assignment reviews a cross-state Aggregator and sends a guarded request',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    SharedPreferences.setMockInitialValues(
        {'auth_token': 'local-admin-session'});
    final customer = <String, dynamic>{
      '_id': 'customer-1',
      'fullName': 'Local Customer',
      'role': 'CUSTOMER',
      'status': 'ACTIVE',
      'zone': 'NORTH',
      'state': 'KANO',
      'agentId': 'old-agent',
      'stateManagerId': 'old-state',
      'zonalManagerId': 'old-zone',
    };
    final destination = <String, dynamic>{
      '_id': 'new-agent',
      'fullName': 'Other-state Aggregator',
      'role': 'AGENT',
      'status': 'ACTIVE',
      'zone': 'SOUTH',
      'state': 'LAGOS',
      'stateManagerId': 'new-state',
      'zonalManagerId': 'new-zone',
    };
    Map<String, dynamic>? submitted;
    final api = Phase1OperationsApi(
      baseUrl: 'https://unused.test/api',
      client: MockClient((request) async {
        Map<String, dynamic> body;
        if (request.method == 'PATCH') {
          expect(
              request.url.path, '/api/admin/role-users/hierarchy-assignments');
          submitted =
              Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          customer.addAll({
            'agentId': 'new-agent',
            'stateManagerId': 'new-state',
            'zonalManagerId': 'new-zone',
            'zone': 'SOUTH',
            'state': 'LAGOS',
          });
          body = {'success': true, 'user': customer, 'duplicate': false};
        } else if (request.url.path.endsWith('/role-users')) {
          body = {
            'success': true,
            'users': request.url.queryParameters['role'] == 'CUSTOMER'
                ? [customer]
                : [destination]
          };
        } else if (request.url.path.endsWith('/customer-1')) {
          body = {'success': true, 'user': customer};
        } else {
          body = {
            'success': true,
            'user': {
              '_id': request.url.pathSegments.last,
              'fullName': 'Previous parent',
              'role': 'AGENT',
              'status': 'ACTIVE',
              'zone': 'NORTH',
              'state': 'KANO',
            }
          };
        }
        return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: HierarchyManagementScreen(
        role: 'HEAD_OFFICE',
        permissions: const {'hierarchy.manage'},
        initialRole: 'CUSTOMER',
        api: api,
      ),
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review / assign'));
    await tester.tap(find.text('Review / assign'));
    await tester.pumpAndSettle();
    expect(find.text('Other-state Aggregator'), findsOneWidget);
    await tester.tap(find.text('Other-state Aggregator'));
    await tester.pumpAndSettle();
    expect(find.textContaining('LAGOS / SOUTH'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    final reason = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Reason');
    await tester.ensureVisible(reason);
    await tester.enterText(reason, 'Approved customer reporting correction.');
    await tester.tap(find.text('Save assignment'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(submitted?['userId'], 'customer-1');
    expect(submitted?['parentId'], 'new-agent');
    expect(submitted?['expectedParentId'], 'old-agent');
    expect(submitted?['requestId'], isNotEmpty);
    expect(submitted?['reason'], 'Approved customer reporting correction.');
    expect(tester.takeException(), isNull);
  });
}
