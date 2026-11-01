import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/financial_control_api.dart';
import 'package:servicepay_app/admin/financial_control_screen.dart';
import 'package:servicepay_app/admin/main_navigation.dart';

void main() {
  testWidgets('failed filter reload clears previously displayed financial figures',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int requests = 0;
    final FinancialControlApi api = FinancialControlApi(
      tokenLoader: () async => 'controlled-fixture-token',
      client: MockClient((http.Request request) async {
        requests++;
        if (requests > 1) {
          return http.Response(jsonEncode(<String, dynamic>{
            'success': false, 'message': 'Controlled report unavailable'
          }), 503);
        }
        return http.Response(jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{
            'currency': 'NGN',
            'period': <String, dynamic>{
              'from': request.url.queryParameters['from'],
              'to': request.url.queryParameters['to'],
              'timezone': 'Africa/Lagos',
            },
            'totals': <String, dynamic>{'recordedRevenue': 987654},
            'reconciliation': <String, dynamic>{'status': 'NOT RECONCILED'},
          }
        }), 200);
      }),
    );
    await tester.pumpWidget(MaterialApp(home: FinancialControlScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('NGN 987,654'), findsOneWidget);
    await tester.ensureVisible(find.text('Apply filters'));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('Controlled report unavailable'), findsOneWidget);
    expect(find.text('NGN 987,654'), findsNothing);
    expect(requests, 2);
  });

  group('Financial Control API', () {
    test('uses the configured endpoint, auth token and report filters',
        () async {
      late Uri requested;
      late Map<String, String> headers;
      final FinancialControlApi api = FinancialControlApi(
        baseUrl: 'https://example.test/api/',
        tokenLoader: () async => 'Bearer session-123',
        client: MockClient((http.Request request) async {
          requested = request.url;
          headers = request.headers;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'totals': <String, dynamic>{'netProfit': null}
              },
            }),
            200,
          );
        }),
      );

      final Map<String, dynamic> result = await api.summary(
        filters: <String, String>{
          'from': '2026-08-01',
          'to': '2026-08-31',
          'service': 'DATA',
          'network': 'network-id-42',
          'branch': 'branch-id-8',
        },
      );
      expect(requested.path, '/api/admin/revenue/financial-control/summary');
      expect(requested.queryParameters['from'], '2026-08-01');
      expect(requested.queryParameters['to'], '2026-08-31');
      expect(requested.queryParameters['network'], 'network-id-42');
      expect(requested.queryParameters['branch'], 'branch-id-8');
      expect(headers['authorization'], 'Bearer session-123');
      expect((result['totals'] as Map)['netProfit'], isNull);
    });

    test('returns explicit errors for malformed and unauthorized responses',
        () async {
      final FinancialControlApi malformed = FinancialControlApi(
        tokenLoader: () async => 'token',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        malformed.summary(filters: const <String, String>{}),
        throwsA(isA<FinancialControlException>().having(
          (FinancialControlException error) => error.message,
          'message',
          contains('invalid response'),
        )),
      );

      final FinancialControlApi unauthorized = FinancialControlApi(
        tokenLoader: () async => null,
        client: MockClient((_) async => http.Response('', 401)),
      );
      await expectLater(
        unauthorized.expenses(filters: const <String, String>{}),
        throwsA(isA<FinancialControlException>().having(
          (FinancialControlException error) => error.statusCode,
          'statusCode',
          401,
        )),
      );
    });

    test(
        'expense submission includes required acknowledgement and preserves error',
        () async {
      late Map<String, dynamic> sent;
      final FinancialControlApi api = FinancialControlApi(
        baseUrl: 'https://example.test',
        tokenLoader: () async => 'token',
        client: MockClient((http.Request request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/admin/revenue/financial-control/expenses');
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{'id': 'expense-1'},
            }),
            201,
          );
        }),
      );
      final Map<String, dynamic> response = await api.createExpense(
        <String, dynamic>{
          'amount': 12500,
          'category': 'HOSTING',
          'date': '2026-08-12',
          'description': 'Monthly hosting invoice',
          'reference': 'INV-2026-008',
          'costNotAlreadyDeducted': true,
          'supportingDocument': <String, dynamic>{
            'name': 'invoice.pdf',
            'type': 'application/pdf',
            'dataBase64': 'JVBERi0xLjQ=',
          },
        },
      );
      expect(sent['costNotAlreadyDeducted'], isTrue);
      expect(sent['amount'], 12500);
      expect(response['id'], 'expense-1');
      expect(
        (sent['supportingDocument'] as Map<String, dynamic>).keys.toSet(),
        <String>{'name', 'type', 'dataBase64'},
      );

      final FinancialControlApi rejected = FinancialControlApi(
        tokenLoader: () async => 'token',
        client: MockClient((_) async => http.Response(
              jsonEncode(
                  <String, dynamic>{'message': 'Reference already exists'}),
              409,
            )),
      );
      await expectLater(
        rejected.createExpense(<String, dynamic>{'reference': 'INV-2026-008'}),
        throwsA(isA<FinancialControlException>().having(
          (FinancialControlException error) => error.message,
          'message',
          'Reference already exists',
        )),
      );
    });
  });

  test('exports authenticated CSV with the selected period and format',
      () async {
    late Uri requested;
    String? savedName;
    final FinancialControlApi api = FinancialControlApi(
      baseUrl: 'https://example.test/api',
      tokenLoader: () async => 'token',
      client: MockClient((http.Request request) async {
        requested = request.url;
        return http.Response.bytes(
          <int>[0x43, 0x53, 0x56],
          200,
          headers: <String, String>{
            'content-disposition': 'attachment; filename="financial.csv"',
            'content-type': 'text/csv',
          },
        );
      }),
      downloadAdapter: (List<int> bytes, String filename, String type) async {
        savedName = filename;
      },
    );
    await api.downloadReport(
      format: 'csv',
      filters: <String, String>{
        'from': '2026-08-01',
        'to': '2026-08-31',
        'service': 'DATA',
      },
    );
    expect(requested.path, '/api/admin/revenue/financial-control/report');
    expect(requested.queryParameters['format'], 'csv');
    expect(requested.queryParameters['from'], '2026-08-01');
    expect(requested.queryParameters['service'], 'DATA');
    expect(savedName, 'financial.csv');
  });

  test('opens the authenticated PDF response through the PDF adapter',
      () async {
    late Uri requested;
    bool openedPdf = false;
    final FinancialControlApi api = FinancialControlApi(
      baseUrl: 'https://example.test',
      tokenLoader: () async => 'token',
      client: MockClient((http.Request request) async {
        requested = request.url;
        return http.Response.bytes(
          <int>[0x25, 0x50, 0x44, 0x46],
          200,
          headers: const <String, String>{'content-type': 'application/pdf'},
        );
      }),
      downloadAdapter: (List<int> bytes, String filename, String type) async {},
      pdfAdapter: (
        List<int> bytes,
        String filename,
        String contentType,
        Future<void> Function(List<int>, String, String) fallback,
      ) async {
        openedPdf = true;
        expect(contentType, 'application/pdf');
        expect(filename, 'ServicePay-Financial-Control.pdf');
        expect(bytes, <int>[0x25, 0x50, 0x44, 0x46]);
      },
    );
    await api.downloadReport(
      format: 'pdf',
      filters: const <String, String>{'from': '2026-08-01', 'to': '2026-08-31'},
    );
    expect(requested.path, '/admin/revenue/financial-control/report');
    expect(requested.queryParameters['format'], 'pdf');
    expect(openedPdf, isTrue);
  });

  test('financial control navigation is exactly Head Office only', () {
    expect(canAccessFinancialControlNavigation(role: 'head-office'), isTrue);
    expect(canAccessFinancialControlNavigation(role: 'HEAD_OFFICE_ADMIN'),
        isFalse);
    expect(canAccessFinancialControlNavigation(role: 'SUPER_ADMIN'), isFalse);
    expect(canAccessFinancialControlNavigation(role: 'STAFF'), isFalse);
  });

  testWidgets('keeps unknown values visible and retains expense form on error',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _FakeFinancialApi api = _FakeFinancialApi();
    await tester.pumpWidget(
      MaterialApp(home: FinancialControlScreen(api: api)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Financial Control Center'), findsOneWidget);
    expect(find.text('DATA UNAVAILABLE'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('financial-metric-pending')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('financial-metric-refunds')),
        matching: find.text('NGN 3,500'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('not a claim that all data is reconciled'),
        findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('NOT RECONCILED'), findsOneWidget);

    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    expect(find.text('NGN 50'), findsOneWidget);

    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();
    expect(find.text('NGN 25'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('NGN 75'), findsOneWidget);
    expect(find.text('branch-id-1'), findsWidgets);

    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record expense').first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (NGN)'), '4200');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'), 'Hosting renewal');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Unique reference (required)'),
        'host-2026-08');
    await tester
        .tap(find.textContaining('I confirm this is separately incurred'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record expense').last);
    await tester.pumpAndSettle();

    expect(find.text('The reference is already in use.'), findsOneWidget);
    expect(find.text('Record a separate expense'), findsOneWidget);
    expect(find.text('Hosting renewal'), findsOneWidget);
    expect(api.lastExpenseBody?['costNotAlreadyDeducted'], isTrue);
    expect(api.lastExpenseBody?['reference'], 'host-2026-08');
  });

  testWidgets('all reporting date presets use the selected Nigeria dates',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _FakeFinancialApi api = _FakeFinancialApi();
    await tester
        .pumpWidget(MaterialApp(home: FinancialControlScreen(api: api)));
    await tester.pumpAndSettle();
    final DateTime nigeriaNow =
        DateTime.now().toUtc().add(const Duration(hours: 1));
    final DateTime nigeriaToday =
        DateTime(nigeriaNow.year, nigeriaNow.month, nigeriaNow.day);
    expect(api.lastFilters!['from']!.endsWith('-01'), isTrue);

    Future<void> choose(String label) async {
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.pumpAndSettle();
    }

    await choose('Today');
    final String today = _formatDay(nigeriaToday);
    expect(api.lastFilters!['from'], today);
    expect(api.lastFilters!['to'], today);
    await choose('Yesterday');
    expect(api.lastFilters!['from'], api.lastFilters!['to']);
    expect(
      api.lastFilters!['from'],
      _formatDay(nigeriaToday.subtract(const Duration(days: 1))),
    );
    await choose('Last 7 days');
    final DateTime last7Start = DateTime.parse(api.lastFilters!['from']!);
    final DateTime last7End = DateTime.parse(api.lastFilters!['to']!);
    expect(last7End.difference(last7Start).inDays, 6);
    expect(api.lastFilters!['to'], today);
    await choose('This month');
    expect(api.lastFilters!['from']!.endsWith('-01'), isTrue);
    await choose('Last month');
    final DateTime lastMonthStart = DateTime.parse(api.lastFilters!['from']!);
    expect(lastMonthStart.day, 1);
    expect(
      lastMonthStart,
      DateTime(nigeriaToday.year, nigeriaToday.month - 1),
    );
    expect(
      DateTime.parse(api.lastFilters!['to']!).day,
      DateTime(nigeriaToday.year, nigeriaToday.month, 0).day,
    );

    await choose('Custom');
    expect(find.text('CUSTOM REPORTING PERIOD'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });
}

String _formatDay(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class _FakeFinancialApi extends FinancialControlApi {
  _FakeFinancialApi() : super(tokenLoader: _testToken);
  static Future<String?> _testToken() async => 'test';

  Map<String, dynamic>? lastExpenseBody;
  Map<String, String>? lastFilters;

  @override
  Future<Map<String, dynamic>> summary({
    required Map<String, String> filters,
  }) async {
    lastFilters = Map<String, String>.from(filters);
    return <String, dynamic>{
      'period': <String, dynamic>{
        'from': filters['from'],
        'to': filters['to'],
        'timezone': 'Africa/Lagos',
      },
      'generatedAt': '2026-08-12T10:00:00Z',
      'currency': 'NGN',
      'totals': <String, dynamic>{
        'transactionValue': 83000,
        'recordedRevenue': 50,
        'knownProviderCosts': 42000,
        'providerCosts': null,
        'grossProfit': null,
        'operatingExpenses': 12000,
        'netProfit': null,
        'pending': 2,
        'failed': 1,
        'refunds': 3500,
        'outstandingSettlements': null,
        'unreconciled': 4,
        'successful': 13,
        'totalCount': 19,
        'refundedCount': 1,
        'successRate': 68.42,
      },
      'reconciliation': <String, dynamic>{
        'status': 'PARTIALLY_RECONCILED',
        'issues': <dynamic>[
          <String, dynamic>{
            'code': 'MISSING_COST',
            'count': 2,
            'note': 'Cost evidence missing'
          }
        ],
      },
      'services': <dynamic>[
        <String, dynamic>{
          'service': 'DATA',
          'count': 13,
          'transactionValue': 83000,
          'recordedRevenue': 50,
          'missingRevenueCount': 1,
          'knownProviderCosts': 42000,
          'providerCosts': 42000,
          'grossProfit': null,
          'operatingExpenses': null,
          'netProfit': null,
        },
      ],
      'networks': <dynamic>[
        <String, dynamic>{
          'network': 'Airtel',
          'count': 3,
          'transactionValue': 12000,
          'recordedRevenue': 25,
          'missingRevenueCount': 1,
          'providerCosts': 6000,
          'grossProfit': null,
          'operatingExpenses': null,
          'netProfit': null,
        }
      ],
      'plans': <dynamic>[
        <String, dynamic>{
          'network': 'Airtel',
          'plan': '2GB',
          'sellingPrice': 500,
          'providerCost': null,
          'grossMargin': null,
          'marginPercent': null,
          'count': 2,
          'recordedEarnings': null,
        },
      ],
      'branches': <dynamic>[
        <String, dynamic>{
          'branch': 'branch-id-1',
          'count': 1,
          'transactionValue': 500,
          'recordedRevenue': 75,
          'missingRevenueCount': 0,
          'providerCosts': 200,
          'grossProfit': null,
          'operatingExpenses': null,
          'netProfit': null,
        }
      ],
      'trends': <String, dynamic>{
        'daily': <dynamic>[
          <String, dynamic>{
            'date': '2026-08-12',
            'revenue': 50,
            'partial': true,
          }
        ],
        'weekly': <dynamic>[],
        'monthly': <dynamic>[],
      },
      'growth': <String, dynamic>{
        'percent': null,
        'note': 'Comparison not available'
      },
      'sourceCoverage': <dynamic>[
        <String, dynamic>{
          'service': 'Wallet',
          'source': 'ledgerentries',
          'status': 'NOT RECONCILED',
          'count': 2,
          'note': 'Custody source needs reconciliation',
        },
      ],
      'methodology': <String>[
        'Revenue means verified earned margins and fees.'
      ],
      'filters': <String, dynamic>{
        'services': <String>['DATA'],
        'networks': <String>['Airtel'],
        'branches': <String>['branch-id-1'],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> expenses({
    required Map<String, String> filters,
  }) async =>
      <String, dynamic>{
        'items': <dynamic>[],
        'totalRecorded': null,
        'status': 'PARTIALLY_RECONCILED',
        'coverage':
            'Recorded expenses do not establish complete period coverage.',
      };

  @override
  Future<Map<String, dynamic>> createExpense(
    Map<String, dynamic> expense,
  ) async {
    lastExpenseBody = Map<String, dynamic>.from(expense);
    throw const FinancialControlException('The reference is already in use.');
  }
}
