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

  test('programme controls and commission report use protected v2 endpoints',
      () async {
    final requests = <http.Request>[];
    final api = AdminReferralsApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/export')) {
          return http.Response('reference,amount\nREF-1,1\n', 200,
              headers: <String, String>{'x-export-limit': '1000'});
        }
        return http.Response(
            jsonEncode(<String, dynamic>{'success': true}), 200);
      }),
    );
    await api.programme();
    await api.updateProgramme(
      enabled: true,
      registrationBonus: 100,
      transactionCommission: 1,
      eligibleServices: <String>['AIRTIME'],
      reason: 'Approved for future activity',
    );
    await api.commissions(query: 'Ada', rewardType: 'registration', page: 2);
    final export =
        await api.exportCommissions(query: 'Ada', rewardType: 'transaction');

    expect(requests[0].url.path, '/api/admin/referrals/programme');
    expect(requests[1].method, 'PATCH');
    expect(jsonDecode(requests[1].body), <String, dynamic>{
      'enabled': true,
      'registrationBonus': 100,
      'transactionCommission': 1,
      'eligibleServices': <String>['AIRTIME'],
      'reason': 'Approved for future activity',
    });
    expect(requests[2].url.queryParameters['rewardType'], 'REGISTRATION');
    expect(requests[2].url.queryParameters['page'], '2');
    expect(requests[3].url.path, '/api/admin/referrals/commissions/export');
    expect(export.csv, contains('REF-1'));
    expect(export.limit, '1000');
    api.close();
  });

  test('unauthenticated programme reads remain server-protected', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    http.Request? seen;
    final api = AdminReferralsApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        seen = request;
        return http.Response('{"message":"Unauthorized"}', 401);
      }),
    );
    await expectLater(api.programme(), throwsA(isA<AdminReferralsException>()));
    expect(seen!.headers.containsKey('Authorization'), isFalse);
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
    expect(find.text('Manage programme'), findsNothing);
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

  testWidgets(
      'programme and commission endpoint failures are visible with retry', (
    tester,
  ) async {
    final api = _FakeReferralsApi()
      ..programmeFailure = AdminReferralsException('Forbidden', statusCode: 403)
      ..commissionsFailure = AdminReferralsException(
          'Report service unavailable',
          statusCode: 500);
    await tester.pumpWidget(MaterialApp(
      home: AdminReferralsScreen(
        api: api,
        initialAccess: const AdminAccess(
          role: 'STAFF',
          permissions: <String>{AdminPermissions.referralsView},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Forbidden'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Forbidden'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Report service unavailable'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Report service unavailable'), findsOneWidget);
    expect(find.text('Retry commission report'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Retry programme'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Retry programme'), findsOneWidget);
    expect(api.summaryCalls, 1);
    expect(api.searchCalls, 1);
  });

  testWidgets('missing additive endpoints fall back to legacy monitoring', (
    tester,
  ) async {
    final api = _FakeReferralsApi()
      ..programmeFailure = AdminReferralsException('Not found', statusCode: 404)
      ..commissionsFailure =
          AdminReferralsException('Not found', statusCode: 404);
    await tester.pumpWidget(MaterialApp(
      home: AdminReferralsScreen(
        api: api,
        initialAccess: const AdminAccess(
          role: 'STAFF',
          permissions: <String>{AdminPermissions.referralsView},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Total Referrals'), findsOneWidget);
    expect(find.text('Referral Monitoring'), findsOneWidget);
    expect(find.text('Commission report unavailable'), findsNothing);
    expect(find.text('Referral programme unavailable'), findsNothing);
  });

  testWidgets(
      'active v2 referrals use actual earnings and independent ledger paging', (
    tester,
  ) async {
    final api = _FakeReferralsApi()
      ..activeV2 = true
      ..referralTotal = 101
      ..commissionTotal = 101
      ..commissionPages = 3
      ..commissionRows = <Map<String, dynamic>>[
        <String, dynamic>{
          'rewardType': 'TRANSACTION',
          'amount': 1,
          'direction': 'CREDIT',
          'date': '2025-03-03',
          'referrer': <String, dynamic>{'fullName': 'Amina Yusuf'},
          'referredCustomer': <String, dynamic>{'fullName': 'Ada'},
        },
      ];
    await tester.pumpWidget(MaterialApp(
      home: AdminReferralsScreen(
        api: api,
        initialAccess: const AdminAccess(
          role: 'STAFF',
          permissions: <String>{AdminPermissions.referralsView},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('All categories'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Verified registration'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Verified registration'), findsOneWidget);
    expect(find.textContaining('successful paid transactions'), findsOneWidget);
    expect(find.text('Category: DATA'), findsNothing);
    await tester.scrollUntilVisible(
      find.byTooltip('Next commission page'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Commission page 1 of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Next commission page'));
    await tester.pumpAndSettle();
    expect(api.commissionRequestedPages, <int>[1, 2]);
    expect(find.text('Commission page 2 of 3'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);
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
  Object? programmeFailure;
  Object? commissionsFailure;
  bool activeV2 = false;
  int referralTotal = 1;
  int commissionTotal = 0;
  int commissionPages = 1;
  List<Map<String, dynamic>> commissionRows = <Map<String, dynamic>>[];
  final List<int> commissionRequestedPages = <int>[];

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
  Future<Map<String, dynamic>> programme() async {
    if (programmeFailure != null) throw programmeFailure!;
    return <String, dynamic>{
      'success': true,
      'canManage': true,
      'programme': <String, dynamic>{
        'version': activeV2 ? 2 : 1,
        'enabled': activeV2,
        if (activeV2) 'activatedAt': '2025-01-01T00:00:00Z',
        'registrationBonus': 100,
        'transactionCommission': 1,
        'eligibleServices': <String>['AIRTIME'],
      },
      'readiness': <String, dynamic>{'ready': true, 'blockers': <String>[]},
    };
  }

  @override
  Future<Map<String, dynamic>> commissions({
    String query = '',
    String rewardType = '',
    int page = 1,
    int limit = 50,
  }) async {
    if (commissionsFailure != null) throw commissionsFailure!;
    commissionRequestedPages.add(page);
    return <String, dynamic>{
      'success': true,
      'items': commissionRows,
      'page': page,
      'pages': commissionPages,
      'total': commissionTotal,
      'summary': <String, dynamic>{
        'registrationBonusesEarned': 100,
        'transactionCommissionsEarned': 1,
        'totalReferralEarnings': 101,
        'legacyRewards': 2000,
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
      'total': referralTotal,
      'rows': <Map<String, dynamic>>[
        <String, dynamic>{
          'customer': <String, dynamic>{'id': 'customer-1', 'firstName': 'Ada'},
          'category': 'DATA',
          'progress': <String, dynamic>{'DATA': 7},
          'qualificationStatus': 'PENDING',
          'rewardStatus': 'AWARDED',
          'rewardReference': 'ledger-1',
          'verified': true,
          'successfulTransactions': 2,
          'registrationBonusEarned': 100,
          'transactionCommissionsEarned': 2,
          'ledgerReference': 'ledger-v2',
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
