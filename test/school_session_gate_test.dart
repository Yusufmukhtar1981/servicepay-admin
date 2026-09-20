import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/school/edupay_school_api.dart';
import 'package:servicepay_app/school/school_login_screen.dart';
import 'package:servicepay_app/school/school_session_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('restores a validated school session after refresh',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'school_auth_token': 'school-token',
      'school_id': 'school-1',
      'school_role': 'SCHOOL_ADMIN',
      'school_membership_status': 'ACTIVE',
      'school_status': 'APPROVED',
      'school_must_change_password': false,
    });
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer school-token');
      expect(request.headers['x-edupay-school-id'], 'school-1');
      return http.Response(
        jsonEncode({
          'success': true,
          'school': {'_id': 'school-1', 'name': 'Restored School'},
          'summary': <String, Object>{},
          'settlements': <Object>[],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: SchoolSessionGate(
        api: EduPaySchoolApi(client: client),
        portalBuilder: (_) => const Text('School dashboard restored'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('School dashboard restored'), findsOneWidget);
    expect(find.byType(SchoolLoginScreen), findsNothing);
  });

  testWidgets('rejects a stale school session and clears its context',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'school_auth_token': 'stale-token',
      'school_id': 'school-1',
      'school_role': 'SCHOOL_ADMIN',
      'school_membership_status': 'ACTIVE',
      'school_status': 'APPROVED',
    });
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'success': false,
            'message': 'Approved EduPay school access required.',
          }),
          403,
          headers: {'content-type': 'application/json'},
        ));

    await tester.pumpWidget(MaterialApp(
      home: SchoolSessionGate(api: EduPaySchoolApi(client: client)),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SchoolLoginScreen), findsOneWidget);
    expect(
        find.text('Approved EduPay school access required.'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('school_auth_token'), isNull);
    expect(prefs.getString('school_id'), isNull);
    expect(prefs.getString('school_role'), isNull);
  });

  testWidgets('restores a teacher through the academic dashboard',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'school_auth_token': 'teacher-token',
      'school_id': 'school-1',
      'school_role': 'TEACHER',
      'school_membership_status': 'ACTIVE',
      'school_status': 'APPROVED',
    });
    final client = MockClient((request) async {
      expect(request.url.path, '/api/edupay/school/academic/dashboard');
      return http.Response(
        jsonEncode({'success': true, 'role': 'TEACHER'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: SchoolSessionGate(
        api: EduPaySchoolApi(client: client),
        portalBuilder: (_) => const Text('Teacher dashboard restored'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Teacher dashboard restored'), findsOneWidget);
    expect(find.byType(SchoolLoginScreen), findsNothing);
  });

  testWidgets('restores finance through the finance dashboard', (tester) async {
    SharedPreferences.setMockInitialValues({
      'school_auth_token': 'finance-token',
      'school_id': 'school-1',
      'school_role': 'FINANCE',
      'school_membership_status': 'ACTIVE',
      'school_status': 'APPROVED',
    });
    final client = MockClient((request) async {
      expect(request.url.path, '/api/edupay/school/dashboard');
      return http.Response(
        jsonEncode({'success': true, 'summary': <String, Object>{}}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: SchoolSessionGate(
        api: EduPaySchoolApi(client: client),
        portalBuilder: (_) => const Text('Finance dashboard restored'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Finance dashboard restored'), findsOneWidget);
    expect(find.byType(SchoolLoginScreen), findsNothing);
  });

  testWidgets('does not grant school access without membership context',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'school_auth_token': 'customer-token',
    });
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount += 1;
      expect(request.url.path, '/api/edupay/school/handoff/consume');
      return http.Response(
        jsonEncode({
          'success': false,
          'code': 'SCHOOL_HANDOFF_REQUIRED',
          'message': 'School Portal handoff required.',
        }),
        401,
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: SchoolSessionGate(api: EduPaySchoolApi(client: client)),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SchoolLoginScreen), findsOneWidget);
    expect(requestCount, 1);
  });

  testWidgets('consumes a one-time customer handoff without a second login',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'success': true,
            'token': 'school-token',
            'schoolId': 'school-1',
            'role': 'OWNER',
            'school': {'_id': 'school-1', 'name': 'Greenfield Academy', 'status': 'APPROVED'},
            'schoolMembership': {
              'schoolId': 'school-1', 'role': 'OWNER', 'status': 'ACTIVE', 'schoolStatus': 'APPROVED',
            },
          }),
          200,
        ));
    await tester.pumpWidget(MaterialApp(
      home: SchoolSessionGate(
        api: EduPaySchoolApi(client: client),
        portalBuilder: (_) => const Text('Handoff school dashboard'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Handoff school dashboard'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('school_auth_token'), 'school-token');
    expect(prefs.getString('school_id'), 'school-1');
  });

  testWidgets('a fresh handoff replaces an existing school session',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'school_auth_token': 'school-a-token',
      'school_id': 'school-a',
      'school_role': 'OWNER',
      'school_membership_status': 'ACTIVE',
      'school_status': 'APPROVED',
    });
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'success': true,
            'token': 'school-b-token',
            'schoolId': 'school-b',
            'role': 'SCHOOL_ADMIN',
            'school': {'_id': 'school-b', 'name': 'School B', 'status': 'APPROVED'},
            'schoolMembership': {
              'schoolId': 'school-b', 'role': 'SCHOOL_ADMIN', 'status': 'ACTIVE', 'schoolStatus': 'APPROVED',
            },
          }),
          200,
        ));
    await tester.pumpWidget(MaterialApp(
      home: SchoolSessionGate(
        api: EduPaySchoolApi(client: client),
        portalBuilder: (_) => const Text('School B dashboard'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('School B dashboard'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('school_auth_token'), 'school-b-token');
    expect(prefs.getString('school_id'), 'school-b');
  });
}
