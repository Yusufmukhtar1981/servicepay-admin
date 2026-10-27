import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:servicepay_app/admin/admin_customer_leaderboard_api.dart';
import 'package:servicepay_app/admin/main_navigation.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('admin report query carries month, limit, sort and admin session',
      () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'admin-session'});
    http.Request? request;
    final api = AdminCustomerLeaderboardApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'enabled': true,
              'period': {'month': '2026-08', 'timeZone': 'Africa/Lagos'},
              'rows': [
                {
                  'rank': 1,
                  'displayName': 'M*** A***',
                  'count': 5,
                  'value': 1000,
                  'isMe': false
                }
              ],
              'totalCustomers': 1,
            },
          }),
          200,
        );
      }),
    );
    final result = await api.report('2026-08', 50, 'value');
    expect(result['success'], true);
    expect(request!.url.path, '/api/customer-leaderboard/admin');
    expect(request!.url.queryParameters, {
      'month': '2026-08',
      'limit': '50',
      'sort': 'value',
    });
    expect(request!.headers['authorization'], 'Bearer admin-session');
    expect((result['data'] as Map)['rows'], hasLength(1));
  });

  test('settings mutation sends revision and selected safe rules', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'admin-session'});
    http.Request? request;
    final api = AdminCustomerLeaderboardApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((value) async {
        request = value;
        return http.Response(
            jsonEncode({
              'success': true,
              'data': {'revision': 9}
            }),
            200);
      }),
    );
    await api.updateSettings({
      'enabled': true,
      'eligibleServices': ['airtime'],
      'minAmount': 250,
      'revision': 8,
    });
    expect(request!.method, 'PATCH');
    expect(request!.url.path, '/api/customer-leaderboard/admin/settings');
    expect(jsonDecode(request!.body), {
      'enabled': true,
      'eligibleServices': ['airtime'],
      'minAmount': 250,
      'revision': 8,
    });
  });

  test('does not fall back to a legacy admin token preference', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'legacy-token'});
    final api = AdminCustomerLeaderboardApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(api.settings(), throwsA(isA<FormatException>()));
  });

  test('Customer Leaderboard is Head Office-only even with settings.view', () {
    final branchLabels = AdminMainNavigation.visibleDestinationLabels(
      const AdminAccess(role: 'BRANCH', permissions: {'settings.view'}),
    );
    final officeLabels = AdminMainNavigation.visibleDestinationLabels(
      const AdminAccess(role: 'HEAD_OFFICE', permissions: {'settings.view'}),
    );
    expect(
      canAccessCustomerLeaderboardNavigation(
        role: 'BRANCH',
        permissions: {'settings.view'},
      ),
      isFalse,
    );
    expect(
      canAccessCustomerLeaderboardNavigation(
        role: 'HEAD OFFICE',
        permissions: {'settings.view'},
      ),
      isTrue,
    );
    expect(branchLabels, isNot(contains('Customer Leaderboard')));
    expect(officeLabels, contains('Customer Leaderboard'));
    expect(officeLabels, contains('Promo Leaderboard'));
  });
}
