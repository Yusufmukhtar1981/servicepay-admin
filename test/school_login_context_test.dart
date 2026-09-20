import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/school/school_login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('requires an explicit school choice for multiple memberships',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount += 1;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (requestCount == 1) {
        expect(body['schoolId'], isNull);
        return http.Response(
          jsonEncode({
            'success': false,
            'code': 'EDUPAY_SCHOOL_CONTEXT_REQUIRED',
            'message': 'Select the school you want to open.',
            'schools': [
              {
                'schoolId': 'school-1',
                'schoolName': 'First School',
                'role': 'OWNER',
                'status': 'ACTIVE',
                'schoolStatus': 'APPROVED',
              },
              {
                'schoolId': 'school-2',
                'schoolName': 'Second School',
                'role': 'SCHOOL_ADMIN',
                'status': 'ACTIVE',
                'schoolStatus': 'APPROVED',
              },
            ],
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      }
      expect(body['schoolId'], 'school-2');
      return http.Response(
        jsonEncode({
          'success': true,
          'token': 'selected-school-token',
          'schoolId': 'school-2',
          'role': 'SCHOOL_ADMIN',
          'school': {
            '_id': 'school-2',
            'name': 'Second School',
            'status': 'APPROVED',
          },
          'schoolMembership': {
            'schoolId': 'school-2',
            'role': 'SCHOOL_ADMIN',
            'status': 'ACTIVE',
            'schoolStatus': 'APPROVED',
          },
          'user': {
            'id': 'user-1',
            'fullName': 'School Owner',
            'email': 'owner@example.com',
            'role': 'CUSTOMER',
          },
          'mustChangePassword': false,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: SchoolLoginScreen(
        client: client,
        authenticatedBuilder: (_) => const Text('Selected school opened'),
      ),
    ));
    await tester.enterText(
      find.widgetWithText(TextField, 'School email'),
      'owner@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'SchoolPass9!',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    for (var frame = 0; frame < 5; frame += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Select the school you want to open.'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Second School · SCHOOL_ADMIN').last);
    await tester.pump(const Duration(milliseconds: 300));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
    await tester.tap(find.byType(FilledButton));
    for (var frame = 0; frame < 5; frame += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(requestCount, 2);
    expect(find.text('Selected school opened'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('school_auth_token'), 'selected-school-token');
    expect(prefs.getString('school_id'), 'school-2');
    expect(prefs.getString('school_role'), 'SCHOOL_ADMIN');
  });
}
