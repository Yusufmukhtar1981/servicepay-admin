import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/customer_profile_admin.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'auth_token': 'head-office-token'});
  });

  test('contact access and direct profile update follow admin contract',
      () async {
    final calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      if (request.method == 'GET') {
        return http.Response(
            '{"success":true,"data":{"canCorrect":true,"phoneVerified":false,"emailVerified":true}}',
            200);
      }
      return http.Response('{"success":true,"data":{"id":"customer-5"}}', 200);
    });
    final api = AdminCustomerProfileApi(
        client: client, baseUrl: 'https://admin.test/api');
    final access = await api.contactCorrectionAccess(customerId: 'customer-5');
    expect(calls.first.url.path,
        '/api/admin/users/customer-5/profile/contact-correction');
    expect(access['canCorrect'], isTrue);
    await api.updateProfile(
      customerId: 'customer-5',
      profile: {
        'fullName': 'Ada Okafor',
        'phone': '08035550123',
        'email': 'ada.new@example.test',
        'address': '18 Palm Avenue',
        'state': 'Oyo',
        'lga': 'Ibadan North',
        'zone': 'South West',
      },
      reason: 'Customer requested correction',
      currentPassword: 'fresh-admin-password',
      expectedPhone: '08030000000',
      expectedEmail: 'ada@example.test',
    );
    expect(jsonDecode(calls.last.body), {
      'fullName': 'Ada Okafor',
      'phone': '08035550123',
      'email': 'ada.new@example.test',
      'address': '18 Palm Avenue',
      'state': 'Oyo',
      'lga': 'Ibadan North',
      'zone': 'South West',
      'reason': 'Customer requested correction',
      'currentPassword': 'fresh-admin-password',
      'expectedPhone': '08030000000',
      'expectedEmail': 'ada@example.test',
    });
    expect(
        calls.every((request) =>
            request.headers['Authorization'] == 'Bearer head-office-token'),
        isTrue);
    api.dispose();
  });

  test('ordinary update omits optional credential and baseline fields',
      () async {
    http.Request? seen;
    final api = AdminCustomerProfileApi(
      client: MockClient((request) async {
        seen = request;
        return http.Response('{"success":true}', 200);
      }),
      baseUrl: 'https://admin.test/api',
    );
    await api.updateProfile(
      customerId: 'cust-1',
      profile: {'fullName': 'Ada Okafor'},
      reason: 'Corrected name',
    );
    expect(jsonDecode(seen!.body), {
      'fullName': 'Ada Okafor',
      'reason': 'Corrected name',
    });
    api.dispose();
  });

  test('legacy proposal APIs and history remain compatible', () async {
    final calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      if (request.url.path.endsWith('/contact-proposal') &&
          request.method == 'GET') {
        return http.Response(
            '{"success":true,"data":{"proposal":{"id":"proposal-9","status":"PENDING_VERIFICATION"}}}',
            200);
      }
      if (request.method == 'PUT') {
        return http.Response(
            '{"success":true,"data":{"proposal":{"id":"proposal-10","status":"PENDING_VERIFICATION"}}}',
            200);
      }
      if (request.method == 'DELETE') {
        return http.Response('{"success":true,"data":{"proposal":null}}', 200);
      }
      return http.Response(
          '{"success":true,"data":{"history":[],"pages":1}}', 200);
    });
    final api = AdminCustomerProfileApi(
        client: client, baseUrl: 'https://admin.test/api');
    final current = await api.contactProposal(customerId: 'cust-7');
    expect(current!['id'], 'proposal-9');
    final next = await api.proposeContactCorrection(
      customerId: 'cust-7',
      phone: '08035550123',
      currentPassword: 'secure-password',
      reason: 'Corrected number',
      expectedProposalId: 'proposal-9',
    );
    expect(next!['id'], 'proposal-10');
    expect(jsonDecode(calls[1].body), {
      'phone': '08035550123',
      'currentPassword': 'secure-password',
      'reason': 'Corrected number',
      'expectedProposalId': 'proposal-9',
    });
    await api.withdrawContactCorrection(
      customerId: 'cust-7',
      currentPassword: 'secure-password',
      reason: 'Customer cancelled',
      expectedProposalId: 'proposal-10',
    );
    expect(calls.last.method, 'DELETE');
    expect((await api.history(customerId: 'cust-7'))['history'], isEmpty);
    api.dispose();
  });

  testWidgets('history marks direct corrected contacts unverified',
      (tester) async {
    final api = AdminCustomerProfileApi(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'history': [
                  {
                    'id': 'history-direct',
                    'actorName': 'Mariam Bello',
                    'actorRole': 'HEAD_OFFICE',
                    'action': 'PROFILE_UPDATED',
                    'reason': 'Customer correction request',
                    'previousData': {
                      'phone': '08030000000',
                      'email': 'ada@example.test',
                    },
                    'newData': {
                      'phone': '08035550123',
                      'email': 'ada.new@example.test',
                    },
                    'metadata': {
                      'directCorrection': {
                        'verificationMethod': 'ADMIN_DIRECT_UNVERIFIED',
                        'unverifiedContactFields': ['phone', 'email'],
                        'ownershipVerified': false,
                      },
                    },
                  },
                ],
                'pages': 1,
              },
            }),
            200,
          )),
      baseUrl: 'https://admin.test/api',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminCustomerProfileHistory(
          customer: const {'id': 'cust-direct'},
          api: api,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('phone status: UNVERIFIED'), findsOneWidget);
    expect(find.textContaining('email status: UNVERIFIED'), findsOneWidget);
    expect(find.textContaining('Ownership: not verified'), findsOneWidget);
    expect(find.textContaining('PROFILE UPDATED · not applied'), findsNothing);
    api.dispose();
  });

  testWidgets(
      'no correction permission locks contacts but allows ordinary save',
      (tester) async {
    Map<String, dynamic>? saved;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
            '{"success":true,"data":{"canCorrect":false,"phoneVerified":true,"emailVerified":true}}',
            200);
      }
      saved = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"success":true}', 200);
    });
    final api = AdminCustomerProfileApi(
        client: client, baseUrl: 'https://admin.test/api');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminCustomerProfileEditor(
          customer: const {
            'id': 'cust-5',
            'fullName': 'Ada Okafor',
            'phone': '08030000000',
            'email': 'ada@example.test',
            'address': '12 Palm Avenue',
            'state': 'Lagos',
            'lga': 'Ikeja',
            'zone': 'South West',
          },
          api: api,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Contact-correction permission is required'),
        findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Phone Number'))
          .readOnly,
      isTrue,
    );
    expect(
        find.byKey(const Key('admin-profile-propose-contact')), findsNothing);
    expect(
        find.byKey(const Key('admin-profile-withdraw-contact')), findsNothing);
    await tester.enterText(
        find.widgetWithText(TextField, 'Full Name'), 'Ada O. Okafor');
    await tester.enterText(
      find.widgetWithText(
          TextField, 'Audit reason (required, at least 5 characters)'),
      'Customer requested correction',
    );
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(saved!.keys.toSet(), {
      'fullName',
      'phone',
      'email',
      'address',
      'state',
      'lga',
      'zone',
      'reason'
    });
    expect(saved!['phone'], '08030000000');
    api.dispose();
  });

  testWidgets('authorized contact corrections save immediately unverified',
      (tester) async {
    Map<String, dynamic>? saved;
    var writes = 0;
    final finishWrite = Completer<void>();
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
            '{"success":true,"data":{"canCorrect":true,"phoneVerified":false,"emailVerified":false}}',
            200);
      }
      writes++;
      saved = jsonDecode(request.body) as Map<String, dynamic>;
      await finishWrite.future;
      return http.Response('{"success":true}', 200);
    });
    final api = AdminCustomerProfileApi(
        client: client, baseUrl: 'https://admin.test/api');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminCustomerProfileEditor(
          customer: const {
            'id': 'cust-22',
            'fullName': 'Ada Okafor',
            'phone': '08030000000',
            'email': 'ada@example.test',
            'address': '12 Palm Avenue',
            'state': 'Lagos',
            'lga': 'Ikeja',
            'zone': 'South West',
          },
          api: api,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('saved immediately as unverified'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Phone Number'), '08035550123');
    await tester.enterText(
        find.widgetWithText(TextField, 'Email Address'), 'new@example.test');
    await tester.enterText(
      find.widgetWithText(
          TextField, 'Current admin password (only for contact changes)'),
      'fresh-password',
    );
    await tester.enterText(
      find.widgetWithText(
          TextField, 'Audit reason (required, at least 5 characters)'),
      'Customer requested contact correction',
    );
    final save = find.text('Save Changes');
    await tester.tap(save);
    await tester.pump();
    expect(writes, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNull,
    );
    finishWrite.complete();
    expect(writes, 1);
    await tester.pumpAndSettle();
    expect(saved!['phone'], '08035550123');
    expect(saved!['email'], 'new@example.test');
    expect(saved!['currentPassword'], 'fresh-password');
    expect(saved!['expectedPhone'], '08030000000');
    expect(saved!['expectedEmail'], 'ada@example.test');
    expect(saved!['reason'], 'Customer requested contact correction');
    expect(find.textContaining('verification unavailable'), findsNothing);
    api.dispose();
  });
}
