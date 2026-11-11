import 'package:flutter_test/flutter_test.dart';
// ignore: avoid_relative_lib_imports
import '../lib/admin/admin_permissions.dart';
// ignore: avoid_relative_lib_imports
import '../lib/admin/main_navigation.dart';

void main() {
  test('Head Office can navigate to the Marketing department', () {
    final labels = AdminMainNavigation.visibleDestinationLabels(
      const AdminAccess(role: 'HEAD_OFFICE', permissions: <String>{}),
    );
    expect(labels, contains('Marketing'));
  });

  test('marketing permission exposes only the Marketing destination', () {
    final labels = AdminMainNavigation.visibleDestinationLabels(
      const AdminAccess(role: 'STAFF', permissions: <String>{'marketing.view'}),
    );
    expect(labels, <String>['Marketing']);
    expect(
      preferredMarketingWorkspaceIndex(
        labels: labels,
        role: 'STAFF',
        permissions: <String>{'marketing.view'},
      ),
      0,
    );
  });

  test('Head of Marketing opens the Marketing workspace by default', () {
    expect(
      preferredMarketingWorkspaceIndex(
        labels: <String>['Marketing'],
        role: 'HEAD_OF_MARKETING',
        permissions: <String>{'marketing.view'},
      ),
      0,
    );
  });

  test('marketing staff cannot inherit Head Office approval grants', () {
    const access = AdminAccess(
      role: 'STAFF',
      permissions: <String>{'marketing.view'},
    );
    expect(access.has('marketing.view'), isTrue);
    expect(access.has('marketing.budgets.approve'), isFalse);
  });
}
