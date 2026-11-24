import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/expense_management/expense_api.dart';
import 'package:servicepay_app/admin/expense_management/expense_management_screen.dart';
import 'package:servicepay_app/admin/expense_management/expense_requests_section.dart';
import 'package:servicepay_app/admin/main_navigation.dart';

http.Response _ok(Map<String, dynamic> data) => http.Response(jsonEncode(<String, dynamic>{'success': true, 'data': data}), 200,
    headers: <String, String>{'content-type': 'application/json'});

const String _base = '/api/admin/expense-management';

Map<String, dynamic> _readiness({
  List<String> permissions = const <String>['expenses.requests.create'],
  bool finance = false,
  bool create = true,
  bool review = false,
  bool pay = false,
  bool policies = false,
}) =>
    <String, dynamic>{
      'ready': true,
      'missing': <String>[],
      'permissions': permissions,
      'actor': <String, dynamic>{'id': 'u1', 'role': policies ? 'HEAD_OFFICE' : 'STAFF', 'fullName': 'Adaeze Okafor'},
      'workflowConfigured': true,
      'limits': <String, dynamic>{'maxDocumentBytes': 8388608, 'maxDocuments': 10},
      'financeAccess': finance,
      'requestAccess': true,
      'canCreateRequests': create,
      'canViewDepartmentRequests': false,
      'canConfigurePolicies': policies,
      'canReviewRequests': review,
      'canRecordPayments': pay,
      'department': 'Operations',
      'departments': <String>['Operations', 'Marketing'],
      'pendingRequestCount': 0,
    };

Map<String, dynamic> _request({String status = 'PENDING_APPROVAL', List<String> actions = const <String>['APPROVE', 'REJECT', 'REQUEST_CHANGES']}) =>
    <String, dynamic>{
      'id': 'r1',
      'recordType': 'DEPARTMENT_REQUEST',
      'revision': 3,
      'title': 'Generator diesel',
      'department': 'Operations',
      'amountMinor': 4572550,
      'currency': 'NGN',
      'categoryName': 'Fuel',
      'beneficiary': 'Ikeja Fuel Depot',
      'businessPurpose': 'Keep the hub powered',
      'description': 'Two drums of diesel',
      'requiredDate': '2025-03-14',
      'status': status,
      'createdByName': 'Adaeze Okafor',
      'documents': <dynamic>[],
      'approvals': <dynamic>[],
      'payment': status == 'PAID' ? <String, dynamic>{'amountMinor': 4500000, 'paidDate': '2025-03-10', 'recipient': 'Ikeja Fuel Depot', 'method': 'BANK_TRANSFER', 'reference': 'TRF-88213', 'evidenceDocumentIds': <String>['d9']} : null,
      'reviewHistory': <dynamic>[
        <String, dynamic>{'action': 'REQUEST_CHANGES', 'actorName': 'Tunde Bello', 'reason': 'Attach the depot quotation please'},
      ],
      'actions': actions,
    };

class _Harness {
  final List<http.Request> requests = <http.Request>[];
  final Map<String, http.Response Function(http.Request)> routes = <String, http.Response Function(http.Request)>{};

  ExpenseManagementApi api(Map<String, dynamic> readiness) => ExpenseManagementApi(
        baseUrl: 'https://admin.test.invalid/api',
        tokenLoader: () async => 'test-session',
        downloadAdapter: (List<int> b, String n, String t) async {},
        client: MockClient((http.Request r) async {
          requests.add(r);
          final String path = r.url.path.replaceFirst(_base, '');
          final String key = '${r.method} $path';
          if (routes.containsKey(key)) return routes[key]!(r);
          return switch (path) {
            '/readiness' => _ok(readiness),
            '/references' => _ok(<String, dynamic>{'categories': <dynamic>[], 'vendors': <dynamic>[]}),
            '/requests/references' => _ok(<String, dynamic>{
                'categories': <dynamic>[<String, dynamic>{'id': 'c1', 'name': 'Fuel', 'active': true}],
                'vendors': <dynamic>[],
                'departments': <String>['Operations', 'Marketing'],
              }),
            '/requests/notifications' => _ok(<String, dynamic>{'pendingCount': 0, 'items': <dynamic>[]}),
            _ => _ok(<String, dynamic>{'items': <dynamic>[], 'total': 0, 'page': 1, 'pageSize': 25, 'hasMore': false}),
          };
        }),
      );

  Iterable<http.Request> writes(String path) => requests.where((http.Request r) => r.method != 'GET' && r.url.path == '$_base$path');
}

Future<void> _pump(WidgetTester tester, ExpenseManagementApi api, {String section = 'dashboard', Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: ExpenseManagementScreen(api: api, initialSection: section, notificationInterval: const Duration(hours: 1))),
  ));
  await tester.pumpAndSettle();
}

Future<void> _enterReason(WidgetTester tester, String reason) async {
  await tester.enterText(find.byKey(const Key('reason-field')), reason);
  await tester.pump();
  await tester.tap(find.byKey(const Key('reason-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  group('navigation', () {
    test('explicit request, approve and pay permissions admit Financial Management', () {
      for (final String p in <String>['expenses.requests.create', 'expenses.requests.department', 'expenses.approve', 'expenses.pay', 'expenses.view']) {
        expect(canAccessExpenseManagementNavigation(permissions: <String>{p}), isTrue, reason: p);
      }
      expect(canAccessExpenseManagementNavigation(permissions: <String>{'*', 'expenses.*'}), isFalse);
      expect(initialExpenseSection(permissions: <String>{'expenses.requests.create'}), 'my');
      expect(initialExpenseSection(permissions: <String>{'expenses.view'}), 'dashboard');
    });
  });

  group('navigation grant merge', () {
    test('merges only the six scoped expense keys from readiness', () {
      final Set<String> merged = mergeExpenseGrantPermissions(<String>{'marketing.view'}, <String, dynamic>{
        'permissions': <String>['expenses.requests.create', 'EXPENSES.DOCUMENTS', 'expenses.manage_policy', 'expenses.*', '*', 'staff.manage', 'expenses.pay'],
      });
      expect(merged, <String>{'marketing.view', 'expenses.requests.create', 'expenses.documents', 'expenses.pay'});
      expect(canAccessExpenseManagementNavigation(permissions: merged), isTrue);
      expect(mergeExpenseGrantPermissions(<String>{'a'}, null), <String>{'a'});
    });

    test('probe merges grants for STAFF, keeps base on 403, skips other roles', () async {
      final _Harness h = _Harness();
      final Set<String> granted = await probeExpenseGrantPermissions(
          role: 'STAFF', base: <String>{'marketing.view'}, api: h.api(_readiness(permissions: <String>['expenses.approve', 'expenses.manage_policy'])));
      expect(granted, <String>{'marketing.view', 'expenses.approve'});
      final _Harness denied = _Harness()..routes['GET /readiness'] = (_) => http.Response('{"success":false,"message":"Forbidden"}', 403);
      final Set<String> base = await probeExpenseGrantPermissions(role: 'STAFF', base: <String>{'marketing.view'}, api: denied.api(_readiness()));
      expect(base, <String>{'marketing.view'});
      expect(canAccessExpenseManagementNavigation(permissions: base), isFalse);
      final _Harness other = _Harness();
      await probeExpenseGrantPermissions(role: 'ZONAL_MANAGER', base: <String>{}, api: other.api(_readiness()));
      expect(other.requests, isEmpty);
    });
  });

  group('api', () {
    test('create sends submit flag, decimal amount and stable key', () async {
      final _Harness h = _Harness();
      h.routes['POST /requests'] = (_) => _ok(<String, dynamic>{'item': _request(status: 'SUBMITTED')});
      final ExpenseManagementApi api = h.api(_readiness());
      final String key = ExpenseIdempotency.newKey('req');
      await api.createRequest(<String, dynamic>{'title': 'Diesel', 'amount': '45725.50', 'documentIds': <String>[]}, submit: true, idempotencyKey: key);
      final http.Request r = h.writes('/requests').single;
      expect(r.headers['Idempotency-Key'], key);
      final Map<String, dynamic> body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['submit'], isTrue);
      expect(body['amount'], '45725.50');
    });

    test('PAY carries payment, external confirmation and rejects short reasons locally', () async {
      final _Harness h = _Harness();
      h.routes['POST /requests/r1/actions'] = (_) => _ok(<String, dynamic>{'item': _request(status: 'PAID', actions: <String>[])});
      final ExpenseManagementApi api = h.api(_readiness());
      expect(
        () => api.requestAction('r1', action: 'REJECT', expectedVersion: 3, reason: 'short', idempotencyKey: ExpenseIdempotency.newKey()),
        throwsA(isA<ExpenseApiException>()),
      );
      await api.requestAction('r1',
          action: 'PAY',
          expectedVersion: 3,
          reason: 'Paid by bank transfer outside ServicePay',
          idempotencyKey: ExpenseIdempotency.newKey(),
          payment: <String, dynamic>{'amount': '45725.50', 'evidenceDocumentIds': <String>['d9']});
      final Map<String, dynamic> body = jsonDecode(h.writes('/requests/r1/actions').single.body) as Map<String, dynamic>;
      expect(body['confirmExternalPayment'], isTrue);
      expect(body['expectedVersion'], 3);
      expect((body['payment'] as Map<String, dynamic>)['evidenceDocumentIds'], <String>['d9']);
    });

    test('assignment sends only true capabilities and never revokes', () async {
      final _Harness h = _Harness();
      h.routes['POST /requests/assignments'] = (_) => _ok(<String, dynamic>{'assigned': true});
      final ExpenseManagementApi api = h.api(_readiness());
      await api.assignRequestCapabilities(
        userId: 'p1',
        capabilities: <String, bool>{'requester': true, 'approver': false},
        expectedRoleId: 'role-ops',
        reason: 'Operations lead submits requests',
        idempotencyKey: ExpenseIdempotency.newKey(),
      );
      final Map<String, dynamic> body = jsonDecode(h.writes('/requests/assignments').single.body) as Map<String, dynamic>;
      expect(body['capabilities'], <String, dynamic>{'requester': true});
      expect(body['expectedRoleId'], 'role-ops');
      expect(
        () => api.assignRequestCapabilities(
            userId: 'p1', capabilities: <String, bool>{'finance': false}, expectedRoleId: 'r', reason: 'long enough reason', idempotencyKey: ExpenseIdempotency.newKey()),
        throwsA(isA<ExpenseApiException>()),
      );
    });

    test('request uploads and downloads use private request endpoints', () async {
      final _Harness h = _Harness();
      h.routes['POST /requests/documents'] = (_) => _ok(<String, dynamic>{'document': <String, dynamic>{'id': 'd1', 'name': 'q.pdf'}});
      h.routes['GET /requests/r1/documents/d1/download'] =
          (_) => http.Response.bytes(<int>[37, 80, 68, 70], 200, headers: <String, String>{'content-type': 'application/pdf'});
      final ExpenseManagementApi api = h.api(_readiness());
      await api.uploadRequestDocument(ExpenseDocumentUpload(bytes: <int>[1, 2, 3], filename: 'q.pdf', idempotencyKey: ExpenseIdempotency.newKey()));
      await api.downloadRequestDocument('r1', 'd1');
      expect(h.requests.map((http.Request r) => r.url.path), containsAll(<String>['$_base/requests/documents', '$_base/requests/r1/documents/d1/download']));
    });

    test('decimalToMinor converts NGN to kobo', () {
      expect(decimalToMinor('45,725.5'), 4572550);
      expect(decimalToMinor('abc'), isNull);
    });
  });

  group('widgets', () {
    testWidgets('request-only staff land on My Expense Requests with no finance sections', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h.api(_readiness()));
      expect(find.text('My Expense Requests'), findsWidgets);
      expect(find.byKey(const Key('expense-nav-dashboard')), findsNothing);
      expect(find.byKey(const Key('expense-nav-vendors')), findsNothing);
      expect(find.byKey(const Key('expense-nav-reports')), findsNothing);
      expect(find.byKey(const Key('expense-nav-audit')), findsNothing);
      expect(h.requests.any((http.Request r) => r.url.path == '$_base/summary' || r.url.path == '$_base/references'), isFalse);
      expect(h.requests.any((http.Request r) => r.url.path == '$_base/requests/notifications'), isTrue);
    });

    testWidgets('phone submit validates offscreen fields and sends nothing', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h.api(_readiness()));
      await tester.tap(find.byKey(const Key('request-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('request-amount')), '0');
      await tester.ensureVisible(find.byKey(const Key('request-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('request-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('request-form-errors')), findsOneWidget);
      expect(find.textContaining('Request title is required.'), findsWidgets);
      expect(find.textContaining('Amount must be greater than zero.'), findsWidgets);
      expect(h.writes('/requests'), isEmpty);
    });

    testWidgets('draft save failure preserves input and retries with the same key', (WidgetTester tester) async {
      final _Harness h = _Harness();
      int calls = 0;
      h.routes['POST /requests'] = (_) {
        calls++;
        return calls == 1
            ? http.Response('{"success":false,"message":"Gateway failure"}', 502)
            : _ok(<String, dynamic>{'item': _request(status: 'DRAFT', actions: <String>['EDIT', 'SUBMIT'])});
      };
      h.routes['GET /requests/r1'] = (_) => _ok(<String, dynamic>{'item': _request(status: 'DRAFT', actions: <String>['EDIT', 'SUBMIT'])});
      h.routes['GET /requests/r1/audit'] = (_) => _ok(<String, dynamic>{'items': <dynamic>[]});
      await _pump(tester, h.api(_readiness()));
      await tester.tap(find.byKey(const Key('request-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('request-title')), 'Generator diesel');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('request-save-draft')), 120,
          scrollable: find.byWidgetPredicate((Widget w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('request-save-draft')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('request-save-error')), findsOneWidget);
      expect(find.text('Generator diesel'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('request-save-draft')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('request-save-draft')));
      await tester.pumpAndSettle();
      final List<http.Request> posts = h.writes('/requests').toList();
      expect(posts, hasLength(2));
      expect(posts[0].headers['Idempotency-Key'], posts[1].headers['Idempotency-Key']);
      expect((jsonDecode(posts[1].body) as Map<String, dynamic>)['submit'], isFalse);
      expect(find.text('Expense request'), findsOneWidget);
    });

    testWidgets('assigned reviewer approves from Pending Approvals and sees history', (WidgetTester tester) async {
      final _Harness h = _Harness();
      h.routes['GET /requests'] = (_) => _ok(<String, dynamic>{'items': <dynamic>[_request()], 'total': 1, 'page': 1, 'pageSize': 25, 'hasMore': false});
      Map<String, dynamic> current = _request();
      h.routes['GET /requests/r1'] = (_) => _ok(<String, dynamic>{'item': current});
      h.routes['GET /requests/r1/audit'] = (_) => _ok(<String, dynamic>{'items': <dynamic>[]});
      h.routes['POST /requests/r1/actions'] = (_) {
        current = _request(status: 'APPROVED', actions: <String>[]);
        return _ok(<String, dynamic>{'item': current});
      };
      await _pump(tester, h.api(_readiness(permissions: <String>['expenses.approve'], create: false, review: true)), section: 'approvals', size: const Size(1280, 1600));
      expect(h.requests.any((http.Request r) => r.url.queryParameters['scope'] == 'assigned'), isTrue);
      await tester.tap(find.byKey(const Key('request-row-r1')));
      await tester.pumpAndSettle();
      expect(find.text('Attach the depot quotation please'), findsOneWidget);
      await tester.tap(find.byKey(const Key('request-action-APPROVE')));
      await tester.pumpAndSettle();
      await _enterReason(tester, 'Within budget and documented');
      final Map<String, dynamic> body = jsonDecode(h.writes('/requests/r1/actions').single.body) as Map<String, dynamic>;
      expect(body['action'], 'APPROVE');
      expect(body['expectedVersion'], 3);
      expect(find.text('Approved'), findsWidgets);
    });

    testWidgets('payment dialog requires proof, matching recipient and confirmation', (WidgetTester tester) async {
      final _Harness h = _Harness();
      final Map<String, dynamic> approved = _request(status: 'APPROVED', actions: <String>['PAY']);
      h.routes['GET /requests/r1'] = (_) => _ok(<String, dynamic>{'item': approved});
      h.routes['GET /requests/r1/audit'] = (_) => _ok(<String, dynamic>{'items': <dynamic>[]});
      h.routes['GET /requests'] = (_) => _ok(<String, dynamic>{'items': <dynamic>[approved], 'total': 1, 'page': 1, 'pageSize': 25, 'hasMore': false});
      await _pump(tester, h.api(_readiness(permissions: <String>['expenses.pay'], create: false, pay: true)), section: 'approved', size: const Size(1280, 1600));
      await tester.tap(find.byKey(const Key('request-row-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('request-action-PAY')));
      await tester.pumpAndSettle();
      expect(find.textContaining('does not send money'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('pay-amount')), '99999999');
      await tester.enterText(find.byKey(const Key('pay-recipient')), 'Someone Else');
      await tester.tap(find.byKey(const Key('pay-submit')));
      await tester.pumpAndSettle();
      final Finder errors = find.byKey(const Key('pay-errors'));
      expect(errors, findsOneWidget);
      expect(find.descendant(of: errors, matching: find.textContaining('Cannot exceed')), findsOneWidget);
      expect(find.descendant(of: errors, matching: find.textContaining('must match the approved payee')), findsOneWidget);
      expect(find.descendant(of: errors, matching: find.textContaining('proof of payment')), findsOneWidget);
      expect(h.writes('/requests/r1/actions'), isEmpty);
    });

    testWidgets('payment record shows paidDate and separates proof from attachments', (WidgetTester tester) async {
      final _Harness h = _Harness();
      final Map<String, dynamic> paid = _request(status: 'PAID', actions: <String>[])
        ..['documents'] = <dynamic>[
          <String, dynamic>{'id': 'd1', 'name': 'quotation.pdf', 'mimeType': 'application/pdf', 'size': 2048},
          <String, dynamic>{'id': 'd9', 'name': 'transfer-slip.png', 'mimeType': 'image/png', 'size': 4096},
        ];
      h.routes['GET /requests/r1'] = (_) => _ok(<String, dynamic>{'item': paid});
      h.routes['GET /requests/r1/audit'] = (_) => _ok(<String, dynamic>{'items': <dynamic>[]});
      h.routes['GET /requests'] = (_) => _ok(<String, dynamic>{'items': <dynamic>[paid], 'total': 1, 'page': 1, 'pageSize': 25, 'hasMore': false});
      await _pump(tester, h.api(_readiness()), size: const Size(1280, 2400));
      await tester.tap(find.byKey(const Key('request-row-r1')));
      await tester.pumpAndSettle();
      expect(find.text('Payment recorded'), findsWidgets);
      expect(find.text('2025-03-10'), findsOneWidget);
      expect(find.text('quotation.pdf'), findsOneWidget);
      expect(find.text('transfer-slip.png'), findsOneWidget);
      expect(find.textContaining('did not execute this transfer'), findsOneWidget);
    });

    testWidgets('policy activation without explicit limits or reviewers is blocked locally', (WidgetTester tester) async {
      final _Harness h = _Harness();
      h.routes['GET /approval-policies'] = (_) => _ok(<String, dynamic>{
            'items': <dynamic>[],
            'people': <dynamic>[
              <String, dynamic>{
                'id': 'p1',
                'fullName': 'Tunde Bello',
                'department': 'Finance',
                'roleId': 'r1',
                'scope': 'GLOBAL',
                'capabilities': <String, dynamic>{'approver': true, 'requester': false, 'departmentManager': false, 'finance': false},
              },
            ],
            'departments': <String>['Operations', 'Marketing'],
          });
      await _pump(tester, h.api(_readiness(permissions: <String>['expenses.manage_policy'], create: false, policies: true)),
          section: 'policies', size: const Size(1280, 2000));
      expect(find.textContaining('No approval policies are configured'), findsOneWidget);
      await tester.tap(find.byKey(const Key('policy-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('policy-name')), 'Operations spend');
      await tester.tap(find.byKey(const Key('policy-dept-Operations')));
      await tester.tap(find.byKey(const Key('policy-active')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('policy-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Activation requires explicit minimum and maximum amounts.'), findsOneWidget);
      expect(find.textContaining('Activation requires at least one approval level.'), findsOneWidget);
      expect(h.writes('/approval-policies'), isEmpty);
      // Assignment dialog keeps existing capabilities and needs confirmation.
      await tester.tap(find.byKey(const Key('assign-p1')));
      await tester.pumpAndSettle();
      expect(find.text('Already granted'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cap-requester')));
      await tester.enterText(find.byKey(const Key('cap-reason')), 'Needs to raise requests');
      await tester.tap(find.byKey(const Key('cap-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Confirm the grant explicitly.'), findsOneWidget);
      expect(h.writes('/requests/assignments'), isEmpty);
    });
  });
}
