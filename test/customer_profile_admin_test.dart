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

  test('contact challenge and profile update use audited admin contract',
      () async {
    final calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      if (request.method == 'POST') {
        return http.Response(
          '{"success":true,"data":{"challengeId":"challenge-7","expiresInSeconds":600}}',
          200,
        );
      }
      return http.Response('{"success":true,"data":{"id":"customer-5"}}', 200);
    });
    final api = AdminCustomerProfileApi(
      client: client,
      baseUrl: 'https://admin.test/api',
    );
    final challenge = await api.requestContactCode(
      customerId: 'customer-5',
      field: 'email',
      value: 'new@example.test',
      currentPassword: 'admin-password',
      reason: 'Customer requested change',
    );
    expect(challenge, 'challenge-7');
    expect(calls.first.url.path,
        '/api/admin/users/customer-5/profile/contact/request');
    expect(jsonDecode(calls.first.body), {
      'field': 'email',
      'value': 'new@example.test',
      'currentPassword': 'admin-password',
      'reason': 'Customer requested change',
    });
    await api.updateProfile(
      customerId: 'customer-5',
      profile: {'fullName': 'Ada Okafor', 'email': 'new@example.test'},
      reason: 'Customer requested change',
      contactVerifications: {
        'email': {
          'challengeId': challenge,
          'code': '111111',
          'approvalCode': '222222',
        },
      },
    );
    expect(calls.last.url.path, '/api/admin/users/customer-5/profile');
    expect(jsonDecode(calls.last.body), {
      'fullName': 'Ada Okafor',
      'email': 'new@example.test',
      'reason': 'Customer requested change',
      'contactVerifications': {
        'email': {
          'challengeId': 'challenge-7',
          'code': '111111',
          'approvalCode': '222222',
        }
      }
    });
    expect(
        calls.every((request) =>
            request.headers['Authorization'] == 'Bearer head-office-token'),
        isTrue);
    api.dispose();
  });

  test('history uses the requested page and presents API failures', () async {
    http.Request? seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
        '{"success":true,"data":{"history":[{"id":"h1","actorName":"M. Bello","actorRole":"HEAD_OFFICE","createdAt":"2026-03-01T10:00:00Z","reason":"Correction","previousData":{},"newData":{}}],"page":2,"total":11,"pages":3}}',
        200,
      );
    });
    final api = AdminCustomerProfileApi(
        client: client, baseUrl: 'https://admin.test/api');
    final page = await api.history(customerId: 'cust-1', page: 2);
    expect(seen!.url.path, '/api/admin/users/cust-1/profile/history');
    expect(seen!.url.queryParameters['page'], '2');
    expect(page['history'], hasLength(1));
    api.dispose();
  });

  test('pending contact proposal uses password, reason, and required CAS id',
      () async {
    final calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      if (request.method == 'GET') {
        return http.Response(
            '{"success":true,"data":{"proposal":{"id":"proposal-9","status":"PENDING_VERIFICATION"}}}',
            200);
      }
      if (request.method == 'PUT') {
        return http.Response(
            '{"success":true,"data":{"proposal":{"id":"proposal-10","status":"PENDING_VERIFICATION","proposedPhone":"08035550123"}}}',
            200);
      }
      return http.Response('{"success":true,"data":{"proposal":null}}', 200);
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
      expectedProposalId: current['id'] as String,
    );
    expect(next!['status'], 'PENDING_VERIFICATION');
    expect(calls[1].method, 'PUT');
    expect(
        calls[1].url.path, '/api/admin/users/cust-7/profile/contact-proposal');
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
    expect(jsonDecode(calls.last.body), {
      'currentPassword': 'secure-password',
      'reason': 'Customer cancelled',
      'expectedProposalId': 'proposal-10',
    });
    api.dispose();
  });

  test('missing admin session fails before making an HTTP request', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    });
    final api = AdminCustomerProfileApi(client: client);
    await expectLater(
      api.history(customerId: 'cust-1'),
      throwsA(isA<StateError>()),
    );
    expect(calls, 0);
    api.dispose();
  });

  testWidgets('ordinary profile editor saves geo but never contact fields',
      (tester) async {
    Map<String, dynamic>? saved;
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response(
            '{"success":false,"message":"Pending proposal API unavailable"}',
            404);
      }
      saved = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"success":true,"data":{"id":"cust-5"}}', 200);
    });
    final api = AdminCustomerProfileApi(
      client: client,
      baseUrl: 'https://admin.test/api',
    );
    const customer = <String, dynamic>{
      '_id': 'cust-5',
      'fullName': 'Ada Okafor',
      'phone': '08030000000',
      'email': 'ada@example.test',
      'address': '12 Palm Avenue',
      'state': 'Lagos',
      'lga': 'Ikeja',
      'zone': 'South West',
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminCustomerProfileEditor(customer: customer, api: api),
      ),
    ));
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Phone Number'))
          .readOnly,
      isTrue,
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'State'))
          .readOnly,
      isFalse,
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Email Address'))
          .controller!
          .text,
      'ada@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Full Name'),
      'Ada O. Okafor',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Residential Address'),
      '18 Palm Avenue',
    );
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Audit reason (required, at least 5 characters)',
      ),
      'Customer requested correction',
    );
    await tester.enterText(find.widgetWithText(TextField, 'State'), 'Oyo');
    await tester.enterText(
        find.widgetWithText(TextField, 'LGA'), 'Ibadan North');
    await tester.enterText(
        find.widgetWithText(TextField, 'Zone'), 'South West');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(saved!['fullName'], 'Ada O. Okafor');
    expect(saved!['address'], '18 Palm Avenue');
    expect(saved!['state'], 'Oyo');
    expect(saved!['lga'], 'Ibadan North');
    expect(saved!['zone'], 'South West');
    expect(saved!['reason'], 'Customer requested correction');
    expect(saved!.keys.toSet(),
        {'fullName', 'address', 'state', 'lga', 'zone', 'reason'});
    expect(
      requests.any((request) => request.url.path.endsWith('/contact/request')),
      isFalse,
    );
    api.dispose();
  });

  testWidgets('contact correction stays pending and can be withdrawn',
      (tester) async {
    final calls = <http.Request>[];
    var hasProposal = false;
    final client = MockClient((request) async {
      calls.add(request);
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'proposal': hasProposal
                  ? {
                      'id': 'proposal-22',
                      'status': 'PENDING_VERIFICATION',
                      'proposedPhone': '08035550123',
                      'proposedEmail': null,
                      'requestedAt': '2026-05-01T10:00:00Z',
                      'requestedByName': 'Mariam Bello',
                      'reason': 'Customer requested correction',
                    }
                  : null,
            }
          }),
          200,
        );
      }
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['currentPassword'] == 'wrong-password') {
          return http.Response(
              '{"success":false,"message":"Incorrect administrator password."}',
              401);
        }
        hasProposal = true;
        return http.Response(
            '{"success":true,"data":{"proposal":{"id":"proposal-22","status":"PENDING_VERIFICATION"}}}',
            200);
      }
      hasProposal = false;
      return http.Response('{"success":true,"data":{"proposal":null}}', 200);
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
        find.textContaining('Current contacts remain active'), findsOneWidget);
    expect(find.text('No pending correction.'), findsOneWidget);
    final submit = find.byKey(const Key('admin-profile-propose-contact'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump();
    expect(
        find.textContaining('Enter a proposed phone or email'), findsOneWidget);
    final phoneField =
        find.widgetWithText(TextField, 'Proposed phone (optional)');
    await tester.ensureVisible(phoneField);
    await tester.enterText(phoneField, '08035550123');
    final passwordField = find.widgetWithText(TextField, 'Admin password');
    await tester.ensureVisible(passwordField);
    await tester.enterText(passwordField, 'admin-password');
    final reasonField = find.widgetWithText(
        TextField, 'Proposal reason (required, at least 5 characters)');
    await tester.ensureVisible(reasonField);
    await tester.enterText(
      reasonField,
      'Customer requested correction',
    );
    await tester.ensureVisible(passwordField);
    await tester.enterText(passwordField, 'wrong-password');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Incorrect administrator password.'), findsOneWidget);
    expect(find.text('No pending correction.'), findsOneWidget);
    await tester.ensureVisible(passwordField);
    await tester.enterText(passwordField, 'admin-password');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.textContaining('PENDING VERIFICATION · not applied'),
        findsOneWidget);
    expect(find.text('Current phone  08030000000'), findsOneWidget);
    final put = calls.lastWhere((request) => request.method == 'PUT');
    expect(jsonDecode(put.body), {
      'phone': '08035550123',
      'currentPassword': 'admin-password',
      'reason': 'Customer requested correction',
      'expectedProposalId': null,
    });
    expect(find.byKey(const Key('admin-profile-withdraw-contact')),
        findsOneWidget);
    final withdraw = find.byKey(const Key('admin-profile-withdraw-contact'));
    await tester.ensureVisible(withdraw);
    await tester.pumpAndSettle();
    await tester.tap(withdraw);
    await tester.pumpAndSettle();
    expect(calls.any((request) => request.method == 'DELETE'), isTrue);
    expect(find.text('No pending correction.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    api.dispose();
  });

  testWidgets('proposal CAS preflight refuses another admin update',
      (tester) async {
    final calls = <http.Request>[];
    var remoteId = 'proposal-31';
    final client = MockClient((request) async {
      calls.add(request);
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'proposal': {
                'id': remoteId,
                'status': 'PENDING_VERIFICATION',
                'proposedPhone': '08035550123',
                'proposedEmail': null,
                'requestedAt': '2026-05-01T10:00:00Z',
                'requestedByName': 'Another operator',
                'reason': 'Initial correction',
              }
            }
          }),
          200,
        );
      }
      return http.Response('{"success":true,"data":{"proposal":null}}', 200);
    });
    final api = AdminCustomerProfileApi(
        client: client, baseUrl: 'https://admin.test/api');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminCustomerProfileEditor(
          customer: const {
            'id': 'cust-31',
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
    final phoneField =
        find.widgetWithText(TextField, 'Proposed phone (optional)');
    await tester.ensureVisible(phoneField);
    await tester.enterText(phoneField, '08036660123');
    final passwordField = find.widgetWithText(TextField, 'Admin password');
    await tester.ensureVisible(passwordField);
    await tester.enterText(passwordField, 'admin-password');
    final reasonField = find.widgetWithText(
        TextField, 'Proposal reason (required, at least 5 characters)');
    await tester.ensureVisible(reasonField);
    await tester.enterText(reasonField, 'Customer requested correction');

    remoteId = 'proposal-32';
    final submit = find.byKey(const Key('admin-profile-propose-contact'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('changed since it was displayed'),
      findsOneWidget,
    );
    expect(calls.where((request) => request.method == 'PUT'), isEmpty);
    expect(find.textContaining('Another operator'), findsOneWidget);

    remoteId = 'proposal-33';
    final withdraw = find.byKey(const Key('admin-profile-withdraw-contact'));
    await tester.ensureVisible(withdraw);
    await tester.pumpAndSettle();
    await tester.tap(withdraw);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('changed since it was displayed'),
      findsOneWidget,
    );
    expect(calls.where((request) => request.method == 'DELETE'), isEmpty);
    expect(tester.takeException(), isNull);
    api.dispose();
  });
}
