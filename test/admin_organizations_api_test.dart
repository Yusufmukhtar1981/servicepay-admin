import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_organizations_api.dart';
import 'package:servicepay_app/admin/admin_organizations_screen.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses canonical organization paths and status bodies', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('{}', 200);
    });
    final api = AdminOrganizationsApi(
      client: client,
      baseUrl: 'https://example.test/api',
      authToken: '',
    );

    await api.summary();
    await api.list(status: 'PENDING_VERIFICATION', search: 'Acme');
    await api.wallet('org-1');
    await api.updateStatus('org-1', 'VERIFIED');
    await api.updateWalletFreeze('org-1', true);
    await api.withdrawalsSummary();
    await api.withdrawals(status: 'PENDING_APPROVAL', search: 'Acme');
    await api.withdrawalDetails('wd-1');
    await api.approveWithdrawal('wd-1', reason: 'Reviewed');
    await api.rejectWithdrawal('wd-2', reason: 'Insufficient documentation');
    await api.settlementAccounts(status: 'PENDING', organizationId: 'org-1');
    await api.approveSettlementAccount('acct-1');
    await api.rejectSettlementAccount('acct-2', reason: 'Account mismatch');
    await api.treasuryConfig('org-1');
    await api.updateTreasuryConfig('org-1', <String, dynamic>{
      'dailyLimit': '100000',
    });

    expect(
      requests[0].url.toString(),
      'https://example.test/api/admin/organizations/summary',
    );
    expect(requests[0].method, 'GET');
    expect(
      requests[1].url.toString(),
      'https://example.test/api/admin/organizations?status=PENDING_VERIFICATION&search=Acme',
    );
    expect(requests[1].method, 'GET');
    expect(requests[2].url.path, '/api/admin/organizations/org-1/wallet');
    expect(requests[3].url.path, '/api/admin/organizations/org-1/status');
    expect(jsonDecode(requests[3].body), <String, dynamic>{
      'status': 'VERIFIED',
    });
    expect(requests[4].url.path, '/api/admin/organizations/org-1/wallet');
    expect(jsonDecode(requests[4].body), <String, dynamic>{
      'status': 'FROZEN',
      'frozen': true,
    });
    expect(
      requests[5].url.path,
      '/api/admin/organizations/withdrawals/summary',
    );
    expect(requests[6].url.path, '/api/admin/organizations/withdrawals');
    expect(requests[6].url.queryParameters['status'], 'PENDING_APPROVAL');
    expect(requests[7].url.path, '/api/admin/organizations/withdrawals/wd-1');
    expect(
      requests[8].url.path,
      '/api/admin/organizations/withdrawals/wd-1/approve',
    );
    expect(requests[8].method, 'POST');
    expect(jsonDecode(requests[8].body), <String, dynamic>{
      'reason': 'Reviewed',
    });
    expect(
      requests[9].url.path,
      '/api/admin/organizations/withdrawals/wd-2/reject',
    );
    expect(jsonDecode(requests[9].body), <String, dynamic>{
      'reason': 'Insufficient documentation',
    });
    expect(
      requests[10].url.path,
      '/api/admin/organizations/settlement-accounts',
    );
    expect(
      requests[11].url.path,
      '/api/admin/organizations/settlement-accounts/acct-1/approve',
    );
    expect(
      requests[12].url.path,
      '/api/admin/organizations/settlement-accounts/acct-2/reject',
    );
    expect(requests[13].url.path, '/api/admin/organizations/treasury-config');
    expect(requests[13].url.queryParameters['organizationId'], 'org-1');
    expect(requests[14].url.path, '/api/admin/organizations/treasury-config');
    expect(requests[14].method, 'PATCH');
  });

  test('status action gates match organization review transitions', () {
    expect(
      organizationStatusPermission('VERIFIED'),
      AdminPermissions.organizationsReview,
    );
    expect(
      organizationStatusPermission('REJECTED'),
      AdminPermissions.organizationsReview,
    );
    expect(
      organizationStatusPermission('SUSPENDED'),
      AdminPermissions.organizationsStatusManage,
    );
    expect(
      organizationStatusPermission('VERIFIED', currentStatus: 'SUSPENDED'),
      AdminPermissions.organizationsStatusManage,
    );
  });

  test('organizations summary accepts the current pending response key', () {
    expect(
      organizationPendingCount(<String, dynamic>{
        'total': 11,
        'pending': 4,
        'pendingVerification': 2,
      }),
      4,
    );
    expect(
      organizationPendingCount(<String, dynamic>{'PENDING_VERIFICATION': 3}),
      3,
    );
  });

  test(
    'reject actions require an audit reason before making a request',
    () async {
      final client = MockClient((request) async => http.Response('{}', 200));
      final api = AdminOrganizationsApi(
        client: client,
        baseUrl: 'https://example.test/api',
        authToken: '',
      );

      expect(
        () => api.rejectWithdrawal('wd-1', reason: '  '),
        throwsA(isA<AdminOrganizationsApiException>()),
      );
      expect(
        () => api.rejectSettlementAccount('account-1', reason: ''),
        throwsA(isA<AdminOrganizationsApiException>()),
      );
    },
  );
}
