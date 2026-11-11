import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: avoid_relative_lib_imports
import '../lib/admin/marketing_api.dart';
// ignore: avoid_relative_lib_imports
import '../lib/admin/marketing_department_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'admin_token': 'fixture-only-token',
      'user_id': 'fixture-user',
    });
  });

  for (final viewport in const <Size>[Size(390, 844), Size(1280, 900)]) {
    testWidgets('Marketing overview renders at ${viewport.width}px',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final client = MockClient((request) async {
        final data = request.url.path.endsWith('/schema')
            ? <String, dynamic>{
                'kinds': ['campaign', 'task'],
                'channels': ['SOCIAL', 'REFERRAL'],
                'fields': <String, dynamic>{},
                'statuses': <String, dynamic>{},
                'permissions': ['marketing.view'],
                'headOffice': false,
              }
            : <String, dynamic>{
                'period': {
                  'from': '2025-04-01',
                  'to': '2025-04-07',
                  'timeZone': 'UTC',
                },
                'metrics': {
                  'totalCustomersAcquired': 37,
                  'newCustomersToday': 4,
                  'activeCustomers': 128,
                  'firstTimeTransactingCustomers': 19,
                  'activeCampaigns': 2,
                  'marketingStaff': 3,
                  'conversionRate': 12.7,
                  'expenditureNaira': 184500,
                  'approvedBudgetNaira': 420000,
                  'retainedCustomers': 11,
                  'roi': null,
                },
                'campaigns': [
                  {
                    'id': 'fixture-campaign',
                    'title': 'Kano merchant launch',
                    'channel': 'REFERRAL',
                    'acquired': 22,
                    'firstTransactions': 13,
                    'expenditureNaira': 80000,
                    'cacNaira': 3636,
                    'roi': null,
                  }
                ],
                'geography': [
                  {'state': 'Kano', 'city': 'Kano', 'acquired': 22}
                ],
                'officers': [
                  {
                    'id': 'fixture-officer',
                    'name': 'Amina Yusuf',
                    'acquired': 18,
                    'firstTransactions': 12,
                    'submittedReports': 3,
                    'publishedContent': 2,
                    'attendance': 5,
                    'scorePercent': 84.5,
                    'scorecard': [
                      {
                        'metric': 'Verified acquisition',
                        'actual': 18,
                        'target': 24,
                        'achievementPercent': 75,
                      }
                    ],
                    'completedTasks': 7,
                    'targetValue': 24,
                    'achievementPercent': 75,
                  }
                ],
                'series': [
                  {'date': '2025-04-01', 'acquired': 5, 'firstTransactions': 2},
                  {'date': '2025-04-02', 'acquired': 8, 'firstTransactions': 4},
                ],
                'referrals': {
                  'registrations': 9,
                  'firstTransactions': 3,
                  'conversionRate': 33.3,
                },
                'social': [
                  {
                    'channel': 'Instagram',
                    'reach': 340,
                    'impressions': 518,
                    'engagements': 27,
                    'reportCount': 2,
                  }
                ],
                'partnerships': [
                  {
                    'id': 'partner-1',
                    'title': 'Kano market association',
                    'status': 'APPROVED',
                    'campaignId': 'fixture-campaign',
                    'acquired': 6,
                    'firstTransactions': 4,
                  }
                ],
                'limitations': ['Manual attribution is evidence-confirmed.'],
              };
        return http.Response(
          jsonEncode({'success': true, 'data': data}),
          200,
        );
      });

      await tester.pumpWidget(MaterialApp(
        home: MarketingDepartmentScreen(
          permissions: const {'marketing.view'},
          isHeadOffice: false,
          api: MarketingApi(client: client),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('The acquisition pulse'), findsOneWidget);
      expect(find.text('37'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('marketing-overview-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(find.text('Acquisition trend'), 260,
          scrollable: scrollable);
      expect(find.text('Acquisition trend'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Interactive line chart')),
          findsOneWidget);
      await tester.scrollUntilVisible(find.text('Campaign performance'), 250,
          scrollable: scrollable);
      expect(find.text('Campaign performance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('partnership form submits evidence fields through schema UI',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Map<String, dynamic>? created;
    final requestedPaths = <String>[];
    final client = MockClient((request) async {
      requestedPaths.add('${request.method} ${request.url.path}');
      if (request.url.path.endsWith('/schema')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'kinds': ['partnership'],
              'fields': {
                'partnership': [
                  'organization',
                  'evidence',
                  'startsAt',
                  'endsAt'
                ]
              },
              'statuses': {
                'partnership': [
                  'SUBMITTED',
                  'APPROVED',
                  'REJECTED',
                  'COMPLETED'
                ]
              },
              'permissions': ['marketing.reports.manage'],
              'headOffice': false,
            }
          }),
          200,
        );
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/records/partnership')) {
        created = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'success': true,
              'data': {'_id': 'partnership-1'}
            }),
            201);
      }
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {'items': [], 'total': 0}
        }),
        200,
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: MarketingDepartmentScreen(
        permissions: const {'marketing.reports.manage'},
        isHeadOffice: false,
        api: MarketingApi(client: client),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Partnerships'));
    await tester.pumpAndSettle();
    expect(requestedPaths.any((path) => path.endsWith('/records/partnership')),
        isTrue);
    await tester.tap(find.text('New Partnership'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Title *'), 'Kano association');
    await tester.enterText(
        find.widgetWithText(TextField, 'Organization *'), 'Kano Traders Union');
    await tester.enterText(
        find.widgetWithText(TextField, 'Evidence *'), 'signed-mou-41');
    await tester.enterText(
        find.widgetWithText(TextField, 'Starts At *'), '2025-04-01T00:00:00Z');
    await tester.enterText(
        find.widgetWithText(TextField, 'Ends At *'), '2025-12-31T23:59:00Z');
    await tester.tap(find.text('Create record'));
    await tester.pumpAndSettle();
    expect(created?['title'], 'Kano association');
    expect(created?['data']['organization'], 'Kano Traders Union');
    expect(created?['data']['evidence'], 'signed-mou-41');
    expect(created?['data']['startsAt'], '2025-04-01T00:00:00.000Z');
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy overview with absent series renders unavailable states',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = MockClient((request) async {
      final data = request.url.path.endsWith('/schema')
          ? {
              'permissions': ['marketing.view'],
              'kinds': ['campaign'],
            }
          : {
              'period': {'timeZone': 'UTC'},
              'metrics': {
                'totalCustomersAcquired': 0,
                'roi': null,
                'verifiedSpendNaira': null,
              },
              'campaigns': [],
              'geography': [],
              'officers': [],
              'limitations': [],
            };
      return http.Response(jsonEncode({'success': true, 'data': data}), 200);
    });
    await tester.pumpWidget(MaterialApp(
      home: MarketingDepartmentScreen(
        permissions: const {'marketing.view'},
        isHeadOffice: false,
        api: MarketingApi(client: client),
      ),
    ));
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byKey(const ValueKey('marketing-overview-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(find.text('Acquisition trend'), 250,
        scrollable: scrollable);
    expect(
        find.text('No dated series returned for this period.'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
