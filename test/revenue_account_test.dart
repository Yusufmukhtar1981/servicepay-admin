import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:servicepay_app/admin/main_navigation.dart';
import 'package:servicepay_app/admin/revenue_account_api.dart';
import 'package:servicepay_app/admin/revenue_account_screen.dart';

void main() {
  group('Revenue Account access', () {
    test('Head Office is allowed; staff and branch wildcard are denied', () {
      expect(
        canAccessRevenueAccountNavigation(
          role: ' head-office ',
          permissions: <String>{},
        ),
        isTrue,
      );
      expect(
        canAccessRevenueAccountNavigation(
          role: 'STAFF',
          permissions: <String>{'*', 'transactions.view'},
        ),
        isFalse,
      );
      expect(
        canViewRevenueAccount(
          role: 'STAFF',
          permissions: <String>{'*', 'transactions.view'},
        ),
        isFalse,
      );
      expect(
        canViewRevenueAccount(
          role: 'branch',
          permissions: <String>{'*', 'transactions.view'},
        ),
        isFalse,
      );
      expect(
        canViewRevenueAccount(
          role: 'agent',
          permissions: <String>{'transactions.view'},
        ),
        isFalse,
      );
    });
  });

  group('RevenueAccountApi', () {
    test('uses configured root, bearer token and inclusive date query',
        () async {
      late Uri requested;
      late Map<String, String> headers;
      final RevenueAccountApi api = RevenueAccountApi(
        baseUrl: 'https://example.test/api/',
        tokenLoader: () async => 'Bearer session-token',
        client: MockClient((http.Request request) async {
          requested = request.url;
          headers = request.headers;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{'totals': <String, dynamic>{}},
            }),
            200,
          );
        }),
      );

      await api.summary(filters: <String, String>{
        'from': '2026-08-01',
        'to': '2026-08-31',
        'service': 'DATA',
        'q': 'ref 42',
        'page': '2',
        'limit': '25',
      });

      expect(requested.path, '/api/admin/revenue/summary');
      expect(requested.queryParameters['from'], '2026-08-01');
      expect(requested.queryParameters['to'], '2026-08-31');
      expect(requested.queryParameters['service'], 'DATA');
      expect(requested.queryParameters['q'], 'ref 42');
      expect(headers['authorization'], 'Bearer session-token');
    });

    test('gives explicit malformed-response and authorization errors',
        () async {
      final RevenueAccountApi malformed = RevenueAccountApi(
        tokenLoader: () async => 'token',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        malformed.ledger(),
        throwsA(isA<RevenueAccountException>().having(
          (RevenueAccountException error) => error.message,
          'message',
          contains('invalid response'),
        )),
      );

      final RevenueAccountApi unauthorized = RevenueAccountApi(
        tokenLoader: () async => null,
        client: MockClient((_) async => http.Response('', 401)),
      );
      await expectLater(
        unauthorized.transactions(),
        throwsA(isA<RevenueAccountException>().having(
          (RevenueAccountException error) => error.statusCode,
          'statusCode',
          401,
        )),
      );
    });

    test('exports authenticated binary using response filename', () async {
      String? downloadedName;
      List<int>? downloadedBytes;
      final RevenueAccountApi api = RevenueAccountApi(
        baseUrl: 'https://example.test',
        tokenLoader: () async => 't',
        client: MockClient((http.Request request) async {
          expect(request.url.path, '/admin/revenue/export');
          expect(request.url.queryParameters['format'], 'csv');
          expect(request.url.queryParameters['service'], 'DATA');
          return http.Response.bytes(
            <int>[1, 2, 3],
            200,
            headers: <String, String>{
              'content-disposition': 'attachment; filename="rev-report.csv"',
              'content-type': 'text/csv',
            },
          );
        }),
        downloadAdapter: (List<int> bytes, String filename, String type) async {
          downloadedName = filename;
          downloadedBytes = bytes;
        },
      );
      await api
          .export(format: 'csv', filters: <String, String>{'service': 'DATA'});
      expect(downloadedName, 'rev-report.csv');
      expect(downloadedBytes, <int>[1, 2, 3]);
    });

    test('reconciliation is one bounded empty-body bookkeeping request',
        () async {
      late http.Request request;
      final RevenueAccountApi api = RevenueAccountApi(
        baseUrl: 'https://example.test/api',
        tokenLoader: () async => 't',
        client: MockClient((http.Request value) async {
          request = value;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'processed': 50,
                'recognized': 42,
                'reversed': 3,
                'adjusted': 5,
                'hasMore': true,
              },
            }),
            200,
          );
        }),
      );
      final Map<String, dynamic> result = await api.reconcile();
      expect(request.method, 'POST');
      expect(request.url.path, '/api/admin/revenue/reconcile');
      expect(request.body, '{}');
      expect(result['hasMore'], isTrue);
    });
  });

  testWidgets('renders missing costs as unresolved and filters/paginates',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _FakeRevenueApi api = _FakeRevenueApi();
    await tester.pumpWidget(MaterialApp(home: RevenueAccountScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('need provider confirmation'), findsOneWidget);
    expect(
        find.textContaining('have no verified invoice cost'), findsOneWidget);
    expect(find.text('Unresolved'), findsWidgets);
    expect(find.textContaining('Known-cost profit'), findsWidgets);

    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 2 · 26 records'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ada Okafor');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(api.lastTransactionFilters?['q'], 'Ada Okafor');
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(api.lastTransactionFilters?['page'], '2');
    expect(api.lastTransactionFilters?['limit'], '25');

    await tester.tap(find.text('Accounting ledger'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('ALL SERVICES / ALL_TIME_POSTED'), findsOneWidget);
    expect(find.textContaining('2026-08-01T12:00:00Z'), findsOneWidget);
    expect(find.text('Posted ledger profit is unresolved'), findsOneWidget);
  });
}

class _FakeRevenueApi extends RevenueAccountApi {
  _FakeRevenueApi() : super(tokenLoader: _emptyToken);
  static Future<String?> _emptyToken() async => 'test';
  Map<String, String>? lastTransactionFilters;

  @override
  Future<Map<String, dynamic>> summary({
    Map<String, String> filters = const <String, String>{},
  }) async =>
      <String, dynamic>{
        'totals': <String, dynamic>{
          'grossRevenue': 1200,
          'providerCosts': 400,
          'grossProfit': null,
          'fees': 10,
          'commissions': 20,
          'otherDirectCosts': 0,
          'netProfit': null,
          'successfulTransactions': 2,
          'uncostedTransactions': 1,
          'unverifiedTransactions': 0,
          'excludedTransactions': 1,
          'costedTransactions': 1,
          'accountingComplete': false,
        },
        'periods': <String, dynamic>{
          'today': 400,
          'yesterday': 300,
          'week': 800,
          'month': 1200,
        },
        'services': <dynamic>[
          <String, dynamic>{
            'serviceType': 'DATA',
            'grossRevenue': 1200,
            'providerCosts': 400,
            'netProfit': null,
            'successfulTransactions': 2,
            'uncostedTransactions': 1,
          },
        ],
        'trend': <dynamic>[
          <String, dynamic>{
            'date': '2026-08-01',
            'grossRevenue': 1200,
            'providerCosts': 400,
            'netProfit': null,
          },
        ],
        'ledger': <String, dynamic>{
          'grossRevenue': 1200,
          'netProfit': null,
          'entries': 1,
          'uncostedTransactions': 1,
          'readOnly': true,
          'asOf': '2026-08-01T12:00:00Z',
        },
        'reconciliation': <String, dynamic>{
          'status': 'CURRENT',
          'lastRunAt': null,
        },
      };

  @override
  Future<Map<String, dynamic>> transactions({
    Map<String, String> filters = const <String, String>{},
  }) async {
    lastTransactionFilters = Map<String, String>.from(filters);
    return <String, dynamic>{
      'items': <dynamic>[
        <String, dynamic>{
          'transactionId': 'tx-1',
          'reference': 'SP-84A',
          'customerName': 'Ada Okafor',
          'serviceType': 'DATA',
          'customerPayment': 1200,
          'providerCost': null,
          'grossProfit': null,
          'fees': 10,
          'commissions': 20,
          'otherDirectCosts': 0,
          'netProfit': null,
          'date': '2026-08-01T10:00:00Z',
          'status': 'SUCCESSFUL',
          'accountingStatus': 'UNCOSTED',
          'provider': 'Telecom Abode',
        },
      ],
      'page': int.tryParse(filters['page'] ?? '1') ?? 1,
      'limit': 25,
      'total': 26,
      'pages': 2,
    };
  }

  @override
  Future<Map<String, dynamic>> ledger({
    Map<String, String> filters = const <String, String>{},
  }) async =>
      <String, dynamic>{
        'items': <dynamic>[],
        'page': 1,
        'limit': 25,
        'total': 0,
        'pages': 1
      };
}
