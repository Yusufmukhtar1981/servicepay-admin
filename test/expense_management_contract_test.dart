import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/expense_management/expense_api.dart';
import 'package:servicepay_app/admin/expense_management/expense_management_screen.dart';

http.Response _ok(Map<String, dynamic> data) => http.Response(jsonEncode(<String, dynamic>{'success': true, 'data': data}), 200,
    headers: <String, String>{'content-type': 'application/json'});

const String _id = 'aaaaaaaaaaaaaaaaaaaaaaaa';

Future<List<http.Request>> _pump(WidgetTester tester, List<String> permissions, String section,
    Map<String, http.Response Function()> routes, {List<String>? downloads}) async {
  final List<http.Request> requests = <http.Request>[];
  final ExpenseManagementApi api = ExpenseManagementApi(
    baseUrl: 'https://admin.test.invalid/api',
    tokenLoader: () async => 'test-session',
    downloadAdapter: (List<int> b, String n, String t) async => downloads?.add(n),
    client: MockClient((http.Request r) async {
      requests.add(r);
      final String path = r.url.path.replaceFirst('/api/admin/expense-management', '');
      if (routes.containsKey(path)) return routes[path]!();
      return switch (path) {
        '/readiness' => _ok(<String, dynamic>{
            'ready': true,
            'permissions': permissions,
            'actor': <String, dynamic>{'id': 'b' * 24, 'role': 'FINANCE'},
            'workflowConfigured': true,
            'limits': <String, dynamic>{},
          }),
        '/references' => _ok(<String, dynamic>{'categories': <dynamic>[], 'vendors': <dynamic>[]}),
        _ => _ok(<String, dynamic>{'items': <dynamic>[], 'total': 0, 'page': 1, 'pageSize': 25, 'hasMore': false}),
      };
    }),
  );
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExpenseManagementScreen(api: api, initialSection: section))));
  await tester.pumpAndSettle();
  return requests;
}

void main() {
  testWidgets('category create requires a 10+ character reason and sends it', (WidgetTester tester) async {
    final List<http.Request> requests = await _pump(tester, <String>['expenses.view', 'expenses.manage_categories'], 'categories',
        <String, http.Response Function()>{});
    await tester.tap(find.byKey(const Key('catalog-add-categories')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('catalog-name')), 'Office supplies');
    await tester.enterText(find.byKey(const Key('catalog-reason')), 'too short');
    await tester.tap(find.byKey(const Key('catalog-save')));
    await tester.pumpAndSettle();
    expect(requests.where((http.Request r) => r.method == 'POST'), isEmpty);
    await tester.enterText(find.byKey(const Key('catalog-reason')), 'New budget line approved');
    await tester.tap(find.byKey(const Key('catalog-save')));
    await tester.pumpAndSettle();
    final http.Request post = requests.singleWhere((http.Request r) => r.method == 'POST');
    expect(post.url.path, endsWith('/categories'));
    expect(post.headers['Idempotency-Key'], isNotEmpty);
    final Map<String, dynamic> body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['name'], 'Office supplies');
    expect(body['reason'], 'New budget line approved');
  });

  Future<void> openPaid(WidgetTester tester, List<String> permissions) async {
    await _pump(tester, permissions, 'expenses', <String, http.Response Function()>{
      '/expenses': () => _ok(<String, dynamic>{
            'items': <dynamic>[<String, dynamic>{'id': _id, 'title': 'Generator repair', 'status': 'PAID', 'amountMinor': 100}],
            'total': 1, 'page': 1, 'pageSize': 25, 'hasMore': false,
          }),
      '/expenses/$_id': () => _ok(<String, dynamic>{
            'item': <String, dynamic>{'id': _id, 'title': 'Generator repair', 'status': 'PAID', 'amountMinor': 100, 'revision': 4,
              'actions': <String>['REVERSE'], 'documents': <dynamic>[]},
          }),
    });
    await tester.tap(find.text('Generator repair'));
    await tester.pumpAndSettle();
  }

  testWidgets('reverse hidden with only expenses.cancel', (WidgetTester tester) async {
    await openPaid(tester, <String>['expenses.view', 'expenses.cancel']);
    expect(find.byKey(const Key('expense-action-REVERSE')), findsNothing);
  });

  testWidgets('reverse shown with expenses.cancel and expenses.pay', (WidgetTester tester) async {
    await openPaid(tester, <String>['expenses.view', 'expenses.cancel', 'expenses.pay']);
    expect(find.byKey(const Key('expense-action-REVERSE')), findsOneWidget);
  });

  testWidgets('historical toggle shows read-only legacy records and downloads receipt', (WidgetTester tester) async {
    final List<String> downloads = <String>[];
    final List<http.Request> requests = await _pump(tester, <String>['expenses.view', 'expenses.documents'], 'expenses',
        <String, http.Response Function()>{
          '/legacy-expenses': () => _ok(<String, dynamic>{
                'items': <dynamic>[<String, dynamic>{'id': 'L1', 'amount': 2500.5, 'date': '2024-03-02', 'category': 'Fuel',
                  'reference': 'OLD-7', 'recordedBy': 'Finance desk', 'supportingDocument': <String, dynamic>{'name': 'r.pdf', 'type': 'application/pdf', 'size': 10}}],
                'totalRecorded': 2500.5, 'status': 'RECORDED', 'coverage': 'partial',
              }),
          '/legacy-expenses/L1/document': () => http.Response.bytes(<int>[1, 2], 200,
              headers: <String, String>{'content-type': 'application/pdf', 'content-disposition': 'attachment; filename="r.pdf"'}),
        }, downloads: downloads);
    await tester.tap(find.byKey(const Key('records-historical')));
    await tester.pumpAndSettle();
    expect(find.text('LEGACY_RECORDED'), findsOneWidget);
    expect(find.text('NGN 2,500.50'), findsOneWidget);
    expect(find.textContaining('Approved'), findsNothing);
    expect(requests.last.url.queryParameters.keys, containsAll(<String>['from', 'to']));
    await tester.tap(find.byKey(const Key('legacy-download-L1')));
    await tester.pumpAndSettle();
    expect(downloads, <String>['r.pdf']);
  });
}
