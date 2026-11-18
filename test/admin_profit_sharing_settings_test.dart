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
        'policyVersion': 3,
        'roles': <String>[
          'HEAD_OFFICE',
          'ZONAL_MANAGER',
          'STATE_MANAGER',
          'AGGREGATOR',
        ],
        'items': items,
      },
    };

Map<String, dynamic> version({Map<String, dynamic>? percentages}) =>
    <String, dynamic>{
      'id': 'v3',
      'serviceType': 'AIRTIME',
      'policyVersion': 3,
      'previousPercentages': <String, dynamic>{
        'HEAD_OFFICE': 35,
        'ZONAL_MANAGER': 25,
        'STATE_MANAGER': 20,
        'AGGREGATOR': 20,
      },
      'enabled': true,
      'effectiveAt': '2030-04-12T09:00:00.000Z',
      'percentages': percentages ??
          <String, dynamic>{
            'HEAD_OFFICE': 38,
            'ZONAL_MANAGER': 27,
            'STATE_MANAGER': 21,
            'AGGREGATOR': 14,
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
  testWidgets('new configuration has four blank fields and no presets',
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
    expect(find.text('Company Profit Sharing Configuration'), findsOneWidget);
    expect(find.text('Distribution is not live'), findsOneWidget);
    expect(find.text('Settlement is not enabled for this environment.'), findsOneWidget);
    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('percentage-HEAD_OFFICE')),
    );
    for (final String role in <String>[
      'HEAD_OFFICE',
      'ZONAL_MANAGER',
      'STATE_MANAGER',
      'AGGREGATOR',
    ]) {
      final TextField field = tester.widget<TextField>(find.byKey(ValueKey<String>('percentage-$role')));
      expect(field.controller!.text, isEmpty);
    }
    expect(find.text('Head Office Percentage'), findsOneWidget);
    expect(find.text('Zonal Managers Percentage'), findsOneWidget);
    expect(find.text('State Managers Percentage'), findsOneWidget);
    expect(find.text('Aggregators Percentage'), findsOneWidget);
    expect(find.text('Remaining unallocated: 100.00%'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('profit-sharing-use-allocation-suggestion')), findsNothing);
    expect(find.byKey(const ValueKey<String>('profit-sharing-pool-percentage')), findsNothing);
    expect(find.textContaining('40 / 35 / 25'), findsNothing);
    await _scrollTo(
      tester,
      find.text('No saved rule for this service yet. Percentages are intentionally blank.'),
    );
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
    expect(
      find.text('Set all four beneficiary percentages explicitly. Zero is allowed.'),
      findsOneWidget,
    );
    expect(find.text('Review future rule'), findsNothing);
  });

  testWidgets('explicit zero rate is accepted when the four rates total 100',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(
        tokenProvider: () async => 'test-token',
        client: MockClient((http.Request request) async =>
            _settingsOrEngine(request, settingsResponse: settings())),
      ),
    ));
    await tester.pumpAndSettle();
    for (final MapEntry<String, String> rate in <MapEntry<String, String>>[
      const MapEntry<String, String>('HEAD_OFFICE', '0'),
      const MapEntry<String, String>('ZONAL_MANAGER', '30'),
      const MapEntry<String, String>('STATE_MANAGER', '30'),
      const MapEntry<String, String>('AGGREGATOR', '40'),
    ]) {
      final Finder field = find.byKey(ValueKey<String>('percentage-${rate.key}'));
      await _scrollTo(tester, field);
      await tester.enterText(field, rate.value);
    }
    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('profit-sharing-remaining-percentage')),
    );
    expect(find.text('Remaining unallocated: 0.00%'), findsOneWidget);
    await _scrollTo(tester, find.text('Save rule'));
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a future date and time for this rule.'), findsOneWidget);
    expect(find.text('The four beneficiary percentages must add up to exactly 100%.'), findsNothing);
  });

  testWidgets('decimal rates report zero remaining without negative zero',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(
        tokenProvider: () async => 'test-token',
        client: MockClient((http.Request request) async =>
            _settingsOrEngine(request, settingsResponse: settings())),
      ),
    ));
    await tester.pumpAndSettle();
    for (final MapEntry<String, String> rate in <MapEntry<String, String>>[
      const MapEntry<String, String>('HEAD_OFFICE', '0.29'),
      const MapEntry<String, String>('ZONAL_MANAGER', '25.71'),
      const MapEntry<String, String>('STATE_MANAGER', '38'),
      const MapEntry<String, String>('AGGREGATOR', '36'),
    ]) {
      final Finder field = find.byKey(ValueKey<String>('percentage-${rate.key}'));
      await _scrollTo(tester, field);
      await tester.enterText(field, rate.value);
    }
    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('profit-sharing-remaining-percentage')),
    );
    expect(find.text('Remaining unallocated: 0.00%'), findsOneWidget);
    expect(find.textContaining('-0.00%'), findsNothing);
    await _scrollTo(tester, find.text('Save rule'));
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a future date and time for this rule.'), findsOneWidget);
  });

  testWidgets('remaining percentage updates and non-100 rates cannot save',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(
        tokenProvider: () async => 'test-token',
        client: MockClient((http.Request request) async =>
            _settingsOrEngine(request, settingsResponse: settings())),
      ),
    ));
    await tester.pumpAndSettle();
    for (final MapEntry<String, String> rate in <MapEntry<String, String>>[
      const MapEntry<String, String>('HEAD_OFFICE', '38'),
      const MapEntry<String, String>('ZONAL_MANAGER', '27'),
      const MapEntry<String, String>('STATE_MANAGER', '21'),
      const MapEntry<String, String>('AGGREGATOR', '13'),
    ]) {
      final Finder field = find.byKey(ValueKey<String>('percentage-${rate.key}'));
      await _scrollTo(tester, field);
      await tester.enterText(field, rate.value);
    }
    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('profit-sharing-remaining-percentage')),
    );
    expect(find.text('Remaining unallocated: 1.00%'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1600));
    await tester.pumpAndSettle();
    await _scrollTo(
      tester,
      find.text('Save rule'),
    );
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(
      find.text('The four beneficiary percentages must add up to exactly 100%.'),
      findsOneWidget,
    );
    expect(find.text('Review future rule'), findsNothing);
  });

  testWidgets('loads v3 values and shows previous/new audit configurations',
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
    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('percentage-HEAD_OFFICE')),
    );
    expect(tester.widget<TextField>(find.byKey(
      const ValueKey<String>('percentage-HEAD_OFFICE'),
    )).controller!.text, '38');
    expect(tester.widget<TextField>(find.byKey(
      const ValueKey<String>('percentage-ZONAL_MANAGER'),
    )).controller!.text, '27');
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('Approved distribution update'), findsOneWidget);
    expect(find.text('Policy v3 · 100% of verified positive company net profit'), findsOneWidget);
    expect(find.text('New configuration'), findsOneWidget);
    expect(find.text('Head Office: 38%'), findsOneWidget);
    expect(find.text('Zonal Managers: 27%'), findsOneWidget);
    expect(find.text('State Managers: 21%'), findsOneWidget);
    expect(find.text('Aggregator: 14%'), findsOneWidget);
    expect(find.text('Previous configuration'), findsOneWidget);
    expect(find.text('Head Office: 35%'), findsOneWidget);
    expect(find.text('Zonal Managers: 25%'), findsOneWidget);
    expect(find.text('Recorded 2029-01-01T12:00:00.000Z · admin@servicepay.ng'), findsOneWidget);
  });

  testWidgets('legacy allocations stay hidden while history metadata is preserved',
      (WidgetTester tester) async {
    final Map<String, dynamic> legacy = version()
      ..remove('policyVersion')
      ..remove('previousPercentages');
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
    for (final String role in <String>[
      'HEAD_OFFICE',
      'ZONAL_MANAGER',
      'STATE_MANAGER',
      'AGGREGATOR',
    ]) {
      expect(
        tester.widget<TextField>(
          find.byKey(ValueKey<String>('percentage-$role')),
        ).controller!.text,
        isEmpty,
      );
    }
    await _scrollTo(
      tester,
      find.textContaining('Legacy version — preserved as recorded'),
    );
    expect(find.textContaining('Legacy version — preserved as recorded'), findsOneWidget);
    expect(find.textContaining('BUSINESS_NETWORK_AGENT'), findsNothing);
    expect(find.textContaining(': 20%'), findsNothing);
    expect(find.text('Head Office: 20%'), findsNothing);
    expect(find.text('Zonal Managers: 20%'), findsNothing);
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
    for (final MapEntry<String, String> rate in <MapEntry<String, String>>[
      const MapEntry<String, String>('HEAD_OFFICE', '38'),
      const MapEntry<String, String>('ZONAL_MANAGER', '27'),
      const MapEntry<String, String>('STATE_MANAGER', '21'),
      const MapEntry<String, String>('AGGREGATOR', '14'),
    ]) {
      final Finder field = find.byKey(ValueKey<String>('percentage-${rate.key}'));
      await _scrollTo(tester, field);
      await tester.enterText(field, rate.value);
    }
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
    final http.Request firstPost =
        requests.lastWhere((http.Request request) => request.method == 'POST');
    final Map<String, dynamic> firstBody =
        jsonDecode(firstPost.body) as Map<String, dynamic>;
    await tester.tap(find.text('Retry same request'));
    await tester.pumpAndSettle();
    expect(
      requests.where((http.Request request) => request.method == 'POST'),
      hasLength(2),
    );
    expect(
      jsonDecode(requests.lastWhere(
        (http.Request request) => request.method == 'POST',
      ).body),
      firstBody,
    );
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
      'HEAD_OFFICE': 38,
      'ZONAL_MANAGER': 27,
      'STATE_MANAGER': 21,
      'AGGREGATOR': 14,
    });
    expect(body.containsKey('policyVersion'), isFalse);
    expect(body.containsKey('poolPercentage'), isFalse);
    expect(
      body['percentages'].keys,
      orderedEquals(<String>[
        'HEAD_OFFICE',
        'ZONAL_MANAGER',
        'STATE_MANAGER',
        'AGGREGATOR',
      ]),
    );
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
          'percentages': <String, num>{
            'HEAD_OFFICE': 38,
            'ZONAL_MANAGER': 27,
            'STATE_MANAGER': 21,
            'AGGREGATOR': 14,
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

  test('save API accepts immutable legacy history beside a v3 version',
      () async {
    final Map<String, dynamic> legacy = version()
      ..remove('policyVersion')
      ..remove('previousPercentages');
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
      'percentages': <String, num>{
        'HEAD_OFFICE': 38,
        'ZONAL_MANAGER': 27,
        'STATE_MANAGER': 21,
        'AGGREGATOR': 14,
      },
    });
    final List versions = (result['data'] as Map)['versions'] as List;
    expect(versions, hasLength(2));
    expect((versions[1] as Map)['percentages'], contains('BUSINESS_NETWORK_AGENT'));
    expect((versions[1] as Map).containsKey('policyVersion'), isFalse);
  });

  test('save API rejects missing, extra, over-precision and non-total roles',
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
      'percentages': <String, num>{
        'HEAD_OFFICE': 38,
        'ZONAL_MANAGER': 27,
        'STATE_MANAGER': 21,
        'AGGREGATOR': 14,
      },
    };
    final List<Map<String, dynamic>> invalidPayloads = <Map<String, dynamic>>[
      <String, dynamic>{
        ...valid,
        'percentages': <String, num>{
          'HEAD_OFFICE': 38,
          'ZONAL_MANAGER': 27,
          'STATE_MANAGER': 35,
        },
      },
      <String, dynamic>{
        ...valid,
        'percentages': <String, num>{
          ...(valid['percentages'] as Map<String, num>),
          'BUSINESS_NETWORK_AGENT': 0,
        },
      },
      <String, dynamic>{
        ...valid,
        'percentages': <String, num>{
          'HEAD_OFFICE': 38.001,
          'ZONAL_MANAGER': 27,
          'STATE_MANAGER': 21,
          'AGGREGATOR': 13.999,
        },
      },
      <String, dynamic>{
        ...valid,
        'percentages': <String, num>{
          'HEAD_OFFICE': 38,
          'ZONAL_MANAGER': 27,
          'STATE_MANAGER': 21,
          'AGGREGATOR': 13,
        },
      },
    ];
    for (final Map<String, dynamic> payload in invalidPayloads) {
      await expectLater(
        api.saveRule(payload),
        throwsA(isA<ProfitSharingApiException>()),
      );
    }
    expect(requestCount, 0);
  });

  test('save API permits explicit zero and sends only policy v3 rates',
      () async {
    late http.Request sentRequest;
    final Map<String, dynamic> zeroRateVersion = version(
      percentages: <String, dynamic>{
        'HEAD_OFFICE': 0,
        'ZONAL_MANAGER': 30,
        'STATE_MANAGER': 30,
        'AGGREGATOR': 40,
      },
    );
    zeroRateVersion['previousPercentages'] = null;
    final ProfitSharingApi api = ProfitSharingApi(
      baseUrl: 'https://servicepay.test/api',
      tokenProvider: () async => 'test-token',
      client: MockClient((http.Request request) async {
        sentRequest = request;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'serviceType': 'AIRTIME',
              'revision': 9,
              'versions': <Map<String, dynamic>>[zeroRateVersion],
              'replayed': false,
            },
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);
    await api.saveRule(<String, dynamic>{
      'serviceType': 'AIRTIME',
      'percentages': <String, num>{
        'HEAD_OFFICE': 0,
        'ZONAL_MANAGER': 30,
        'STATE_MANAGER': 30,
        'AGGREGATOR': 40,
      },
      'poolPercentage': 99,
      'policyVersion': 2,
    });
    final Map<String, dynamic> body =
        jsonDecode(sentRequest.body) as Map<String, dynamic>;
    expect(body['percentages']['HEAD_OFFICE'], 0);
    expect(body.containsKey('poolPercentage'), isFalse);
    expect(body.containsKey('policyVersion'), isFalse);
  });

  test('save API accepts decimal rates with backend-shaped v3 history',
      () async {
    const Map<String, num> decimalRates = <String, num>{
      'HEAD_OFFICE': 0.29,
      'ZONAL_MANAGER': 25.71,
      'STATE_MANAGER': 38,
      'AGGREGATOR': 36,
    };
    final Map<String, dynamic> savedVersion =
        version(percentages: decimalRates.cast<String, dynamic>())
          ..['previousPercentages'] = null;
    final ProfitSharingApi api = ProfitSharingApi(
      baseUrl: 'https://servicepay.test/api',
      tokenProvider: () async => 'test-token',
      client: MockClient((http.Request request) async => http.Response(
        jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{
            'serviceType': 'AIRTIME',
            'revision': 10,
            'versions': <Map<String, dynamic>>[savedVersion],
            'replayed': false,
          },
        }),
        200,
      )),
    );
    addTearDown(api.close);
    final Map<String, dynamic> result = await api.saveRule(<String, dynamic>{
      'serviceType': 'AIRTIME',
      'percentages': decimalRates,
    });
    expect((result['data'] as Map)['revision'], 10);
    expect(
      ((result['data'] as Map)['versions'] as List).first['previousPercentages'],
      isNull,
    );
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
