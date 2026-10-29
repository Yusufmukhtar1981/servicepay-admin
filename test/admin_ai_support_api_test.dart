import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:servicepay_app/admin/admin_support_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends http.BaseClient {
  _Client(this.responses);
  final List<http.Response> responses;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];
  final List<String> bodies = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    bodies.add(utf8.decode(await request.finalize().toBytes()));
    final http.Response response = responses.removeAt(0);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'head-office-test-token',
    });
  });

  test('AI endpoints use build-configured API base and correct verbs',
      () async {
    final _Client client = _Client(<http.Response>[
      http.Response('{"data":{"conversations":14}}', 200),
      http.Response('{"data":{"enabled":true}}', 200),
    ]);
    final AdminSupportApi api = AdminSupportApi(
      client: client,
      aiBaseUrlOverride: 'https://staging.servicepay.invalid/api',
    );

    expect((await api.aiMetrics())['data']['conversations'], 14);
    await api.saveAiSettings(<String, dynamic>{
      'enabled': true,
      'hausaVoiceEnabled': false,
    });

    expect(client.requests[0].url.toString(),
        'https://staging.servicepay.invalid/api/admin/support/ai-metrics');
    expect(client.requests[1].method, 'PUT');
    expect(client.requests[1].url.path, '/api/admin/support/ai-settings');
    expect(jsonDecode(client.bodies[1])['hausaVoiceEnabled'], isFalse);
    expect(
        client.requests.every((request) =>
            request.headers['Authorization'] ==
            'Bearer head-office-test-token'),
        isTrue);
    api.close();
  });

  test('AI admin calls refuse implicit production fallback', () async {
    final AdminSupportApi api = AdminSupportApi(
      client: _Client(<http.Response>[]),
      aiBaseUrlOverride: '',
    );
    expect(() => api.aiMetrics(), throwsStateError);
    api.close();
  });
}
