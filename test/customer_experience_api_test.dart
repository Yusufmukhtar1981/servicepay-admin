import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:servicepay_app/admin/customer_experience_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QueueClient extends http.BaseClient {
  _QueueClient(this.responses);
  final List<http.Response> responses;
  final List<http.BaseRequest> requests = [];
  final List<String> bodies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    bodies.add(utf8.decode(await request.finalize().toBytes()));
    final response = responses.removeAt(0);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  test('credit amounts are parsed exactly, not rounded from floating point', () {
    expect(parseCashbackAmount('2.55'), 255);
    expect(parseCashbackAmount('1,234.01'), 123401);
    expect(parseCashbackAmount('0.001'), isNull);
    expect(parseCashbackAmount('-1'), isNull);
    expect(parseCashbackAmount('0'), isNull);
    expect(parseCashbackAmount('10000000.01'), isNull);
  });

  test('pending credit is persisted and verified before submission', () async {
    SharedPreferences.setMockInitialValues({});
    final pending = {
      'customerId': 'customer-1',
      'requestKey': 'stable-test-key-0001',
      'amountMinor': 255,
      'description': 'Support appreciation',
    };
    await persistCashbackRequest('pending-test-credit', pending);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('pending-test-credit')!), pending);
    await persistCashbackRequest('pending-test-credit', pending);
    expect(jsonDecode(prefs.getString('pending-test-credit')!), pending);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'admin-session'});
  });

  test('credit carries the exact idempotency key and integer kobo payload',
      () async {
    final client =
        _QueueClient([http.Response('{"success":true,"entry":{}}', 200)]);
    final api = CustomerExperienceApi(
      client: client,
      baseUrl: 'https://api.servicepay.invalid/api/customer-experience',
    );
    await api.credit(
      customerId: 'customer/123',
      amountMinor: 2575,
      description: 'Service recovery',
      requestKey: 'stable-key-012',
    );
    expect(client.requests.single.url.path,
        '/api/customer-experience/admin/customers/customer%2F123/cashback');
    expect(
        client.requests.single.headers['X-Idempotency-Key'], 'stable-key-012');
    expect(jsonDecode(client.bodies.single), {
      'amountMinor': 2575,
      'description': 'Service recovery',
    });
    expect(client.requests.single.headers['Authorization'],
        'Bearer admin-session');
    api.close();
  });

  test('access parses backend capabilities and surfaces server message',
      () async {
    final client = _QueueClient([
      http.Response(
          '{"success":true,"canManage":true,"canCreditCashback":false}', 200),
      http.Response(
          '{"success":false,"message":"Head Office access required"}', 403),
    ]);
    final api = CustomerExperienceApi(
      client: client,
      baseUrl: 'https://api.servicepay.invalid/api/customer-experience',
    );
    final access = await api.access();
    expect(access['canManage'], isTrue);
    expect(access['canCreditCashback'], isFalse);
    await expectLater(
        api.access(),
        throwsA(
          isA<CustomerExperienceAdminException>().having(
            (error) => error.message,
            'message',
            'Head Office access required',
          ),
        ));
    api.close();
  });
}
