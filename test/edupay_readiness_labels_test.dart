import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/edupay_control_center_screen.dart';

void main() {
  test('Launch Readiness uses human duty-holder titles', () {
    expect(
      [
        eduPayDutyDisplayLabel('account.manage'),
        eduPayDutyDisplayLabel('account.verify'),
        eduPayDutyDisplayLabel('settlement.process'),
      ],
      [
        'Account Management Officer',
        'Account Verification Officer',
        'Settlement Processing Officer',
      ],
    );
  });
}