import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/admin_customer_360_api.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/admin_virtual_account_management_api.dart';
import 'package:servicepay_app/admin/admin_virtual_account_management_screen.dart';
import 'package:servicepay_app/admin/main_navigation.dart';

Map<String, dynamic> _job(String id, String status,
        {int failed = 0, int total = 12}) =>
    {
      'id': id,
      'status': status,
      'total': total,
      'processed': total - 2,
      'successful': total - 2 - failed,
      'failed': failed,
      'pending': 2,
      'skipped': 0,
      'createdAt': '2025-03-04T09:12:00Z',
      'updatedAt': '2025-03-04T09:14:00Z',
    };

class _Backend {
  _Backend({
    this.storageReady = true,
    this.generate = true,
    this.bulk = true,
    this.jobStatus = 'COMPLETED',
    this.failed = 3,
  });
  bool storageReady, generate, bulk;
  String jobStatus;
  int failed;
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? onPost;

  http.Response _ok(Object data) =>
      http.Response(jsonEncode({'success': true, 'data': data}), 200,
          headers: {'content-type': 'application/json'});

  MockClient get client => MockClient((r) async {
        requests.add(r);
        final p = r.url.path;
        if (r.method == 'POST') return onPost!(r);
        if (p.endsWith('/summary')) {
          return _ok({
            'totalCustomers': 4187,
            'withoutAccounts': 213,
            'withAccounts': 3974,
            'permissions': {'view': true, 'generate': generate, 'bulk': bulk},
            'storageReady': storageReady,
          });
        }
        if (p.endsWith('/report')) {
          return http.Response.bytes(utf8.encode('customerId,status\nc1,SUCCESS\n'), 200,
              headers: {
                'content-type': 'text/csv',
                'content-disposition':
                    'attachment; filename="../va job 7.csv"',
              });
        }
        if (p.endsWith('/jobs')) {
          return _ok({
            'items': [_job('job-7', jobStatus, failed: failed)],
            'pagination': {'page': 1, 'limit': 20, 'total': 1, 'pages': 1},
          });
        }
        if (p.contains('/jobs/')) {
          return _ok({
            'job': _job('job-7', jobStatus, failed: failed),
            'items': [
              {
                'customerId': 'c1',
                'fullName': 'Chinedu Okafor',
                'phone': '08031234567',
                'status': 'FAILED',
                'reason': 'BVN mismatch',
                'updatedAt': '2025-03-04T09:14:00Z'
              }
            ],
            'pagination': {'page': 1, 'limit': 20, 'total': 1, 'pages': 1},
          });
        }
        if (p.endsWith('/customer360/directory')) {
          return _ok({
            'items': [
              {
                'id': 'c9',
                'fullName': 'Aisha Lawal',
                'phone': '08099998888',
                'email': 'aisha@example.ng',
                'status': 'ACTIVE',
                'active': true,
                'hasVirtualAccount': false,
                'eligibility': {
                  'reason': 'Eligible',
                  'canGenerate': true,
                  'canRetry': false,
                  'requiresReconciliation': false
                }
              }
            ],
            'pagination': {'page': 1, 'limit': 20, 'total': 1, 'pages': 1},
          });
        }
        return http.Response('{}', 404);
      });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'auth_token': 'admin-session-token', 'user_role': 'HEAD_OFFICE'});
  });

  Future<List<List<Object>>> pump(WidgetTester tester, _Backend backend,
      {Duration timeout = const Duration(seconds: 30)}) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final downloads = <List<Object>>[];
    final client = backend.client;
    await tester.pumpWidget(MaterialApp(
      home: AdminVirtualAccountManagementScreen(
        api: AdminVirtualAccountManagementApi(
            client: client, baseUrl: 'https://test.local/api', timeout: timeout),
        directoryApi: AdminCustomer360Api(client: client),
        access: const AdminAccess(role: 'HEAD_OFFICE', permissions: {}),
        downloader: (bytes, type, name) async =>
            downloads.add([bytes, type, name]),
        pollInterval: const Duration(seconds: 5),
      ),
    ));
    await tester.pumpAndSettle();
    return downloads;
  }

  Future<void> confirm(WidgetTester tester, {String reason = 'Monthly backfill'}) async {
    await tester.enterText(find.byKey(const Key('va-reason')), reason);
    await tester.tap(find.byKey(const Key('va-acknowledge')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('va-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('renders real summary at 390px without overflow', (tester) async {
    await pump(tester, _Backend());
    expect(find.text('4187'), findsOneWidget);
    expect(find.text('213'), findsOneWidget);
    expect(find.text('Generate Missing Accounts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing storage disables generation and never posts',
      (tester) async {
    final backend = _Backend(storageReady: false);
    await pump(tester, backend);
    expect(find.byKey(const Key('va-storage-missing')), findsOneWidget);
    final button =
        tester.widget<FilledButton>(find.byKey(const Key('va-generate')));
    expect(button.onPressed, isNull);
    expect(backend.requests.any((r) => r.method == 'POST'), isFalse);
  });

  testWidgets('confirmation requires reason + acknowledgement; cancel sends nothing',
      (tester) async {
    final backend = _Backend();
    await pump(tester, backend);
    await tester.tap(find.byKey(const Key('va-generate')));
    await tester.pumpAndSettle();
    expect(
        tester.widget<FilledButton>(find.byKey(const Key('va-confirm'))).onPressed,
        isNull);
    await tester.enterText(find.byKey(const Key('va-reason')), 'abc');
    await tester.tap(find.byKey(const Key('va-acknowledge')));
    await tester.pumpAndSettle();
    expect(
        tester.widget<FilledButton>(find.byKey(const Key('va-confirm'))).onPressed,
        isNull);
    await tester.tap(find.byKey(const Key('va-cancel')));
    await tester.pumpAndSettle();
    expect(backend.requests.any((r) => r.method == 'POST'), isFalse);
  });

  testWidgets('ALL mode posts confirmed body once', (tester) async {
    final backend = _Backend();
    final bodies = <Map<String, dynamic>>[];
    backend.onPost = (r) async {
      bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
      return http.Response(
          jsonEncode({
            'success': true,
            'data': {'job': _job('job-8', 'QUEUED')}
          }),
          201);
    };
    await pump(tester, backend);
    await tester.tap(find.byKey(const Key('va-generate')));
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(bodies, hasLength(1));
    expect(bodies.single['mode'], 'ALL');
    expect(bodies.single['confirmed'], true);
    expect(bodies.single['customerIds'], isEmpty);
    expect(bodies.single['reason'], 'Monthly backfill');
    expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4').hasMatch(bodies.single['requestId']),
        isTrue);
  });

  testWidgets('selected customers come from directory', (tester) async {
    final backend = _Backend();
    final bodies = <Map<String, dynamic>>[];
    backend.onPost = (r) async {
      bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
      return http.Response(
          jsonEncode({
            'success': true,
            'data': {'job': _job('job-9', 'COMPLETED')}
          }),
          201);
    };
    await pump(tester, backend);
    await tester.tap(find.byKey(const Key('directory-select-c9')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('va-generate')));
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(bodies.single['mode'], 'SELECTED');
    expect(bodies.single['customerIds'], ['c9']);
  });

  testWidgets('timeout keeps requestId, refreshes jobs, never auto-resends',
      (tester) async {
    final backend = _Backend();
    final bodies = <Map<String, dynamic>>[];
    backend.onPost = (r) async {
      bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
      if (bodies.length == 1) {
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      return http.Response(
          jsonEncode({
            'success': true,
            'data': {'job': _job('job-10', 'QUEUED')}
          }),
          200);
    };
    await pump(tester, backend, timeout: const Duration(seconds: 1));
    final jobsBefore =
        backend.requests.where((r) => r.url.path.endsWith('/jobs')).length;
    await tester.tap(find.byKey(const Key('va-generate')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('va-reason')), 'Monthly backfill');
    await tester.tap(find.byKey(const Key('va-acknowledge')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('va-confirm')));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('va-uncertain')), findsOneWidget);
    expect(bodies, hasLength(1));
    expect(
        backend.requests.where((r) => r.url.path.endsWith('/jobs') && r.method == 'GET').length,
        greaterThan(jobsBefore));
    expect(
        tester.widget<FilledButton>(find.byKey(const Key('va-generate'))).onPressed,
        isNull);

    await tester.tap(find.byKey(const Key('va-resubmit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('va-resubmit-confirm')));
    await tester.pumpAndSettle();
    expect(bodies, hasLength(2));
    expect(bodies[1]['requestId'], bodies[0]['requestId']);
    expect(find.byKey(const Key('va-uncertain')), findsNothing);
  });

  testWidgets('503 on create is treated as possibly committed', (tester) async {
    final backend = _Backend();
    final bodies = <Map<String, dynamic>>[];
    backend.onPost = (r) async {
      bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
      return http.Response(
          jsonEncode({'success': false, 'message': 'Service unavailable'}),
          503);
    };
    await pump(tester, backend);
    await tester.tap(find.byKey(const Key('va-generate')));
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(find.byKey(const Key('va-uncertain')), findsOneWidget);
    expect(bodies, hasLength(1));
    expect(
        tester.widget<FilledButton>(find.byKey(const Key('va-generate'))).onPressed,
        isNull);
    await tester.tap(find.byKey(const Key('va-resubmit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('va-resubmit-confirm')));
    await tester.pumpAndSettle();
    expect(bodies, hasLength(2));
    expect(bodies[1]['requestId'], bodies[0]['requestId']);
    expect(bodies[1]['reason'], bodies[0]['reason']);
  });

  testWidgets('generate without bulk cannot create any background job',
      (tester) async {
    final backend = _Backend(bulk: false);
    await pump(tester, backend);
    expect(
        tester.widget<FilledButton>(find.byKey(const Key('va-generate'))).onPressed,
        isNull);
    expect(find.byKey(const Key('directory-select-c9')), findsNothing);
    // Individual generation stays available through the existing panel.
    expect(find.byKey(const Key('directory-va-c9')), findsOneWidget);
    await tester.tap(find.byKey(const Key('va-job-job-7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('va-retry')), findsNothing);
    expect(backend.requests.any((r) => r.method == 'POST'), isFalse);
  });

  testWidgets('retry only for failed results of inactive jobs', (tester) async {
    final backend = _Backend(jobStatus: 'RUNNING');
    await pump(tester, backend);
    await tester.tap(find.byKey(const Key('va-job-job-7')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
        tester.widget<OutlinedButton>(find.byKey(const Key('va-retry'))).onPressed,
        isNull);
    // Active job polls while visible.
    final before = backend.requests.length;
    await tester.pump(const Duration(seconds: 6));
    expect(backend.requests.length, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    final afterDispose = backend.requests.length;
    await tester.pump(const Duration(seconds: 12));
    expect(backend.requests.length, afterDispose);
  });

  testWidgets('retry posts to job retry endpoint and CSV downloads sanitized',
      (tester) async {
    final backend = _Backend();
    final posts = <http.Request>[];
    backend.onPost = (r) async {
      posts.add(r);
      return http.Response(
          jsonEncode({
            'success': true,
            'data': {'job': _job('job-7', 'QUEUED')}
          }),
          200);
    };
    final downloads = await pump(tester, backend);
    await tester.tap(find.byKey(const Key('va-job-job-7')));
    await tester.pumpAndSettle();
    expect(find.text('Chinedu Okafor'), findsOneWidget);

    await tester.tap(find.byKey(const Key('va-download')));
    await tester.pumpAndSettle();
    expect(downloads.single[2], 'va_job_7.csv');

    await tester.tap(find.byKey(const Key('va-retry')));
    await tester.pumpAndSettle();
    await confirm(tester, reason: 'Retry BVN mismatches');
    expect(posts.single.url.path, endsWith('/jobs/job-7/retry'));
    final body = jsonDecode(posts.single.body) as Map<String, dynamic>;
    expect(body['confirmed'], true);
    expect(body.containsKey('mode'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  test('report rejects HTML bodies', () async {
    final api = AdminVirtualAccountManagementApi(
      baseUrl: 'https://test.local/api',
      tokenLoader: () async => 't',
      client: MockClient((_) async => http.Response('<html>login</html>', 200,
          headers: {'content-type': 'text/html'})),
    );
    expect(() => api.report('job-1'),
        throwsA(isA<VirtualAccountManagementException>()));
  });

  test('navigation gate: Head Office or explicit view permission', () {
    expect(
        canAccessVirtualAccountManagementNavigation(
            role: 'HEAD_OFFICE', permissions: {}),
        isTrue);
    expect(
        canAccessVirtualAccountManagementNavigation(
            role: 'STAFF',
            permissions: {AdminPermissions.operationsVirtualAccountsView}),
        isTrue);
    expect(
        canAccessVirtualAccountManagementNavigation(
            role: 'STAFF', permissions: {'*'}),
        isFalse);
    expect(
        AdminMainNavigation.visibleDestinationLabels(const AdminAccess(
            role: 'STAFF',
            permissions: {AdminPermissions.operationsVirtualAccountsView})),
        contains('Virtual Account Management'));
  });
}
