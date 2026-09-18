import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EduPay screen no longer contains officer configuration UI', () {
    final source = File(
      'lib/admin/edupay_control_center_screen.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('EduPayOfficerAssignmentsDialog')));
    expect(source, isNot(contains('configure-edupay-officers')));
    expect(source, isNot(contains('Configure officers')));
  });
}
