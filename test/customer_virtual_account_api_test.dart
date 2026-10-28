import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:servicepay_app/admin/customer_virtual_account_admin.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'sandbox-only-token'});
  });

  test('load uses authenticated canonical customer route and bounded cursor', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/admin/users/customer-id/virtual-account');
      expect(request.url.queryParameters['before'], 'cursor-id');
      expect(request.headers['Authorization'], 'Bearer sandbox-only-token');
      return http.Response(jsonEncode({'success': true, 'data': {
        'virtualAccount': {'status': 'NOT_CREATED'},
        'history': [],
      }}), 200);
    });
    final api = AdminCustomerVirtualAccountApi(
      client: client, baseUrl: 'https://example.invalid/api/',
    );
    final result = await api.load(customerId: 'customer-id', before: 'cursor-id');
    expect(result['virtualAccount']['status'], 'NOT_CREATED');
    client.close();
  });

  test('generation sends only explicit reason and durable request ID', () async {
    const requestId = '65ac1d46-4b46-40ea-93ab-c8caa4458cb4';
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.method, 'POST');
      expect(request.headers['Authorization'], 'Bearer sandbox-only-token');
      expect(jsonDecode(request.body), {
        'reason': 'Customer requested dedicated account',
        'requestId': requestId,
      });
      return http.Response(jsonEncode({'success': true, 'data': {
        'virtualAccount': {'status': 'PENDING'},
        'eligibility': {'canGenerate': false},
      }}), 200);
    });
    final api = AdminCustomerVirtualAccountApi(
      client: client, baseUrl: 'https://example.invalid/api',
    );
    final result = await api.generate(
      customerId: 'customer-id',
      reason: 'Customer requested dedicated account',
      requestId: requestId,
    );
    expect(result['virtualAccount']['status'], 'PENDING');
    expect(requests, 1);
    client.close();
  });

  test('provider credentials and diagnostic payloads are never surfaced', () async {
    final client = MockClient((request) async => http.Response(jsonEncode({
      'success': false,
      'message': 'Invalid API key fake-private-credential',
      'providerResponse': {'token': 'fake-private-token'},
    }), 503));
    final api = AdminCustomerVirtualAccountApi(
      client: client, baseUrl: 'https://example.invalid/api',
    );
    try {
      await api.load(customerId: 'customer-id');
      fail('Expected a safe error.');
    } catch (error) {
      expect(error.toString(), isNot(contains('fake-private')));
      expect(error.toString(), contains('configuration is unavailable'));
    } finally {
      client.close();
    }
  });
}
