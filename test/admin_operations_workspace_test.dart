import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/admin_staff_workspace_api.dart';
import 'package:servicepay_app/admin/operations_workspace_screens.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(
        <String, Object>{'auth_token': 'ops-token'},
      ));

  test('uses the operational hub, directory, activity and marketplace routes',
      () async {
    final requests = <http.Request>[];
    final api = AdminStaffWorkspaceApi(
      baseUrl: 'https://example.test/admin/staff-workspace',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'items': <dynamic>[],
              'total': 0,
              'page': 1,
              'pages': 1
            },
          }),
          200,
        );
      }),
    );

    await api.operationalHub();
    await api.directory(role: 'AGGREGATOR', query: 'Ada Okoro', page: 2);
    await api.activity(period: 'year', page: 3);
    await api.marketplaceOperations(kind: 'orders', query: 'SP-42', page: 4);
    await api.updateCustomerProfile(
      'customer/9',
      fullName: 'Ada Okoro',
      address: '12 Market Road',
      reason: 'Verified correction',
    );
    await api.updateMarketplaceSellerStatus(
      'seller-4',
      status: 'ACTIVE',
      expectedStatus: 'PENDING',
      reason: 'Documents reviewed',
    );

    expect(requests.map((request) => request.url.path).toList(), [
      '/admin/staff-workspace/operational-hub',
      '/admin/staff-workspace/directory',
      '/admin/staff-workspace/activity',
      '/admin/staff-workspace/marketplace-operations',
      '/admin/staff-workspace/customers/customer%2F9/profile',
      '/admin/staff-workspace/marketplace-sellers/seller-4/status',
    ]);
    expect(requests[1].url.queryParameters, {
      'role': 'AGGREGATOR',
      'q': 'Ada Okoro',
      'page': '2',
      'limit': '20',
    });
    expect(requests[2].url.queryParameters, {'period': 'year', 'page': '3'});
    expect(requests[3].url.queryParameters, {
      'kind': 'orders',
      'q': 'SP-42',
      'page': '4',
    });
    expect(requests[4].method, 'PATCH');
    expect(jsonDecode(requests[4].body), {
      'fullName': 'Ada Okoro',
      'address': '12 Market Road',
      'reason': 'Verified correction',
    });
    expect(jsonDecode(requests[5].body), {
      'status': 'ACTIVE',
      'expectedStatus': 'PENDING',
      'reason': 'Documents reviewed',
    });
    for (final request in requests) {
      expect(request.headers['authorization'], 'Bearer ops-token');
    }
    api.close();
  });

  testWidgets('directory shows only populated manager assignments and pages',
      (tester) async {
    final requests = <http.Request>[];
    final api = AdminStaffWorkspaceApi(
      baseUrl: 'https://example.test/admin/staff-workspace',
      client: MockClient((request) async {
        requests.add(request);
        final page = int.parse(request.url.queryParameters['page'] ?? '1');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'items': page == 1
                  ? <dynamic>[
                      <String, dynamic>{
                        '_id': 'agg-1',
                        'fullName': 'Mina Yusuf',
                        'phone': '08011112222',
                        'email': 'mina@example.test',
                        'state': 'Kano',
                        'zone': 'North West',
                        'lga': 'Nassarawa',
                        'status': 'ACTIVE',
                        'zonalManagerId': <String, dynamic>{
                          '_id': 'zm-1',
                          'fullName': 'Ibrahim Musa',
                          'role': 'ZONAL_MANAGER',
                        },
                        'stateManagerId': null,
                        'createdAt': '2026-04-10',
                      }
                    ]
                  : <dynamic>[],
              'total': 2,
              'page': page,
              'pages': 2,
            },
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DirectoryOperationsScreen(api: api, role: 'AGGREGATOR'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Mina Yusuf'), findsOneWidget);
    expect(find.text('Zonal manager · Ibrahim Musa'), findsOneWidget);
    expect(find.text('State manager · Not recorded'), findsOneWidget);
    expect(find.textContaining('Not assigned'), findsNothing);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['page'], '2');
    expect(find.text('No directory records'), findsOneWidget);
    api.close();
  });

  testWidgets('marketplace listing gates seller actions by moderation grant',
      (tester) async {
    final api = AdminStaffWorkspaceApi(
      baseUrl: 'https://example.test/admin/staff-workspace',
      client: MockClient((request) async => http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'items': <dynamic>[
                  <String, dynamic>{
                    '_id': 'seller-7',
                    'storeName': 'Northline Traders',
                    'status': 'PENDING',
                    'phone': '08055556666',
                    'email': 'ops@northline.example',
                    'state': 'Kaduna',
                    'user': <String, dynamic>{'_id': 'user-7'},
                  }
                ],
                'total': 1,
                'page': 1,
                'pages': 1,
              },
            }),
            200,
          )),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MarketplaceOperationsScreen(api: api, canModerate: false),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Northline Traders'), findsOneWidget);
    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('Change status'), findsNothing);
    expect(find.textContaining('require marketplaceModerate permission'),
        findsOneWidget);
    api.close();
  });

  testWidgets('profile editor keeps phone and email out of editable fields',
      (tester) async {
    final api = AdminStaffWorkspaceApi(
      baseUrl: 'https://example.test/admin/staff-workspace',
      client: MockClient((_) async => http.Response(
            '{"success":true,"data":{"user":{"fullName":"Mina Yusuf"}}}',
            200,
          )),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CustomerProfileEditForm(
            api: api,
            initialCustomer: <String, dynamic>{
              '_id': 'customer-1',
              'fullName': 'Mina Yusuf',
              'address': '12 Market Road',
              'phone': '08011112222',
              'email': 'mina@example.test',
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('customer-1'), findsOneWidget);
    expect(find.text('Mina Yusuf'), findsOneWidget);
    expect(find.text('12 Market Road'), findsOneWidget);
    expect(find.text('Phone and email · read-only'), findsOneWidget);
    expect(find.textContaining('Head Office'), findsAtLeastNWidgets(1));
    api.close();
  });
}
