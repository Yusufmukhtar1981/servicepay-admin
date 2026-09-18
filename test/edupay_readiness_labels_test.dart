import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EduPay readiness UI has automatic financial status contract', () {
    final source = File(
      'lib/admin/edupay_control_center_screen.dart',
    ).readAsStringSync();
    for (final removed in [
      'Duty Separation',
      'Account Management Officer',
      'Account Verification Officer',
      'Settlement Processing Officer',
      'Verify configuration',
      'Enable EduPay',
      'Overall Readiness',
    ]) {
      expect(source, isNot(contains(removed)));
    }
    expect(source, contains('EduPay Status'));
    expect(source, contains('Automatically enabled'));
    for (final financialRow in [
      'Payout Provider',
      'Account Encryption',
      'Settlement Method',
      'Rates',
      'Missing production environment configuration',
    ]) {
      expect(source, contains(financialRow));
    }
  });
}
