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
        'roles': <String>[
          'BUSINESS_NETWORK_AGENT',
          'AGGREGATOR',
          'STATE_MANAGER',
          'ZONAL_MANAGER',
          'HEAD_OFFICE',
        ],
        'items': items,
      },
    };

Map<String, dynamic> version({Map<String, dynamic>? percentages}) =>
    <String, dynamic>{
      'id': 'v3',
      'serviceType': 'AIRTIME',
      'enabled': true,
      'effectiveAt': '2030-04-12T09:00:00.000Z',
      'percentages': percentages ??
          <String, dynamic>{
            'BUSINESS_NETWORK_AGENT': 20,
            'AGGREGATOR': 20,
            'STATE_MANAGER': 20,
            'ZONAL_MANAGER': 20,
            'HEAD_OFFICE': 20,
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
    for (final String role in <String>[
      'BUSINESS_NETWORK_AGENT',
      'AGGREGATOR',
      'STATE_MANAGER',
      'ZONAL_MANAGER',
      'HEAD_OFFICE',
    ]) {
      final TextField field = tester.widget<TextField>(find.byKey(ValueKey<String>('percentage-$role')));
      expect(field.controller!.text, isEmpty);
    }
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
    expect(find.text('Enter a percentage for every role.'), findsOneWidget);
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
    const List<String> roles = <String>[
      'BUSINESS_NETWORK_AGENT',
      'AGGREGATOR',
      'STATE_MANAGER',
      'ZONAL_MANAGER',
      'HEAD_OFFICE',
    ];
    const List<String> amounts = <String>['20', '20', '20', '20', '19'];
    for (int index = 0; index < roles.length; index++) {
      await tester.enterText(
        find.byKey(ValueKey<String>('percentage-${roles[index]}')),
        amounts[index],
      );
    }
    await tester.drag(find.byType(ListView), const Offset(0, -1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(find.text('Percentages must add up to exactly 100%.'), findsOneWidget);
    expect(find.text('Review future rule'), findsNothing);
  });

  testWidgets('loads saved values and preserves audit version history',
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
    final TextField agent = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('percentage-BUSINESS_NETWORK_AGENT')),
    );
    expect(agent.controller!.text, '20');
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('Approved distribution update'), findsOneWidget);
    expect(find.text('Business Network Agent: 20%'), findsOneWidget);
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
    const List<String> values = <String>['20', '20', '20', '20', '20'];
    const List<String> roles = <String>[
      'BUSINESS_NETWORK_AGENT',
      'AGGREGATOR',
      'STATE_MANAGER',
      'ZONAL_MANAGER',
      'HEAD_OFFICE',
    ];
    for (int i = 0; i < roles.length; i++) {
      await tester.enterText(find.byKey(ValueKey<String>('percentage-${roles[i]}')), values[i]);
    }
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Approved annual service margin');
    await tester.tap(find.text('Choose future date and time'));
    await tester.pumpAndSettle();
    // Date picker initially selects a date in the future.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
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
      'BUSINESS_NETWORK_AGENT': 20,
      'AGGREGATOR': 20,
      'STATE_MANAGER': 20,
      'ZONAL_MANAGER': 20,
      'HEAD_OFFICE': 20,
    });
    expect(body['idempotencyKey'], isNotEmpty);
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.text('Distribution is not live'), findsOneWidget);
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
        await api.saveRule(<String, dynamic>{'serviceType': 'AIRTIME'});
        fail('Expected HTTP $status to be rejected.');
      } on ProfitSharingApiException catch (error) {
        expect(error.statusCode, status);
        if (status == 403) expect(error.isForbidden, isTrue);
        if (status == 409) expect(error.isConflict, isTrue);
      }
    }
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
    expect(find.text('Version history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
