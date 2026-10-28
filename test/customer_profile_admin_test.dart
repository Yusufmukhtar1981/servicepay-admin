import 'dart:convert';

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
}
