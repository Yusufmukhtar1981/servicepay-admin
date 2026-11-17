import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/admin_management_access.dart';
import 'package:servicepay_app/admin/main_navigation.dart';

void main() {
  test('new management pages stay unloaded until selected', () {
    for (final label in ['Management Performance', 'Customer Assignments']) {
      expect(shouldBuildHeadOfficeManagementPage(label, 3, 0), false);
      expect(shouldBuildHeadOfficeManagementPage(label, 3, 3), true);
    }
    expect(shouldBuildHeadOfficeManagementPage('Dashboard', 3, 0), true);
  });
  test('new destinations remain Head Office permission gated', () {
    final labels = AdminMainNavigation.visibleDestinationLabels(
      const AdminAccess(role: 'HEAD_OFFICE', permissions: <String>{}),
    );
    expect(labels, contains('Management Performance'));
    expect(labels, isNot(contains('Customer Assignments')));

    final noUsersView = AdminMainNavigation.visibleDestinationLabels(
      const AdminAccess(
          role: 'HEAD_OFFICE', permissions: <String>{'hierarchy.manage'}),
    );
    expect(noUsersView, contains('Management Performance'));
    expect(noUsersView, contains('Customer Assignments'));

    final noHierarchy = AdminMainNavigation.visibleDestinationLabels(
      const AdminAccess(
          role: 'HEAD_OFFICE', permissions: <String>{'users.view'}),
    );
    expect(noHierarchy, contains('Management Performance'));
    expect(noHierarchy, isNot(contains('Customer Assignments')));
    final wildcard = AdminMainNavigation.visibleDestinationLabels(
        const AdminAccess(role: 'HEAD_OFFICE', permissions: <String>{'*'}));
    expect(wildcard, contains('Management Performance'));
    expect(wildcard, isNot(contains('Customer Assignments')));
  });

  test('wildcard scoped roles and support roles never see destinations', () {
    for (final String role in <String>[
      'OPERATIONS_MANAGER',
      'CUSTOMER_SUPPORT',
      'BRANCH',
      'AGENT',
    ]) {
      final labels = AdminMainNavigation.visibleDestinationLabels(
        AdminAccess(role: role, permissions: <String>{
          '*',
          AdminPermissions.usersView,
          AdminPermissions.hierarchyManage,
        }),
      );
      expect(labels, isNot(contains('Management Performance')), reason: role);
      expect(labels, isNot(contains('Customer Assignments')), reason: role);
    }
  });
}
