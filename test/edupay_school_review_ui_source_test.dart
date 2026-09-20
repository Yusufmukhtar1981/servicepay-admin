import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/edupay_control_center_screen.dart';

void main() {
  test('school request review UI exposes the safe lifecycle actions', () {
    final source = File(
      'lib/admin/edupay_control_center_screen.dart',
    ).readAsStringSync();

    expect(source, contains('PENDING_REVIEW'));
    expect(source, contains('APPROVED'));
    expect(source, contains('REJECTED'));
    expect(source, contains('Approve this school for Servicepay EduPay?'));
    expect(source, contains('Approve School'));
    expect(source, contains('Reject School Application'));
    expect(source, contains('Reject Application'));
    expect(
      source,
      contains(
        'I verified this requester is authorized to represent the school.',
      ),
    );
    expect(source, contains('representativeAuthorityConfirmed: true'));
    expect(source, contains('Requester Email'));
    expect(source, contains('Requester Phone'));
    expect(source, contains("'Requester Name': details['requesterName']"));
    expect(source, contains("'Requester Email': details['requesterEmail']"));
    expect(source, contains("'Requester Phone': details['requesterPhone']"));
    expect(source, contains("'School Contact Phone': details['contactPhone']"));
    expect(
      source,
      isNot(contains("'Requester Phone': details['contactPhone']")),
    );
    expect(source, contains('schoolRequestDetail'));
    expect(source, contains('schoolRequestAction'));
    expect(source, contains('SchoolRequestActionControls'));
    expect(source, contains('SchoolRequestDetailsActions'));
    expect(source, contains('_reviewType'));
    expect(source, contains('_reviewStatus'));
    expect(source, contains('Refresh'));
    expect(source, contains('Future<void> _loadAccess()'));
    expect(source, contains('_loadAccess();'));
    expect(source, contains('Future<void> _loadReadiness()'));
    final readinessStart = source.indexOf('Future<void> _loadReadiness()');
    final loadStart = source.indexOf('Future<void> _load()');
    expect(
      source.substring(readinessStart, loadStart),
      isNot(contains('SharedPreferences.getInstance()')),
    );
  });

  test(
      'school request review and manual mutations use separate backend role gates',
      () {
    for (final role in const [
      'HEAD_OFFICE',
      'HEAD_OFFICE_ADMIN',
      'ADMIN',
      'SUPER_ADMIN',
      'SERVICEPAY_SUPER_ADMIN',
    ]) {
      expect(eduPayAdminRoleCanReviewSchoolRequests(role), isTrue,
          reason: role);
    }
    expect(eduPayAdminRoleCanManage('HEAD_OFFICE'), isTrue);
    expect(eduPayAdminRoleCanManage('HEAD_OFFICE_ADMIN'), isFalse);
    expect(eduPayAdminRoleCanManage('ADMIN'), isFalse);
    expect(eduPayAdminRoleCanManage('STAFF'), isFalse);
    expect(eduPayAdminRoleCanManage('CUSTOMER'), isFalse);
  });

  test('admin login allowlist includes ServicePay super admin alias', () {
    final source = File('lib/admin/login_screen.dart').readAsStringSync();
    expect(source, contains("'SERVICEPAY_SUPER_ADMIN'"));
  });

  test('access loading is independent from readiness failures', () {
    final source = File(
      'lib/admin/edupay_control_center_screen.dart',
    ).readAsStringSync();
    expect(
      source.indexOf('_loadAccess();'),
      lessThan(source.indexOf('_loadReadiness();')),
    );
    final readinessStart = source.indexOf('Future<void> _loadReadiness()');
    final loadStart = source.indexOf('Future<void> _load()');
    final readiness = source.substring(readinessStart, loadStart);
    expect(readiness, contains('catch (_)'));
    expect(readiness, isNot(contains('adminRole =')));
    expect(readiness, isNot(contains('permissions =')));
  });

  test('teacher activity reachability and scoped loader are wired', () {
    final source =
        File('lib/school/academic_operations_screen.dart').readAsStringSync();
    expect(source, contains("section == 'Activities'"));
    expect(source, contains('_createActivity'));
    expect(
        source, contains('Future<Map<String, dynamic>> _combinedActivities()'));
    expect(source, contains('widget.api.academicStudents()'));
    expect(source, contains('widget.api.activities()'));
    expect(source, contains("'audience': audience"));
    expect(source, contains("'CLASS'"));
    expect(source, contains("'STUDENT'"));
    expect(source, contains("['DRAFT', 'RETURNED']"));
  });

  test('school request rows cannot use full-school mutation endpoint', () {
    final source = File(
      'lib/admin/edupay_control_center_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_isSchoolRequestRow'));
    expect(source, contains('_schoolRequestAction'));
    expect(source, contains('_api.schoolRequestAction'));
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
    final source = File(
      'lib/admin/edupay_control_center_screen.dart',
    ).readAsStringSync();
    expect(source, contains("case 'CONTACTED':"));
    expect(source, contains("'Contacted'"));
    expect(source, contains("'Closed'"));
    expect(source, contains('_schoolStatusLabel'));
  });

  testWidgets(
    'production SCHOOL_REQUEST pending row shows visible actions at mobile width',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final row = <String, dynamic>{
        'type': ' SCHOOL_REQUEST ',
        'status': ' pending_review ',
        'schoolName': 'Khadijah Yusuf Academy',
        'location': 'Lagos',
        '_requestId': 'request-1',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchoolRequestActionControls(
              row: row,
              canManage: true,
              onView: () {},
              onApprove: () {},
              onReject: () {},
            ),
          ),
        ),
      );

      expect(find.text('View School'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
    },
  );

  testWidgets(
    'details actions show Reject, Approve, and Close for authorized pending request',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchoolRequestDetailsActions(
              pending: true,
              canManage: true,
              onApprove: () {},
              onReject: () {},
              onClose: () {},
            ),
          ),
        ),
      );

      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    },
  );

  testWidgets('unauthorized pending viewer retains only View School', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchoolRequestActionControls(
            row: <String, dynamic>{
              'type': 'SCHOOL_REQUEST',
              'status': 'PENDING_REVIEW',
            },
            canManage: false,
            onView: () {},
            onApprove: () {},
            onReject: () {},
          ),
        ),
      ),
    );

    expect(find.text('View School'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });
}
