import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:servicepay_app/admin/admin_announcements_api.dart';
import 'package:servicepay_app/admin/admin_announcements_screen.dart';
import 'package:servicepay_app/admin/admin_dashboard_screen.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ScreenClient extends http.BaseClient {
  _ScreenClient(this.body);
  final Map<String, dynamic> body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final responseBody = request.url.path.endsWith('/summary')
        ? {
            'data': {'summary': body['summary']}
          }
        : {
            'data': {'announcements': body['announcements']}
          };
    // Keep the fixture intentionally canonical: the screen must parse data.*.
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(responseBody))),
      200,
      request: request,
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Fintech Announcements opens the existing protected editor with image upload',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = AdminAnnouncementsApi(
        client: _ScreenClient({'announcements': [], 'summary': {}}));
    await tester.pumpWidget(MaterialApp(
      home: AdminDashboardScreen(
        initialAccess: const AdminAccess(role: 'HEAD_OFFICE', permissions: {'*'}),
        dashboardLoader: (_) async => <String, dynamic>{},
        promoApi: api,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fintech Control Center').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Announcements');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Announcements').last);
    await tester.pumpAndSettle();
    expect(find.byType(AdminAnnouncementsScreen), findsOneWidget);
    expect(find.text('New announcement'), findsOneWidget);
    await tester.tap(find.text('New announcement'));
    await tester.pumpAndSettle();
    expect(find.text('Upload banner image'), findsOneWidget);
  });

  test('delivery diagnostics expose expired, inactive, draft and popup-only banners', () {
    final issues = announcementDeliveryIssues({
      'isActive': false,
      'style': 'POPUP',
      'campaignTrackingEnabled': true,
      'campaignStatus': 'DRAFT',
      'endAt': '2026-11-16T10:00:00+01:00',
    }, now: DateTime.utc(2026, 11, 16, 9));
    expect(issues, containsAll([
      'Inactive', 'Expired', 'Campaign DRAFT',
      'Popup only — not a dashboard banner',
    ]));
    expect(announcementDeliveryIssues({
      'isActive': true, 'style': 'BANNER',
      'startAt': '2026-11-16T10:00:00+01:00',
      'endAt': '2026-12-01T00:00:00Z',
    }, now: DateTime.utc(2026, 11, 16, 9)), isEmpty);
    expect(announcementDeliveryIssues({
      'isActive': true, 'style': 'BANNER',
      'startAt': '2026-12-01T00:00:00Z',
    }, now: DateTime.utc(2026, 11, 16)), contains('Scheduled for the future'));
  });

  testWidgets('shows loading then empty state and hides ungranted controls',
      (tester) async {
    final access = const AdminAccess(
      role: 'STAFF',
      permissions: {AdminPermissions.announcementsView},
    );
    await tester.pumpWidget(MaterialApp(
      home: AdminAnnouncementsScreen(
        initialAccess: access,
        api: AdminAnnouncementsApi(
          client: _ScreenClient({'announcements': [], 'summary': {}}),
        ),
      ),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('No customer announcements yet'), findsOneWidget);
    expect(find.text('New announcement'), findsNothing);
    expect(find.text('Unique views'), findsNothing);
  });

  testWidgets('renders responsive announcement data and validation editor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const access = AdminAccess(
      role: 'STAFF',
      permissions: {
        AdminPermissions.announcementsView,
        AdminPermissions.announcementsSummary,
        AdminPermissions.announcementsCreate,
        AdminPermissions.announcementsUpdate,
        AdminPermissions.announcementsActivate,
        AdminPermissions.announcementsDelete,
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: AdminAnnouncementsScreen(
        initialAccess: access,
        api: AdminAnnouncementsApi(
          client: _ScreenClient({
            'announcements': [
              {
                'id': 'a1',
                'title': 'Planned downtime',
                'message': 'Service window',
                'isActive': true,
                'metrics': {
                  'views': 10,
                  'acknowledgements': 8,
                  'dismissals': 2,
                  'clicks': 4
                }
              }
            ],
            'summary': {
              'total': 9,
              'active': 4,
              'scheduled': 3,
              'expired': 2,
              'views': 18,
              'acknowledgements': 11,
              'dismissals': 3,
              'clicks': 6
            }
          }),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('9'), findsWidgets);
    expect(find.text('4'), findsWidgets);
    expect(find.text('3'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    expect(find.text('18'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Planned downtime'), 300);
    expect(find.text('Planned downtime'), findsOneWidget);
    expect(find.text('Views 10'), findsOneWidget);
    expect(find.text('Acknowledgements 8'), findsOneWidget);
    expect(find.text('Dismissals 2'), findsOneWidget);
    expect(find.text('Clicks 4'), findsOneWidget);
    await tester.tap(find.text('New announcement'));
    await tester.pumpAndSettle();
    expect(find.text('Preview'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Title is required'), findsOneWidget);
    await tester.tap(find.text('Preview'));
    await tester.pump();
    expect(find.text('Customer preview'), findsNothing);
  });

  testWidgets('renders API error with retry', (tester) async {
    final client = _FailingClient();
    await tester.pumpWidget(MaterialApp(
      home: AdminAnnouncementsScreen(
        initialAccess: const AdminAccess(
            role: 'STAFF', permissions: {AdminPermissions.announcementsView}),
        api: AdminAnnouncementsApi(client: client),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });
}

class _FailingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('{}')), 500,
          request: request);
}
