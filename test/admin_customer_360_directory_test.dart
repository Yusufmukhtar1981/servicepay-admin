import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/admin_customer_360_api.dart';
import 'package:servicepay_app/admin/admin_customer_360_screen.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/customer_360_directory.dart';

Map<String, dynamic> _row(String id, {bool hasAccount = false}) => {
      'id': id,
      'fullName': 'Halima Bello $id',
      'phone': '+234 803 555 0$id',
      'email': 'halima$id@example.ng',
      'status': 'ACTIVE',
      'active': true,
      'hasVirtualAccount': hasAccount,
      'accountStatus': hasAccount ? 'ACTIVE' : null,
      'eligibility': {
        'reason': hasAccount ? 'Account already active' : 'Eligible',
        'canGenerate': !hasAccount,
        'canRetry': false,
        'requiresReconciliation': false,
      },
    };

MockClient _client(List<http.Request> requests,
        {int total = 2, int pages = 2, bool fail = false, bool empty = false}) =>
    MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('/customer360/directory')) {
        if (fail) {
          return http.Response(
              jsonEncode({'success': false, 'message': 'Directory offline'}),
              500);
        }
        final page = int.parse(request.url.queryParameters['page'] ?? '1');
        return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'items': empty ? [] : [_row('${page}1'), _row('${page}2', hasAccount: true)],
                'pagination': {
                  'page': page,
                  'limit': 20,
                  'total': empty ? 0 : total,
                  'pages': empty ? 0 : pages
                },
              }
            }),
            200);
      }
      if (path.contains('/customer360/')) {
        return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'profile': {'id': '11', 'fullName': 'Halima Bello 11'},
                'items': [],
                'pagination': {'page': 1, 'totalPages': 1},
                'capabilities': {},
              }
            }),
            200);
      }
      return http.Response('{}', 404);
    });

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'auth_token': 'admin-session-token', 'user_role': 'HEAD_OFFICE'});
  });

  Future<void> pumpDirectory(WidgetTester tester, AdminCustomer360Api api,
      {List<Uri>? dialled}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdminCustomer360Directory(
            api: api,
            onOpenProfile: (_) {},
            phoneLauncher: (uri) async {
              dialled?.add(uri);
              return true;
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('loads directory and applies status/account filters',
      (tester) async {
    final requests = <http.Request>[];
    await pumpDirectory(
        tester, AdminCustomer360Api(client: _client(requests)));
    expect(find.text('Halima Bello 11'), findsOneWidget);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(requests.last.url.queryParameters.containsKey('status'), isFalse);

    await tester.tap(find.byKey(const Key('directory-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Active').last);
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['status'], 'ACTIVE');

    await tester.tap(find.byKey(const Key('directory-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Without account').last);
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['account'], 'WITHOUT');
    expect(requests.last.url.queryParameters['page'], '1');

    await tester.tap(find.byKey(const Key('directory-next')));
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['page'], '2');
    expect(find.text('Halima Bello 21'), findsOneWidget);
  });

  testWidgets('search requires two characters before requesting',
      (tester) async {
    final requests = <http.Request>[];
    await pumpDirectory(
        tester, AdminCustomer360Api(client: _client(requests)));
    final before = requests.length;
    await tester.enterText(find.byKey(const Key('directory-search')), 'h');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('directory-search-min')), findsOneWidget);
    expect(requests.length, before);
    await tester.enterText(find.byKey(const Key('directory-search')), 'ha');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(requests.last.url.queryParameters['q'], 'ha');
  });

  testWidgets('shows error with retry and empty state', (tester) async {
    var offline = true;
    final api = AdminCustomer360Api(client: MockClient((request) async =>
        http.Response(
            jsonEncode(offline
                ? {'success': false, 'message': 'Directory offline'}
                : {
                    'success': true,
                    'data': {
                      'items': [],
                      'pagination': {'page': 1, 'limit': 20, 'total': 0, 'pages': 1}
                    }
                  }),
            offline ? 503 : 200,
            headers: {'content-type': 'application/json'})));
    await pumpDirectory(tester, api);
    expect(find.byKey(const Key('directory-error')), findsOneWidget);
    expect(find.text('Directory offline'), findsOneWidget);

    offline = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('directory-empty')), findsOneWidget);
  });

  testWidgets('phone numbers open tel links', (tester) async {
    final dialled = <Uri>[];
    await pumpDirectory(tester, AdminCustomer360Api(client: _client([])),
        dialled: dialled);
    await tester.tap(find.byKey(const Key('directory-call-11')));
    await tester.pumpAndSettle();
    expect(dialled.single.scheme, 'tel');
    expect(dialled.single.path, '+2348035550' '11');
  });

  testWidgets('Customer 360 directory opens profile via existing selection',
      (tester) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final requests = <http.Request>[];
    await tester.pumpWidget(MaterialApp(
      home: AdminCustomer360Screen(
        api: AdminCustomer360Api(client: _client(requests)),
        access: const AdminAccess(role: 'HEAD_OFFICE', permissions: {}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer-directory')), findsOneWidget);
    expect(find.byKey(const Key('directory-va-11')), findsOneWidget);
    await tester.tap(find.byKey(const Key('directory-open-11')));
    await tester.pumpAndSettle();
    expect(
        requests.any((r) => r.url.path.endsWith('/customer360/11')), isTrue);
    // Selecting a profile never posts a generation request.
    expect(requests.every((r) => r.method == 'GET'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('VA view permission shows VA action without profile editing',
      (tester) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: AdminCustomer360Screen(
        api: AdminCustomer360Api(client: _client([])),
        access: const AdminAccess(
            role: 'STAFF',
            permissions: {AdminPermissions.operationsVirtualAccountsView}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('directory-va-11')), findsOneWidget);
    expect(find.text('READ ONLY'), findsOneWidget);
    await tester.tap(find.byKey(const Key('directory-open-11')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer360-virtual-account')), findsOneWidget);
    expect(find.byKey(const Key('customer360-edit-profile')), findsNothing);
    expect(find.byKey(const Key('customer360-profile-history')), findsNothing);
  });
}
