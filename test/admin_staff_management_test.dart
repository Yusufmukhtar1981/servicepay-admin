import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/admin_roles_permissions_api.dart';
import 'package:servicepay_app/admin/login_screen.dart';
import 'package:servicepay_app/admin/main.dart';
import 'package:servicepay_app/admin/main_navigation.dart';
import 'package:servicepay_app/admin/staff_management_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Staff Management access and navigation', () {
    test('Head Office fallback exposes Staff Management beside support', () {
      final labels = AdminMainNavigation.visibleDestinationLabels(
        const AdminAccess(role: 'HEAD_OFFICE', permissions: <String>{}),
      );
      final supportIndex = labels.indexOf('Customer support desk');
      expect(
          labels.where((label) => label == 'Staff Management'), hasLength(1));
      expect(labels.indexOf('Staff Management'), supportIndex + 1);
    });

    test('Operations and Customer Support stay out of staff administration',
        () {
      for (final role in <String>['OPERATIONS_MANAGER', 'CUSTOMER_SUPPORT']) {
        final labels = AdminMainNavigation.visibleDestinationLabels(
          AdminAccess(
            role: role,
            permissions: <String>{
              AdminPermissions.operationsWorkspaceView,
              AdminPermissions.supportWorkspaceView,
            },
          ),
        );
        expect(labels, isNot(contains('Staff Management')));
        expect(
          canAccessStaffManagementRoute(token: 'session', role: role),
          isFalse,
        );
      }
      expect(canAccessStaffManagementRoute(token: '', role: 'HEAD_OFFICE'),
          isFalse);
    });

    test('partial workspace permissions remain visible without staff access',
        () {
      final operationsLabels = AdminMainNavigation.visibleDestinationLabels(
        const AdminAccess(
          role: 'STAFF',
          permissions: <String>{AdminPermissions.operationsWorkspaceView},
        ),
      );
      final supportLabels = AdminMainNavigation.visibleDestinationLabels(
        const AdminAccess(
          role: 'STAFF',
          permissions: <String>{AdminPermissions.supportWorkspaceView},
        ),
      );
      expect(operationsLabels, contains('Operations overview'));
      expect(operationsLabels, isNot(contains('Customer support desk')));
      expect(supportLabels, contains('Customer support desk'));
      expect(supportLabels, isNot(contains('Operations overview')));
      expect(operationsLabels, isNot(contains('Staff Management')));
      expect(supportLabels, isNot(contains('Staff Management')));
    });

    testWidgets('Head Office empty staff result has composed empty state',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_token': 'test-session',
      });
      final api = AdminRolesPermissionsApi(
        client: MockClient((request) async => http.Response(
            jsonEncode(<String, dynamic>{'success': true, 'staff': []}), 200)),
        baseUrl: 'https://preview.servicepay.test/api',
      );
      await tester.pumpWidget(MaterialApp(
        home: StaffManagementScreen(
          role: 'HEAD_OFFICE',
          staffApi: api,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No staff account found.'), findsOneWidget);
      expect(find.text('Create Staff'), findsOneWidget);
    });

    testWidgets(
        'populated staffRoleId drives role label, activation and row controls',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_token': 'test-session',
      });
      tester.view.physicalSize = const Size(1200, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final List<http.Request> requests = <http.Request>[];
      final api = AdminRolesPermissionsApi(
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'success': true,
                'staff': <Map<String, dynamic>>[
                  <String, dynamic>{
                    '_id': 'staff-42',
                    'fullName': 'Mina Bello',
                    'email': 'mina@example.test',
                    'role': 'STAFF',
                    'staffRoleId': <String, dynamic>{
                      '_id': 'r-ops',
                      'name': 'OPERATIONS_MANAGER',
                      'displayName': 'Operations Manager',
                      'status': 'ACTIVE',
                    },
                    'status': 'SUSPENDED',
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('{"success":true}', 200);
        }),
        baseUrl: 'https://preview.servicepay.test/api',
      );
      await tester.pumpWidget(MaterialApp(
        home: StaffManagementScreen(
          role: 'HEAD_OFFICE',
          staffApi: api,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Operations Manager'), findsOneWidget);
      expect(find.text('Activate'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Assign role'), findsOneWidget);
      expect(find.text('Revoke role'), findsOneWidget);
      expect(find.text('Reset password'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();
      expect(
          requests.any((request) =>
              request.method == 'PUT' &&
              request.url.path ==
                  '/api/staff-management/staff/staff-42/status' &&
              jsonDecode(request.body)['status'] == 'ACTIVE'),
          isTrue);
    });

    testWidgets('Operations account sees denial and issues no staff request',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_token': 'test-session',
      });
      var requestCount = 0;
      final api = AdminRolesPermissionsApi(
        client: MockClient((request) async {
          requestCount++;
          return http.Response('{"success":true,"staff":[]}', 200);
        }),
        baseUrl: 'https://preview.servicepay.test/api',
      );
      await tester.pumpWidget(MaterialApp(
        home: StaffManagementScreen(role: 'OPERATIONS_MANAGER', staffApi: api),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Access denied'), findsOneWidget);
      expect(requestCount, 0);
      expect(find.text('Create Staff'), findsNothing);
    });

    testWidgets('named route checks the saved session rather than URL input',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_token': 'ops-session',
        'user_role': 'CUSTOMER_SUPPORT',
        'staff_permissions': <String>[
          AdminPermissions.supportWorkspaceView,
        ],
      });
      await tester.pumpWidget(const ServicepayAdminApp());
      await tester.pumpAndSettle();
      final BuildContext loginContext = tester.element(
        find.byType(AdminLoginScreen).first,
      );
      Navigator.of(loginContext).pushNamed('/staff-management');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Staff Management requires a Head Office session'),
        findsOneWidget,
      );
    });
  });

  test('staff mutation endpoints send the required bodies', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'test-session',
    });
    final List<http.Request> requests = <http.Request>[];
    final api = AdminRolesPermissionsApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{"success":true}', 200);
      }),
      baseUrl: 'https://preview.servicepay.test/api',
    );

    await api.updateStaff('s-19', <String, dynamic>{'fullName': 'Ada Okafor'});
    await api.assignStaffRole('s-19', 'r-ops');
    await api.revokeStaffRole('s-19', reason: 'Role no longer required');
    await api.updateStaffStatus('s-19', 'SUSPENDED');
    await api.resetStaffPassword('s-19', temporaryPassword: 'LongTemp!234');

    expect(requests.map((r) => r.url.path), <String>[
      '/api/staff-management/staff/s-19',
      '/api/staff-management/staff/s-19/role',
      '/api/staff-management/staff/s-19/role',
      '/api/staff-management/staff/s-19/status',
      '/api/staff-management/staff/s-19/password',
    ]);
    expect(jsonDecode(requests[1].body), <String, dynamic>{'roleId': 'r-ops'});
    expect(jsonDecode(requests[2].body), <String, dynamic>{
      'revoke': true,
      'reason': 'Role no longer required',
    });
    expect(jsonDecode(requests[4].body), <String, dynamic>{
      'temporaryPassword': 'LongTemp!234',
    });
  });
}
