import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/admin/phase1_operations_api.dart';
import '../lib/admin/main_navigation.dart';
import '../lib/admin/phase1_operations_screen.dart';
import '../lib/admin/roles_permissions_screen.dart';

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
