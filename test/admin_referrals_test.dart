import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/admin_referrals_api.dart';
import 'package:servicepay_app/admin/admin_referrals_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'test-token',
    });
  });

  test('referral API sends the protected monitoring contract', () async {
    final requests = <http.Request>[];
    final api = AdminReferralsApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'summary': <String, dynamic>{'attributedReferrals': 1},
            'rows': <dynamic>[],
          }),
          200,
        );
      }),
    );

    await api.summary();
    await api.search(search: 'Ada', category: 'data', rewardStatus: 'awarded');
    await api.progress('customer-1');
    await api.audit('customer-1');

    expect(requests[0].url.path, '/api/admin/referrals/summary');
    expect(requests[1].url.queryParameters, <String, String>{
      'q': 'Ada',
      'category': 'DATA',
      'rewardStatus': 'AWARDED',
      'page': '1',
      'limit': '50',
    });
    expect(requests[2].url.path, '/api/admin/referrals/customer-1/progress');
    expect(requests[3].url.path, '/api/admin/referrals/customer-1/audit');
    api.close();
  });

  testWidgets('authorized staff sees privacy-safe referral monitoring', (
    tester,
  ) async {
    final api = _FakeReferralsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminReferralsScreen(
          api: api,
          initialAccess: const AdminAccess(
            role: 'STAFF',
            permissions: <String>{AdminPermissions.referralsView},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.summaryCalls, 1);
    expect(api.searchCalls, 1);
    expect(find.text('Total Referrals'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Qualified'), findsOneWidget);
    expect(find.text('Paid Rewards'), findsOneWidget);
    expect(find.text('Total Reward Value'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ada'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ada'), findsOneWidget);
    expect(find.textContaining('DATA 7/10'), findsOneWidget);
    expect(find.textContaining('Ledger: ledger-1'), findsOneWidget);
  });

  testWidgets('staff without referral permission is denied before fetching', (
    tester,
  ) async {
    final api = _FakeReferralsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminReferralsScreen(
          api: api,
          initialAccess: const AdminAccess(
            role: 'STAFF',
            permissions: <String>{AdminPermissions.dashboardView},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('You do not have permission to view referral monitoring.'),
      findsOneWidget,
    );
    expect(api.summaryCalls, 0);
    expect(api.searchCalls, 0);
  });

  test('permission and registry wiring are explicit', () {
    final registry = File(
      'lib/admin/fintech_screen_registry.dart',
    ).readAsStringSync();
    final navigation = File(
      'lib/admin/main_navigation.dart',
    ).readAsStringSync();
    expect(AdminPermissions.referralsView, 'referrals.view');
    expect(registry.contains("case 'Referral Monitoring':"), isTrue);
    expect(registry.contains('return const AdminReferralsScreen();'), isTrue);
    expect(navigation.contains('AdminPermissions.referralsView'), isTrue);
    expect(navigation.contains("label: 'Referral Monitoring'"), isTrue);
  });
}

class _FakeReferralsApi extends AdminReferralsApi {
  int summaryCalls = 0;
  int searchCalls = 0;

  @override
  Future<Map<String, dynamic>> summary() async {
    summaryCalls++;
    return <String, dynamic>{
      'summary': <String, dynamic>{
        'attributedReferrals': 1,
        'pending': 1,
        'qualified': 0,
        'awardedClaims': 1,
        'awardedAmount': 2000,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> search({
    String query = '',
    String search = '',
    String category = '',
    String rewardStatus = '',
    int page = 1,
    int limit = 50,
  }) async {
    searchCalls++;
    return <String, dynamic>{
      'total': 1,
      'rows': <Map<String, dynamic>>[
        <String, dynamic>{
          'customer': <String, dynamic>{'id': 'customer-1', 'firstName': 'Ada'},
          'category': 'DATA',
          'progress': <String, dynamic>{'DATA': 7},
          'qualificationStatus': 'PENDING',
          'rewardStatus': 'AWARDED',
          'rewardReference': 'ledger-1',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> progress(String customerId) async =>
      <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> audit(String customerId) async =>
      <String, dynamic>{};
}
