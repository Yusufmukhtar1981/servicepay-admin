import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:servicepay_app/admin/admin_staff_workspace_api.dart';
import 'package:servicepay_app/admin/admin_transaction_reliability_panel.dart';

Map<String, dynamic> reliabilityPayload({
  int page = 1,
  int total = 25,
  bool nullableMetrics = false,
  String reference = 'ref-2025-07-transaction-001',
}) =>
    {
      'success': true,
      'data': {
        'generatedAt': '2025-07-17T12:00:00.000Z',
        'windowHours': 24,
        'windowTruncated': false,
        'summary': {
          'total': 42,
          'successCount': 35,
          'failedCount': 4,
          'refundedCount': 1,
          'pendingCount': 2,
          'successRate': nullableMetrics ? null : 83.3,
          'failureRate': nullableMetrics ? null : 9.5,
          'averageRecordedSettlementMs': nullableMetrics ? null : 815.4,
          'settlementSamples': nullableMetrics ? 0 : 28,
          'httpErrorRate': nullableMetrics ? null : 6.2,
          'httpSamples': nullableMetrics ? 0 : 16,
        },
        'backlog': {
          'pendingCount': 18,
          'manualReviewCount': 3,
          'walletDiscrepancyCount': 2,
          'ledgerAuditedCount': 91,
          'legacyUnlinkedCount': 4,
          'automaticVerificationLimit': 12,
        },
        'alerts': [
          {
            'code': 'OVERDUE_PENDING',
            'severity': 'HIGH',
            'message': 'Pending records are overdue.',
            'count': 3,
          },
        ],
        'providers': [
          {
            'provider': 'Northstar Telecom',
            'total': 21,
            'successCount': 18,
            'failedCount': 2,
          },
        ],
        'items': [
          {
            'id': 'txn-1',
            'reference': reference,
            'type': 'DATA',
            'provider': 'Northstar Telecom',
            'financialStatus': 'PENDING',
            'lifecycleState': 'VERIFYING',
            'createdAt': '2025-07-17T10:00:00.000Z',
            'lastCheckedAt': '2025-07-17T11:00:00.000Z',
            'nextCheckAt': '2025-07-17T12:10:00.000Z',
            'verificationAttempts': 5,
            'reasonCode': 'PROVIDER_TIMEOUT',
            'walletStatus': 'DEBIT_LINKED',
          },
        ],
        'page': page,
        'limit': 20,
        'total': total,
      },
    };

Widget testPanel(AdminStaffWorkspaceApi api) => MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [AdminTransactionReliabilityPanel(api: api)],
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'auth_token': 'test-session'});
  });

  testWidgets('renders backend metrics, alerts, queue and nullable values',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/transaction-reliability'));
      expect(request.url.queryParameters['page'], '1');
      expect(request.url.queryParameters['limit'], '20');
      return http.Response(jsonEncode(reliabilityPayload()), 200);
    });
    final api = AdminStaffWorkspaceApi(
      client: client,
      baseUrl: 'https://admin.example.test/admin/staff-workspace',
    );
    await tester.pumpWidget(testPanel(api));
    await tester.pumpAndSettle();

    expect(find.text('Transaction reliability'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('35'), findsOneWidget);
    expect(find.text('OVERDUE_PENDING'), findsOneWidget);
    expect(find.textContaining('not provider or device end-to-end duration'),
        findsOneWidget);
    expect(find.textContaining('not full wallet certification'),
        findsOneWidget);
    expect(find.textContaining('Northstar Telecom'), findsWidgets);
    expect(find.textContaining('ref-2025-07-transaction-001'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('nullable evidence and HTTP metrics display Not recorded',
      (tester) async {
    final client = MockClient((_) async =>
        http.Response(jsonEncode(reliabilityPayload(nullableMetrics: true)), 200));
    final api = AdminStaffWorkspaceApi(
      client: client,
      baseUrl: 'https://admin.example.test/admin/staff-workspace',
    );
    await tester.pumpWidget(testPanel(api));
    await tester.pumpAndSettle();

    expect(find.text('Not recorded'), findsAtLeastNWidgets(2));
    expect(find.textContaining('0 samples'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('shows strict API failure with retry and advances queue page',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    int requestCount = 0;
    final List<int> requestedPages = [];
    final client = MockClient((request) async {
      requestCount++;
      requestedPages.add(int.parse(request.url.queryParameters['page']!));
      if (requestCount == 1) {
        return http.Response(
            jsonEncode({'success': false, 'message': 'Temporary outage'}), 503);
      }
      return http.Response(
          jsonEncode(reliabilityPayload(page: requestedPages.last)), 200);
    });
    final api = AdminStaffWorkspaceApi(
      client: client,
      baseUrl: 'https://admin.example.test/admin/staff-workspace',
    );
    await tester.pumpWidget(testPanel(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('Temporary outage'), findsOneWidget);
    expect(find.text('No reliability data is available yet.'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 2 · 25 records'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Next queue page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next queue page'));
    await tester.pumpAndSettle();

    expect(requestedPages, [1, 1, 2]);
    expect(find.text('Page 2 of 2 · 25 records'), findsOneWidget);
    expect(find.text('Refund'), findsNothing);
    expect(find.text('Reconcile'), findsNothing);
    expect(find.text('Retry purchase'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
