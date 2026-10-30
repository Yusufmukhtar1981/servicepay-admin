import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/admin_staff_workspace_api.dart';
import 'package:servicepay_app/admin/admin_staff_workspace_screens.dart';
import 'package:servicepay_app/admin/main_navigation.dart';

class _WorkspaceApi extends AdminStaffWorkspaceApi {
  _WorkspaceApi() : super(client: MockClient((_) async => http.Response('{}', 200)));

  @override
  Future<Map<String, dynamic>> overview() async => {
        'success': true,
        'data': {
          'transactions': {
            'today': [
              {'_id': 'SUCCESS', 'count': 12, 'amount': 26490}
            ],
            'byStatus': [],
            'services': [],
          },
          'tickets': {'byAgent': []},
          'issues': {'virtualAccounts': [], 'delivery': []},
          'branches': [],
        },
      };
}

void main() {
  test('Head Office sees ordinary staff workspaces with an empty permission fixture', () {
    final labels = AdminMainNavigation.visibleDestinationLabels(const AdminAccess(role: 'HEAD_OFFICE', permissions: <String>{}));
    expect(labels, contains('Operations overview'));
    expect(labels, contains('Customer support desk'));
  });
  TestWidgetsFlutterBinding.ensureInitialized();

  test('workspace navigation is permission-visible and role-defaulted', () {
    const Set<String> operations = {AdminPermissions.operationsWorkspaceView};
    const Set<String> support = {AdminPermissions.supportWorkspaceView};
    final labels = AdminMainNavigation.visibleDestinationLabels(
      const AdminAccess(role: 'STAFF', permissions: operations),
    );
    expect(labels, contains('Operations overview'));
    expect(labels, isNot(contains('Customer support desk')));
    expect(
      AdminMainNavigation.preferredWorkspaceIndex(
        labels: ['Settings', 'Operations overview'],
        role: 'STAFF',
        permissions: operations,
      ),
      1,
    );
    expect(
      AdminMainNavigation.visibleDestinationLabels(
        const AdminAccess(role: 'STAFF', permissions: support),
      ),
      contains('Customer support desk'),
    );
    expect(
      AdminMainNavigation.preferredWorkspaceIndex(
        labels: ['Dashboard', 'Customer support desk'],
        role: 'STAFF',
        permissions: support,
      ),
      1,
    );
    expect(
      AdminMainNavigation.preferredWorkspaceIndex(
        labels: ['Existing first destination', 'Operations overview'],
        role: 'HEAD_OFFICE',
        permissions: operations,
      ),
      0,
    );
    expect(
      AdminMainNavigation.visibleDestinationLabels(
        const AdminAccess(role: 'STAFF', permissions: <String>{}),
      ),
      isNot(contains('Operations overview')),
    );
  });

  testWidgets('operations dashboard renders real overview and gross disclaimer',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'session'});
    await tester.pumpWidget(
      MaterialApp(home: OperationsManagerDashboard(api: _WorkspaceApi())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Operations overview'), findsOneWidget);
    expect(find.textContaining('₦26490.00'), findsOneWidget);
    expect(find.textContaining('not net profit'), findsOneWidget);
    expect(find.text('No operational records to show.'), findsWidgets);
  });

  testWidgets('customer workspace starts with a privacy-conscious search state',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CustomerSupportDashboard(api: _WorkspaceApi())),
    );
    expect(
      find.text('Search securely to investigate a customer.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('name, phone, email, ID or transaction reference'),
      findsOneWidget,
    );
  });

  test('workspace endpoints use protected staff-workspace route', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'workspace-session'});
    http.Request? request;
    final api = AdminStaffWorkspaceApi(
      baseUrl: 'https://example.test/api/admin/staff-workspace',
      client: MockClient((value) async {
        request = value;
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      }),
    );
    await api.customers(query: 'Amina 0800', page: 2);
    expect(request!.url.path, '/api/admin/staff-workspace/customers');
    expect(request!.url.queryParameters, {'q': 'Amina 0800', 'page': '2', 'limit': '20'});
    expect(request!.headers['authorization'], 'Bearer workspace-session');
    api.close();
  });

  test('role provisioning POST is explicit and sends no scope overrides',
      () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'head-office'});
    http.Request? request;
    String? body;
    final api = AdminStaffWorkspaceApi(
      baseUrl: 'https://example.test/api/admin/staff-workspace',
      client: MockClient((value) async {
        request = value;
        body = value.body;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'roles': [
                {'name': 'OPERATIONS_MANAGER'},
                {'name': 'CUSTOMER_SUPPORT'}
              ]
            }
          }),
          200,
        );
      }),
    );
    final result = await api.provisionRoles();
    expect(request!.method, 'POST');
    expect(
      request!.url.path,
      '/api/admin/staff-workspace/provision-roles',
    );
    expect(request!.headers['authorization'], 'Bearer head-office');
    expect(jsonDecode(body!), isEmpty);
    expect(
      (result['data'] as Map)['roles'],
      hasLength(2),
    );
    api.close();
  });

  test('staff history uses the authenticated staff-workspace endpoint',
      () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'head-office'});
    http.Request? request;
    final api = AdminStaffWorkspaceApi(
      baseUrl: 'https://example.test/api/admin/staff-workspace',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'staff': {'id': 'staff-42', 'fullName': 'Amina Bello', 'status': 'ACTIVE'},
              'logins': [
                {'_id': 'l1', 'outcome': 'SUCCESS', 'eventType': 'LOGIN', 'createdAt': '2026-06-01T09:00:00Z'}
              ],
              'activities': [
                {'_id': 'a1', 'action': 'TICKET_REPLY', 'reason': 'Customer response', 'createdAt': '2026-06-01T09:10:00Z'}
              ],
              'access': [
                {'_id': 'r1', 'method': 'GET', 'path': '/api/admin/support/tickets', 'statusCode': 200, 'createdAt': '2026-06-01T09:11:00Z'}
              ],
            },
          }),
          200,
        );
      }),
    );
    final result = await api.staffHistory('staff-42');
    expect(request!.method, 'GET');
    expect(
      request!.url.path,
      '/api/admin/staff-workspace/staff/staff-42/history',
    );
    expect(request!.headers['authorization'], 'Bearer head-office');
    expect((result['data'] as Map)['logins'], hasLength(1));
    expect((result['data'] as Map)['activities'], hasLength(1));
    expect((result['data'] as Map)['access'], hasLength(1));
    api.close();
  });
}
