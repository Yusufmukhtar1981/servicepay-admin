import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: avoid_relative_lib_imports
import '../lib/admin/admin_permissions.dart';
// ignore: avoid_relative_lib_imports
import '../lib/admin/main_navigation.dart';
// ignore: avoid_relative_lib_imports
import '../lib/admin/marketing_api.dart';
// ignore: avoid_relative_lib_imports
import '../lib/admin/marketing_management_screen.dart';
// ignore: avoid_relative_lib_imports
import '../lib/admin/marketing_performance_screen.dart';

class _MarketingApiFake extends MarketingApi {
  _MarketingApiFake() : super();

  final List<Map<String, String>> queries = [];
  Map<String, dynamic>? createdTarget;
  Map<String, dynamic>? updatedTarget;
  int managementCalls = 0;
  String? requestedPerformancePeriod;
  String? requestedPerformanceFrom;
  String? requestedPerformanceTo;

  @override
  Future<Map<String, dynamic>> management(Map<String, String> query) async {
    managementCalls++;
    queries.add(Map<String, String>.from(query));
    return {
      'period': query['period'] ?? 'MONTHLY',
      'from': '2026-03-01',
      'to': '2026-03-31',
      'note':
          'Values use verified records; unknown evidence remains unavailable.',
      'summary': {
        'teamMembers': 2,
        'assignedTargets': 2,
        'verifiedAchievements': 1,
        'staffMeetingTargets': 1,
        'staffBelowTargets': 0,
        'departmentPerformance': null,
        'pendingReports': 1,
      },
      'periods': [
        {
          'period': 'MONTHLY',
          'assignedTargets': 2,
          'achievementPercent': null,
          'actual': null,
        }
      ],
      'staff': [
        {
          'id': 'manager-1',
          'name': 'Ada Manager',
          'role': 'HEAD_OF_MARKETING',
          'achievement': null,
          'score': null,
          'rank': null,
          'targets': [],
        },
        {
          'id': 'staff-1',
          'name': 'Bisi Marketer',
          'role': 'Marketing Officer',
          'achievement': null,
          'targets': [],
        },
      ],
      'targets': [
        {
          '_id': 'target-1',
          'title': 'New partners',
          'officerId': 'staff-1',
          'revision': 4,
          'status': 'ACTIVE',
          'actual': null,
          'achievementPercent': null,
          'remaining': null,
          'data': {
            'scope': 'INDIVIDUAL',
            'authority': 'ADMIN',
            'metric': 'MERCHANT_ACQUISITIONS',
            'value': 4,
            'period': 'MONTHLY',
            'startsAt': '2026-03-01',
            'endsAt': '2026-03-31',
            'objective': 'Grow trusted partners',
          },
        },
      ],
      'departmentTargets': [
        {
          '_id': 'department-target-1',
          'title': 'Department partners',
          'revision': 2,
          'status': 'PAUSED',
          'actual': null,
          'achievementPercent': null,
          'data': {
            'scope': 'DEPARTMENT',
            'metric': 'PARTNERSHIPS',
            'value': 8,
            'period': 'MONTHLY',
            'startsAt': '2026-03-01',
            'endsAt': '2026-03-31',
            'objective': 'Department-wide goal',
          },
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> team() async => {
        'items': [
          {
            '_id': 'manager-1',
            'name': 'Ada Manager',
            'role': 'HEAD_OF_MARKETING',
            'email': 'ada@example.test',
            'phone': '+234800000001',
          },
          {
            '_id': 'staff-1',
            'name': 'Bisi Marketer',
            'role': 'Marketing Officer',
            'email': 'bisi@example.test',
            'phone': '+234800000002',
          },
        ],
      };

  @override
  Future<Map<String, dynamic>> performanceContext() async =>
      {'headOffice': true, 'superAdmin': false};

  @override
  Future<Map<String, dynamic>> createRecord(
    String kind,
    Map<String, dynamic> payload, {
    required String idempotencyKey,
  }) async {
    createdTarget = payload;
    return {'id': 'new-target'};
  }

  @override
  Future<Map<String, dynamic>> updateRecord(
    String kind,
    String id,
    Map<String, dynamic> payload,
  ) async {
    updatedTarget = payload;
    return {'id': id};
  }

  @override
  Future<Map<String, dynamic>> performanceDepartment({
    String period = 'MONTHLY',
    String? from,
    String? to,
    int page = 1,
    int limit = 20,
    String search = '',
  }) async {
    requestedPerformancePeriod = period;
    requestedPerformanceFrom = from;
    requestedPerformanceTo = to;
    return {'items': [], 'departmentTargets': []};
  }
}

void main() {
  test('new targets default to independent UTC calendar period boundaries', () {
    final at = DateTime.utc(2026, 11, 11, 22);
    final daily = marketingTargetPeriodBounds('DAILY', at);
    expect(daily, (DateTime.utc(2026, 11, 11), DateTime.utc(2026, 11, 12)));
    final weekly = marketingTargetPeriodBounds('WEEKLY', at);
    expect(weekly, (DateTime.utc(2026, 11, 9), DateTime.utc(2026, 11, 16)));
    final monthly = marketingTargetPeriodBounds('MONTHLY', at);
    expect(monthly, (DateTime.utc(2026, 11), DateTime.utc(2026, 12)));
    final yearly = marketingTargetPeriodBounds('YEARLY', at);
    expect(yearly, (DateTime.utc(2026), DateTime.utc(2027)));
  });
  TestWidgetsFlutterBinding.ensureInitialized();

  test('central Marketing Management navigation is Head Office only', () {
    final headOffice = AdminMainNavigation.visibleDestinationLabels(
      const AdminAccess(role: 'HEAD_OFFICE', permissions: {}),
    );
    final staff = AdminMainNavigation.visibleDestinationLabels(
      const AdminAccess(role: 'STAFF', permissions: {'marketing.view'}),
    );
    expect(headOffice, contains('Marketing Management'));
    expect(staff, isNot(contains('Marketing Management')));
    expect(canUseMarketingManagement(role: 'MARKETING_MANAGER'), isFalse);
    expect(canUseMarketingManagement(role: 'SUPER_ADMIN'), isTrue);
  });

  testWidgets('period and performance filters reach management query',
      (tester) async {
    final api = _MarketingApiFake();
    await tester
        .pumpWidget(MaterialApp(home: MarketingManagementScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('marketing-period-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly').last);
    await tester.pumpAndSettle();
    expect(api.queries.last['period'], 'WEEKLY');

    await tester
        .tap(find.byKey(const ValueKey('marketing-performance-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Below targets').last);
    await tester.pumpAndSettle();
    expect(api.queries.last['performance'], 'BELOW');
  });

  testWidgets(
      'department target creation omits individual assignee and authority',
      (tester) async {
    final api = _MarketingApiFake();
    await tester
        .pumpWidget(MaterialApp(home: MarketingManagementScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Target Management'));
    await tester.tap(find.text('Target Management'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New target'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('target-assignment-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entire department').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).at(0), 'Quarterly expansion');
    await tester.enterText(find.byType(TextFormField).at(1), '12');
    await tester.tap(find.text('Create target'));
    await tester.pumpAndSettle();

    expect(api.createdTarget, isNotNull);
    expect(api.createdTarget!['officerId'], isNull);
    expect(api.createdTarget!.containsKey('authority'), isFalse);
    expect(api.createdTarget!['data']['scope'], 'DEPARTMENT');
    expect(api.createdTarget!['data']['value'], 12);
    expect(api.createdTarget!['data']['period'], 'MONTHLY');
  });

  testWidgets('HEAD_OF_MARKETING role is included in the manager view',
      (tester) async {
    final api = _MarketingApiFake();
    await tester
        .pumpWidget(MaterialApp(home: MarketingManagementScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Marketing Manager'));
    await tester.tap(find.text('Marketing Manager'));
    await tester.pumpAndSettle();
    expect(find.text('Ada Manager'), findsOneWidget);
    expect(isMarketingManagerRole('HEAD_OF_MARKETING'), isTrue);
  });

  testWidgets('editing individual target to department clears officerId',
      (tester) async {
    final api = _MarketingApiFake();
    await tester
        .pumpWidget(MaterialApp(home: MarketingManagementScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Target Management'));
    await tester.tap(find.text('Target Management'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Target actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit target'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('target-assignment-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entire department').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(api.updatedTarget!['data']['scope'], 'DEPARTMENT');
    expect(api.updatedTarget!['officerId'], isNull);
  });

  testWidgets('target status filters include department targets',
      (tester) async {
    final api = _MarketingApiFake();
    await tester
        .pumpWidget(MaterialApp(home: MarketingManagementScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Target Management'));
    await tester.tap(find.text('Target Management'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paused'));
    await tester.pumpAndSettle();
    expect(find.text('Department partners'), findsOneWidget);
    expect(find.text('New partners'), findsNothing);
  });

  testWidgets('performance screen accepts outer period and date filters',
      (tester) async {
    final api = _MarketingApiFake();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MarketingPerformanceScreen(
          api: api,
          initialView: 'department',
          initialPeriod: 'WEEKLY',
          initialFrom: DateTime(2026, 3, 2),
          initialTo: DateTime(2026, 3, 8),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(api.requestedPerformancePeriod, 'WEEKLY');
    expect(api.requestedPerformanceFrom, '2026-03-02T00:00:00.000Z');
    expect(api.requestedPerformanceTo, '2026-03-09T00:00:00.000Z');
  });

  testWidgets('unknown KPI evidence stays unavailable on narrow layouts',
      (tester) async {
    final api = _MarketingApiFake();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(MaterialApp(home: MarketingManagementScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Target Management'));
    await tester.tap(find.text('Target Management'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unavailable'), findsWidgets);
    expect(find.textContaining('0 / 4'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
