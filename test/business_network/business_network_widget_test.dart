import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:servicepay_app/admin/business_network/business_network_admin_api.dart';
import 'package:servicepay_app/admin/business_network/business_network_screen.dart';

void main() {
  testWidgets('overview renders API metrics without mock totals',
      (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/business-network/admin/overview');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'agents': {
              'registered': 12,
              'approved': 8,
              'pending': 2,
              'active': 7,
              'suspended': 1,
            },
            'merchants': {
              'registered': 4,
              'approved': 3,
              'pending': 1,
              'active': 3,
              'suspended': 0,
            },
            'transactions': {
              'total': 19,
              'successful': 17,
              'pending': 1,
              'failed': 1,
              'volumeKobo': 825000,
            },
            'commissions': {'earnedKobo': 32000, 'pendingKobo': 5000},
            'locations': [],
          },
        }),
        200,
      );
    });
    await tester.pumpWidget(MaterialApp(
      home: BusinessNetworkScreen(
        api: BusinessNetworkAdminApi(
          client: client,
          tokenProvider: () async => 'admin-token',
          baseUrl: 'https://test.servicepay.invalid/api',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Network Overview' &&
            widget.style?.fontSize == 22,
      ),
      findsOneWidget,
    );
    expect(find.text('RETAIL AGENTS'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('₦8250.00'), findsOneWidget);
    client.close();
  });

  testWidgets('Agent report has a distinct print action and native fallback',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/reports')) {
        expect(request.url.queryParameters['format'], 'csv');
        expect(request.url.queryParameters['kind'], 'AGENT');
        return http.Response('service,status\nAIRTIME,SUCCESSFUL\n', 200);
      }
      return http.Response(
        jsonEncode({'success': true, 'data': {}}),
        200,
      );
    });
    await tester.pumpWidget(MaterialApp(
      home: BusinessNetworkScreen(
        initialSection: 11,
        api: BusinessNetworkAdminApi(
          client: client,
          tokenProvider: () async => 'admin-token',
          baseUrl: 'https://test.servicepay.invalid/api',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print Agent report'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Direct printing is unavailable on this platform'),
      findsOneWidget,
    );
    client.close();
  });

  testWidgets(
      'commission history pages summaries and displays public references',
      (tester) async {
    final requestedPages = <String>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/commissions')) {
        expect(request.url.queryParameters['profileId'], isNull);
        expect(request.url.queryParameters['limit'], '50');
        requestedPages.add(request.url.queryParameters['page'] ?? '');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'items': [
                {
                  '_id': 'commission-key',
                  'transaction': 'mongo-transaction-secret',
                  'reference': 'AG-REF-7651',
                  'serviceType': 'DATA',
                  'transactionStatus': 'SUCCESSFUL',
                  'event': 'SALE',
                  'amountKobo': 1250,
                }
              ],
              'total': 101,
              'page': int.parse(request.url.queryParameters['page'] ?? '1'),
              'limit': 50,
              'totals': {
                'earnedKobo': 9000,
                'pendingKobo': 0,
                'paidKobo': 0,
                'reversedKobo': 0,
                'recoveryKobo': 0,
              },
            },
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'data': {}}),
        200,
      );
    });
    await tester.pumpWidget(MaterialApp(
      home: BusinessNetworkScreen(
        initialSection: 10,
        api: BusinessNetworkAdminApi(
          client: client,
          tokenProvider: () async => 'admin-token',
          baseUrl: 'https://test.servicepay.invalid/api',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('AG-REF-7651'), findsOneWidget);
    expect(find.textContaining('mongo-transaction-secret'), findsNothing);
    final reportList = find.descendant(
      of: find.byType(RefreshIndicator).last,
      matching: find.byType(ListView),
    );
    await tester.drag(reportList, const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(requestedPages, ['1', '2']);
    expect(find.text('Page 2 of 3'), findsOneWidget);
    client.close();
  });
}
