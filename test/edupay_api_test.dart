import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/edupay_api.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_token': 'token',
      }));

  test('uses final readiness and explicit payout lifecycle routes', () async {
    final requests = <http.Request>[];
    final api = EduPayApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
            jsonEncode(<String, dynamic>{'success': true, 'ready': true}), 200);
      }),
    );
    await api.readiness();
    await api.processSettlement('set-1');
    await api.requerySettlement('set-1');
    expect(requests.map((r) => '${r.method} ${r.url.path}'), <String>[
      'GET /api/admin/edupay/readiness',
      'POST /api/admin/edupay/settlements/set-1/process',
      'POST /api/admin/edupay/settlements/set-1/requery',
    ]);
    expect(requests[1].url.path, isNot(contains('confirm')));
  });

  test('uses versioned settlement-account verification contract', () async {
    late http.Request request;
    final api = EduPayApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((value) async {
        request = value;
        return http.Response(
            jsonEncode(<String, dynamic>{'success': true}), 200);
      }),
    );
    await api.verifySettlementAccount('school-1',
        accountId: 'account-1', version: 3);
    expect(request.method, 'POST');
    expect(request.url.path,
        '/api/admin/edupay/schools/school-1/settlement-account/verify');
    expect(jsonDecode(request.body),
        <String, dynamic>{'accountId': 'account-1', 'version': 3});
  });
}
