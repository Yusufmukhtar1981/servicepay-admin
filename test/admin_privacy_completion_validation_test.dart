import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/admin_privacy_requests_screen.dart';

void main() {
  final now = DateTime.utc(2026, 11, 21);
  Map<String, dynamic> validEvidence() => {
        'confirmation': 'DELETE DEL-TEST',
        'associatedDataReviewReference':
            'Associated case reviewed: local fixture.',
        'processorRequestsReference':
            'Processor actions reviewed: local fixture.',
        'retentionPolicyReference': 'Approved policy reviewed: local fixture.',
        'retentionScope': 'Required audit records under the approved policy.',
        'retentionReviewBy': DateTime.utc(2026, 12, 21).toIso8601String(),
        'otherSystemsReviewed': true,
        'processorsReviewed': true,
        'financialObligationsReviewed': true,
      };
  String? validate(Map<String, dynamic> evidence,
          {String note = 'Reviewed disposable fixture.',
          String password = 'fake-test-password'}) =>
      validateAccountDeletionCompletion(
        note: note,
        password: password,
        reference: 'DEL-TEST',
        evidence: evidence,
        now: now,
      );

  test('blank completion is blocked before any submission', () {
    expect(validate({}, note: '', password: ''), isNotNull);
    expect(validate(validEvidence(), note: 'short'), isNotNull);
    expect(validate(validEvidence(), password: ''), isNotNull);
  });
  test('exact confirmation, all evidence and every attestation are mandatory',
      () {
    for (final key in validEvidence().keys) {
      final evidence = validEvidence()..remove(key);
      expect(validate(evidence), isNotNull, reason: key);
    }
    expect(validate(validEvidence()..['confirmation'] = 'DELETE SOMEONE-ELSE'),
        isNotNull);
    expect(
        validate(validEvidence()..['processorsReviewed'] = false), isNotNull);
    expect(
        validate(validEvidence()..['retentionScope'] = 'too short'), isNotNull);
  });
  test('valid evidence passes and expired review dates are rejected', () {
    expect(validate(validEvidence()), isNull);
    expect(
        validate(
            validEvidence()..['retentionReviewBy'] = now.toIso8601String()),
        isNotNull);
    expect(validate(validEvidence()..['retentionReviewBy'] = 'invalid'),
        isNotNull);
  });
}
