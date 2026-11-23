import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/main_navigation.dart';

void main() {
  test('Financial Management requires the explicit expense view permission', () {
    expect(canAccessExpenseManagementNavigation(permissions: <String>{}), isFalse);
    expect(canAccessExpenseManagementNavigation(permissions: <String>{'*', 'finance.view'}), isFalse);
    expect(canAccessExpenseManagementNavigation(permissions: <String>{'expenses.view'}), isTrue);
  });
}
