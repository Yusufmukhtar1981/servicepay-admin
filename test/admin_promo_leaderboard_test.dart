import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:servicepay_app/admin/admin_announcements_api.dart';
import 'package:servicepay_app/admin/admin_executive_dashboard_screen.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/admin_promo_leaderboard_screen.dart';
import 'package:servicepay_app/admin/main_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LeaderboardClient extends http.BaseClient {
  _LeaderboardClient(this.responses);
  final List<http.Response> responses;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = responses.removeAt(0);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      request: request,
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'auth_token': 'token'}));

  test('leaderboard access follows the backend Head Office role boundary', () {
    const permission = AdminPermissions.announcementsParticipantsView;
    for (final role in <String>[
      'STAFF',
      'BRANCH',
      'BUSINESS_PARTNER',
      'OFFICER',
    ]) {
      final access = AdminAccess(
        role: role,
        permissions: const <String>{permission},
      );
      expect(access.isHeadOffice, isFalse, reason: role);
      expect(access.hasHeadOfficePermission(permission), isFalse, reason: role);
      expect(AdminMainNavigation.visibleDestinationLabels(access),
          isNot(contains('Promo Leaderboard')));
    }

    for (final role in <String>[
      'HEAD_OFFICE',
      'HEAD_OFFICE_ADMIN',
      'ADMIN',
      'SUPER_ADMIN',
      'SERVICEPAY_SUPER_ADMIN',
    ]) {
      final access = AdminAccess(
        role: role,
        permissions: const <String>{},
      );
      expect(access.isHeadOffice, isTrue, reason: role);
      expect(access.hasHeadOfficePermission(permission), isFalse, reason: role);
      expect(AdminMainNavigation.visibleDestinationLabels(access),
          contains('Promo Leaderboard'));
    }

    const wildcard = AdminAccess(
      role: 'HEAD_OFFICE',
      permissions: <String>{'*'},
    );
    expect(wildcard.hasHeadOfficePermission(permission), isTrue);
    expect(AdminMainNavigation.visibleDestinationLabels(wildcard),
        contains('Promo Leaderboard'));
  });

  test('promo leaderboard API sends list and detail contract queries',
      () async {
    final client = _LeaderboardClient([
      http.Response(
          jsonEncode({
            'data': {
              'participants': [],
              'topParticipants': [],
              'summary': {'activeParticipants': 0}
            }
          }),
          200),
      http.Response(
          jsonEncode({
            'data': {
              'customer': {'name': 'Ada'}
            }
          }),
          200),
    ]);
    final api = AdminAnnouncementsApi(client: client);

    await api.promoLeaderboard(
      campaignId: 'campaign-1',
      range: 'custom',
      from: '2026-01-01',
      to: '2026-01-31',
      status: 'QUALIFIED',
      search: 'Ada',
      page: 2,
      limit: 10,
    );
    await api.promoLeaderboardDetail('customer/1',
        campaignId: 'campaign-1',
        range: 'custom',
        from: '2026-01-01',
        to: '2026-01-31',
        status: 'QUALIFIED',
        search: 'Ada',
        page: 3,
        limit: 5);

    expect(client.requests[0].url.path,
        '/api/announcements/admin/promo-leaderboard');
    expect(client.requests[0].url.queryParameters, {
      'campaignId': 'campaign-1',
      'range': 'custom',
      'from': '2026-01-01',
      'to': '2026-01-31',
      'status': 'QUALIFIED',
      'search': 'Ada',
      'page': '2',
      'limit': '10',
    });
    expect(client.requests[1].url.path,
        '/api/announcements/admin/promo-leaderboard/customer%2F1');
    expect(client.requests[1].url.queryParameters, {
      'campaignId': 'campaign-1',
      'range': 'custom',
      'from': '2026-01-01',
      'to': '2026-01-31',
      'status': 'QUALIFIED',
      'search': 'Ada',
      'page': '3',
      'limit': '5',
    });
  });

  testWidgets('leaderboard checks participant permission before fetching',
      (tester) async {
    final client = _LeaderboardClient(<http.Response>[]);
    await tester.pumpWidget(MaterialApp(
      home: AdminPromoLeaderboardScreen(
        api: AdminAnnouncementsApi(client: client),
        initialAccess: const AdminAccess(
          role: 'STAFF',
          permissions: <String>{AdminPermissions.announcementsView},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
        find.text('You do not have permission to view the promo leaderboard.'),
        findsOneWidget);
    expect(client.requests, isEmpty);
  });

  testWidgets('non Head Office wildcard cannot fetch or render leaderboard',
      (tester) async {
    final client = _LeaderboardClient(<http.Response>[]);
    await tester.pumpWidget(MaterialApp(
      home: AdminPromoLeaderboardScreen(
        api: AdminAnnouncementsApi(client: client),
        initialAccess: const AdminAccess(
          role: 'BRANCH',
          permissions: <String>{'*'},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
        find.text('You do not have permission to view the promo leaderboard.'),
        findsOneWidget);
    expect(client.requests, isEmpty);
  });

  testWidgets('non Head Office dashboard hides promo widget and does not fetch',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_role': 'STAFF',
      'admin_effective_permissions': <String>[
        AdminPermissions.announcementsParticipantsView,
      ],
    });
    final client = _LeaderboardClient(<http.Response>[]);
    await tester.pumpWidget(MaterialApp(
      home: AdminExecutiveDashboardScreen(
        promoApi: AdminAnnouncementsApi(client: client),
        initialAccess: const AdminAccess(
          role: 'STAFF',
          permissions: <String>{
            AdminPermissions.announcementsParticipantsView,
          },
        ),
        dashboardLoader: (_) async => <String, dynamic>{
          'generatedAt': '2026-01-01T00:00:00Z',
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Top Promo Participants'), findsNothing);
    expect(find.text('Promo Leaderboard'), findsNothing);
    expect(client.requests, isEmpty);
  });

  testWidgets(
      'Head Office dashboard shows promo widget without a permission list',
      (tester) async {
    final client = _LeaderboardClient([
      http.Response(
          jsonEncode({
            'data': {
              'topParticipants': <dynamic>[],
            },
          }),
          200),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: AdminExecutiveDashboardScreen(
        promoApi: AdminAnnouncementsApi(client: client),
        initialAccess: const AdminAccess(
          role: 'HEAD_OFFICE',
          permissions: <String>{},
        ),
        dashboardLoader: (_) async => <String, dynamic>{
          'generatedAt': '2026-01-01T00:00:00Z',
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Top Promo Participants'), findsOneWidget);
    expect(find.text('View Full Leaderboard'), findsOneWidget);
    expect(client.requests, hasLength(1));
  });

  testWidgets('leaderboard renders summary, top three and opens details',
      (tester) async {
    final client = _LeaderboardClient([
      http.Response(
          jsonEncode({
            'data': {
              'campaign': {'name': 'January Rewards', 'id': 'campaign-1'},
              'summary': {
                'activeParticipants': 4,
                'qualifiedCustomers': 1,
                'almostQualified': 2,
                'rewardsPending': 1,
                'rewardsPaid': 0,
                'totalEligibleTransactions': 8,
                'totalEligibleTransactionValue': 12000,
                'conversionRate': 25
              },
              'topParticipants': [
                {
                  'customerId': 'customer-1',
                  'name': 'Ada Lovelace',
                  'rank': 42,
                  'progressPercentage': 80,
                  'eligibleTransactionCount': 4,
                  'qualificationTargetCount': 5,
                  'status': 'IN_PROGRESS'
                },
                {
                  'customerId': 'customer-2',
                  'name': 'Grace Hopper',
                  'progressPercentage': 100,
                  'status': 'QUALIFIED'
                },
                {'customerId': 'customer-3', 'name': 'Linus Torvalds'}
              ],
              'participants': [
                {
                  'customerId': 'customer-1',
                  'name': 'Ada Lovelace',
                  'rank': 42,
                  'progressPercentage': 80,
                  'eligibleTransactionCount': 4,
                  'qualificationTargetCount': 5,
                  'status': 'IN_PROGRESS'
                }
              ],
              'pagination': {'page': 1, 'total': 1, 'totalPages': 1},
              'lastUpdated': '2026-01-10T10:00:00Z'
            }
          }),
          200),
      http.Response(
          jsonEncode({
            'data': {
              'customer': {
                'name': 'Ada Lovelace',
                'maskedIdentifier': '***123'
              },
              'requirements': {'transactionCount': 5},
              'progress': {'percentage': 80},
              'eligibleTransactionCount': 4,
              'eligibleTransactionValue': 8000,
              'eligibleTransactions': [],
              'pagination': {'page': 1, 'total': 26, 'totalPages': 2},
              'reward': null
            }
          }),
          200),
      http.Response(
          jsonEncode({
            'data': {
              'eligibleTransactions': [
                {'type': 'PURCHASE', 'amount': 1200, 'createdAt': '2026-01-20'}
              ],
              'pagination': {'page': 2, 'total': 26, 'totalPages': 2}
            }
          }),
          200),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: AdminPromoLeaderboardScreen(
        api: AdminAnnouncementsApi(client: client),
        initialAccess: const AdminAccess(
          role: 'HEAD_OFFICE',
          permissions: <String>{},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Promo Leaderboard'), findsOneWidget);
    expect(find.text('January Rewards'), findsOneWidget);
    expect(find.text('Active participants'), findsOneWidget);
    expect(find.text('Reward paid'), findsNothing);
    await tester.scrollUntilVisible(find.text('Top 5 promo participants'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Top 5 promo participants'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    expect(find.text('Ada Lovelace'), findsWidgets);
    await tester.tap(find.text('Ada Lovelace').first);
    await tester.pumpAndSettle();
    expect(find.text('Eligible transactions'), findsWidgets);
    expect(find.text('8000'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2 · 26 transactions'), findsOneWidget);
    expect(client.requests.last.url.queryParameters['page'], '2');
  });
}
