import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_branch_management_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{'auth_token': 'isolated-branch-widget-token'});
    await SharedPreferences.getInstance();
  });

  testWidgets('legacy branches render without optional location fields',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1000);
    addTearDown(tester.view.reset);
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'branches': <Map<String, dynamic>>[
              <String, dynamic>{
                '_id': 'legacy-branch',
                'name': 'Legacy branch',
                'code': 'LEGACY-001',
                'status': 'ACTIVE',
                'state': 'Kano',
                'lga': null,
              },
              <String, dynamic>{
                '_id': 'empty-location-branch',
                'name': 'Unrecorded location branch',
                'code': 'LEGACY-002',
                'status': 'ACTIVE',
                'city': null,
              },
            ],
            'users': <dynamic>[],
            'managers': <dynamic>[],
          }),
          200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
        home: AdminBranchManagementScreen(
          canManage: true,
          canViewReports: false,
          canViewApprovals: false,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Legacy branch'), findsOneWidget);
      expect(find.text('Kano'), findsOneWidget);
      expect(find.text('Location not recorded'), findsOneWidget);
      expect(find.text('View branch'), findsNWidgets(2));
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });
}
