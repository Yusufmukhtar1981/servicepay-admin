import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/commission/profit_sharing_api.dart';
import 'package:servicepay_app/admin/commission/profit_sharing_settings_screen.dart';

Map<String, dynamic> settings({
  List<Map<String, dynamic>> items = const <Map<String, dynamic>>[],
  bool canManage = true,
}) =>
    <String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'canManage': canManage,
        'distributionLive': false,
        'readinessMessage': 'Settlement is not enabled for this environment.',
        'services': <String>['AIRTIME', 'DATA'],
        'roles': <String>['AGGREGATOR', 'STATE_MANAGER', 'ZONAL_MANAGER'],
        'allocationSuggestion': <String, dynamic>{
          'AGGREGATOR': 40,
          'STATE_MANAGER': 35,
          'ZONAL_MANAGER': 25,
        },
        'items': items,
      },
    };

Map<String, dynamic> version({Map<String, dynamic>? percentages}) =>
    <String, dynamic>{
      'id': 'v3',
      'serviceType': 'AIRTIME',
      'policyVersion': 2,
      'poolPercentage': 12.5,
      'enabled': true,
      'effectiveAt': '2030-04-12T09:00:00.000Z',
      'percentages': percentages ??
          <String, dynamic>{
            'AGGREGATOR': 40,
            'STATE_MANAGER': 35,
            'ZONAL_MANAGER': 25,
          },
      'createdAt': '2029-01-01T12:00:00.000Z',
      'createdBy': 'admin@servicepay.ng',
      'reason': 'Approved distribution update',
    };

Map<String, dynamic> engine() => <String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'mode': 'BLOCKED',
        'distributionLive': false,
        'revision': 4,
        'ready': false,
        'storageBlockers': <String>[
          'Settlement is not enabled for this environment.',
        ],
        'services': <Map<String, dynamic>>[
          <String, dynamic>{
            'serviceType': 'AIRTIME',
            'ruleId': 'airtime-rule-4',
            'blockers': <String>[],
          },
          <String, dynamic>{
            'serviceType': 'DATA',
            'ruleId': 'data-rule-4',
            'blockers': <String>[],
          },
        ],
      },
    };

http.Response _settingsOrEngine(
  http.Request request, {
  required Map<String, dynamic> settingsResponse,
}) =>
    http.Response(
      jsonEncode(
        request.url.path.endsWith('/engine') ? engine() : settingsResponse,
      ),
      200,
    );

Future<void> _scrollTo(
  WidgetTester tester,
  Finder target, {
  double delta = 220,
}) async {
  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(
    tester.element(target.first),
    alignment: 0.35,
    duration: Duration.zero,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('new service percentages are blank and readiness is prominent',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(
        tokenProvider: () async => 'test-token',
        client: MockClient((http.Request request) async =>
            _settingsOrEngine(request, settingsResponse: settings())),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Distribution is not live'), findsOneWidget);
    expect(find.text('Settlement is not enabled for this environment.'), findsOneWidget);
    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('percentage-AGGREGATOR')),
    );
    for (final String role in <String>[
      'AGGREGATOR',
      'STATE_MANAGER',
      'ZONAL_MANAGER',
    ]) {
      final TextField field = tester.widget<TextField>(find.byKey(ValueKey<String>('percentage-$role')));
      expect(field.controller!.text, isEmpty);
    }
    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('profit-sharing-pool-percentage')),
      delta: -250,
    );
    expect(tester.widget<TextField>(find.byKey(
      const ValueKey<String>('profit-sharing-pool-percentage'),
    )).controller!.text, isEmpty);
    await _scrollTo(
      tester,
      find.textContaining('Head Office is the controller'),
    );
    expect(find.textContaining('Head Office is the controller'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(find.text('No saved rule for this service yet. Percentages are intentionally blank.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validates missing percentages and audit reason before confirmation',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(
        tokenProvider: () async => 'test-token',
        client: MockClient((http.Request request) async =>
            _settingsOrEngine(request, settingsResponse: settings())),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save rule'));
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(find.text('Set the percentage of verified net profit assigned to the pool.'), findsOneWidget);
    expect(find.text('Review future rule'), findsNothing);
  });

  testWidgets('rejects allocations that do not total exactly 100 percent',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(
        tokenProvider: () async => 'test-token',
        client: MockClient((http.Request request) async =>
            _settingsOrEngine(request, settingsResponse: settings())),
      ),
    ));
    await tester.pumpAndSettle();
    final Finder suggestion = find.byKey(
      const ValueKey<String>('profit-sharing-use-allocation-suggestion'),
    );
    await _scrollTo(
      tester,
      suggestion,
    );
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    final Finder zonal = find.byKey(
      const ValueKey<String>('percentage-ZONAL_MANAGER'),
    );
    await _scrollTo(
      tester,
      zonal,
    );
    await tester.enterText(zonal, '24');
    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('profit-sharing-pool-percentage')),
      delta: -150,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profit-sharing-pool-percentage')),
      '12.5',
    );
    await tester.drag(find.byType(ListView), const Offset(0, -1600));
    await tester.pumpAndSettle();
    await _scrollTo(
      tester,
      find.text('Save rule'),
    );
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(find.text('Review future rule'), findsNothing);
  });

  testWidgets('loads v2 saved values and preserves audit version history',
      (WidgetTester tester) async {
    final Map<String, dynamic> loaded = settings(items: <Map<String, dynamic>>[
      <String, dynamic>{
        'serviceType': 'AIRTIME',
        'revision': 7,
        'versions': <Map<String, dynamic>>[version()],
      },
    ]);
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(
        tokenProvider: () async => 'test-token',
        client: MockClient((http.Request request) async =>
            _settingsOrEngine(request, settingsResponse: loaded)),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pumpAndSettle();
    final TextField aggregator = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('percentage-AGGREGATOR')),
    );
    expect(aggregator.controller!.text, '40');
    expect(tester.widget<TextField>(find.byKey(
      const ValueKey<String>('profit-sharing-pool-percentage'),
    )).controller!.text, '12.5');
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('Approved distribution update'), findsOneWidget);
    expect(find.text('Pool: 12.5% of verified positive net profit · policy v2'), findsOneWidget);
    expect(find.text('Aggregator: 40%'), findsOneWidget);
  });

  testWidgets('legacy allocations stay hidden while history metadata is preserved',
      (WidgetTester tester) async {
    final Map<String, dynamic> legacy = version()
      ..remove('policyVersion')
      ..remove('poolPercentage');
    legacy['percentages'] = <String, dynamic>{
      'BUSINESS_NETWORK_AGENT': 20,
      'AGGREGATOR': 20,
      'STATE_MANAGER': 20,
      'ZONAL_MANAGER': 20,
      'HEAD_OFFICE': 20,
    };
    final Map<String, dynamic> loaded = settings(items: <Map<String, dynamic>>[
      <String, dynamic>{
        'serviceType': 'AIRTIME',
        'revision': 7,
        'versions': <Map<String, dynamic>>[legacy],
      },
    ]);
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(
        tokenProvider: () async => 'test-token',
        client: MockClient((http.Request request) async =>
            _settingsOrEngine(request, settingsResponse: loaded)),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.textContaining('Legacy rule:'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(
      const ValueKey<String>('percentage-AGGREGATOR'),
    )).controller!.text, isEmpty);
    expect(tester.widget<TextField>(find.byKey(
      const ValueKey<String>('profit-sharing-pool-percentage'),
    )).controller!.text, isEmpty);
    await tester.drag(find.byType(ListView), const Offset(0, -2800));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.textContaining('Legacy version — preserved as recorded'), findsOneWidget);
    expect(find.textContaining('BUSINESS_NETWORK_AGENT'), findsNothing);
    expect(find.textContaining('HEAD_OFFICE'), findsNothing);
    expect(find.textContaining(': 20%'), findsNothing);
    expect(find.textContaining('Effective 2030-04-12T09:00:00.000Z'), findsOneWidget);
    expect(find.text('Approved distribution update'), findsOneWidget);
  });

  testWidgets('confirmation sends exact future rule contract',
      (WidgetTester tester) async {
    final List<http.Request> requests = <http.Request>[];
    int postCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(
        tokenProvider: () async => 'Bearer test-token',
        client: MockClient((http.Request request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return _settingsOrEngine(
              request,
              settingsResponse: settings(),
            );
          }
          postCount++;
          if (postCount == 1) return http.Response('{}', 200);
          return http.Response(jsonEncode(<String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'serviceType': 'AIRTIME',
              'revision': 1,
              'versions': <Map<String, dynamic>>[version()],
              'replayed': false,
            },
          }), 200);
        }),
      ),
    ));
    await tester.pumpAndSettle();
    final Finder suggestion = find.byKey(
      const ValueKey<String>('profit-sharing-use-allocation-suggestion'),
    );
    await _scrollTo(
      tester,
      suggestion,
    );
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('profit-sharing-pool-percentage')),
      delta: -150,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profit-sharing-pool-percentage')),
      '12.5',
    );
    final Finder reason = find.byKey(
      const ValueKey<String>('profit-sharing-audit-reason'),
    );
    await _scrollTo(tester, reason);
    await tester.enterText(reason, 'Approved annual service margin');
    await _scrollTo(
      tester,
      find.text('Choose future date and time'),
      delta: -250,
    );
    await tester.tap(find.text('Choose future date and time'));
    await tester.pumpAndSettle();
    // Date picker initially selects a date in the future.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    await _scrollTo(
      tester,
      find.text('Save rule'),
    );
    await tester.ensureVisible(find.text('Save rule'));
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(find.text('Review future rule'), findsOneWidget);
    await tester.tap(find.text('Confirm save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Outcome is unknown'), findsOneWidget);
    expect(find.text('Retry same request'), findsOneWidget);
    final http.Request firstPost = requests.last;
    final Map<String, dynamic> firstBody =
        jsonDecode(firstPost.body) as Map<String, dynamic>;
    await tester.tap(find.text('Retry same request'));
    await tester.pumpAndSettle();
    expect(
      requests.where((http.Request request) => request.method == 'POST'),
      hasLength(2),
    );
    expect(jsonDecode(requests.last.body), firstBody);
    final http.Request post = firstPost;
    expect(post.method, 'POST');
    expect(post.url.path, '/api/admin/product-commissions/profit-sharing');
    expect(post.headers['authorization'], 'Bearer test-token');
    final Map<String, dynamic> body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['serviceType'], 'AIRTIME');
    expect(body['revision'], 0);
    expect(body['confirmation'], true);
    expect(body['reason'], 'Approved annual service margin');
    expect(DateTime.parse(body['effectiveAt'] as String).isAfter(DateTime.now()), isTrue);
    expect(body['percentages'], <String, dynamic>{
      'AGGREGATOR': 40,
      'STATE_MANAGER': 35,
      'ZONAL_MANAGER': 25,
    });
    expect(body['poolPercentage'], 12.5);
    expect(body.containsKey('policyVersion'), isFalse);
    expect(body['idempotencyKey'], isNotEmpty);
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.text('Distribution is not live'), findsOneWidget);
    expect(
      requests.where((http.Request request) =>
          request.url.path.endsWith('/activation')),
      isEmpty,
    );
  });

  test('save API rejects malformed HTTP 200 and surfaces 403/409 statuses',
      () async {
    for (final int status in <int>[200, 403, 409]) {
      final ProfitSharingApi api = ProfitSharingApi(
        baseUrl: 'https://servicepay.test/api',
        tokenProvider: () async => 'test-token',
        client: MockClient((http.Request request) async {
          if (status == 200) return http.Response('{}', status);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': false,
              'message': 'Rejected for review.',
            }),
            status,
          );
        }),
      );
      try {
        await api.saveRule(<String, dynamic>{
          'serviceType': 'AIRTIME',
          'poolPercentage': 12.5,
          'percentages': <String, num>{
            'AGGREGATOR': 40,
            'STATE_MANAGER': 35,
            'ZONAL_MANAGER': 25,
          },
        });
        fail('Expected HTTP $status to be rejected.');
      } on ProfitSharingApiException catch (error) {
        expect(error.statusCode, status);
        if (status == 403) expect(error.isForbidden, isTrue);
        if (status == 409) expect(error.isConflict, isTrue);
      }
    }
  });

  test('save API accepts immutable legacy history beside a v2 version',
      () async {
    final Map<String, dynamic> legacy = version()
      ..remove('policyVersion')
      ..remove('poolPercentage');
    legacy['percentages'] = <String, dynamic>{
      'BUSINESS_NETWORK_AGENT': 20,
      'AGGREGATOR': 20,
      'STATE_MANAGER': 20,
      'ZONAL_MANAGER': 20,
      'HEAD_OFFICE': 20,
    };
    final ProfitSharingApi api = ProfitSharingApi(
      baseUrl: 'https://servicepay.test/api',
      tokenProvider: () async => 'test-token',
      client: MockClient((http.Request request) async => http.Response(
        jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{
            'serviceType': 'AIRTIME',
            'revision': 8,
            'versions': <Map<String, dynamic>>[version(), legacy],
            'replayed': false,
          },
        }),
        200,
      )),
    );
    addTearDown(api.close);
    final Map<String, dynamic> result = await api.saveRule(<String, dynamic>{
      'serviceType': 'AIRTIME',
      'poolPercentage': 12.5,
      'percentages': <String, num>{
        'AGGREGATOR': 40,
        'STATE_MANAGER': 35,
        'ZONAL_MANAGER': 25,
      },
    });
    final List versions = (result['data'] as Map)['versions'] as List;
    expect(versions, hasLength(2));
    expect((versions[1] as Map)['percentages'], contains('BUSINESS_NETWORK_AGENT'));
    expect((versions[1] as Map).containsKey('poolPercentage'), isFalse);
  });

  test('save API rejects an unset or over-precision pool before sending',
      () async {
    int requestCount = 0;
    final ProfitSharingApi api = ProfitSharingApi(
      baseUrl: 'https://servicepay.test/api',
      tokenProvider: () async => 'test-token',
      client: MockClient((http.Request request) async {
        requestCount++;
        return http.Response('{}', 500);
      }),
    );
    addTearDown(api.close);
    final Map<String, dynamic> valid = <String, dynamic>{
      'serviceType': 'AIRTIME',
      'poolPercentage': 10.25,
      'percentages': <String, num>{
        'AGGREGATOR': 40,
        'STATE_MANAGER': 35,
        'ZONAL_MANAGER': 25,
      },
    };
    for (final dynamic pool in <dynamic>[null, -0.01, 100.01, 12.345]) {
      final Map<String, dynamic> payload = Map<String, dynamic>.from(valid)
        ..['poolPercentage'] = pool;
      await expectLater(
        api.saveRule(payload),
        throwsA(isA<ProfitSharingApiException>()),
      );
    }
    expect(requestCount, 0);
  });

  testWidgets('layout remains scrollable and unconstrained at phone width',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(
        tokenProvider: () async => 'test-token',
        client: MockClient((http.Request request) async =>
            _settingsOrEngine(request, settingsResponse: settings())),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Version history'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Version history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
