import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/commission/profit_sharing_api.dart';
import 'package:servicepay_app/admin/commission/profit_sharing_settings_screen.dart';

Map<String, dynamic> _settlements({
  List<Map<String, dynamic>> items = const <Map<String, dynamic>>[],
  Map<String, dynamic>? companyProfit,
  int? heldKobo = 5500,
}) =>
    <String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'summary': <String, dynamic>{
          'companyProfitKobo': 123456789,
          'creditedKobo': 250045,
          'reversedKobo': null,
          'netAllocatedKobo': 250045,
          'heldKobo': heldKobo,
          'allocations': <Map<String, dynamic>>[
            <String, dynamic>{
              'role': 'HEAD_OFFICE',
              'creditedKobo': 250045,
              'reversedKobo': 0,
              'netKobo': 250045,
              'heldKobo': heldKobo,
            },
          ],
          if (companyProfit != null) ...companyProfit,
        },
        'companyAccount': <String, dynamic>{
          'availableKobo': 250045,
          'reservedKobo': 0,
          'withdrawnKobo': null,
          'recoveryDebtKobo': 0,
          'earnedKobo': 250045,
          'reversedKobo': 0,
        },
        'items': items,
        'page': 1,
        'limit': 25,
        'total': items.length,
        'source': 'FUTURE_PROFIT_SHARING_ONLY',
      },
    };

class _FakeProfitSharingApi extends ProfitSharingApi {
  _FakeProfitSharingApi() : super(tokenProvider: () async => 'test');

  Future<Map<String, dynamic>> Function(
    int page,
    String? from,
    String? to,
  )? loader;
  final List<int> requestedPages = <int>[];
  final List<(String?, String?)> requestedPeriods =
      <(String?, String?)>[];

  @override
  Future<Map<String, dynamic>> getSettlements(
      {int page = 1, int limit = 25, String? from, String? to}) {
    requestedPages.add(page);
    requestedPeriods.add((from, to));
    return loader?.call(page, from, to) ??
        Future<Map<String, dynamic>>.value(_settlements());
  }
}

void main() {
  test('integer kobo formats exactly in naira and missing evidence stays unavailable',
      () {
    expect(ProfitSharingSettlementHistory.formatKobo(1), '₦0.01');
    expect(ProfitSharingSettlementHistory.formatKobo(123456789), '₦1,234,567.89');
    expect(ProfitSharingSettlementHistory.formatKobo(-275), '-₦2.75');
    expect(ProfitSharingSettlementHistory.formatKobo(null), 'Unavailable');
    expect(ProfitSharingSettlementHistory.formatKobo(1.5), 'Unavailable');
  });

  testWidgets('settlement summary/history shows loading then custody evidence',
      (WidgetTester tester) async {
    final Completer<Map<String, dynamic>> completer =
        Completer<Map<String, dynamic>>();
    final _FakeProfitSharingApi api = _FakeProfitSharingApi()
      ..loader = (_, __, ___) => completer.future;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProfitSharingSettlementHistory(api: api),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey<String>('settlement-period-from')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('settlement-period-to')),
        findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    completer.complete(_settlements(items: <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'settlement-1',
        'kind': 'CREDIT',
        'reference': 'receipt-14',
        'serviceType': 'AIRTIME',
        'createdAt': '2030-02-03',
        'amountKobo': 250045,
        'companyProfitKobo': 1000000,
        'entries': <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'HEAD_OFFICE',
            'accountId': 'beneficiary:0123456789abcdef01234567',
            'amountKobo': 250045,
          },
          <String, dynamic>{
            'role': 'AGGREGATOR',
            'accountId': 'commission-pool',
            'amountKobo': 5000,
          },
        ],
      },
    ]));
    await tester.pumpAndSettle();
    expect(find.text('₦1,234,567.89'), findsOneWidget);
    expect(find.textContaining('₦2,500.45'), findsWidgets);
    expect(find.textContaining('Unavailable'), findsWidgets);
    expect(find.textContaining('Held / unallocated custody'), findsWidgets);
    expect(find.byKey(const ValueKey<String>('settlement-held-warning')),
        findsOneWidget);
    expect(
      find.textContaining('Beneficiary allocation · HEAD_OFFICE · ₦2,500.45'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Held / unallocated custody · not a beneficiary credit · ₦50.00',
      ),
      findsOneWidget,
    );
    expect(find.text('Funding source: Commission custody'), findsNothing);
    expect(find.textContaining('Legacy main-wallet commissions are excluded.'),
        findsOneWidget);
    expect(find.textContaining('LIVE'), findsNothing);
    expect(find.textContaining('receipt-14'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settlement history has explicit empty and retryable error states',
      (WidgetTester tester) async {
    final _FakeProfitSharingApi api = _FakeProfitSharingApi();
    api.loader = (_, __, ___) async => throw StateError('private server detail');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProfitSharingSettlementHistory(api: api),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to load settlement history'), findsOneWidget);
    expect(find.textContaining('private server detail'), findsNothing);
    api.loader = (_, __, ___) async => _settlements();
    await tester.tap(find.text('Retry history'));
    await tester.pumpAndSettle();
    expect(find.text('No future profit-sharing settlements recorded yet.'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
  });

  testWidgets('zero held balance stays zero without a held warning',
      (WidgetTester tester) async {
    final _FakeProfitSharingApi api = _FakeProfitSharingApi()
      ..loader = (_, __, ___) async => _settlements(heldKobo: 0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProfitSharingSettlementHistory(api: api),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Held / unallocated custody'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('settlement-held-warning')),
        findsNothing);
    expect(find.text('₦0.00'), findsWidgets);
  });

  testWidgets('settlement history paginates and refresh reloads the current page',
      (WidgetTester tester) async {
    final _FakeProfitSharingApi api = _FakeProfitSharingApi();
    api.loader = (int page, String? _, String? __) async {
      final Map<String, dynamic> result = _settlements();
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(result['data'] as Map)
            ..['page'] = page
            ..['total'] = 60;
      return <String, dynamic>{'success': true, 'data': data};
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProfitSharingSettlementHistory(api: api),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Next history page'));
    await tester.tap(find.byTooltip('Next history page'));
    await tester.pumpAndSettle();
    expect(api.requestedPages, <int>[1, 2]);
    await tester.ensureVisible(find.byTooltip('Refresh settlement history'));
    await tester.tap(find.byTooltip('Refresh settlement history'));
    await tester.pumpAndSettle();
    expect(api.requestedPages, <int>[1, 2, 2]);
  });

  test('settlement request uses explicit paged endpoint and limit', () async {
    final List<http.Request> requests = <http.Request>[];
    final ProfitSharingApi api = ProfitSharingApi(
      baseUrl: 'https://example.test/api',
      tokenProvider: () async => 'test-token',
      client: MockClient((http.Request request) async {
        requests.add(request);
        return http.Response(jsonEncode(_settlements()), 200);
      }),
    );
    await api.getSettlements(
      page: 3,
      limit: 25,
      from: '2025-02-01',
      to: '2025-02-28',
    );
    expect(
      requests.single.url.toString(),
      'https://example.test/api/admin/product-commissions/profit-sharing/settlements?page=3&limit=25&from=2025-02-01&to=2025-02-28',
    );
    api.close();
  });
}
