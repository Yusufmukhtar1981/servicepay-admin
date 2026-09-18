import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/edupay_control_center_screen.dart';

void main() {
  test('school request review UI exposes the safe lifecycle actions', () {
    final source = File('lib/admin/edupay_control_center_screen.dart')
        .readAsStringSync();

    expect(source, contains('PENDING_REVIEW'));
    expect(source, contains('APPROVED'));
    expect(source, contains('REJECTED'));
    expect(source, contains('Approve this school for Servicepay EduPay?'));
    expect(source, contains('Approve School'));
    expect(source, contains('Reject School Application'));
    expect(source, contains('Reject Application'));
    expect(source, contains(
        'I verified this requester is authorized to represent the school.'));
    expect(source, contains('representativeAuthorityConfirmed: true'));
    expect(source, contains('Requester Email'));
    expect(source, contains('Requester Phone'));
    expect(source, contains("'Requester Name': details['requesterName']"));
    expect(source, contains("'Requester Email': details['requesterEmail']"));
    expect(source, contains("'Requester Phone': details['requesterPhone']"));
    expect(source, contains("'School Contact Phone': details['contactPhone']"));
    expect(source,
        isNot(contains("'Requester Phone': details['contactPhone']")));
    expect(source, contains('schoolRequestDetail'));
    expect(source, contains('schoolRequestAction'));
    expect(source, contains('PopupMenuButton<String>'));
    expect(source, contains('Refresh'));
  });

  test('school request rows cannot use full-school mutation endpoint', () {
    final source = File('lib/admin/edupay_control_center_screen.dart')
        .readAsStringSync();

    expect(source, contains("r['type'] == 'SCHOOL_REQUEST'"));
    expect(source, contains('_schoolRequestAction'));
    expect(source, contains('_api.schoolRequestAction(id, action'));
  });

  test('approved linked request is not duplicated beside its school row', () {
    final rows = eduPaySchoolReviewRows(
      [
        {'id': 'school-1', 'name': 'Khadijah Yusuf Academy'},
      ],
      [
        {
          'id': 'request-approved',
          'schoolName': 'Khadijah Yusuf Academy',
          'status': 'APPROVED',
          'schoolId': 'school-1',
        },
        {
          'id': 'request-unlinked',
          'schoolName': 'Pending Link Academy',
          'status': 'APPROVED',
        },
      ],
    );

    expect(rows.where((row) => row['type'] == 'SCHOOL_REQUEST'), hasLength(1));
    expect(rows.first['_requestId'], 'request-unlinked');
    expect(rows.where((row) => row['id'] == 'school-1'), hasLength(1));
  });

  test('nested linked school remains compatibility-only for dedupe', () {
    final rows = eduPaySchoolReviewRows(
      [
        {'id': 'school-2', 'name': 'Nested Link Academy'},
      ],
      [
        {
          'id': 'request-nested',
          'schoolName': 'Nested Link Academy',
          'status': 'APPROVED',
          'linkedSchool': {'id': 'school-2'},
        },
      ],
    );
    expect(rows.where((row) => row['type'] == 'SCHOOL_REQUEST'), isEmpty);
  });

  test('legacy contacted and closed requests remain neutral statuses', () {
    final source = File('lib/admin/edupay_control_center_screen.dart')
        .readAsStringSync();
    expect(source, contains("state == 'CONTACTED' || state == 'CLOSED'"));
    expect(source, contains("'Contacted'"));
    expect(source, contains("'Closed'"));
    expect(source, contains('Icons.info_outline'));
  });
}