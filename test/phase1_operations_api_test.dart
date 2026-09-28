import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/admin/phase1_operations_api.dart';
import '../lib/admin/main_navigation.dart';
import '../lib/admin/admin_permissions.dart';
import '../lib/admin/phase1_operations_screen.dart';
import '../lib/admin/roles_permissions_screen.dart';
import '../lib/admin/hierarchy_management_screen.dart';

void main() {
  test('Head Office role assignment uses secured existing route and body', () {
    expect(
      headOfficeRoleAssignmentPath('user/one'),
      '/staff-management/staff/user%2Fone/head-office-role',
    );
    expect(
      headOfficeRoleAssignmentBody('role-wallet'),
      {'roleId': 'role-wallet'},
    );
  });

  test('manager visibility is role-scoped and wallet adjustment is exact', () {
    expect(
      canAccessAdminNavigationModule(
        role: 'STATE_MANAGER',
        permissions: <String>{'wallets.view'},
        permission: 'wallets.adjust',
      ),
      isFalse,
    );
    expect(
      canAccessAdminNavigationModule(
        role: 'STATE_MANAGER',
        permissions: <String>{'wallets.adjust'},
        permission: 'wallets.adjust',
      ),
      isTrue,
    );
    expect(
      canAccessAdminNavigationModule(
        role: 'HEAD_OFFICE',
        permissions: const <String>{},
        permission: 'wallets.adjust',
      ),
      isTrue,
    );
  });

  test('creates canonical Zonal Manager through role-users contract', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'token'});
    final requests = <http.Request>[];
    final api = Phase1OperationsApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'success': true}), 201);
      }),
    );
    await api.createZonalManager(
      fullName: 'Zone Lead',
      email: 'lead@example.test',
      phone: '08000000000',
      password: 'temporary-password',
      zone: 'North',
    );
    expect(requests.single.url.path, '/api/admin/role-users/zonal-managers');
    expect(jsonDecode(requests.single.body)['role'], 'ZONAL_MANAGER');
    expect(jsonDecode(requests.single.body)['zone'], 'North');
  });

  test('wallet adjustment sends stable audit/idempotency fields', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'token'});
    final requests = <http.Request>[];
    final api = Phase1OperationsApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );
    await api.adjustWallet(
      identifier: 'customer-1',
      action: 'DEBIT',
      amount: '100',
      reason: 'Correction',
      reference: 'REF-1',
      idempotencyKey: 'attempt-1',
    );
    final body = jsonDecode(requests.single.body) as Map;
    expect(requests.single.url.path, '/api/admin/wallet-adjustment');
    expect(requests.single.headers['idempotency-key'], 'attempt-1');
    expect(body['identifier'], 'customer-1');
    expect(body['reference'], 'REF-1');
    expect(body['reason'], 'Correction');
  });

  test('summary and transactions use server-scoped paginated contracts',
      () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'token'});
    final requests = <http.Request>[];
    final api = Phase1OperationsApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );
    await api.hierarchySummary();
    await api.downlineTransactions(page: 3, limit: 25);
    expect(requests[0].url.path, '/api/management/downline/summary');
    expect(requests[1].url.path, '/api/management/downline/transactions');
    expect(requests[1].url.queryParameters, {'page': '3', 'limit': '25'});
  });

  test('retrying an ambiguous wallet attempt can reuse its exact key',
      () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'token'});
    final requests = <http.Request>[];
    var first = true;
    final api = Phase1OperationsApi(
      client: MockClient((request) async {
        requests.add(request);
        if (first) {
          first = false;
          throw Exception('ambiguous timeout');
        }
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );
    Future<void> call() => api.adjustWallet(
          identifier: 'customer-1',
          action: 'CREDIT',
          amount: '10',
          reason: 'Correction',
          reference: 'REF-1',
          idempotencyKey: 'same-attempt',
        );
    await expectLater(call(), throwsException);
    await call();
    expect(requests, hasLength(2));
    expect(requests[0].headers['idempotency-key'], 'same-attempt');
    expect(requests[1].headers['idempotency-key'], 'same-attempt');
  });

  test('hierarchy assignment client preserves audit contract', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'token'});
    final requests = <http.Request>[];
    final api = Phase1OperationsApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'success': true,
            'duplicate': false,
            'records': <dynamic>[],
          }),
          200,
        );
      }),
    );
    await api.hierarchyUsers(role: 'AGENT', search: 'Ada', page: 2);
    await api.assignHierarchy(
      userId: 'agent-1',
      parentId: 'state-2',
      reason: 'Regional coverage change',
      requestId: 'request-1',
    );
    await api.hierarchyHistory(role: 'AGENT', type: 'REASSIGNMENT');
    expect(requests[0].url.path, '/api/admin/hierarchy/users');
    expect(requests[0].url.queryParameters['role'], 'AGENT');
    expect(requests[0].url.queryParameters['search'], 'Ada');
    expect(requests[1].url.path, '/api/admin/hierarchy/assignments');
    expect(jsonDecode(requests[1].body), {
      'userId': 'agent-1',
      'parentId': 'state-2',
      'reason': 'Regional coverage change',
      'requestId': 'request-1',
    });
    expect(requests[2].url.path, '/api/admin/hierarchy/history');
    expect(requests[2].url.queryParameters['type'], 'REASSIGNMENT');
  });

  test('role assignment uses the guarded HEAD OFFICE endpoint contract', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'token'});
    final requests = <http.Request>[];
    final api = Phase1OperationsApi(
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'PATCH') {
          return http.Response(
            jsonEncode({
              'success': false,
              'code': 'HIERARCHY_HISTORY_UNVERIFIED',
              'message': 'This user has legacy transactions.',
            }),
            409,
          );
        }
        if (request.url.path.endsWith('/state-1')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'user': {
                '_id': 'state-1',
                'role': 'STATE_MANAGER',
                'zonalManagerId': 'zonal-1',
                'zone': 'North',
                'state': 'Kano',
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'users': <dynamic>[]}),
          200,
        );
      }),
    );

    await api.roleUsers(role: 'STATE_MANAGER', search: 'Ada');
    await api.roleUser('state-1');
    await expectLater(
      api.assignRoleUser(
        userId: 'state-1',
        parentId: 'zonal-2',
        expectedParentId: 'zonal-1',
        reason: 'Verified regional coverage change',
        requestId: 'assignment-request-1',
      ),
      throwsA(
        isA<Phase1OperationsException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having((error) => error.code, 'code', 'HIERARCHY_HISTORY_UNVERIFIED')
            .having((error) => error.message, 'message', 'This user has legacy transactions.'),
      ),
    );

    expect(requests.map((request) => request.method), ['GET', 'GET', 'PATCH']);
    expect(requests[0].url.path, '/api/admin/role-users');
    expect(requests[0].url.queryParameters, {
      'role': 'STATE_MANAGER',
      'search': 'Ada',
    });
    expect(requests[1].url.path, '/api/admin/role-users/state-1');
    expect(requests[2].url.path, '/api/admin/role-users/hierarchy-assignments');
    expect(jsonDecode(requests[2].body), {
      'userId': 'state-1',
      'parentId': 'zonal-2',
      'expectedParentId': 'zonal-1',
      'reason': 'Verified regional coverage change',
      'requestId': 'assignment-request-1',
    });
  });

  test('hierarchy management is never granted to scoped manager roles', () {
    expect(
      AdminAccess(
        role: 'STATE_MANAGER',
        permissions: <String>{'hierarchy.manage'},
      ).hasHeadOfficePermission('hierarchy.manage'),
      isFalse,
    );
    expect(
      AdminAccess(
        role: 'HEAD_OFFICE',
        permissions: <String>{'hierarchy.manage'},
      ).hasHeadOfficePermission('hierarchy.manage'),
      isTrue,
    );
    expect(
      AdminMainNavigation.visibleDestinationLabels(
        AdminAccess(
          role: 'HEAD_OFFICE',
          permissions: <String>{'hierarchy.manage'},
        ),
      ),
      contains('Hierarchy Management'),
    );
    expect(
      AdminMainNavigation.visibleDestinationLabels(
        AdminAccess(
          role: 'STATE_MANAGER',
          permissions: <String>{'hierarchy.manage'},
        ),
      ),
      isNot(contains('Hierarchy Management')),
    );
  });

  testWidgets(
      'Head Office without exact wallet permission keeps hierarchy only',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Phase1OperationsScreen(
          role: 'HEAD_OFFICE',
          permissions: <String>{},
        ),
      ),
    );
    expect(find.text('Create Zonal Manager'), findsNWidgets(2));
    expect(find.text('Manual customer wallet adjustment'), findsNothing);
  });

  testWidgets('hierarchy selector searches server-side and confirms assignment',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({'auth_token': 'token'});
    final requests = <http.Request>[];
    final api = Phase1OperationsApi(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/admin/role-users') {
          final role = request.url.queryParameters['role'];
          return http.Response(
            jsonEncode({
              'success': true,
              'users': role == 'STATE_MANAGER'
                  ? [
                      {
                        '_id': 'state-1',
                        'fullName': 'State A',
                        'phone': '0801',
                        'email': 'state@test',
                        'zone': 'North',
                        'state': 'Kano',
                        'status': 'ACTIVE',
                      }
                    ]
                  : [
                      {
                        '_id': 'zonal-new',
                        'fullName': 'Zonal New',
                        'phone': '0802',
                        'email': 'new@test',
                        'zone': 'North',
                        'status': 'ACTIVE',
                      }
                    ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/state-1')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'user': {
                '_id': 'state-1',
                'fullName': 'State A',
                'role': 'STATE_MANAGER',
                'zonalManagerId': 'zonal-old',
                'zone': 'North',
                'state': 'Kano',
                'status': 'ACTIVE',
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/zonal-old')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'user': {
                '_id': 'zonal-old',
                'fullName': 'Zonal Old',
                'role': 'ZONAL_MANAGER',
                'zone': 'North',
                'status': 'ACTIVE',
              },
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HierarchyManagementScreen(
            role: 'HEAD_OFFICE',
            permissions: const <String>{'hierarchy.manage'},
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.where((request) => request.url.path == '/api/admin/role-users'),
        isNotEmpty);
    expect(find.text('Unable to load hierarchy users'), findsNothing);
    expect(find.text('No matching users found.'), findsNothing);
    expect(find.text('State A'), findsOneWidget);
    await tester.tap(find.text('Review / assign'));
    await tester.pumpAndSettle();
    expect(find.text('Select Zonal Manager'), findsOneWidget);
    expect(find.text('Zonal New'), findsOneWidget);
    await tester.tap(find.text('Zonal New'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm reassignment'), findsOneWidget);
    expect(find.text('Current reporting line'), findsOneWidget);
    expect(find.text('Zonal Manager: Zonal Old (zonal-old)'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Coverage correction for region');
    await tester.tap(find.text('Save assignment'));
    await tester.pumpAndSettle();
    expect(
      requests.any(
          (http.Request request) =>
              request.url.path == '/api/admin/role-users/hierarchy-assignments' &&
              request.method == 'PATCH'),
      isTrue,
    );
    final http.Request patch = requests.firstWhere((http.Request request) =>
        request.url.path == '/api/admin/role-users/hierarchy-assignments');
    final Map<String, dynamic> payload =
        Map<String, dynamic>.from(jsonDecode(patch.body) as Map);
    expect(payload.remove('requestId'), isNotEmpty);
    expect(payload, {
      'userId': 'state-1',
      'parentId': 'zonal-new',
      'expectedParentId': 'zonal-old',
      'reason': 'Coverage correction for region',
    });
  });

  testWidgets('409 legacy-history response is shown without claiming success',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({'auth_token': 'token'});
    final api = Phase1OperationsApi(
      client: MockClient((request) async {
        if (request.url.path == '/api/admin/role-users') {
          final String role = request.url.queryParameters['role'] ?? '';
          final Map<String, dynamic> user = switch (role) {
            'AGENT' => {
                '_id': 'agent-2',
                'fullName': 'Aggregator Two',
                'zone': 'North',
                'state': 'Kano',
                'status': 'ACTIVE',
              },
            'CUSTOMER' => {
                '_id': 'customer-1',
                'fullName': 'Customer One',
                'zone': 'North',
                'state': 'Kano',
                'status': 'ACTIVE',
              },
            _ => {
                '_id': 'state-1',
                'fullName': 'State One',
                'zone': 'North',
                'state': 'Kano',
                'status': 'ACTIVE',
              },
          };
          return http.Response(
            jsonEncode({
              'success': true,
              'users': [user],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/customer-1')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'user': {
                '_id': 'customer-1',
                'fullName': 'Customer One',
                'role': 'CUSTOMER',
                'agentId': 'agent-1',
                'stateManagerId': 'state-1',
                'zone': 'North',
                'state': 'Kano',
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/agent-1')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'user': {
                '_id': 'agent-1',
                'fullName': 'Aggregator One',
                'role': 'AGENT',
                'stateManagerId': 'state-1',
                'zone': 'North',
                'state': 'Kano',
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/state-1')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'user': {
                '_id': 'state-1',
                'fullName': 'State One',
                'role': 'STATE_MANAGER',
                'zonalManagerId': 'zone-1',
                'zone': 'North',
                'state': 'Kano',
              },
            }),
            200,
          );
        }
        if (request.method == 'PATCH') {
          return http.Response(
            jsonEncode({
              'success': false,
              'code': 'HIERARCHY_HISTORY_UNVERIFIED',
              'message': 'Legacy history blocks assignment.',
            }),
            409,
          );
        }
        return http.Response(jsonEncode({'success': true}), 200);
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
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review / assign'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select Aggregator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggregator Two').last);
    await tester.pumpAndSettle();
    expect(find.text('Current reporting line'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).last, 'Correct parent assignment');
    await tester.tap(find.text('Save assignment'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Assignment blocked:'), findsOneWidget);
    expect(find.textContaining('Legacy history blocks assignment.'), findsNothing);
  });

  testWidgets('reporting chain drills down through actual parent IDs',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({'auth_token': 'token'});
    final requests = <http.Request>[];
    final api = Phase1OperationsApi(
      client: MockClient((request) async {
        requests.add(request);
        final role = request.url.queryParameters['role'];
        final data = switch (role) {
          'ZONAL_MANAGER' => {'_id': 'zone-1', 'fullName': 'Zone One', 'role': role},
          'STATE_MANAGER' => {'_id': 'state-1', 'fullName': 'State One', 'role': role},
          'AGENT' => {'_id': 'agent-1', 'fullName': 'Aggregator One', 'role': role},
          _ => {'_id': 'customer-1', 'fullName': 'Customer One', 'role': role},
        };
        return http.Response(jsonEncode({
          'users': [data],
          'pagination': {'pages': 1, 'total': 1},
        }), 200);
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HierarchyManagementScreen(
          role: 'HEAD_OFFICE',
          permissions: const {'hierarchy.manage'},
          api: api,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View reporting chain'));
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['role'], 'ZONAL_MANAGER');
    await tester.tap(find.text('Zone One'));
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['parentId'], 'zone-1');
    expect(requests.last.url.queryParameters['role'], 'STATE_MANAGER');
    await tester.tap(find.text('State One').last);
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['parentId'], 'state-1');
    expect(requests.last.url.queryParameters['role'], 'AGENT');
    await tester.tap(find.text('Aggregator One'));
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['parentId'], 'agent-1');
    expect(requests.last.url.queryParameters['role'], 'CUSTOMER');
    expect(find.text('Customer One'), findsOneWidget);
  });

  testWidgets('Head Office exact wallet permission renders wallet controls',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Phase1OperationsScreen(
          role: 'HEAD_OFFICE',
          permissions: <String>{'wallets.adjust'},
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    expect(find.textContaining('Manual customer wallet adjustment'),
        findsOneWidget);
    expect(find.text('Search customers'), findsOneWidget);
  });

  testWidgets('downline totals, recent rows and pagination render',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'token'});
    final api = Phase1OperationsApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/summary')) {
          return http.Response(
            jsonEncode({
              'counts': {
                'totalDownline': 4,
                'customers': 2,
                'transactions': 7,
                'transactionValue': 1250,
              },
              'recentTransactions': [
                {'type': 'Airtime', 'status': 'SUCCESS', 'amount': 100},
              ],
              'users': [
                {'id': 'user-1', 'fullName': 'Downline User'},
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'transactions': List.generate(
              25,
              (index) => {
                'type': 'Transfer',
                'status': 'SUCCESS',
                'amount': index,
              },
            ),
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Phase1OperationsScreen(
          role: 'STATE_MANAGER',
          api: api,
        ),
      ),
    );
    await tester.tap(find.text('View permitted downline summary'));
    await tester.pumpAndSettle();
    expect(find.text('Total downline: 4'), findsOneWidget);
    expect(find.text('Customers: 2'), findsOneWidget);
    expect(find.text('Transactions: 7'), findsOneWidget);
    expect(find.text('Value: 1250'), findsOneWidget);
    expect(find.text('Recent transactions'), findsOneWidget);
    expect(find.text('Airtime'), findsOneWidget);
    expect(find.text('Transactions (page 1)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Next'), 400);
    expect(find.text('Next'), findsOneWidget);
  });
}
