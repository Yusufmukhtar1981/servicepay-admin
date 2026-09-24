import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/admin/phase1_operations_api.dart';

void main() {
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
    );
    expect(requests.single.url.path, '/api/admin/role-users');
    expect(jsonDecode(requests.single.body)['role'], 'ZONAL_MANAGER');
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
      customerId: 'customer-1',
      action: 'DEBIT',
      amount: '100',
      reason: 'Correction',
      reference: 'REF-1',
      idempotencyKey: 'attempt-1',
    );
    final body = jsonDecode(requests.single.body) as Map;
    expect(requests.single.url.path, '/api/admin/wallet-adjustment');
    expect(body['idempotencyKey'], 'attempt-1');
    expect(body['reference'], 'REF-1');
    expect(body['reason'], 'Correction');
  });
}
