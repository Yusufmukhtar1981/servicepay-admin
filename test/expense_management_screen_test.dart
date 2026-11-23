import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/expense_management/expense_api.dart';
import 'package:servicepay_app/admin/expense_management/expense_management_screen.dart';

http.Response _ok(Map<String, dynamic> data) => http.Response(jsonEncode(<String, dynamic>{'success': true, 'data': data}), 200,
    headers: <String, String>{'content-type': 'application/json'});

Map<String, dynamic> _ready(List<String> permissions) => <String, dynamic>{
      'ready': true,
      'missing': <String>[],
      'permissions': permissions,
      'actor': <String, dynamic>{'id': 'b' * 24, 'role': 'HEAD_OFFICE'},
      'workflowConfigured': true,
      'limits': <String, dynamic>{'maxDocumentBytes': 8388608, 'maxDocuments': 10},
    };

Future<List<http.Request>> _pump(WidgetTester tester, Map<String, dynamic> readiness, String section,
    {Size size = const Size(390, 844), Map<String, http.Response Function()>? routes}) async {
  final List<http.Request> requests = <http.Request>[];
  final ExpenseManagementApi api = ExpenseManagementApi(
    baseUrl: 'https://admin.test.invalid/api',
    tokenLoader: () async => 'test-session',
    downloadAdapter: (List<int> b, String n, String t) async {},
    client: MockClient((http.Request r) async {
      requests.add(r);
      final String path = r.url.path.replaceFirst('/api/admin/expense-management', '');
      if (routes != null && routes.containsKey(path)) return routes[path]!();
      return switch (path) {
        '/readiness' => _ok(readiness),
        '/references' => _ok(<String, dynamic>{'categories': <dynamic>[], 'vendors': <dynamic>[]}),
        _ => _ok(<String, dynamic>{'items': <dynamic>[], 'total': 0, 'page': 1, 'pageSize': 25, 'hasMore': false}),
      };
    }),
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExpenseManagementScreen(api: api, initialSection: section))));
  await tester.pumpAndSettle();
  return requests;
}

void main() {
  testWidgets('wildcard Head Office access is denied with the named permission', (WidgetTester tester) async {
    await _pump(tester, _ready(<String>['*']), 'audit');
    expect(find.text('Access not granted'), findsOneWidget);
    expect(find.textContaining('expenses.audit'), findsWidgets);
  });

  testWidgets('readiness failure shows no fabricated metrics', (WidgetTester tester) async {
    await _pump(tester, <String, dynamic>{}, 'dashboard', routes: <String, http.Response Function()>{
      '/readiness': () => http.Response('{"success":false,"message":"Service unavailable"}', 503),
    });
    expect(find.textContaining('could not confirm readiness'), findsOneWidget);
    expect(find.textContaining('NGN 0'), findsNothing);
  });

  testWidgets('empty expense form lists every missing field at phone width', (WidgetTester tester) async {
    final List<http.Request> requests = await _pump(tester, _ready(<String>['expenses.create', 'expenses.view']), 'new');
    await tester.ensureVisible(find.byKey(const Key('expense-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expense-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expense-form-errors')), findsOneWidget);
    expect(find.textContaining('Select an expense category.'), findsWidgets);
    expect(requests.where((http.Request r) => r.method == 'POST'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard renders server totals only', (WidgetTester tester) async {
    await _pump(tester, _ready(<String>['expenses.view']), 'dashboard', size: const Size(1280, 900), routes: <String, http.Response Function()>{
      '/summary': () => _ok(<String, dynamic>{
            'period': <String, dynamic>{'from': '2025-01-01', 'to': '2025-01-31'},
            'currency': 'NGN',
            'totals': <String, dynamic>{'totalMinor': 4725050, 'pendingCount': 3},
            'byCategory': <dynamic>[<String, dynamic>{'id': 'c', 'label': 'Fuel', 'amountMinor': 4725050, 'count': 2}],
            'byDepartment': <dynamic>[],
            'byVendor': <dynamic>[],
            'daily': <dynamic>[],
          }),
    });
    expect(find.text('NGN 47,250.50'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
    expect(find.text('Fuel'), findsOneWidget);
  });
}
