import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:servicepay_app/admin/pending_resolution_api.dart';
import 'package:servicepay_app/admin/main_navigation.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('transaction filters are authenticated and page size is capped',
      () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'staff-session'});
    http.Request? request;
    final PendingResolutionApi api = PendingResolutionApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((http.Request value) async {
        request = value;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'items': <dynamic>[],
              'page': 2,
              'limit': 50,
              'total': 0,
              'pages': 1,
              'generatedAt': '2026-04-21T10:00:00Z',
            },
          }),
          200,
        );
      }),
    );

    final Map<String, dynamic> response = await api.transactions(
      page: 2,
      limit: 100,
      search: 'customer@example.ng',
      type: 'DATA',
      from: '2026-04-01',
      to: '2026-04-21',
      minAmount: '150',
      maxAmount: '2500',
      duration: 'DELAYED',
      status: 'PENDING',
    );

    expect(response['success'], isTrue);
    expect(request!.url.path, '/api/admin/pending-resolution/transactions');
    expect(request!.url.queryParameters, <String, String>{
      'page': '2',
      'limit': '50',
      'search': 'customer@example.ng',
      'type': 'DATA',
      'from': '2026-04-01',
      'to': '2026-04-21',
      'minAmount': '150',
      'maxAmount': '2500',
      'duration': 'DELAYED',
      'status': 'PENDING',
    });
    expect(request!.headers['authorization'], 'Bearer staff-session');
  });

  test('retry replays the exact durable body and key after timeout and 202',
      () async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'staff-session',
      'user_id': 'staff-42',
    });
    final List<http.Request> requests = <http.Request>[];
    int attempt = 0;
    final PendingResolutionApi api = PendingResolutionApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((http.Request request) async {
        requests.add(request);
        attempt++;
        if (attempt == 1) throw Exception('ambiguous timeout');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'state': 'PROCESSING',
              'message': 'Provider status check is processing.',
            },
          }),
          202,
        );
      }),
    );

    await expectLater(
      api.submitRetry('txn-98', reason: 'Check provider status after delay'),
      throwsA(isA<PendingResolutionApiException>()),
    );
    final PendingResolutionIntent? saved = await api.loadIntent('txn-98');
    expect(saved, isNotNull);
    expect(saved!.action, PendingResolutionAction.retry);

    final Map<String, dynamic> firstReplay = await api.submitRetry(
      'txn-98',
      reason: 'Check provider status after delay',
    );
    expect(firstReplay['data']['state'], 'PROCESSING');
    await api.submitRetry('txn-98',
        reason: 'Check provider status after delay');

    expect(requests, hasLength(3));
    expect(requests[0].url.path,
        '/api/admin/pending-resolution/transactions/txn-98/retry');
    expect(requests[0].headers['x-idempotency-key'],
        requests[1].headers['x-idempotency-key']);
    expect(requests[1].headers['x-idempotency-key'],
        requests[2].headers['x-idempotency-key']);
    expect(jsonDecode(requests[0].body), jsonDecode(requests[1].body));
    expect(jsonDecode(requests[1].body), jsonDecode(requests[2].body));
    expect(
        (await api.loadIntent('txn-98'))?.idempotencyKey, saved.idempotencyKey);
  });

  test('a saved action cannot be changed while outcome is ambiguous', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'staff-session'});
    final PendingResolutionApi api = PendingResolutionApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((http.Request request) async {
        throw Exception('connection lost');
      }),
    );
    await expectLater(
      api.submitAction(
        'txn-1',
        action: PendingResolutionAction.markSuccessful,
        reason: 'Provider evidence confirms delivery',
        evidenceReference: 'case-12345',
        deliveryConfirmed: true,
      ),
      throwsA(isA<PendingResolutionApiException>()),
    );
    await expectLater(
      api.submitAction(
        'txn-1',
        action: PendingResolutionAction.refund,
        reason: 'Refund after a failed payment',
        providerRiskAcknowledged: true,
      ),
      throwsA(
        predicate<PendingResolutionApiException>(
          (PendingResolutionApiException error) =>
              error.message.contains('unresolved'),
        ),
      ),
    );
  });

  test('gateway timeout retains the original retry key and reason', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'timeout-session'});
    final List<http.Request> requests = <http.Request>[];
    final api = PendingResolutionApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'success': false, 'message': 'Gateway timeout'}), 408);
      }),
    );
    for (int i = 0; i < 2; i++) {
      await expectLater(api.submitRetry('timeout-transaction',
          reason: 'Keep the original uncertain query request.'), throwsA(isA<PendingResolutionApiException>()));
    }
    expect(requests[0].body, requests[1].body);
    expect(requests[0].headers['X-Idempotency-Key'], requests[1].headers['X-Idempotency-Key']);
    expect(await api.loadIntent('timeout-transaction'), isNotNull);
  });

  test(
      'Pending Resolution navigation is limited to Head Office and Ops workspace',
      () {
    expect(
      canAccessPendingResolutionNavigation(
        role: 'HEAD_OFFICE',
        permissions: <String>{},
      ),
      isTrue,
    );
    expect(
      canAccessPendingResolutionNavigation(
        role: 'STAFF',
        permissions: <String>{AdminPermissions.operationsWorkspaceView},
      ),
      isTrue,
    );
    expect(
      canAccessPendingResolutionNavigation(
        role: 'CUSTOMER_SUPPORT',
        permissions: <String>{AdminPermissions.supportWorkspaceView},
      ),
      isFalse,
    );
  });
}
