import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/main_navigation.dart';

void main() {
  test('EduPay navigation requires the final view permission', () {
    expect(
        canAccessEduPayNavigation(
          role: 'HEAD_OFFICE',
          permissions: <String>{},
        ),
        isFalse);
    expect(
        canAccessEduPayNavigation(
          role: 'HEAD_OFFICE',
          permissions: <String>{AdminPermissions.edupayView},
        ),
        isTrue);
    expect(
        canAccessEduPayNavigation(
          role: 'STAFF',
          permissions: <String>{AdminPermissions.edupayView},
        ),
        isFalse);
  });

  test('EduPay destination is not exposed to unrelated staff', () {
    final labels = AdminMainNavigation.visibleDestinationLabels(
      AdminAccess(role: 'STAFF', permissions: <String>{}),
    );
    expect(labels, isNot(contains('EduPay')));
  });
}
