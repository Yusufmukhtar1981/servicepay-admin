import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: avoid_relative_lib_imports
import '../lib/admin/marketing_api.dart';
// ignore: avoid_relative_lib_imports
import '../lib/admin/marketing_performance_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('officer sees only personal targets with verified progress',
      (tester) async {
    SharedPreferences.setMockInitialValues({'admin_token': 'mock-token'});
    final requests = <String>[];
    final api = MarketingApi(
      client: MockClient((request) async {
        requests.add(request.url.path);
        final data = request.url.path.endsWith('/performance/context')
            ? {
                'role': 'MARKETING_OFFICER',
                'manager': false,
                'headOffice': false,
                'superAdmin': false,
                'actorId': 'officer-1',
                'periods': ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'],
              }
            : {
                'staff': {'id': 'officer-1', 'name': 'Amina Yusuf'},
                'periods': [
                  for (final period in ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'])
                    {
                    'period': period,
                    'from': '2025-06-01T00:00:00Z',
                    'to': '2025-06-02T00:00:00Z',
                    'targets': period == 'DAILY'
                        ? [
                      {
                        '_id': 'target-1',
                        'title': 'New customer acquisition',
                        'status': 'ACTIVE',
                        'outcome': 'IN_PROGRESS',
                        'actual': 3,
                        'achievementPercent': 60,
                        'remaining': 2,
                        'data': {
                          'metric': 'ACQUISITIONS',
                          'value': 5,
                          'startsAt': '2025-06-01T00:00:00Z',
                          'endsAt': '2025-06-02T00:00:00Z',
                          'objective': 'Bring new market traders onboard',
                        },
                      }
                    ]
                        : [],
                    }
                ],
                'targets': [],
                'tasks': [],
                'reports': [],
                'history': [],
                'notifications': [],
                'recentActivities': [],
                'feedback': [],
                'methodology': {'methodology': []},
              };
        return http.Response(jsonEncode({'success': true, 'data': data}), 200);
      }),
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MarketingPerformanceScreen(api: api))));
    await tester.pumpAndSettle();

    expect(find.text('Amina Yusuf'), findsOneWidget);
    expect(find.text('New customer acquisition'), findsOneWidget);
    expect(find.text('Actual 3 / 5'), findsOneWidget);
    expect(find.text('YEARLY'), findsOneWidget);
    expect(find.text('Department'), findsNothing);
    expect(requests, contains('/api/admin/marketing/performance/me'));
    api.close();
  });

  testWidgets('Head Office defaults to department without requesting /me',
      (tester) async {
    SharedPreferences.setMockInitialValues({'admin_token': 'mock-token'});
    final requests = <String>[];
    final api = MarketingApi(
      client: MockClient((request) async {
        requests.add(request.url.path);
        final data = request.url.path.endsWith('/performance/context')
            ? {
                'role': 'SUPER_ADMIN',
                'manager': true,
                'headOffice': true,
                'superAdmin': true,
                'actorId': 'head-office-1',
                'periods': ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'],
              }
            : {
                'period': {'period': 'MONTHLY'},
                'items': [],
                'total': 0,
                'methodology': {'weights': {}, 'methodology': []},
              };
        return http.Response(jsonEncode({'success': true, 'data': data}), 200);
      }),
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MarketingPerformanceScreen(api: api))));
    await tester.pumpAndSettle();

    expect(find.text('Department ranking'), findsOneWidget);
    expect(find.text('My performance'), findsNothing);
    expect(requests, contains('/api/admin/marketing/performance/department'));
    expect(requests, isNot(contains('/api/admin/marketing/performance/me')));
    api.close();
  });
}
