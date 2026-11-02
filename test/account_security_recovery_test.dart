import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/account_security_recovery.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';

class _RecoveryApi extends AccountSecurityRecoveryApi {
  _RecoveryApi({
    required this.permissions,
    this.loadCompleter,
  });

  final List<String> permissions;
  final Completer<Map<String, dynamic>>? loadCompleter;
  int challengeCalls = 0;
  int verifyCalls = 0;
  Map<String, dynamic>? challengePayload;
  Map<String, dynamic>? verifyPayload;

  Map<String, dynamic> get snapshot => {
        'customer': {
          'id': 'cust-1',
          'fullName': 'Ada Okafor',
          'email': 'ada@example.test',
          'phone': '08000000000',
          'status': 'ACTIVE',
          'emailVerified': true,
        },
        'diagnostics': {
          'lastSuccessfulLogin': '2025-02-01T10:20:00Z',
          'failedLoginAttempts': 2,
          'ordinaryLockSupported': false,
          'restrictionsPreserved': true,
        },
        'permissions': permissions,
        'channelAvailable': true,
        'recovery': {'status': 'NONE'},
        'history': [],
      };

  @override
  Future<Map<String, dynamic>> load(String customerId) =>
      loadCompleter?.future ?? Future.value(snapshot);

  @override
  Future<Map<String, dynamic>> challenge(
    String customerId, {
    required String action,
    required String reason,
    required String currentPassword,
  }) async {
    challengeCalls++;
    challengePayload = {
      'action': action,
      'reason': reason,
      'currentPassword': currentPassword,
    };
    return {
      'challengeId': 'challenge-1',
      'expiresAt': '2025-02-01T11:00:00Z',
      'message': 'A code was sent to the customer.',
    };
  }

  @override
  Future<Map<String, dynamic>> verify(
    String customerId, {
    required String challengeId,
    required String otp,
    required String currentPassword,
  }) async {
    verifyCalls++;
    verifyPayload = {
      'challengeId': challengeId,
      'otp': otp,
      'currentPassword': currentPassword,
    };
    return {'message': 'Customer recovery was verified.'};
  }
}

Widget _app({
  required AccountSecurityRecoveryApi api,
  Set<String> localPermissions = const {},
}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AccountSecurityRecovery(
            customerId: 'cust-1',
            api: api,
            access: AdminAccess(
              role: 'HEAD_OFFICE',
              permissions: localPermissions,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows loading state while security data is pending',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final api = _RecoveryApi(
      permissions: const ['VIEW_ACCOUNT_RECOVERY'],
      loadCompleter: pending,
    );
    await tester.pumpWidget(_app(
      api: api,
      localPermissions: const {'VIEW_ACCOUNT_RECOVERY'},
    ));
    expect(find.text('Loading security details'), findsOneWidget);
    pending.complete(api.snapshot);
    await tester.pumpAndSettle();
    expect(find.text('Ada Okafor'), findsOneWidget);
  });

  testWidgets(
      'denies action without exact assigned permission and has no new-password field',
      (tester) async {
    final api = _RecoveryApi(
      permissions: const ['VIEW_ACCOUNT_RECOVERY'],
    );
    await tester.pumpWidget(_app(
      api: api,
      // Wildcard is deliberately not a recovery grant.
      localPermissions: const {'*', 'VIEW_ACCOUNT_RECOVERY'},
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery-permission-denied')), findsOneWidget);
    expect(find.byKey(const Key('recovery-send-challenge')).hitTestable(),
        findsNothing);
    expect(find.byKey(const Key('recovery-admin-current-password')),
        findsOneWidget);
    expect(find.byKey(const Key('new-password')), findsNothing);
    expect(api.challengeCalls, 0);
  });

  testWidgets('starts challenge and verifies customer email code',
      (tester) async {
    final api = _RecoveryApi(
      permissions: const [
        'VIEW_ACCOUNT_RECOVERY',
        'INITIATE_PASSWORD_RESET',
      ],
    );
    await tester.pumpWidget(_app(
      api: api,
      localPermissions: const {
        'VIEW_ACCOUNT_RECOVERY',
        'INITIATE_PASSWORD_RESET',
      },
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recovery-reason')),
        'Customer requested access recovery');
    await tester.pump();
    await tester
        .ensureVisible(find.byKey(const Key('recovery-send-challenge')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
              find.byKey(const Key('recovery-send-challenge')))
          .onPressed,
      isNull,
    );
    expect(api.challengeCalls, 0);
    await tester.enterText(
      find.byKey(const Key('recovery-admin-current-password')),
      'admin-current-9x',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('recovery-send-challenge')));
    await tester.pumpAndSettle();
    expect(api.challengeCalls, 1);
    expect(api.challengePayload?['action'], 'PASSWORD_RESET');
    expect(api.challengePayload?['currentPassword'], 'admin-current-9x');
    expect(find.byKey(const Key('recovery-customer-otp')), findsOneWidget);
    expect(find.textContaining('sent to the customer'), findsOneWidget);
    expect(find.byKey(const Key('new-password')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('recovery-customer-otp')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('recovery-customer-otp')), '246810');
    await tester.pump();
    await tester
        .ensureVisible(find.byKey(const Key('recovery-verify-challenge')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
              find.byKey(const Key('recovery-verify-challenge')))
          .onPressed,
      isNull,
    );
    await tester
        .ensureVisible(find.byKey(const Key('recovery-admin-verify-password')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('recovery-admin-verify-password')),
      'fresh-admin-verify-6m',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('recovery-verify-challenge')));
    await tester.pumpAndSettle();
    expect(api.verifyCalls, 1);
    expect(api.verifyPayload?['otp'], '246810');
    expect(api.verifyPayload?['currentPassword'], 'fresh-admin-verify-6m');
    expect(find.byKey(const Key('recovery-customer-otp')), findsNothing);
  });
}
