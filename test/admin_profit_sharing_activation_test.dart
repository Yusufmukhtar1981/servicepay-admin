import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/commission/profit_sharing_api.dart';
import 'package:servicepay_app/admin/commission/profit_sharing_activation_panel.dart';
import 'package:servicepay_app/admin/commission/profit_sharing_settings_screen.dart';

Map<String, dynamic> _settings({
  List<String> services = const <String>['AIRTIME'],
}) =>
    <String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'canManage': true,
        'distributionLive': true,
        'services': services,
        'items': <Map<String, dynamic>>[],
      },
    };

Map<String, dynamic> _engine({
  String mode = 'PAUSED',
  bool ready = true,
  bool live = false,
  List<String> serviceBlockers = const <String>[],
  List<String> storageBlockers = const <String>[],
  List<Map<String, dynamic>>? services,
}) =>
    <String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'mode': mode,
        'distributionLive': live,
        'revision': 12,
        'ready': ready,
        'storageBlockers': storageBlockers,
        'services': services ??
            <Map<String, dynamic>>[
          <String, dynamic>{
            'serviceType': 'AIRTIME',
            'ruleId': 'rule-airtime-12',
            'blockers': serviceBlockers,
          },
        ],
      },
    };

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    220,
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
  testWidgets('global pause scope is explicit and requires confirmation before sending',
      (WidgetTester tester) async {
    final List<http.Request> requests = <http.Request>[];
    int refreshes = 0;
    final ProfitSharingApi api = ProfitSharingApi(
      baseUrl: 'https://servicepay.test/api',
      tokenProvider: () async => 'session-token',
      client: MockClient((http.Request request) async {
        requests.add(request);
        return http.Response(jsonEncode(<String, dynamic>{
          'success': true, 'data': <String, dynamic>{'mode': 'PAUSED', 'revision': 13},
        }), 200);
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: ProfitSharingActivationPanel(
        api: api, engine: _engine(mode: 'LIVE', live: true)['data'] as Map<String, dynamic>,
        service: 'AIRTIME', canManage: true, refreshStatus: () async { refreshes++; },
      ),
    ))));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const ValueKey<String>('profit-sharing-expand-controls')));
    await tester.tap(find.byKey(const ValueKey<String>('profit-sharing-expand-controls')));
    await tester.pumpAndSettle();
    for (final entry in <String, String>{
      'profit-sharing-activation-reason': 'Stop new admissions for safety',
      'profit-sharing-current-password': 'synthetic-current-password',
    }.entries) {
      final Finder field = find.byKey(ValueKey<String>(entry.key));
      await _scrollTo(tester, field); await tester.enterText(field, entry.value);
    }
    final Finder pause = find.text('Pause all future admissions');
    await _scrollTo(tester, pause); await tester.tap(pause); await tester.pumpAndSettle();
    expect(find.textContaining('all active services'), findsOneWidget);
    expect(find.textContaining('Already admitted settlements and refunds'), findsOneWidget);
    expect(requests, isEmpty);
    await tester.tap(find.text('Confirm pause')); await tester.pumpAndSettle();
    expect(requests, hasLength(1)); expect(refreshes, 1);
    expect((jsonDecode(requests.single.body) as Map)['mode'], 'PAUSED');
    final TextField password = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('profit-sharing-current-password')));
    expect(password.controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });
  test('engine and dry-run use authenticated scoped endpoints and safe body', () async {
    final List<http.Request> requests = <http.Request>[];
    final ProfitSharingApi api = ProfitSharingApi(
      baseUrl: 'https://servicepay.test/api',
      tokenProvider: () async => 'session-token',
      client: MockClient((http.Request request) async {
        requests.add(request);
        if (request.url.path.endsWith('/engine')) {
          return http.Response(jsonEncode(_engine()), 200);
        }
        if (request.url.path.endsWith('/dry-run')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'id': 'dry-run-1',
                'plan': <String, dynamic>{'eligible': true, 'poolKobo': 12500},
                'serviceType': 'AIRTIME',
                'ruleId': 'rule-airtime-12',
                'adapterVersion': 'test-v1',
                'financialWrites': 0,
              },
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    try {
      await api.getEngine();
      await api.dryRun('0123456789abcdef01234567');
      expect(requests.map((http.Request request) => request.url.path), <String>[
        '/api/admin/product-commissions/profit-sharing/engine',
        '/api/admin/product-commissions/profit-sharing/dry-run',
      ]);
      expect(requests.every((http.Request request) =>
          request.headers['authorization'] == 'Bearer session-token'), isTrue);
      expect(requests[1].method, 'POST');
      expect(jsonDecode(requests[1].body), <String, dynamic>{
        'transactionId': '0123456789abcdef01234567',
      });
      expect((jsonDecode(requests[1].body) as Map).keys,
          unorderedEquals(<String>['transactionId']));
      expect(
        () => api.dryRun('not-an-id'),
        throwsA(isA<ProfitSharingApiException>()),
      );
    } finally {
      api.close();
    }
  });

  testWidgets('backend status controls live label and blockers remain visible',
      (WidgetTester tester) async {
    final List<String> requestedPaths = <String>[];
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(
        tokenProvider: () async => 'session-token',
        client: MockClient((http.Request request) async {
          requestedPaths.add(request.url.path);
          if (request.url.path.endsWith('/engine')) {
            return http.Response(
              jsonEncode(_engine(
                mode: 'PAUSED',
                ready: false,
                live: false,
                storageBlockers: <String>['Ledger write path unavailable.'],
                serviceBlockers: <String>['Production adapter is not registered.'],
              )),
              200,
            );
          }
          return http.Response(jsonEncode(_settings()), 200);
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Distribution is not live'), findsOneWidget);
    expect(find.text('Distribution is LIVE'), findsNothing);
    final Finder selectedBlocker =
        find.text('AIRTIME: Production adapter is not registered.');
    await _scrollTo(tester, selectedBlocker);
    expect(selectedBlocker, findsOneWidget);
    final Finder storageBlocker =
        find.text('Ledger write path unavailable.');
    await _scrollTo(tester, storageBlocker);
    expect(storageBlocker, findsOneWidget);
    final Finder controls = find.byKey(
      const ValueKey<String>('profit-sharing-expand-controls'),
    );
    await _scrollTo(tester, controls);
    await tester.tap(controls);
    await tester.pumpAndSettle();
    final Finder activateLabel =
        find.text('Activate future profit sharing');
    await _scrollTo(tester, activateLabel);
    final FilledButton activate =
        tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('profit-sharing-activate')),
    );
    expect(activate.onPressed, isNull);
    expect(requestedPaths.any((String path) => path.endsWith('/engine')), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activation requires eligible dry-run and sends one-service confirmation',
      (WidgetTester tester) async {
    final List<http.Request> requests = <http.Request>[];
    bool live = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(
        tokenProvider: () async => 'session-token',
        client: MockClient((http.Request request) async {
          requests.add(request);
          if (request.url.path.endsWith('/engine')) {
            return http.Response(jsonEncode(_engine(live: live, mode: live ? 'LIVE' : 'PAUSED')), 200);
          }
          if (request.url.path.endsWith('/dry-run')) {
            final Map<String, dynamic> body =
                jsonDecode(request.body) as Map<String, dynamic>;
            expect(body.keys, unorderedEquals(<String>['transactionId']));
            return http.Response(
              jsonEncode(<String, dynamic>{
                'success': true,
                'data': <String, dynamic>{
                  'id': 'receipt-24',
                   'plan': <String, dynamic>{
                     'eligible': true,
                     'netProfitKobo': 10000,
                     'poolKobo': 10000,
                     'headOfficeKobo': 3800,
                     'beneficiaryKobo': 6200,
                     'unallocatedKobo': 0,
                     'roundingKobo': 0,
                   },
                  'serviceType': 'AIRTIME',
                  'ruleId': 'rule-airtime-12',
                  'adapterVersion': 'test-v1',
                  'financialWrites': 0,
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/activation')) {
            live = true;
            return http.Response(jsonEncode(_engine(mode: 'LIVE', live: true)), 200);
          }
          return http.Response(jsonEncode(_settings()), 200);
        }),
      ),
    ));
    await tester.pumpAndSettle();
    final Finder controls = find.byKey(
      const ValueKey<String>('profit-sharing-expand-controls'),
    );
    await _scrollTo(tester, controls);
    await tester.tap(controls);
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Run zero-write dry-run'));
    await tester.enterText(
      find.byKey(const ValueKey<String>('profit-sharing-transaction-id')),
      '0123456789abcdef01234567',
    );
    await tester.tap(find.text('Run zero-write dry-run'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.textContaining('Eligible receipt receipt-24'));
    expect(find.textContaining('Eligible receipt receipt-24'), findsOneWidget);
    expect(find.textContaining('Verified net profit: ₦100.00'), findsOneWidget);
    expect(find.textContaining('Profit pool: ₦100.00'), findsOneWidget);
    expect(
      find.textContaining('Head Office share · company custody: ₦38.00'),
      findsOneWidget,
    );
    expect(find.textContaining('Other beneficiary shares: ₦62.00'), findsOneWidget);
    expect(find.textContaining('Unallocated commission: ₦0.00'), findsOneWidget);
    expect(find.textContaining('Company-retained profit'), findsNothing);

    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('profit-sharing-activation-reason')),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profit-sharing-activation-reason')),
      'Approved readiness review',
    );
    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('profit-sharing-current-password')),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profit-sharing-current-password')),
      'current-password',
    );
    await _scrollTo(
      tester,
      find.byKey(
        const ValueKey<String>('profit-sharing-activation-confirmation'),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profit-sharing-activation-confirmation')),
      'ACTIVATE FUTURE PROFIT SHARING',
    );
    await _scrollTo(tester, find.text('Activate future profit sharing'));
    await tester.tap(find.text('Activate future profit sharing'));
    await tester.pumpAndSettle();

    final http.Request activation = requests.firstWhere(
      (http.Request request) => request.url.path.endsWith('/activation'),
    );
    final Map<String, dynamic> body =
        jsonDecode(activation.body) as Map<String, dynamic>;
    expect(body['mode'], 'LIVE');
    expect(body['revision'], 12);
    expect(body['services'], <String>['AIRTIME']);
    expect(body['confirmation'], true);
    expect(body['confirmationText'], 'ACTIVATE FUTURE PROFIT SHARING');
    expect(body['dryRunIds'], <String, String>{'AIRTIME': 'receipt-24'});
    expect(body['reason'], 'Approved readiness review');
    expect(body['currentPassword'], 'current-password');
    await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
    await tester.pumpAndSettle();
    expect(find.text('Distribution is LIVE'), findsOneWidget);
    expect(requests.where((http.Request request) =>
        request.url.path.endsWith('/activation')), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy rule or missing pool blocker cannot be bypassed',
      (WidgetTester tester) async {
    final List<http.Request> requests = <http.Request>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProfitSharingActivationPanel(
            api: ProfitSharingApi(
              baseUrl: 'https://servicepay.test/api',
              tokenProvider: () async => 'session-token',
              client: MockClient((http.Request request) async {
                requests.add(request);
                return http.Response('{}', 500);
              }),
            ),
            engine: _engine(
              services: <Map<String, dynamic>>[
                <String, dynamic>{
                  'serviceType': 'AIRTIME',
                  'ruleId': 'legacy-rule',
                  'blockers': <String>[
                    'Current rule is legacy or has no explicit pool percentage.',
                  ],
                },
              ],
            )['data'] as Map<String, dynamic>,
            service: 'AIRTIME',
            canManage: true,
            refreshStatus: () async {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('profit-sharing-expand-controls')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('profit-sharing-expand-controls')),
    );
    await tester.pumpAndSettle();
    final Finder activate = find.byKey(
      const ValueKey<String>('profit-sharing-activate'),
    );
    await _scrollTo(tester, activate);
    expect(tester.widget<FilledButton>(activate).onPressed, isNull);
    expect(
      find.text(
        'Selected service blockers: Current rule is legacy or has no explicit pool percentage.',
      ),
      findsOneWidget,
    );
    expect(
      requests.where((http.Request request) =>
          request.url.path.endsWith('/activation')),
      isEmpty,
    );
  });

  testWidgets(
      'selected DATA can reactivate in BLOCKED mode when only AIRTIME is blocked',
      (WidgetTester tester) async {
    final List<http.Request> requests = <http.Request>[];
    bool distributionLive = false;
    final List<Map<String, dynamic>> initialServices = <Map<String, dynamic>>[
      <String, dynamic>{
        'serviceType': 'AIRTIME',
        'ruleId': 'airtime-rule',
        'blockers': <String>['Airtime adapter is not registered.'],
      },
      <String, dynamic>{
        'serviceType': 'DATA',
        'ruleId': 'data-rule',
        'blockers': <String>[],
      },
    ];
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(
        tokenProvider: () async => 'session-token',
        client: MockClient((http.Request request) async {
          requests.add(request);
          if (request.url.path.endsWith('/engine')) {
            return http.Response(
              jsonEncode(_engine(
                mode: distributionLive ? 'LIVE' : 'BLOCKED',
                live: distributionLive,
                ready: false,
                services: initialServices,
              )),
              200,
            );
          }
          if (request.url.path.endsWith('/dry-run')) {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'success': true,
                'data': <String, dynamic>{
                  'id': 'data-receipt',
                  'plan': <String, dynamic>{'eligible': true, 'poolKobo': 880},
                  'serviceType': 'DATA',
                  'ruleId': 'data-rule',
                  'adapterVersion': 'test-v1',
                  'financialWrites': 0,
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/activation')) {
            distributionLive = true;
            return http.Response(
              jsonEncode(_engine(
                mode: 'LIVE',
                live: true,
                ready: false,
                services: initialServices,
              )),
              200,
            );
          }
          return http.Response(
            jsonEncode(_settings(services: <String>['AIRTIME', 'DATA'])),
            200,
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();

    final Finder servicePicker = find.byKey(
      const ValueKey<String>('profit-sharing-service-selector'),
    );
    await _scrollTo(tester, servicePicker);
    await tester.tap(servicePicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Data').last);
    await tester.pumpAndSettle();

    final Finder controls = find.byKey(
      const ValueKey<String>('profit-sharing-expand-controls'),
    );
    await _scrollTo(tester, controls);
    await tester.tap(controls);
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Run zero-write dry-run'));
    await tester.enterText(
      find.byKey(const ValueKey<String>('profit-sharing-transaction-id')),
      '0123456789abcdef01234567',
    );
    await tester.tap(find.text('Run zero-write dry-run'));
    await tester.pumpAndSettle();

    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('profit-sharing-activation-reason')),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profit-sharing-activation-reason')),
      'Scoped DATA adapter reviewed',
    );
    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('profit-sharing-current-password')),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profit-sharing-current-password')),
      'current-password',
    );
    await _scrollTo(
      tester,
      find.byKey(
        const ValueKey<String>('profit-sharing-activation-confirmation'),
      ),
    );
    await tester.enterText(
      find.byKey(
        const ValueKey<String>('profit-sharing-activation-confirmation'),
      ),
      'ACTIVATE FUTURE PROFIT SHARING',
    );
    await _scrollTo(
      tester,
      find.byKey(const ValueKey<String>('profit-sharing-activate')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('profit-sharing-activate')),
    );
    await tester.pumpAndSettle();

    final http.Request activation = requests.firstWhere(
      (http.Request request) => request.url.path.endsWith('/activation'),
    );
    final Map<String, dynamic> body =
        jsonDecode(activation.body) as Map<String, dynamic>;
    expect(body['mode'], 'LIVE');
    expect(body['services'], <String>['DATA']);
    expect(body['dryRunIds'], <String, String>{'DATA': 'data-receipt'});
    expect(body['currentPassword'], 'current-password');
    expect(requests.where((http.Request request) =>
        request.url.path.endsWith('/activation')), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
