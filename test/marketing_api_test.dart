import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: avoid_relative_lib_imports
import '../lib/admin/marketing_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'admin_token': 'local-test-token'});
  });

  test('overview uses the Admin Marketing route and Bearer session', () async {
    Uri? seenUri;
    Map<String, String>? seenHeaders;
    final api = MarketingApi(
      client: MockClient((request) async {
        seenUri = request.url;
        seenHeaders = request.headers;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'period': {'timeZone': 'UTC'},
              'metrics': {'totalCustomersAcquired': 17},
            }
          }),
          200,
        );
      }),
    );
    final result = await api.overview({'preset': '7days'});
    expect(seenUri!.path, endsWith('/admin/marketing/overview'));
    expect(seenUri!.queryParameters['preset'], '7days');
    expect(
      seenHeaders!.entries
          .firstWhere((entry) => entry.key.toLowerCase() == 'authorization')
          .value,
      'Bearer local-test-token',
    );
    expect(result['metrics']['totalCustomersAcquired'], 17);
    api.close();
  });

  test('record creation carries stable idempotency header and body envelope',
      () async {
    Map<String, String>? headers;
    Map<String, dynamic>? payload;
    final api = MarketingApi(
      client: MockClient((request) async {
        headers = request.headers;
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'_id': 'campaign-1'}
          }),
          201,
        );
      }),
    );
    await api.createRecord(
      'campaign',
      {
        'title': 'Kano merchant launch',
        'description': 'Evidence-linked acquisition',
        'data': {'objective': 'Acquisition'},
      },
      idempotencyKey: 'mk_local_test_001',
    );
    expect(
      headers!.entries
          .firstWhere((entry) => entry.key.toLowerCase() == 'idempotency-key')
          .value,
      'mk_local_test_001',
    );
    expect(payload!['title'], 'Kano merchant launch');
    expect(payload!['data']['objective'], 'Acquisition');
    api.close();
  });

  test('503 readiness response remains explicit to the caller', () async {
    final api = MarketingApi(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'success': false,
              'message': 'Marketing storage is not ready'
            }),
            503,
          )),
    );
    await expectLater(
      api.schema(),
      throwsA(predicate((error) => '$error'.contains('503'))),
    );
    api.close();
  });

  test('overview export forwards selected date range and format', () async {
    final seen = <Uri>[];
    final api = MarketingApi(
      client: MockClient((request) async {
        seen.add(request.url);
        return http.Response('report-bytes', 200);
      }),
    );
    await api.export('overview', 'xlsx', query: {
      'preset': 'custom',
      'from': '2025-04-01T00:00:00.000Z',
      'to': '2025-04-07T23:59:59.000Z',
    });
    expect(seen.last.path, endsWith('/admin/marketing/export/overview'));
    expect(seen.last.queryParameters['format'], 'xlsx');
    expect(seen.last.queryParameters['preset'], 'custom');
    expect(seen.last.queryParameters['from'], '2025-04-01T00:00:00.000Z');
    expect(seen.last.queryParameters['to'], '2025-04-07T23:59:59.000Z');
    await api.export('campaign', 'pdf', query: {
      'preset': '30days',
      'search': 'Kano',
      'status': 'ACTIVE',
    });
    expect(seen.last.path, endsWith('/admin/marketing/export/campaign'));
    expect(seen.last.queryParameters['format'], 'pdf');
    expect(seen.last.queryParameters['preset'], '30days');
    expect(seen.last.queryParameters['search'], 'Kano');
    expect(seen.last.queryParameters['status'], 'ACTIVE');
    api.close();
  });

  test('asset upload omits forbidden multipart fields', () async {
    String? body;
    final api = MarketingApi(
      client: MockClient((request) async {
        body = request.body;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'_id': 'asset-1'}
          }),
          201,
        );
      }),
    );
    await api.uploadAsset('proof.png', 'image/png', Uint8List.fromList([1, 2]),
        idempotencyKey: 'upload-fixture');
    expect(body, isNot(contains('name="mime"')));
    expect(body, contains('name="file"'));
    api.close();
  });

  test('performance archive and ranking policy use authenticated routes', () async {
    final calls = <http.Request>[];
    final api = MarketingApi(
      client: MockClient((request) async {
        calls.add(request);
        return http.Response(
          jsonEncode({
            'success': true,
            'data': request.method == 'GET'
                ? {'items': [], 'total': 0, 'revision': 4}
                : {'revision': 5}
          }),
          200,
        );
      }),
    );
    await api.performanceArchive(
      kind: 'report',
      period: 'YEARLY',
      status: 'REJECTED',
      search: 'Kano',
      page: 2,
      archived: false,
    );
    await api.updateRankingPolicy({
      'revision': 4,
      'reason': 'Quarterly methodology review',
      'weights': {
        'achievement': 40,
        'acquisitions': 15,
        'firstTransactions': 15,
        'tasks': 10,
        'reportCompliance': 10,
        'campaigns': 10,
      },
    });
    expect(calls.first.url.path, endsWith('/performance/archive'));
    expect(calls.first.url.queryParameters['period'], 'YEARLY');
    expect(calls.first.url.queryParameters['archived'], 'false');
    expect(calls.last.method, 'PATCH');
    expect(calls.last.url.path, endsWith('/performance/ranking-policy'));
    expect(jsonDecode(calls.last.body)['revision'], 4);
    api.close();
  });
}
