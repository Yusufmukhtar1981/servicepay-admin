import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/commission/profit_sharing_api.dart';
import 'package:servicepay_app/admin/commission/profit_sharing_settings_screen.dart';

const Map<String, num> _rates = <String, num>{
  'HEAD_OFFICE': 40,
  'ZONAL_MANAGER': 25,
  'STATE_MANAGER': 20,
  'AGGREGATOR': 15,
};

Map<String, dynamic> _company({
  bool canManage = true,
  bool enabled = false,
  bool hasRule = false,
}) {
  final Map<String, dynamic>? current = hasRule
      ? <String, dynamic>{
          'id': 'company-rule-1',
          'percentages': _rates,
          'createdAt': '2025-03-01T12:00:00.000Z',
          'createdBy': 'admin@servicepay.ng',
          'reason': 'Approved allocation for verified net profit',
        }
      : null;
  return <String, dynamic>{
    'success': true,
    'data': <String, dynamic>{
      'revision': 8,
      'enabled': enabled,
      'currentRule': current,
      'versions': hasRule
          ? <Map<String, dynamic>>[
              <String, dynamic>{
                ...current!,
                'enabled': enabled,
              },
            ]
          : <Map<String, dynamic>>[],
      'storageBlockers': <String>[],
      'canManage': canManage,
      'pendingVerificationCount': 3,
      'settlementSource': 'VERIFIED_COMPANY_PROFIT_ONLY',
    },
  };
}

Future<void> _scrollToCompany(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(
    tester.element(target.first),
    alignment: 0.35,
    duration: Duration.zero,
  );
  await tester.pumpAndSettle();
}

Future<void> _confirmCompanyWrite(WidgetTester tester, String password) async {
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey<String>('company-current-password')),
    password,
  );
  await tester.tap(find.byType(CheckboxListTile));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
}

void main() {
  group('company profit API', () {
    test('saves a company rule to its relative endpoint with exact contract',
        () async {
      http.Request? captured;
      final ProfitSharingApi api = ProfitSharingApi(
        baseUrl: 'https://admin.example.test',
        tokenProvider: () async => 'session-token',
        client: MockClient((http.Request request) async {
          captured = request;
          return http.Response(jsonEncode(_company(hasRule: true)), 200);
        }),
      );
      final Map<String, dynamic> payload = <String, dynamic>{
        'revision': 8,
        'idempotencyKey': 'company-rule-key-1',
        'percentages': _rates,
        'reason': 'Approved allocation for verified net profit',
        'confirmation': true,
        'currentPassword': 'fresh-password',
      };

      await api.saveCompanyRule(payload);

      expect(captured!.url.path, '${ProfitSharingApi.endpoint}/company');
      expect(captured!.method, 'POST');
      expect(jsonDecode(captured!.body), payload);
      api.close();
    });

    test('rejects an invalid percentage sum before making a request', () async {
      int requests = 0;
      final ProfitSharingApi api = ProfitSharingApi(
        tokenProvider: () async => 'token',
        client: MockClient((http.Request request) async {
          requests++;
          return http.Response(jsonEncode(_company()), 200);
        }),
      );
      await expectLater(
        api.saveCompanyRule(<String, dynamic>{
          'revision': 8,
          'idempotencyKey': 'bad-sum',
          'percentages': <String, num>{..._rates, 'AGGREGATOR': 10},
          'reason': 'This allocation should not be accepted',
          'confirmation': true,
          'currentPassword': 'fresh-password',
        }),
        throwsA(isA<ProfitSharingApiException>()),
      );
      expect(requests, 0);
      api.close();
    });

    test('enable and disable use only company activation contract fields',
        () async {
      final List<http.Request> requests = <http.Request>[];
      final ProfitSharingApi api = ProfitSharingApi(
        tokenProvider: () async => 'token',
        client: MockClient((http.Request request) async {
          requests.add(request);
          final bool enabled = jsonDecode(request.body)['enabled'] as bool;
          return http.Response(
            jsonEncode(_company(enabled: enabled, hasRule: true)),
            200,
          );
        }),
      );
      for (final bool enabled in <bool>[true, false]) {
        await api.setCompanyEnabled(<String, dynamic>{
          'revision': 8,
          'enabled': enabled,
          'reason': 'Authorized company status change',
          'confirmation': true,
          'currentPassword': 'fresh-password',
        });
      }
      expect(
        requests.map((http.Request request) => request.url.path),
        everyElement(
            endsWith('${ProfitSharingApi.endpoint}/company/activation')),
      );
      for (final http.Request request in requests) {
        expect(
          (jsonDecode(request.body) as Map<String, dynamic>).keys.toSet(),
          <String>{
            'revision',
            'enabled',
            'reason',
            'confirmation',
            'currentPassword',
          },
        );
      }
      api.close();
    });

    test('preserves unauthorized and server error responses', () async {
      for (final int status in <int>[401, 403, 503]) {
        final ProfitSharingApi api = ProfitSharingApi(
          tokenProvider: () async => 'token',
          client: MockClient((http.Request request) async => http.Response(
                jsonEncode(<String, dynamic>{
                  'success': false,
                  'message': 'Company write rejected',
                }),
                status,
              )),
        );
        await expectLater(
          api.setCompanyEnabled(<String, dynamic>{
            'revision': 8,
            'enabled': false,
            'reason': 'Authorized company status change',
            'confirmation': true,
            'currentPassword': 'fresh-password',
          }),
          throwsA(
            isA<ProfitSharingApiException>()
                .having((ProfitSharingApiException error) => error.statusCode,
                    'statusCode', status)
                .having((ProfitSharingApiException error) => error.message,
                    'message', 'Company write rejected'),
          ),
        );
        api.close();
      }
    });
  });

  testWidgets('read-only company access cannot save or toggle distribution',
      (WidgetTester tester) async {
    final ProfitSharingApi api = ProfitSharingApi(
      tokenProvider: () async => 'token',
      client: MockClient((http.Request request) async {
        if (request.url.path.endsWith('/company')) {
          return http.Response(jsonEncode(_company(canManage: false)), 200);
        }
        if (request.url.path.endsWith('/engine')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'mode': 'BLOCKED',
                'distributionLive': false,
                'revision': 1,
                'ready': false,
                'storageBlockers': <String>[],
                'services': <dynamic>[],
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'canManage': false,
              'services': <String>[],
              'items': <dynamic>[],
            },
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(api: api),
    ));
    await tester.pumpAndSettle();

    final FilledButton save = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('save-company-profit-rule')),
    );
    final OutlinedButton toggle = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey<String>('enable-company-distribution')),
    );
    expect(save.onPressed, isNull);
    expect(toggle.onPressed, isNull);
    expect(find.textContaining('Read-only access'), findsOneWidget);
    api.close();
  });

  testWidgets(
      'company rule save and activation controls require fresh password',
      (WidgetTester tester) async {
    Map<String, dynamic> current =
        _company(hasRule: false)['data'] as Map<String, dynamic>;
    final List<Map<String, dynamic>> writes = <Map<String, dynamic>>[];
    final ProfitSharingApi api = ProfitSharingApi(
      tokenProvider: () async => 'token',
      client: MockClient((http.Request request) async {
        if (request.url.path.endsWith('/company/activation')) {
          final Map<String, dynamic> body =
              jsonDecode(request.body) as Map<String, dynamic>;
          writes.add(body);
          current = <String, dynamic>{
            ...current,
            'revision': (current['revision'] as int) + 1,
            'enabled': body['enabled'],
          };
          return http.Response(
              jsonEncode(<String, dynamic>{
                'success': true,
                'data': current,
              }),
              200);
        }
        if (request.url.path.endsWith('/company') && request.method == 'POST') {
          final Map<String, dynamic> body =
              jsonDecode(request.body) as Map<String, dynamic>;
          writes.add(body);
          final Map<String, dynamic> rule = <String, dynamic>{
            'id': 'company-rule-${current['revision']}',
            'percentages': body['percentages'],
            'createdAt': '2025-03-02T10:00:00.000Z',
            'createdBy': 'admin@servicepay.ng',
            'reason': body['reason'],
          };
          current = <String, dynamic>{
            ...current,
            'revision': (current['revision'] as int) + 1,
            'currentRule': rule,
            'versions': <Map<String, dynamic>>[
              <String, dynamic>{...rule, 'enabled': current['enabled']},
            ],
          };
          return http.Response(
              jsonEncode(<String, dynamic>{
                'success': true,
                'data': current,
              }),
              200);
        }
        if (request.url.path.endsWith('/company')) {
          return http.Response(
              jsonEncode(<String, dynamic>{
                'success': true,
                'data': current,
              }),
              200);
        }
        if (request.url.path.endsWith('/engine')) {
          return http.Response(
              jsonEncode(<String, dynamic>{
                'success': true,
                'data': <String, dynamic>{
                  'mode': 'BLOCKED',
                  'distributionLive': false,
                  'revision': 1,
                  'ready': false,
                  'storageBlockers': <String>[],
                  'services': <dynamic>[],
                },
              }),
              200);
        }
        return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'canManage': true,
                'services': <String>[],
                'items': <dynamic>[],
              },
            }),
            200);
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: ProfitSharingSettingsScreen(api: api),
    ));
    await tester.pumpAndSettle();

    for (final MapEntry<String, num> rate in _rates.entries) {
      final Finder field =
          find.byKey(ValueKey<String>('company-percentage-${rate.key}'));
      await _scrollToCompany(tester, field);
      await tester.enterText(field, rate.value.toString());
    }
    final Finder reason =
        find.byKey(const ValueKey<String>('company-profit-audit-reason'));
    await _scrollToCompany(tester, reason);
    await tester.enterText(reason, 'Approved company allocation rule');
    final Finder save =
        find.byKey(const ValueKey<String>('save-company-profit-rule'));
    await _scrollToCompany(tester, save);
    await tester.tap(save);
    await _confirmCompanyWrite(tester, 'current-password-one');

    await _scrollToCompany(tester, reason);
    await tester.enterText(reason, 'Authorized company activation');
    Finder enable =
        find.byKey(const ValueKey<String>('enable-company-distribution'));
    await _scrollToCompany(tester, enable);
    await tester.tap(enable);
    await _confirmCompanyWrite(tester, 'current-password-two');

    await _scrollToCompany(tester, reason);
    await tester.enterText(reason, 'Authorized company deactivation');
    Finder disable =
        find.byKey(const ValueKey<String>('disable-company-distribution'));
    await _scrollToCompany(tester, disable);
    await tester.tap(disable);
    await _confirmCompanyWrite(tester, 'current-password-three');

    expect(writes, hasLength(3));
    expect(writes[0].keys.toSet(), <String>{
      'revision',
      'idempotencyKey',
      'percentages',
      'reason',
      'confirmation',
      'currentPassword',
    });
    expect(writes[1]['enabled'], isTrue);
    expect(writes[2]['enabled'], isFalse);
    expect(
      writes.every((Map<String, dynamic> body) =>
          body['currentPassword'] is String &&
          (body['currentPassword'] as String).startsWith('current-password')),
      isTrue,
    );
    expect(find.text('Disabled'), findsWidgets);
    expect(tester.takeException(), isNull);
    api.close();
  });
}
