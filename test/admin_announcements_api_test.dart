import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:servicepay_app/admin/admin_announcements_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends http.BaseClient {
  final List<http.Response> responses;
  final List<http.BaseRequest> requests = [];
  final List<String> bodies = [];
  _Client(this.responses);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    bodies.add(utf8.decode(await request.finalize().toBytes()));
    final response = responses.removeAt(0);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
  });

  test('list and summary parse their exact admin endpoints', () async {
    final client = _Client([
      http.Response(
          jsonEncode({
            'data': {
              'announcements': [
                {'id': 'a1', 'title': 'System maintenance'}
              ]
            }
          }),
          200),
      http.Response(
          jsonEncode({
            'data': {
              'summary': {
                'views': 44,
                'acknowledgements': 12,
                'dismissals': 3,
                'clicks': 7
              }
            }
          }),
          200),
    ]);
    final api = AdminAnnouncementsApi(client: client);
    expect((await api.list())['data']['announcements'][0]['id'], 'a1');
    final summary = await api.summary();
    expect(summary['data']['summary']['views'], 44);
    expect(summary['data']['summary'].containsKey('uniqueViews'), isFalse);
    expect(client.requests[0].url.path, '/api/announcements/admin');
    expect(client.requests[1].url.path, '/api/announcements/admin/summary');
  });

  test('create, edit, activate and delete use exact verbs, paths and payloads',
      () async {
    final client = _Client(List.generate(4, (_) => http.Response('{}', 200)));
    final api = AdminAnnouncementsApi(client: client);
    final payload = {
      'title': 'Notice',
      'message': 'Please note',
      'type': 'INFO',
      'style': 'BOTH',
      'audience': 'SELECTED_CUSTOMERS',
      'selectedCustomerIds': ['c1'],
      'selectedRole': null,
      'visibility': 'UNTIL_DISMISSED',
      'priority': 3,
      'startAt': '2026-01-01T00:00:00Z',
      'endAt': null,
      'cta': {'label': 'Read more', 'url': 'https://servicepay.ng'},
      'imageUrl': 'https://cdn.servicepay.ng/a.png',
      'isActive': false,
    };
    await api.create(payload);
    await api.update('a/1', payload);
    await api.updateStatus('a/1', true);
    await api.remove('a/1');
    expect(client.requests.map((r) => r.method),
        ['POST', 'PATCH', 'PATCH', 'DELETE']);
    expect(client.requests[1].url.path, '/api/announcements/admin/a%2F1');
    expect(
        client.requests[2].url.path, '/api/announcements/admin/a%2F1/status');
    expect(client.bodies[0], jsonEncode(payload));
    expect(client.bodies[0].contains('displayStyle'), isFalse);
    expect(client.bodies[0].contains('startsAt'), isFalse);
    expect(client.bodies[2], '{"isActive":true}');
  });

  test(
      'tracked participant query, winner confirmation and history use admin paths',
      () async {
    final client = _Client([
      http.Response(
          jsonEncode({
            'data': {'participants': []}
          }),
          200),
      http.Response('{}', 200),
      http.Response(
          jsonEncode({
            'data': {'winners': []}
          }),
          200),
    ]);
    final api = AdminAnnouncementsApi(client: client);
    await api.participants('promo/1',
        search: 'Ada Smith',
        status: 'QUALIFIED',
        page: 2,
        limit: 10,
        sort: 'qualificationDate');
    await api.markWinner('promo/1', 'customer/2');
    await api.winnersHistory('promo/1');

    expect(client.requests[0].method, 'GET');
    expect(client.requests[0].url.path,
        '/api/announcements/admin/promo%2F1/participants');
    expect(client.requests[0].url.queryParameters, {
      'search': 'Ada Smith',
      'status': 'QUALIFIED',
      'page': '2',
      'limit': '10',
      'sort': 'qualificationDate',
    });
    expect(client.requests[1].method, 'POST');
    expect(client.requests[1].url.path,
        '/api/announcements/admin/promo%2F1/participants/customer%2F2/winner');
    expect(client.requests[2].url.path,
        '/api/announcements/admin/promo%2F1/winners/history');
  });
}
