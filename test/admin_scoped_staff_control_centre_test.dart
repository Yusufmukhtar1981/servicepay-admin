import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/main_navigation.dart';
import 'package:servicepay_app/admin/staff_control_centre_scoped.dart';
import 'package:servicepay_app/admin/staff_management_screen.dart';

const _ops = AdminAccess(
  role: 'STAFF',
  permissions: {AdminPermissions.operationsStaffManage},
);

class _Backend {
  _Backend({this.zonals = true, this.canCreateSupport = true});
  final bool zonals, canCreateSupport;
  final requests = <http.Request>[];

  http.Response _json(Object body, [int code = 200]) =>
      http.Response(jsonEncode(body), code);

  MockClient get client => MockClient((r) async {
        requests.add(r);
        final p = r.url.path;
        if (p.endsWith('/staff/options')) {
          return _json({
            'success': true,
            'data': {
              'supportRole': canCreateSupport
                  ? {'id': 'r1', 'name': 'CUSTOMER_SUPPORT', 'displayName': 'Customer Support'}
                  : null,
              'canCreateSupport': canCreateSupport,
              'zonalManagers': zonals
                  ? [
                      {'id': 'z1', 'fullName': 'Musa Danjuma', 'zone': 'North Central'}
                    ]
                  : [],
              'managerTypes': ['ZONAL_MANAGER', 'STATE_MANAGER'],
              'zonalPermissionProfiles': [
                {'id': 'STANDARD', 'label': 'Standard', 'permissions': ['operations.workspace.view', 'users.view']},
                {'id': 'READ_ONLY', 'label': 'Read only', 'permissions': ['operations.workspace.view']},
                {'id': 'GODMODE', 'label': 'Injected', 'permissions': ['*']},
              ],
            }
          });
        }
        if (p.endsWith('/managers') && r.method == 'GET') {
          return _json({
            'success': true,
            'data': {
              'items': [
                {
                  'id': 'm1',
                  'fullName': 'Musa Danjuma',
                  'role': r.url.queryParameters['role'],
                  'status': 'ACTIVE',
                  'zone': 'North Central',
                  'phone': '08030001111',
                  'permissionProfile': 'READ_ONLY',
                }
              ],
              'pagination': {'page': 1, 'limit': 20, 'total': 1, 'pages': 1},
            }
          });
        }
        if (p.endsWith('/control-centre/staff') && r.method == 'GET') {
          return _json({
            'success': true,
            'count': 1,
            'staff': [
              {
                '_id': 's1',
                'fullName': 'Ngozi Eze',
                'email': 'ngozi@servicepay.ng',
                'phone': '08035550000',
                'status': 'ACTIVE',
                'staffRoleId': {'_id': 'r1', 'displayName': 'Customer Support'},
              }
            ],
          });
        }
        if (p.endsWith('/head-office-dashboard')) {
          return _json({
            'success': true,
            'data': {'generatedAt': '2025-03-04T09:12:00Z', 'totals': {}}
          });
        }
        if (r.method == 'POST' || r.method == 'PUT') {
          return _json({'success': true, 'data': {}}, 201);
        }
        return _json({'success': false, 'message': 'Not found'}, 404);
      });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'auth_token': 'ops-session', 'user_role': 'STAFF'});
  });

  Future<_Backend> pump(WidgetTester tester,
      {_Backend? backend, AdminAccess access = _ops}) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = backend ?? _Backend();
    await tester.pumpWidget(MaterialApp(
      home: StaffManagementScreen(
        role: access.role,
        scoped: true,
        access: access,
        controlCentreApi: AdminStaffControlCentreApi(
            client: b.client, baseUrl: 'https://test.local/api'),
      ),
    ));
    await tester.pumpAndSettle();
    return b;
  }

  Future<void> fillAccount(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('scoped-name')), 'Bola Ade');
    await tester.enterText(find.byKey(const Key('scoped-phone')), '08031112222');
    await tester.enterText(
        find.byKey(const Key('scoped-email')), 'bola@servicepay.ng');
    await tester.enterText(
        find.byKey(const Key('scoped-password')), 'Temporary#Pass12');
    await tester.enterText(
        find.byKey(const Key('scoped-password-confirm')), 'Temporary#Pass12');
  }

  testWidgets('scoped view hides HO-only actions and lists managers at 390px',
      (tester) async {
    final b = await pump(tester);
    expect(find.text('Operations Staff'), findsOneWidget);
    expect(find.text('Ngozi Eze'), findsOneWidget);
    expect(find.text('Assign role'), findsNothing);
    expect(find.text('Revoke role'), findsNothing);
    expect(find.text('Reset password'), findsNothing);
    expect(find.text('History'), findsNothing);
    expect(find.text('Roles & Permissions'), findsNothing);
    expect(find.byKey(const Key('scoped-manager-directory')), findsOneWidget);
    expect(find.byKey(const Key('scoped-manager-m1')), findsOneWidget);
    expect(
        b.requests.every((r) =>
            r.url.path.contains('/admin/staff-workspace/control-centre/')),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without capability shows access denied and calls nothing',
      (tester) async {
    final b = await pump(tester,
        access: const AdminAccess(role: 'STAFF', permissions: {'*'}));
    expect(find.textContaining('operations.staff.manage'), findsOneWidget);
    expect(b.requests, isEmpty);
  });

  testWidgets('create support staff posts confirmed reason and password',
      (tester) async {
    final b = await pump(tester);
    await tester.tap(find.byKey(const Key('scoped-create-support')));
    await tester.pumpAndSettle();
    await fillAccount(tester);
    await tester.enterText(
        find.byKey(const Key('scoped-reason')), 'Short');
    await tester.tap(find.byKey(const Key('scoped-confirm-check')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scoped-submit')));
    await tester.pumpAndSettle();
    expect(b.requests.where((r) => r.method == 'POST'), isEmpty);

    await tester.enterText(find.byKey(const Key('scoped-reason')),
        'New support hire for Abuja desk');
    await tester.tap(find.byKey(const Key('scoped-submit')));
    await tester.pumpAndSettle();
    final post = b.requests.singleWhere((r) => r.method == 'POST');
    expect(post.url.path, endsWith('/control-centre/staff'));
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['confirmed'], true);
    expect(body.containsKey('role'), isFalse);
    expect(body.containsKey('staffRoleId'), isFalse);
  });

  testWidgets('state manager uses a listed zonal manager', (tester) async {
    final b = await pump(tester);
    await tester.tap(find.byKey(const Key('scoped-create-state')));
    await tester.pumpAndSettle();
    await fillAccount(tester);
    await tester.tap(find.byKey(const Key('scoped-zonal-manager')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Musa Danjuma · North Central').last);
    await tester.pumpAndSettle();
    expect(find.text('Zone: North Central'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('scoped-state')), 'Niger');
    await tester.enterText(find.byKey(const Key('scoped-reason')),
        'Coverage for Niger State operations');
    await tester.tap(find.byKey(const Key('scoped-confirm-check')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scoped-submit')));
    await tester.pumpAndSettle();
    final post = b.requests.singleWhere((r) => r.method == 'POST');
    expect(post.url.path, endsWith('/managers/state'));
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['zonalManagerId'], 'z1');
    expect(body['state'], 'Niger');
  });

  testWidgets('state creation hidden when no active zonal managers',
      (tester) async {
    await pump(tester, backend: _Backend(zonals: false));
    expect(find.byKey(const Key('scoped-create-state')), findsNothing);
    expect(find.byKey(const Key('scoped-create-zonal')), findsOneWidget);
  });

  testWidgets('suspend requires reason and uses scoped status endpoint',
      (tester) async {
    final b = await pump(tester);
    await tester.tap(find.text('Suspend'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('scoped-staff-reason')),
        'Repeated policy breach reported');
    await tester.tap(find.byKey(const Key('scoped-staff-confirm-check')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scoped-staff-confirm')));
    await tester.pumpAndSettle();
    final put = b.requests.singleWhere((r) => r.method == 'PUT');
    expect(put.url.path, endsWith('/control-centre/staff/s1/status'));
    final body = jsonDecode(put.body) as Map<String, dynamic>;
    expect(body['status'], 'SUSPENDED');
    expect(body['confirmed'], true);
  });

  test('navigation: scoped page for explicit capability only, HO unchanged',
      () {
    final opsLabels = AdminMainNavigation.visibleDestinationLabels(_ops);
    expect(opsLabels.where((l) => l == 'Staff Management'), hasLength(1));
    expect(opsLabels, isNot(contains('Head Office Dashboard')));
    final ho = AdminMainNavigation.visibleDestinationLabels(
        const AdminAccess(role: 'HEAD_OFFICE', permissions: {}));
    expect(ho.where((l) => l == 'Staff Management'), hasLength(1));
    expect(ho, isNot(contains('Head Office Dashboard')));
    expect(
        canAccessScopedOperationsStaffNavigation(
            role: 'OPERATIONS_MANAGER', permissions: {'*'}),
        isFalse);
  });

  testWidgets('zonal creation sends server profile and status', (tester) async {
    final b = await pump(tester);
    await tester.tap(find.byKey(const Key('scoped-create-zonal')));
    await tester.pumpAndSettle();
    await fillAccount(tester);
    await tester.enterText(find.byKey(const Key('scoped-zone')), 'South West');
    await tester.tap(find.byKey(const Key('scoped-zonal-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Injected'), findsNothing);
    await tester.tap(find.text('Read only').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scoped-readonly-notice')), findsOneWidget);
    expect(find.text('operations.workspace.view'), findsOneWidget);
    await tester.tap(find.text('Suspended'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('scoped-reason')),
        'Onboarding pending document checks');
    await tester.tap(find.byKey(const Key('scoped-confirm-check')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scoped-submit')));
    await tester.pumpAndSettle();
    final post = b.requests.singleWhere((r) => r.method == 'POST');
    expect(post.url.path, endsWith('/managers/zonal'));
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['permissionProfile'], 'READ_ONLY');
    expect(body['status'], 'SUSPENDED');
    expect(body.containsKey('permissions'), isFalse);
  });

  test('scoped dashboard uses control-centre endpoint with mapped range',
      () async {
    final b = _Backend();
    final api = AdminStaffControlCentreApi(
        client: b.client, baseUrl: 'https://test.local/api');
    final data = await api.headOfficeDashboard('7d');
    expect(data['generatedAt'], isNotNull);
    final r = b.requests.single;
    expect(r.url.path,
        '/api/admin/staff-workspace/control-centre/head-office-dashboard');
    expect(r.url.queryParameters['range'], 'week');
    await api.headOfficeDashboard('custom:2025-01-01:2025-01-05');
    final c = b.requests.last.url.queryParameters;
    expect(c['startDate'], '2025-01-01T00:00:00+01:00');
    expect(c['endDate'], '2025-01-05T23:59:59.999+01:00');
    expect(c.containsKey('range'), isFalse);
  });

  test('Head Office Dashboard nav needs explicit operations.executive.view',
      () {
    expect(
        canAccessScopedHeadOfficeDashboardNavigation(
            role: 'STAFF',
            permissions: {AdminPermissions.operationsExecutiveView}),
        isTrue);
    expect(
        canAccessScopedHeadOfficeDashboardNavigation(
            role: 'STAFF', permissions: {'*'}),
        isFalse);
    expect(
        canAccessScopedHeadOfficeDashboardNavigation(
            role: 'HEAD_OFFICE',
            permissions: {AdminPermissions.operationsExecutiveView}),
        isFalse);
    expect(
        AdminMainNavigation.visibleDestinationLabels(const AdminAccess(
            role: 'STAFF',
            permissions: {AdminPermissions.operationsExecutiveView})),
        contains('Head Office Dashboard'));
  });

  testWidgets('zonal Access & status saves strict payload', (tester) async {
    final b = await pump(tester);
    await tester.ensureVisible(
        find.byKey(const Key('scoped-manager-access-m1')));
    await tester.tap(find.byKey(const Key('scoped-manager-access-m1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scoped-access-readonly-notice')),
        findsOneWidget);
    await tester.tap(find.text('Standard').last);
    await tester.tap(find.text('Suspended').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('scoped-access-reason')),
        'Restoring standard access after review');
    await tester.tap(find.byKey(const Key('scoped-access-confirm-check')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scoped-access-save')));
    await tester.pumpAndSettle();
    final put = b.requests.singleWhere((r) => r.method == 'PUT');
    expect(put.url.path, endsWith('/control-centre/managers/m1/access'));
    expect(jsonDecode(put.body), {
      'permissionProfile': 'STANDARD',
      'status': 'SUSPENDED',
      'confirmed': true,
      'reason': 'Restoring standard access after review',
    });
  });

  testWidgets('State Manager rows have no access action', (tester) async {
    await pump(tester);
    await tester.ensureVisible(find.byKey(const Key('scoped-manager-role')));
    await tester.tap(find.text('State').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scoped-manager-m1')), findsOneWidget);
    expect(find.byKey(const Key('scoped-manager-access-m1')), findsNothing);
    expect(find.text('Access & status'), findsNothing);
  });
}
