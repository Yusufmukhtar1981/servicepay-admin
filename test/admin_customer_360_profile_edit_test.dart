import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/admin_customer_360_api.dart';
import 'package:servicepay_app/admin/admin_customer_360_screen.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/customer_profile_admin.dart';

const _customerId = 'customer-360-1';

void main() {
  Future<void> prepareAccess({
    required String role,
    required Set<String> permissions,
  }) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'admin-session-token',
      'user_role': role,
    });
    await AdminSessionStore.saveAccess(
      AdminAccess(role: role, permissions: permissions),
    );
  }

  MockClient makeClient({
    required List<http.Request> requests,
    required Map<String, String> updated,
  }) =>
      MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('/customer360/search')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'items': [
                  {
                    'id': _customerId,
                    'fullName': 'Ada Okafor',
                    'servicePayId': 'SP-4102',
                    'phone': '08030000000',
                    'email': 'ada@example.test',
                    'status': 'ACTIVE',
                  }
                ]
              }
            }),
            200,
          );
        }
        if (path.endsWith('/customer360/$_customerId')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'profile': {
                  'id': _customerId,
                  'fullName': updated['fullName']!,
                  'phone': updated['phone']!,
                  'email': updated['email']!,
                  'address': updated['address']!,
                  'state': updated['state'] ?? 'Lagos',
                  'lga': updated['lga'] ?? 'Ikeja',
                  'zone': updated['zone'] ?? 'South West',
                  'role': updated['role'] ?? 'CUSTOMER',
                  'status': 'ACTIVE',
                  'kycStatus': 'VERIFIED',
                },
                'capabilities': {
                  'financial': false,
                  'kyc': false,
                  'support': false,
                  'security': false,
                },
                'usage': [],
              }
            }),
            200,
          );
        }
        if (path.endsWith('/customer360/$_customerId/timeline') ||
            path.endsWith('/customer360/$_customerId/transactions')) {
          return http.Response(
            '{"success":true,"data":{"items":[],"pagination":{"page":1,"totalPages":1}}}',
            200,
          );
        }
        if (path.endsWith('/admin/users/$_customerId/profile/history')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'history': [
                  {
                    'id': 'history-1',
                    'actorName': 'Mariam Bello',
                    'actorRole': 'HEAD_OFFICE',
                    'createdAt': '2026-04-14T09:15:00Z',
                    'reason': 'Customer requested address correction',
                    'previousData': {'address': '12 Palm Avenue'},
                    'newData': {'address': updated['address']},
                  }
                ],
                'page': 1,
                'total': 1,
                'pages': 1,
              }
            }),
            200,
          );
        }
        if (path.endsWith(
                '/admin/users/$_customerId/profile/contact-proposal') &&
            request.method == 'GET') {
          return http.Response(
              '{"success":true,"data":{"proposal":null}}', 200);
        }
        if (path.endsWith('/admin/users/$_customerId/profile') &&
            request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(
            body.keys.toSet(),
            {'fullName', 'address', 'state', 'lga', 'zone', 'reason'},
          );
          for (final entry in body.entries) {
            if (entry.key != 'reason') {
              updated[entry.key] = entry.value.toString();
            }
          }
          return http.Response(
              '{"success":true,"data":{"id":"$_customerId"}}', 200);
        }
        return http.Response(
          '{"success":false,"message":"Unexpected mocked route: $path"}',
          404,
        );
      });

  Future<void> exerciseCustomer360(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    final updated = <String, String>{
      'fullName': 'Ada Okafor',
      'address': '12 Palm Avenue',
      'phone': '08030000000',
      'email': 'ada@example.test',
      'state': 'Lagos',
      'lga': 'Ikeja',
      'zone': 'South West',
    };
    final client = makeClient(requests: requests, updated: updated);
    final customerApi = AdminCustomer360Api(client: client);
    final profileApi = AdminCustomerProfileApi(
      client: client,
      baseUrl: 'https://unit.test/api',
    );
    await tester.pumpWidget(MaterialApp(
      home: AdminCustomer360Screen(
        api: customerApi,
        profileApi: profileApi,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ada');
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    final result = find.widgetWithText(ListTile, 'Ada Okafor');
    await tester.ensureVisible(result);
    await tester.tap(result);
    await tester.pumpAndSettle();

    final editButton = find.byKey(const Key('customer360-edit-profile'));
    await tester.ensureVisible(editButton);
    await tester.pumpAndSettle();
    await tester.tap(editButton);
    await tester.pumpAndSettle();
    expect(find.text('Edit Customer Profile'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Phone Number'),
          )
          .readOnly,
      isTrue,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Full Name'),
      'Ada Okafor Adeyemi',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Residential Address'),
      '18 Palm Avenue',
    );
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Audit reason (required, at least 5 characters)',
      ),
      'Customer requested address correction',
    );
    await tester.enterText(find.widgetWithText(TextField, 'State'), 'Oyo');
    await tester.enterText(
        find.widgetWithText(TextField, 'LGA'), 'Ibadan North');
    await tester.enterText(
        find.widgetWithText(TextField, 'Zone'), 'South West');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(
      requests.any((request) =>
          request.method == 'PUT' &&
          request.url.path == '/api/admin/users/$_customerId/profile'),
      isTrue,
    );
    expect(find.text('Ada Okafor Adeyemi'), findsOneWidget);
    expect(find.textContaining('18 Palm Avenue'), findsOneWidget);
    expect(updated['state'], 'Oyo');
    expect(updated['lga'], 'Ibadan North');
    expect(updated['zone'], 'South West');
    expect(
      requests.where((request) =>
          request.method == 'GET' &&
          request.url.path.endsWith('/customer360/$_customerId')),
      hasLength(2),
    );

    final historyButton = find.byKey(const Key('customer360-profile-history'));
    await tester.ensureVisible(historyButton);
    await tester.pumpAndSettle();
    await tester.tap(historyButton);
    await tester.pumpAndSettle();
    expect(find.text('Profile modification history'), findsOneWidget);
    expect(find.textContaining('Mariam Bello'), findsOneWidget);
    expect(find.textContaining('2026-04-14T09:15:00Z'), findsOneWidget);
    expect(find.textContaining('Customer requested address correction'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    profileApi.dispose();
    customerApi.close();
  }

  testWidgets(
      'Head Office empty-permissions session can edit and audit on desktop',
      (tester) async {
    await prepareAccess(role: 'HEAD_OFFICE', permissions: {});
    await exerciseCustomer360(tester, 1280);
  });

  testWidgets('Head Office empty-permissions session remains usable on mobile',
      (tester) async {
    await prepareAccess(role: 'HEAD_OFFICE', permissions: {});
    await exerciseCustomer360(tester, 390);
  });

  testWidgets(
      'non-Head-Office wildcard and missing users.update do not expose edit',
      (tester) async {
    await prepareAccess(role: 'STATE_MANAGER', permissions: {'*'});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    final client = makeClient(
      requests: requests,
      updated: {
        'fullName': 'Ada Okafor',
        'address': '12 Palm Avenue',
      },
    );
    final api = AdminCustomer360Api(client: client);
    final profileApi = AdminCustomerProfileApi(
        client: client, baseUrl: 'https://unit.test/api');
    await tester.pumpWidget(MaterialApp(
      home: AdminCustomer360Screen(api: api, profileApi: profileApi),
    ));
    await tester.enterText(find.byType(TextField).first, 'Ada');
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Ada Okafor'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer360-edit-profile')), findsNothing);
    expect(find.byKey(const Key('customer360-profile-history')), findsNothing);
    profileApi.dispose();
    api.close();
  });

  testWidgets(
      'production-shaped Head Office with partial permissions can edit and audit',
      (tester) async {
    await prepareAccess(role: 'HEAD_OFFICE', permissions: {'wallets.adjust'});
    await exerciseCustomer360(tester, 1280);
  });

  testWidgets('explicit non-customer overview never receives profile actions',
      (tester) async {
    await prepareAccess(role: 'HEAD_OFFICE', permissions: {});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = makeClient(
      requests: <http.Request>[],
      updated: {
        'fullName': 'Alex Agent',
        'address': 'Not a customer',
        'role': 'AGENT',
      },
    );
    final api = AdminCustomer360Api(client: client);
    final profileApi = AdminCustomerProfileApi(
        client: client, baseUrl: 'https://unit.test/api');
    await tester.pumpWidget(MaterialApp(
      home: AdminCustomer360Screen(api: api, profileApi: profileApi),
    ));
    await tester.enterText(find.byType(TextField).first, 'Alex');
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Ada Okafor'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer360-edit-profile')), findsNothing);
    expect(find.byKey(const Key('customer360-profile-history')), findsNothing);
    profileApi.dispose();
    api.close();
  });
}
