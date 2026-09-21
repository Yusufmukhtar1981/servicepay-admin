import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('academic catalog UI and API contracts stay discoverable', () {
    final screen = File(
      'lib/school/academic_operations_screen.dart',
    ).readAsStringSync();
    final portal = File(
      'lib/school/school_portal_screen.dart',
    ).readAsStringSync();
    final api = File('lib/school/edupay_school_api.dart').readAsStringSync();

    for (final label in const [
      'Search classes',
      'Search subjects',
      'Select all',
      'Add classes',
      'Add subjects',
      'Add New Class',
      'Add New Subject',
      'Class-to-subject mapping',
      'Edit subjects',
      'School level',
      'English Language',
      'Mathematics',
      'JSS 1',
      'SSS 3',
      'Playgroup',
      'Pre-Nursery',
      'Reception',
      'General Mathematics',
      'Animal Husbandry',
      'Insurance',
    ]) {
      expect(screen, contains(label), reason: label);
    }
    expect(api, contains('/edupay/school/academic/classes/batch'));
    expect(api, contains('/edupay/school/academic/subjects/batch'));
    expect(api, contains('/edupay/school/academic/classes/\$classId/subjects'));
    expect(api, contains("'session': session"));
    expect(api, contains("'subjectIds': subjectIds"));
    expect(screen, contains("'educationLevel': row['level']"));
    expect(screen, contains('No subjects mapped yet'));
    expect(screen, contains('_classCanonical'));
    expect(screen, contains('All selected subjects are already added'));
    expect(screen, contains('Already added'));
    expect(screen, contains('Search classes'));
    expect(screen, contains('Search subjects'));
    expect(screen, contains('Widget _friendlyAcademicTable'));
    expect(screen, contains("'Teacher'"));
    expect(screen, isNot(contains("columns: rows.first.keys")));
    expect(screen, contains('Set up Academic Session'));
    expect(screen, contains("'name': 'First Term'"));
    expect(screen, contains("'status': 'ACTIVE'"));
    expect(screen, contains('createAcademicPortalSession'));
    expect(screen, contains('createAcademicPortalTerm'));
    expect(screen, contains('activeTerms'));
    expect(screen, contains('Class added successfully.'));
    expect(screen, contains('Subject added successfully.'));
    expect(screen, contains('await _load();'));
    expect(screen, contains('_currentSchoolYear'));
    expect(
      screen,
      contains('Academic session and First Term created successfully.'),
    );
    expect(
      screen,
      contains(
        'No classes or subjects have been assigned to your teacher account yet.',
      ),
    );
    expect(screen, contains('if (!widget.manager)'));
    expect(portal, contains('Second Term'));
    expect(portal, contains('Third Term'));
    expect(portal, contains('Start date (YYYY-MM-DD)'));
    expect(portal, contains('End date (YYYY-MM-DD)'));
    expect(portal, contains('UPCOMING'));
    expect(portal, contains('CLOSED'));
    expect(portal, contains('ACTIVE is the current session/term'));
    expect(portal, contains('Enter an official fee amount greater than zero.'));
    expect(portal, contains('_editSession'));
    expect(portal, contains('_editTerm'));
    expect(portal, contains('Create First, Second and Third Terms'));
    expect(portal, contains('createStandardTerms'));
    expect(portal, contains('Set current'));
    expect(portal, contains("'isCurrent': true"));
    expect(portal, contains('before submitting.'));
    expect(portal, contains("'Fees / EduPay' => 'fees'"));
    expect(portal, isNot(contains("value: 'DRAFT'")));
  });

  test('fee review controls and API routes remain discoverable', () {
    final center = File(
      'lib/admin/edupay_control_center_screen.dart',
    ).readAsStringSync();
    final api = File('lib/admin/edupay_api.dart').readAsStringSync();
    expect(center, contains('Pending school fee review'));
    expect(center, contains('Approve fee'));
    expect(center, contains('Reject fee'));
    expect(center, contains('Rejection reason'));
    expect(api, contains("'/admin/edupay/fees/\$feeId'"));
  });

  test('calendar and fee APIs expose scoped management operations', () {
    final api = File('lib/school/edupay_school_api.dart').readAsStringSync();
    expect(api, contains('updateAcademicSession'));
    expect(api, contains('updateAcademicTerm'));
    expect(
      api,
      contains("request('PATCH', '/edupay/school/academic/sessions/"),
    );
    expect(api, contains("request('PATCH', '/edupay/school/academic/terms/"));
    expect(api, contains('createFee'));
    expect(api, contains("request('POST', '/edupay/school/fees'"));
  });
}
