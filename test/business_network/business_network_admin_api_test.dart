import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/business_network/business_network_admin_api.dart';

void main() {
  test('admin client uses build-base, admin prefix and bearer token', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(),
          'https://test.servicepay.invalid/api/business-network/admin/overview');
      expect(request.headers['authorization'], 'Bearer admin-token');
      return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'agents': {'registered': 3}
            }
          }),
          200);
    });
    final api = BusinessNetworkAdminApi(
      client: client,
      tokenProvider: () async => 'admin-token',
      baseUrl: 'https://test.servicepay.invalid/api',
    );
    final data = await api.get('overview') as Map;
    expect(((data['agents'] as Map)['registered']), 3);
    client.close();
  });

  test('admin client respects backend denial', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode(
              {'success': false, 'message': 'Forbidden', 'code': 'FORBIDDEN'}),
          403,
        ));
    final api = BusinessNetworkAdminApi(
      client: client,
      tokenProvider: () async => 'admin-token',
      baseUrl: 'https://test.servicepay.invalid/api',
    );
    await expectLater(
        api.get('overview'), throwsA(isA<BusinessNetworkAdminException>()));
    client.close();
  });

  test('merchant admin controls use the shared non-admin profile routes',
      () async {
    final client = MockClient((request) async {
      expect(request.url.path,
          '/api/business-network/profiles/profile-7/branches');
      expect(request.headers['authorization'], 'Bearer head-office-token');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {'items': []}
        }),
        200,
      );
    });
    final api = BusinessNetworkAdminApi(
      client: client,
      tokenProvider: () async => 'head-office-token',
      baseUrl: 'https://test.servicepay.invalid/api',
    );
    final data = await api.getProfileBranches('profile-7') as Map;
    expect(data['items'], isEmpty);
    client.close();
  });

  test('branch status and staff reinvitation use PATCH without activation',
      () async {
    var requestNumber = 0;
    final client = MockClient((request) async {
      requestNumber++;
      expect(request.method, 'PATCH');
      if (requestNumber == 1) {
        expect(
          request.url.path,
          '/api/business-network/profiles/profile-7/branches/branch-2',
        );
        expect(jsonDecode(request.body), {'status': 'SUSPENDED'});
      } else {
        expect(request.url.path, '/api/business-network/staff/staff-3');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['status'], 'INVITED');
        expect(body['branchId'], 'branch-2');
        expect(body['permissions'], ['reports.view']);
        expect(body.containsKey('ACTIVE'), isFalse);
      }
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {'updated': true}
        }),
        200,
      );
    });
    final api = BusinessNetworkAdminApi(
      client: client,
      tokenProvider: () async => 'head-office-token',
      baseUrl: 'https://test.servicepay.invalid/api',
    );
    await api.updateProfileBranch(
      'profile-7',
      'branch-2',
      {'status': 'SUSPENDED'},
    );
    await api.updateProfileStaff('staff-3', {
      'status': 'INVITED',
      'branchId': 'branch-2',
      'permissions': ['reports.view'],
    });
    expect(requestNumber, 2);
    client.close();
  });

  test('commission endpoint accepts profile-scoped page and bounded limit',
      () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/business-network/admin/commissions');
      expect(request.url.queryParameters, {
        'profileId': 'profile-7',
        'page': '2',
        'limit': '50',
      });
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'items': [],
            'total': 101,
            'page': 2,
            'limit': 50,
            'totals': {'earnedKobo': 99000},
          },
        }),
        200,
      );
    });
    final api = BusinessNetworkAdminApi(
      client: client,
      tokenProvider: () async => 'admin-token',
      baseUrl: 'https://test.servicepay.invalid/api',
    );
    final result = await api.get('commissions', query: {
      'profileId': 'profile-7',
      'page': '2',
      'limit': '50',
    }) as Map;
    expect(result['total'], 101);
    expect((result['totals'] as Map)['earnedKobo'], 99000);
    client.close();
  });
}
