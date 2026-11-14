import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:servicepay_app/admin/business_network/business_network_admin_api.dart';
import 'package:servicepay_app/admin/business_network/business_network_screen.dart';

Future<void> _scrollToBusinessElement(
    WidgetTester tester, Finder target) async {
  final scrollable = find
      .byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      )
      .first;
  await tester.scrollUntilVisible(
    target,
    240,
    maxScrolls: 30,
    scrollable: scrollable,
  );
}

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

  testWidgets('Merchant report selection requests Merchant CSV',
      (tester) async {
    final reportRequests = <Uri>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/reports')) {
        reportRequests.add(request.url);
        return http.Response('service,status\nDATA,SUCCESSFUL\n', 200);
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
    await tester
        .tap(find.byKey(const ValueKey('business-network-report-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merchant').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print Merchant report'));
    await tester.pumpAndSettle();

    expect(reportRequests, hasLength(1));
    expect(reportRequests.single.queryParameters['format'], 'csv');
    expect(reportRequests.single.queryParameters['kind'], 'MERCHANT');
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

  testWidgets('performance view assigns a level with current profile revision',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <http.Request>[];
    final premium = {
      'businessServices': {
        'AGENT': ['AIRTIME'],
        'MERCHANT': ['AIRTIME']
      },
      'levels': [
        {
          'code': 'STARTER',
          'label': 'Starter Agent',
          'enabled': true,
          'minTransactions': 1,
          'minVolumeKobo': 1000,
          'commissionGroup': 'STARTER',
        },
        {
          'code': 'SILVER',
          'label': 'Silver Agent',
          'enabled': false,
          'minTransactions': 0,
          'minVolumeKobo': 0,
          'commissionGroup': 'SILVER',
        },
        {
          'code': 'GOLD',
          'label': 'Gold Agent',
          'enabled': false,
          'minTransactions': 0,
          'minVolumeKobo': 0,
          'commissionGroup': 'GOLD',
        },
        {
          'code': 'PLATINUM',
          'label': 'Platinum Agent',
          'enabled': false,
          'minTransactions': 0,
          'minVolumeKobo': 0,
          'commissionGroup': 'PLATINUM',
        },
      ],
      'loyalty': {
        'enabled': false,
        'pointsPerTransaction': 0,
        'maxPointsPerCustomer': 0,
        'expiryDays': 30,
        'eligibleServices': [],
        'effectiveFrom': null,
      },
      'goals': [],
      'campaigns': [],
      'revision': 4,
      'features': {
        'merchantQr': false,
        'payByLink': false,
        'automaticPayouts': false,
      },
      'capabilityReasons': {},
      'serviceCatalogue': {'AGENT': [], 'MERCHANT': []},
    };
    final client = MockClient((request) async {
      calls.add(request);
      final path = request.url.path;
      if (path.endsWith('/admin/performance')) {
        expect(
            request.url.queryParameters, {'kind': 'AGENT', 'period': 'month'});
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'items': [
                {
                  'profileId': 'agent-1',
                  'transactions': 8,
                  'volumeKobo': 12500,
                  'rank': 1,
                  'profile': {
                    '_id': 'agent-1',
                    'networkId': 'SPN-AGENT-1',
                    'kind': 'AGENT',
                    'level': null,
                    'details': {'businessName': 'Musa Corner'},
                  },
                }
              ],
              'period': 'month',
            },
          }),
          200,
        );
      }
      if (path.endsWith('/admin/premium')) {
        return http.Response(
            jsonEncode({'success': true, 'data': premium}), 200);
      }
      if (path.endsWith('/admin/profiles/agent-1') && request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'profile': {
                '_id': 'agent-1',
                'kind': 'AGENT',
                'status': 'APPROVED',
                'revision': 12,
              }
            },
          }),
          200,
        );
      }
      if (path.endsWith('/admin/profiles/agent-1/level') &&
          request.method == 'POST') {
        expect(jsonDecode(request.body), {
          'level': 'STARTER',
          'revision': 12,
          'reason': 'Verified threshold review',
        });
        return http.Response(
            jsonEncode({
              'success': true,
              'data': {'profile': {}}
            }),
            200);
      }
      return http.Response(
        jsonEncode({'success': false, 'message': 'Unexpected route: $path'}),
        404,
      );
    });
    await tester.pumpWidget(MaterialApp(
      home: BusinessNetworkScreen(
        initialSection: 19,
        api: BusinessNetworkAdminApi(
          client: client,
          tokenProvider: () async => 'head-office-token',
          baseUrl: 'https://test.servicepay.invalid/api',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Musa Corner'), findsOneWidget);
    expect(find.textContaining('checked again by the backend'), findsOneWidget);
    await _scrollToBusinessElement(
        tester, find.byTooltip('Assign a qualified level'));
    await tester.tap(find.byTooltip('Assign a qualified level'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).last, 'Verified threshold review');
    await tester.tap(find.text('Assign level'));
    await tester.pumpAndSettle();
    expect(find.text('Assign a qualified Agent level'), findsNothing);
    expect(
      calls.any((request) =>
          request.method == 'POST' &&
          request.url.path.endsWith('/admin/profiles/agent-1/level')),
      isTrue,
      reason: calls
          .map((request) => '${request.method} ${request.url.path}')
          .join('\n'),
    );
    client.close();
  });

  testWidgets('Head Office service controls save audited partial settings',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    Map<String, dynamic> premium = {
      'businessServices': {
        'AGENT': ['AIRTIME'],
        'MERCHANT': ['DATA'],
      },
      'levels': [],
      'loyalty': {
        'enabled': false,
        'pointsPerTransaction': 0,
        'maxPointsPerCustomer': 0,
        'expiryDays': 30,
        'eligibleServices': [],
        'effectiveFrom': null,
      },
      'goals': [],
      'campaigns': [],
      'revision': 3,
      'features': {
        'merchantQr': false,
        'payByLink': false,
        'automaticPayouts': false,
      },
      'capabilityReasons': {},
      'serviceCatalogue': {
        'AGENT': [
          {
            'code': 'AIRTIME',
            'label': 'Airtime',
            'category': 'Bill payments',
            'preferencesEnabled': true,
            'processable': true,
            'available': true,
            'reason': '',
          }
        ],
        'MERCHANT': [],
      },
    };
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET' &&
          request.url.path.endsWith('/admin/premium')) {
        return http.Response(
            jsonEncode({'success': true, 'data': premium}), 200);
      }
      if (request.method == 'PUT' &&
          request.url.path.endsWith('/admin/premium')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['revision'], 3);
        expect(body['reason'], 'Pause Agent Airtime preferences');
        expect(body['configuration'], {
          'businessServices': {'AGENT': []}
        });
        premium = {
          ...premium,
          'businessServices': {
            'AGENT': [],
            'MERCHANT': ['DATA'],
          },
          'revision': 4,
        };
        return http.Response(
            jsonEncode({'success': true, 'data': premium}), 200);
      }
      return http.Response(
          jsonEncode({'success': false, 'message': 'Unexpected route'}), 404);
    });
    await tester.pumpWidget(MaterialApp(
      home: BusinessNetworkScreen(
        initialSection: 23,
        api: BusinessNetworkAdminApi(
          client: client,
          tokenProvider: () async => 'head-office-token',
          baseUrl: 'https://test.servicepay.invalid/api',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('AGENT service preferences'), findsOneWidget);
    await _scrollToBusinessElement(tester, find.byType(CheckboxListTile).first);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Save AGENT service preferences'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).last, 'Pause Agent Airtime preferences');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Save AGENT service preferences'), findsNothing);
    expect(
      requests.any((request) =>
          request.method == 'PUT' &&
          request.url.path.endsWith('/admin/premium')),
      isTrue,
    );
    client.close();
  });

  testWidgets('voucher inventory reads backend contract without mock stock',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var voucherRequested = false;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/admin/premium')) {
        return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'businessServices': {'AGENT': [], 'MERCHANT': []},
                'levels': [],
                'loyalty': {},
                'goals': [],
                'campaigns': [],
                'revision': 1,
                'features': {},
                'capabilityReasons': {
                  'rechargeVouchers':
                      'Purchase and inventory remain disabled pending safeguards.',
                },
                'serviceCatalogue': {'AGENT': [], 'MERCHANT': []},
              }
            }),
            200);
      }
      if (request.url.path.endsWith('/admin/vouchers')) {
        voucherRequested = true;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'enabled': false,
              'inventoryVerified': false,
              'items': [],
              'contract': {
                'enabled': false,
                'airtime': {
                  'documentation':
                      'https://telecomabode.com.ng/documentation/airtimepin-request',
                  'issue': '/recharge_card',
                },
                'data': {
                  'documentation':
                      'https://telecomabode.com.ng/documentation/datapin-request',
                  'issue': '/data_card',
                  'catalogueVerified': false,
                },
                'prerequisites': [
                  'Actual pre-purchase price',
                  'Idempotent recovery',
                  'Dedicated voucher encryption key',
                ],
              },
              'capabilityReasons': {},
            },
          }),
          200,
        );
      }
      return http.Response(
          jsonEncode({'success': false, 'message': 'Unexpected route'}), 404);
    });
    await tester.pumpWidget(MaterialApp(
      home: BusinessNetworkScreen(
        initialSection: 17,
        api: BusinessNetworkAdminApi(
          client: client,
          tokenProvider: () async => 'head-office-token',
          baseUrl: 'https://test.servicepay.invalid/api',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(voucherRequested, isTrue);
    expect(find.textContaining('/recharge_card'), findsOneWidget);
    expect(find.textContaining('Dedicated voucher encryption key'),
        findsOneWidget);
    expect(find.textContaining('No inventory, PIN'), findsNothing);
    client.close();
  });

  testWidgets('loyalty section shows real paginated non-cash statements',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/admin/premium')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'businessServices': {'AGENT': [], 'MERCHANT': []},
              'levels': [],
              'loyalty': {
                'enabled': false,
                'pointsPerTransaction': 0,
                'maxPointsPerCustomer': 0,
                'expiryDays': 30,
                'eligibleServices': [],
                'effectiveFrom': null,
              },
              'goals': [],
              'campaigns': [],
              'revision': 2,
              'features': {},
              'capabilityReasons': {},
              'serviceCatalogue': {'AGENT': [], 'MERCHANT': []},
            },
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/admin/loyalty')) {
        expect(request.url.queryParameters, {'page': '1'});
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'items': [
                {
                  'profile': {
                    'networkId': 'SPN-LOYALTY-8',
                    'kind': 'AGENT',
                    'details': {'businessName': 'Musa Corner'},
                  },
                  'earned': 18,
                  'reversed': 2,
                  'available': 9,
                  'expired': 7,
                  'items': [],
                  'cashValueKobo': 0,
                  'redemptionEnabled': false,
                }
              ],
              'page': 1,
              'total': 1,
              'cashValueKobo': 0,
              'redemptionEnabled': false,
            },
          }),
          200,
        );
      }
      return http.Response(
          jsonEncode({'success': false, 'message': 'Unexpected route'}), 404);
    });
    await tester.pumpWidget(MaterialApp(
      home: BusinessNetworkScreen(
        initialSection: 21,
        api: BusinessNetworkAdminApi(
          client: client,
          tokenProvider: () async => 'head-office-token',
          baseUrl: 'https://test.servicepay.invalid/api',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Non-cash loyalty statements'), findsOneWidget);
    expect(find.text('Musa Corner'), findsOneWidget);
    expect(
        find.textContaining('Earned 18 · Reversed 2 · Available 9 · Expired 7'),
        findsOneWidget);
    expect(find.text('₦0.00'), findsOneWidget);
    client.close();
  });
}
