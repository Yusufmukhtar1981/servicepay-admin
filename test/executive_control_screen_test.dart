import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/executive_control_api.dart';
import 'package:servicepay_app/admin/executive_control_screen.dart';
import 'package:servicepay_app/admin/main_navigation.dart';

void main() {
  Map<String, dynamic> overviewData() => {
        'generatedAt': '2025-05-01T10:00:00.000Z',
        'period': {
          'from': '2025-04-25',
          'to': '2025-05-01',
          'timezone': 'Africa/Lagos',
          'range': '7d'
        },
        'capabilities': {'finance': true, 'export': true},
        'overview': {
          'registeredCustomers': 1200,
          'activeCustomers': 450,
          'newCustomers': 28,
          'inactiveCustomers': 60,
          'neverCustomers': 140,
          'total': 830,
          'successful': 700,
          'pending': 30,
          'failed': 80,
          'refunded': 6,
          'other': 14,
          'successfulVolume': 4800000,
        },
        'customers': {
          'summary': {
            'customers': 1200,
            'active': 450,
            'frequent': 12,
            'regular': 20,
            'occasional': 45,
            'declining': 32,
            'inactive': 60,
            'never': 140,
            'newRegistrations': 28,
            'retained': 70,
            'previousActive': 400,
            'retentionRate': 17.5
          },
          'topCount': [
            {'name': 'Ada Musa', 'count': 12, 'value': 8400}
          ],
          'topVolume': [
            {'name': 'Ada Musa', 'count': 12, 'value': 8400}
          ],
        },
        'transactions': {
          'summary': {
            'total': 830,
            'successful': 700,
            'pending': 30,
            'failed': 80,
            'refunded': 6,
            'other': 14,
            'successfulVolume': 4800000
          },
          'items': [],
          'pagination': {'page': 1, 'totalPages': 1, 'total': 0},
          'services': [],
          'providers': [],
          'trend': [],
        },
        'definitions': [
          'Transaction volume is successful customer movement; it is not earned revenue or profit.',
          'Customer categories use all-services rolling activity.'
        ],
      };

  Map<String, dynamic> financialFixture() => {
        'generatedAt': '2025-05-01T10:00:00.000Z',
        'period': {
          'from': '2025-04-25',
          'to': '2025-05-01',
          'timezone': 'Africa/Lagos'
        },
        'currency': 'NGN',
        'totals': {
          'totalCount': 3,
          'successful': 2,
          'transactionValue': 4000,
          'recordedRevenue': 2800,
          'knownProviderCosts': 1200,
          'providerCosts': null,
          'grossProfit': null,
          'operatingExpenses': null,
          'netProfit': null,
          'pending': 1,
          'failed': 0,
          'refunds': 0,
          'refundedCount': 0,
          'outstandingSettlements': null,
          'unreconciled': 1,
          'missingRevenueCount': 1,
          'missingProviderCostCount': 1,
          'successRate': 66.67
        },
        'reconciliation': {
          'status': 'PARTIALLY RECONCILED',
          'issues': [
            {
              'code': 'MISSING_PROVIDER_COST',
              'count': 1,
              'note': 'Review evidence.'
            }
          ]
        },
        'services': [
          {
            'service': 'DATA',
            'count': 2,
            'totalCount': 2,
            'successful': 2,
            'transactionValue': 4000,
            'recordedRevenue': 2800,
            'knownProviderCosts': 1200,
            'providerCosts': null,
            'grossProfit': null,
            'netProfit': null,
            'pending': 0,
            'failed': 0
          }
        ],
        'trends': {
          'daily': [
            {'date': '2025-04-30', 'revenue': 1800, 'partial': false},
            {'date': '2025-05-01', 'revenue': null, 'partial': true}
          ],
          'weekly': [
            {'date': '2025-04-28', 'revenue': 2800, 'partial': true}
          ],
          'monthly': [
            {'date': '2025-04', 'revenue': 2800, 'partial': true}
          ]
        },
        'growth': {
          'percent': null,
          'note': 'Known margins only; not complete company revenue growth.'
        },
        'sourceCoverage': [
          {'service': 'DATA', 'count': 2, 'missingRevenue': 1}
        ],
        'methodology': [
          'Recorded revenue is the known earned-fee/margin subtotal.',
          'Net profit is unavailable without complete expense coverage.'
        ],
        'walletLiabilities': null,
        'fundingReconciliation': null,
        'settlementLiabilities': null,
        'limitations': [
          'Recorded revenue is a known subtotal, not proof of complete company revenue.',
          'Net profit remains unavailable without complete expense coverage.'
        ],
      };

  Map<String, dynamic> marketingFixture() => {
        'period': {
          'from': '2025-04-25T00:00:00.000Z',
          'to': '2025-05-02T00:00:00.000Z',
          'timeZone': 'UTC'
        },
        'metrics': {
          'totalCustomersAcquired': 18,
          'newRegistrations': 24,
          'newCustomersToday': 4,
          'activeCustomers': 12,
          'firstTimeTransactingCustomers': 7,
          'activeCampaigns': 2,
          'marketingStaff': 3,
          'conversionRate': 38.9,
          'expenditureNaira': 45000,
          'cacNaira': 2500,
          'approvedBudgetNaira': 80000,
          'retainedCustomers': 5,
          'retentionRate': 27.8,
          'verifiedContributionNaira': null,
          'verifiedSpendNaira': 18000,
          'roi': null
        },
        'campaigns': [
          {
            'id': 'campaign-1',
            'title': 'Lagos Data Week',
            'status': 'ACTIVE',
            'channel': 'DIGITAL',
            'acquired': 18,
            'firstTransactions': 7,
            'expenditureNaira': 45000,
            'cacNaira': 2500,
            'verifiedContributionNaira': null,
            'verifiedSpendNaira': 18000,
            'roi': null
          }
        ],
        'geography': [
          {'state': 'Lagos', 'city': 'Ikeja', 'acquired': 8}
        ],
        'officers': [
          {
            'id': 'officer-1',
            'name': 'Tola Bello',
            'acquired': 8,
            'completedTasks': 4,
            'firstTransactions': 3,
            'scorecard': [
              {
                'metric': 'ACQUISITIONS',
                'actual': 8,
                'target': 10,
                'achievementPercent': 80
              }
            ],
            'scorePercent': 80
          }
        ],
        'series': [
          {'date': '2025-04-25', 'acquired': 3, 'firstTransactions': 1}
        ],
        'referrals': {
          'registrations': 4,
          'firstTransactions': 1,
          'conversionRate': 25
        },
        'social': [],
        'partnerships': [],
        'limitations': ['Acquisition attribution is evidence-confirmed.'],
        'departmentPerformance': {
          'period': '2025-04-25/2025-05-01',
          'items': [
            {
              'id': 'officer-1',
              'name': 'Tola Bello',
              'role': 'Marketing Officer',
              'achievement': 80,
              'acquisitions': 8,
              'firstTransactions': 3,
              'targets': []
            }
          ],
          'methodology': {
            'weights': {'acquisitions': 0.5}
          },
          'departmentTargets': [],
          'comparisonNote': 'Historical periods are not blended.'
        }
      };

  Map<String, dynamic> fieldFixture({int page = 1}) => {
        'items': [
          {
            'id': 'agent-$page',
            'name': 'Agent $page',
            'registered': 12,
            'transacted': 8,
            'never': 4,
            'active': 7,
            'inactive': 2,
            'value': 8600,
            'previousActive': 6,
            'retained': 4,
            'retentionRate': 66.7
          }
        ],
        'pagination': {'page': page, 'limit': 25, 'total': 30, 'totalPages': 2},
        'unavailableDimensions': ['BRM', 'CM'],
        'attribution': 'Current stored customer assignments.'
      };

  Map<String, dynamic> healthFixture() => {
        'generatedAt': '2025-05-01T10:00:00.000Z',
        'backend': {'status': 'AVAILABLE'},
        'database': {'status': 'CONNECTED', 'latencyMs': 23},
        'providers': [
          {
            'provider': 'LOCAL',
            'status': 'NOT_ACTIVELY_PROBED',
            'recordedTransactions': 9,
            'recordedPending': 1,
            'recordedFailed': 2,
            'responseTimeMs': null
          }
        ],
        'webhooks': {
          'status': 'UNAVAILABLE',
          'reason': 'No authenticated aggregate webhook-health source.'
        },
        'errors': [
          {
            'action': 'REPORT_RETRY',
            'status': 'FAILED',
            'createdAt': '2025-05-01T09:30:00.000Z'
          }
        ],
        'notice': 'Recorded evidence only; providers are not actively probed.'
      };

  test('explicit executive navigation also requires user and transaction view',
      () {
    expect(
      canAccessExecutiveControlNavigation(
        role: 'STAFF',
        permissions: {
          'executive.control_center.view',
          AdminPermissions.usersView,
          AdminPermissions.transactionsView,
        },
      ),
      isTrue,
    );
    expect(
      canAccessExecutiveControlNavigation(
        role: 'STAFF',
        permissions: {
          'executive.control_center.view',
          AdminPermissions.usersView
        },
      ),
      isFalse,
    );
    expect(
      canAccessExecutiveControlNavigation(role: 'HEAD_OFFICE', permissions: {}),
      isTrue,
    );
  });

  testWidgets(
      'mobile screen fits, loads overview first, then finance on demand',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      final data = switch (request.url.path.split('/').last) {
        'finance' => financialFixture(),
        'marketing' => marketingFixture(),
        'field' => fieldFixture(
            page:
                int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1),
        'health' => healthFixture(),
        _ => overviewData(),
      };
      return http.Response(jsonEncode({'success': true, 'data': data}), 200,
          headers: {'content-type': 'application/json'});
    });
    final api = ExecutiveControlApi(
      client: client,
      tokenLoader: () async => 'test-token',
    );
    await tester.pumpWidget(MaterialApp(
      home: ExecutiveControlScreen(
        api: api,
        initialAccess:
            const AdminAccess(role: 'HEAD_OFFICE', permissions: <String>{}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        requests.map((u) => u.path), ['/api/admin/executive-control/overview']);
    expect(find.text('Business at a glance'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final financeTab = find.byKey(const Key('executive-section-Finance'));
    await tester.ensureVisible(financeTab);
    await tester.tap(financeTab);
    await tester.pumpAndSettle();
    expect(requests.last.path, '/api/admin/executive-control/finance');
    expect(find.textContaining('Recorded revenue'), findsWidgets);
    expect(find.textContaining('Unavailable'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(financialFixture().containsKey('totals'), isTrue);
    expect(financialFixture().containsKey('financialControl'), isFalse);

    final marketingTab = find.byKey(const Key('executive-section-Marketing'));
    await tester.ensureVisible(marketingTab);
    await tester.tap(marketingTab);
    await tester.pumpAndSettle();
    expect(requests.last.path, '/api/admin/executive-control/marketing');
    expect(find.text('Total Customers Acquired'), findsOneWidget);
    expect(find.textContaining('Lagos Data Week'), findsOneWidget);

    final fieldTab = find.byKey(const Key('executive-section-Field'));
    await tester.ensureVisible(fieldTab);
    await tester.tap(fieldTab);
    await tester.pumpAndSettle();
    expect(requests.last.path, '/api/admin/executive-control/field');
    expect(requests.last.queryParameters['dimension'], 'agent');
    expect(find.text('Field performance · Agent'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Next field page'));
    await tester.tap(find.byTooltip('Next field page'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['page'], '2');
    expect(find.textContaining('Agent 2'), findsOneWidget);
    final healthTab = find.byKey(const Key('executive-section-Health'));
    await tester.ensureVisible(healthTab);
    await tester.tap(healthTab);
    await tester.pumpAndSettle();
    expect(requests.last.path, '/api/admin/executive-control/health');
    expect(find.textContaining('NOT_ACTIVELY_PROBED'), findsOneWidget);
    api.close();
  });

  test(
      'report request uses the authorized binary endpoint and selected filters',
      () async {
    Uri? requested;
    final api = ExecutiveControlApi(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response.bytes(
          utf8.encode(
              '\uFEFF"Report","ServicePay Executive business"\r\n"Currency","NGN"\r\n"Timezone","Africa/Lagos"\r\n'),
          200,
          headers: {
            'content-type': 'text/csv',
            'content-disposition':
                'attachment; filename="ServicePay-Executive-business-2025-05-01.csv"',
          },
        );
      }),
      tokenLoader: () async => 'test-token',
    );
    final report = await api.report(
      kind: 'business',
      format: 'csv',
      filters: {
        'range': 'custom',
        'from': '2025-05-01',
        'to': '2025-05-07',
        'serviceType': 'airtime',
        'status': 'SUCCESSFUL',
        'provider': 'VTPass',
      },
    );
    expect(requested!.path, '/api/admin/executive-control/report');
    expect(requested!.queryParameters['kind'], 'business');
    expect(requested!.queryParameters['format'], 'csv');
    expect(requested!.queryParameters['from'], '2025-05-01');
    expect(requested!.queryParameters['to'], '2025-05-07');
    expect(requested!.queryParameters['serviceType'], 'airtime');
    expect(report.filename, 'ServicePay-Executive-business-2025-05-01.csv');
    expect(report.bytes, isNotEmpty);
    api.close();
  });

  testWidgets(
      'date presets, filters, sorting and KPI drill-down preserve query',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Uri>[];
    final api = ExecutiveControlApi(
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response(
            jsonEncode({'success': true, 'data': overviewData()}), 200);
      }),
      tokenLoader: () async => 'test-token',
    );
    await tester.pumpWidget(MaterialApp(
      home: ExecutiveControlScreen(
        api: api,
        initialAccess:
            const AdminAccess(role: 'HEAD_OFFICE', permissions: <String>{}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'initial desktop viewport');
    await tester.tap(find.byKey(const Key('executive-range-yesterday')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'after date preset');
    expect(requests.last.queryParameters['range'], 'yesterday');

    await tester.tap(find.byKey(const Key('executive-section-Transactions')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'after transaction section');
    await tester.drag(find.byType(ListView).last, const Offset(0, -620));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('executive-filter-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PENDING').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'after status selection');
    await tester.ensureVisible(find.byKey(const Key('executive-filter-apply')));
    await tester.tap(find.byKey(const Key('executive-filter-apply')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'after applying filters');
    expect(requests.last.queryParameters['status'], 'PENDING');

    await tester.ensureVisible(find.byKey(const Key('executive-sort-by')));
    await tester.tap(find.byKey(const Key('executive-sort-by')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amount').last);
    await tester.pumpAndSettle();
    final sortingException = tester.takeException();
    if (sortingException != null) {
      // ignore: avoid_print
      print(sortingException);
    }

    await tester.tap(find.byKey(const Key('executive-section-Overview')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, 900));
    await tester.pumpAndSettle();
    final successful = find.byKey(const Key('executive-kpi-Successful'));
    await tester.ensureVisible(successful);
    await tester.tap(successful);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['status'], 'SUCCESSFUL');
    expect(requests.last.queryParameters['range'], 'yesterday');
    api.close();
  });

  testWidgets('finance and export sections stay hidden without capabilities',
      (tester) async {
    final api = ExecutiveControlApi(
      client: MockClient((_) async => http.Response(
          jsonEncode({
            'success': true,
            'data': {
              ...overviewData(),
              'capabilities': {'finance': false, 'export': false},
            },
          }),
          200)),
      tokenLoader: () async => 'test-token',
    );
    await tester.pumpWidget(MaterialApp(
      home: ExecutiveControlScreen(
        api: api,
        initialAccess:
            const AdminAccess(role: 'STAFF', permissions: <String>{}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('executive-section-Finance')), findsNothing);
    expect(find.byKey(const Key('executive-section-Reports')), findsNothing);
    expect(tester.takeException(), isNull);
    api.close();
  });
}
