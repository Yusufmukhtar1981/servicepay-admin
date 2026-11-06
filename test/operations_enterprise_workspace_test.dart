import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/admin_staff_workspace_api.dart';
import 'package:servicepay_app/admin/admin_staff_workspace_screens.dart';

class _EnterpriseFixtureApi extends AdminStaffWorkspaceApi {
  _EnterpriseFixtureApi({this.refundPermission = false})
      : super(client: MockClient((_) async => http.Response('{}', 200)));
  final bool refundPermission;

  @override
  Future<Map<String, dynamic>> enterprise({String period = 'day'}) async => {
        'success': true,
        'data': {
          'generatedAt': '2026-07-16T12:00:00Z',
          'period': period,
          'from': '2026-07-16',
          'to': '2026-07-16',
          'permissions': {
            'refund': refundPermission,
            'customerManage': false,
            'serviceControl': false,
            'reportExport': false,
            'staffManage': false,
          },
          'summary': {'total': 0},
          'customers': {'total': 0},
          'trends': [],
          'services': [],
          'financial': {},
          'staff': [],
          'staffCoverage': {'limit': 100, 'truncated': false},
          'support': {},
          'alerts': [],
          'activity': [],
          'serviceControls': [],
        },
      };

  @override
  Future<Map<String, dynamic>> reliability({int page = 1}) async => {
        'success': true,
        'data': {
          'summary': {},
          'backlog': {},
          'alerts': [],
          'providers': [],
          'items': [],
          'total': 0,
          'page': page,
        },
      };

  @override
  Future<Map<String, dynamic>> transactions({
    String status = '',
    String type = '',
    String query = '',
    String customerId = '',
    String from = '',
    String to = '',
    String minAmount = '',
    String maxAmount = '',
    int page = 1,
    int limit = 20,
  }) async =>
      {
        'success': true,
        'data': {
          'items': [
            {
              'id': 'txn-1',
              'reference': 'SP-001',
              'service': 'DATA',
              'status': 'PENDING',
              'amount': 1200,
              'createdAt': '2026-07-16T11:00:00Z',
            }
          ],
          'total': 1,
        },
      };

  @override
  Future<Map<String, dynamic>> transactionDetail(String id) async => {
        'success': true,
        'data': {
          'transaction': {
            'id': id,
            'reference': 'SP-001',
            'service': 'DATA',
            'status': 'PENDING',
            'amount': 1200,
            'createdAt': '2026-07-16T11:00:00Z',
          },
          'customer': {
            'phone': '080****001',
            'email': 'a***@example.test',
            'walletBalance': 5000,
          },
          'history': [],
          'providerDiagnostics': {
            'code': 'PENDING',
            'status': 'Pending',
            'message': 'Provider outcome not confirmed',
          },
          'processingDurationMs': null,
          'canRefund': refundPermission,
          'refundEligibility': {
            'eligible': false,
            'blockers': ['Provider outcome has not been confirmed'],
          },
        },
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('enterprise API uses the selected day/week/month period', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'ops-session'});
    http.Request? request;
    final api = AdminStaffWorkspaceApi(
      baseUrl: 'https://example.test/api/admin/staff-workspace',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'period': 'week'}
          }),
          200,
        );
      }),
    );
    await api.enterprise(period: 'week');
    expect(request!.url.path, '/api/admin/staff-workspace/enterprise');
    expect(request!.url.queryParameters, {'period': 'week'});
    expect(request!.headers['authorization'], 'Bearer ops-session');
    api.close();
  });

  test('transaction filters include time and amount bounds without defaults',
      () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'ops-session'});
    http.Request? request;
    final api = AdminStaffWorkspaceApi(
      baseUrl: 'https://example.test/api/admin/staff-workspace',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'items': [], 'total': 0}
          }),
          200,
        );
      }),
    );
    await api.transactions(
      status: 'FAILED',
      type: 'DATA',
      query: 'SP-24',
      from: '2026-07-01',
      to: '2026-07-16',
      minAmount: '200',
      maxAmount: '4500',
      page: 2,
    );
    expect(request!.url.queryParameters, {
      'status': 'FAILED',
      'type': 'DATA',
      'q': 'SP-24',
      'from': '2026-07-01',
      'to': '2026-07-16',
      'minAmount': '200',
      'maxAmount': '4500',
      'page': '2',
      'limit': '20',
    });
    api.close();
  });

  test('safe customer and service actions use scoped status contracts',
      () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'ops-session'});
    final requests = <http.Request>[];
    final api = AdminStaffWorkspaceApi(
      baseUrl: 'https://example.test/api/admin/staff-workspace',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'success': true, 'data': {}}),
          200,
        );
      }),
    );
    await api.updateCustomerStatus(
      'customer-7',
      status: 'SUSPENDED',
      reason: 'Confirmed account compromise',
    );
    await api.updateServiceStatus(
      'DATA',
      enabled: false,
      reason: 'Recorded provider incident',
    );
    expect(requests[0].url.path,
        '/api/admin/staff-workspace/customers/customer-7/status');
    expect(jsonDecode(requests[0].body), {
      'status': 'SUSPENDED',
      'reason': 'Confirmed account compromise',
    });
    expect(requests[1].url.path,
        '/api/admin/staff-workspace/services/DATA/status');
    expect(jsonDecode(requests[1].body), {
      'enabled': false,
      'reason': 'Recorded provider incident',
    });
    api.close();
  });

  test('transaction detail uses the safe investigation route', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'ops-session'});
    http.Request? request;
    final api = AdminStaffWorkspaceApi(
      baseUrl: 'https://example.test/api/admin/staff-workspace',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'transaction': {'id': 'txn-9'},
              'customer': {'phone': '080****009'},
              'history': [],
              'providerDiagnostics': {'message': 'No secrets'},
              'canRefund': false,
            }
          }),
          200,
        );
      }),
    );
    final response = await api.transactionDetail('txn-9');
    expect(request!.url.path,
        '/api/admin/staff-workspace/transactions/txn-9/detail');
    expect(response['data']['customer']['phone'], '080****009');
    api.close();
  });

  test('export preserves bytes, content type and server filename', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'ops-session'});
    final payload = <int>[0x50, 0x4b, 0x03, 0x04, 0x11, 0x00];
    http.Request? request;
    final api = AdminStaffWorkspaceApi(
      baseUrl: 'https://example.test/api/admin/staff-workspace',
      client: MockClient((value) async {
        request = value;
        return http.Response.bytes(
          payload,
          200,
          headers: {
            'content-type':
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'content-disposition': 'attachment; filename="ops-week.xlsx"',
          },
        );
      }),
    );
    final file = await api.export(period: 'week', format: 'xlsx');
    expect(request!.url.path, '/api/admin/staff-workspace/enterprise/export');
    expect(request!.url.queryParameters, {'period': 'week', 'format': 'xlsx'});
    expect(file.bytes, payload);
    expect(file.contentType,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    expect(file.filename, 'ops-week.xlsx');
    api.close();
  });

  testWidgets('enterprise shell fits a 390px viewport with permissions off',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'ops-session'});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: OperationsManagerDashboard(api: _EnterpriseFixtureApi()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('ServicePay operations'), findsOneWidget);
    expect(find.text('Executive overview'), findsOneWidget);
    await tester.tap(find.text('Transactions').first);
    await tester.pumpAndSettle();
    expect(find.text('Transaction reliability'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refund review stays unavailable when backend denies permission',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'ops-session'});
    await tester.pumpWidget(MaterialApp(
      home: OperationsManagerDashboard(api: _EnterpriseFixtureApi()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transactions').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('SP-001'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('SP-001'));
    await tester.pumpAndSettle();
    expect(find.text('Review refund'), findsNothing);
    expect(find.text('Refund eligibility'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'refund action is only exposed from backend permission and eligibility',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'ops-session'});
    await tester.pumpWidget(MaterialApp(
      home: OperationsManagerDashboard(
        api: _EnterpriseFixtureApi(refundPermission: true),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transactions').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('SP-001'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('SP-001'));
    await tester.pumpAndSettle();
    expect(find.text('Review refund'), findsOneWidget);
    expect(find.textContaining('Provider outcome has not been confirmed'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer status controls stay hidden without the explicit grant',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'ops-session'});
    await tester.pumpWidget(MaterialApp(
      home: OperationsManagerDashboard(api: _EnterpriseFixtureApi()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customers').first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Customer status controls are unavailable'),
      findsOneWidget,
    );
    expect(find.text('Customer ID'), findsNothing);
    expect(find.text('Apply status change'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
