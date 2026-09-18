import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:servicepay_app/school/edupay_school_api.dart';
import 'package:servicepay_app/school/student_activity_center_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('Student Management opens the existing Students workflow',
      (tester) async {
    var openedStudents = false;
    final api = EduPaySchoolApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((_) async =>
          Response(jsonEncode({'success': true, 'data': {}}), 200)),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StudentActivityCenterScreen(
          api: api,
          onOpenStudents: () => openedStudents = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Student Management'));
    await tester.pumpAndSettle();
    expect(find.text('Open Students'), findsOneWidget);
    await tester.tap(find.text('Open Students'));
    expect(openedStudents, isTrue);
  });

  testWidgets('Parents/Guardians exposes invite action, not unsupported list',
      (tester) async {
    final api = EduPaySchoolApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((_) async =>
          Response(jsonEncode({'success': true, 'data': {}}), 200)),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StudentActivityCenterScreen(api: api),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parents/Guardians'));
    await tester.pumpAndSettle();
    expect(find.text('Create guardian invite'), findsOneWidget);
    expect(find.text('Invite a verified parent or guardian'), findsOneWidget);
  });
}
