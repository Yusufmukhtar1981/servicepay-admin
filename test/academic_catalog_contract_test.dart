import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('academic catalog UI and API contracts stay discoverable', () {
    final screen =
        File('lib/school/academic_operations_screen.dart').readAsStringSync();
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
  });
}
