import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:servicepay_app/admin/admin_announcements_api.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/admin_promo_participants_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ParticipantClient extends http.BaseClient {
  _ParticipantClient(this.participants, {this.qualificationRate = 0});
  final List<Map<String, dynamic>> participants;
  final num qualificationRate;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final status = request.url.queryParameters['status'];
    final visibleParticipants = status == 'QUALIFIED'
        ? participants
            .where((item) => item['status'] == 'QUALIFIED')
            .toList()
        : participants;
    final qualified = participants
        .where((item) => item['status'] == 'QUALIFIED')
        .length;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({
        'data': {
          'participants': visibleParticipants,
          'summary': {
            'totalParticipants': participants.length,
            'qualifiedCustomers': qualified,
            'inProgressCustomers': participants.length - qualified,
            'totalQualifyingTransactionValue': 693500,
            'qualificationRate': qualificationRate,
          },
          'pagination': {
            'total': visibleParticipants.length,
            'pages': 1
          }
        }
      }))),
      200,
      request: request,
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('winner action requires permission and qualified status',
      (tester) async {
    final client = _ParticipantClient([
      {
        'customerId': 'qualified',
        'name': 'Qualified customer',
        'status': 'QUALIFIED'
      },
      {
        'customerId': 'progress',
        'name': 'In progress customer',
        'status': 'IN_PROGRESS'
      },
    ]);
    await tester.pumpWidget(MaterialApp(
      home: AdminPromoParticipantsScreen(
        announcementId: 'promo-1',
        api: AdminAnnouncementsApi(client: client),
        initialAccess: const AdminAccess(
          role: 'STAFF',
          permissions: {AdminPermissions.announcementsParticipantsView},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Qualified customer'), findsOneWidget);
    expect(find.text('In progress customer'), findsOneWidget);
    expect(find.text('Mark Winner'), findsNothing);
  });

  testWidgets('qualified participant can open exact winner confirmation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _ParticipantClient([
      {
        'customerId': 'qualified',
        'name': 'Qualified customer',
        'status': 'QUALIFIED'
      },
    ]);
    await tester.pumpWidget(MaterialApp(
      home: AdminPromoParticipantsScreen(
        announcementId: 'promo-1',
        api: AdminAnnouncementsApi(client: client),
        initialAccess: const AdminAccess(
          role: 'STAFF',
          permissions: {
            AdminPermissions.announcementsParticipantsView,
            AdminPermissions.announcementsWinnerManage,
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Mark Winner'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Mark Winner'));
    await tester.pumpAndSettle();

    expect(find.text(confirmWinnerText), findsOneWidget);
    expect(find.text('Confirm winner'), findsOneWidget);
  });

  testWidgets(
      'shows backend qualification rate while filtered participant rows remain visible',
      (tester) async {
    final client = _ParticipantClient(
      [
        {
          'customerId': 'qualified',
          'name': 'Qualified customer',
          'status': 'QUALIFIED'
        },
        {
          'customerId': 'progress',
          'name': 'In progress customer',
          'status': 'IN_PROGRESS'
        },
      ],
      qualificationRate: 42.5,
    );
    await tester.pumpWidget(MaterialApp(
      home: AdminPromoParticipantsScreen(
        announcementId: 'promo-1',
        api: AdminAnnouncementsApi(client: client),
        initialAccess: const AdminAccess(
          role: 'STAFF',
          permissions: {AdminPermissions.announcementsParticipantsView},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Qualification rate'), findsOneWidget);
    expect(find.text('42.5%'), findsOneWidget);
    expect(find.text('Qualified customer'), findsOneWidget);
    expect(find.text('In progress customer'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Qualified').last);
    await tester.pumpAndSettle();

    expect(client.requests.last.url.queryParameters['status'], 'QUALIFIED');
    expect(find.text('Qualified customer'), findsOneWidget);
    expect(find.text('In progress customer'), findsNothing);
    expect(find.text('42.5%'), findsOneWidget);
  });
}