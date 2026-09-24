import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/admin/phase1_operations_api.dart';
import '../lib/admin/main_navigation.dart';

void main() {
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
}
