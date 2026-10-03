import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:servicepay_app/admin/admin_organizations_api.dart';
import 'package:servicepay_app/admin/admin_organizations_screen.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';

class _ManualWithdrawalsClient extends http.BaseClient {
  final requests = <String>[];
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add('${request.method} ${request.url.path}');
    final body = await request.finalize().bytesToString();
    bodies.add(
      body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>,
    );
    final path = request.url.path;
    final response = path.endsWith('/summary')
        ? {'success': true, 'summary': {}}
        : path.endsWith('/manual-withdrawals')
            ? {
                'success': true,
                'data': {
                  'withdrawals': [
                    {
                      '_id': 'wd-17',
                      'reference': 'ORG-MAN-17',
                      'amount': 1250,
                      'status': 'PENDING',
                      'createdAt': '2025-02-14T11:45:00.000Z',
                      'organization': {
                        '_id': 'org-4',
                        'name': 'Lola Foods',
                        'code': 'LF-04',
                      },
                      'requestedBy': {
                        '_id': 'owner-2',
                        'fullName': 'Lola Adeyemi',
                        'phone': '08030000000',
                      },
                      'destinationSnapshot': {
                        'accountName': 'Lola Foods Ltd',
                        'accountNumber': '0123456789',
                        'bankName': 'Cedar Bank',
                      },
                    },
                  ],
                  'pagination': {'page': 1, 'pages': 1},
                },
              }
            : {'success': true};
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(response))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

Widget _screen(_ManualWithdrawalsClient client, Set<String> permissions) =>
    MaterialApp(
      home: Scaffold(
        body: AdminOrganizationsScreen(
          api: AdminOrganizationsApi(
            client: client,
            baseUrl: 'https://test/api',
            authToken: 'test-token',
          ),
          access: AdminAccess(role: 'LIMITED_STAFF', permissions: permissions),
        ),
      ),
    );

void main() {
  testWidgets('view-only organization permission cannot mark or reject', (
    tester,
  ) async {
    final client = _ManualWithdrawalsClient();
    await tester.pumpWidget(
      _screen(client, {AdminPermissions.organizationsWithdrawalsView}),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Organization withdrawals'));
    await tester.pumpAndSettle();
    expect(find.text('Lola Foods'), findsOneWidget);
    expect(find.textContaining('Lola Foods Ltd'), findsOneWidget);
    expect(find.textContaining('0123456789'), findsOneWidget);
    expect(find.textContaining('ORG-MAN-17'), findsOneWidget);
    expect(find.text('Mark as paid'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets('review requires explicit manual-transfer confirmation', (
    tester,
  ) async {
    final client = _ManualWithdrawalsClient();
    await tester.pumpWidget(
      _screen(client, {
        AdminPermissions.organizationsWithdrawalsView,
        AdminPermissions.organizationsWithdrawalsReview,
      }),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Organization withdrawals'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark as paid'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Confirm that ₦1250 has already been manually transferred to Lola Foods Ltd — Cedar Bank — 0123456789.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Not transferred'));
    await tester.pumpAndSettle();
    expect(
      client.requests.any((request) => request.contains('/mark-paid')),
      isFalse,
    );

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Account mismatch');
    await tester.tap(find.text('Reject request'));
    await tester.pumpAndSettle();
    expect(
      client.requests,
      contains('POST /api/admin/organizations/withdrawals/wd-17/reject'),
    );
    expect(
      client.bodies[client.requests.lastIndexOf(
        'POST /api/admin/organizations/withdrawals/wd-17/reject',
      )],
      {'reason': 'Account mismatch'},
    );
  });

  testWidgets('mark paid sends exact stored confirmation tuple',
      (tester) async {
    final client = _ManualWithdrawalsClient();
    await tester.pumpWidget(
      _screen(client, {
        AdminPermissions.organizationsWithdrawalsView,
        AdminPermissions.organizationsWithdrawalsReview,
      }),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Organization withdrawals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as paid'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm transfer'));
    await tester.pumpAndSettle();
    expect(
      client.requests,
      contains('POST /api/admin/organizations/withdrawals/wd-17/mark-paid'),
    );
    expect(
      client.bodies[client.requests.lastIndexOf(
        'POST /api/admin/organizations/withdrawals/wd-17/mark-paid',
      )],
      {
        'confirmed': true,
        'confirmation': {
          'reference': 'ORG-MAN-17',
          'amount': 1250,
          'accountName': 'Lola Foods Ltd',
          'accountNumber': '0123456789',
          'bankName': 'Cedar Bank',
        },
      },
    );
  });
}
