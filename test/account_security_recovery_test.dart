import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/account_security_recovery.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';

class _RecoveryApi extends AccountSecurityRecoveryApi {
  _RecoveryApi({
    required this.permissions,
    this.loadCompleter,
    this.remainingLoadFailures = 0,
    this.emailVerified = true,
    this.emailAvailable = true,
    this.phoneVerified = false,
    this.smsAvailable = false,
    this.phonePinRecoveryAvailable = false,
    this.recoveryStatus = 'NONE',
    this.retryAfter,
  });

  final List<String> permissions;
  final Completer<Map<String, dynamic>>? loadCompleter;
  int remainingLoadFailures;
  int loadCalls = 0;
  int challengeCalls = 0;
  int verifyCalls = 0;
  int contactReviewCalls = 0;
  final bool emailVerified;
  final bool emailAvailable;
  final bool phoneVerified;
  final bool smsAvailable;
  final bool phonePinRecoveryAvailable;
  final String recoveryStatus;
  final String? retryAfter;
  Map<String, dynamic>? challengePayload;
  Map<String, dynamic>? verifyPayload;

  Map<String, dynamic> get snapshot => {
        'customer': {
          'id': 'cust-1',
          'fullName': 'Ada Okafor',
          'email': 'ada@example.test',
          'phone': '08000000000',
          'status': 'ACTIVE',
          'emailVerified': emailVerified,
          'phoneMasked': '080****0000',
          'phoneVerified': phoneVerified,
        },
        'diagnostics': {
          'lastSuccessfulLogin': '2025-02-01T10:20:00Z',
          'failedLoginAttempts': 2,
          'ordinaryLockSupported': false,
          'restrictionsPreserved': true,
        },
        'permissions': permissions,
        'channelAvailable': emailAvailable,
        'recoveryMethods': {
          'email': {'verified': emailVerified, 'available': emailAvailable},
          'phone': {
            'verified': phoneVerified,
            'available': smsAvailable,
            if (phonePinRecoveryAvailable) 'pinRecoveryAvailable': true,
          },
        },
        'recovery': {
          'status': recoveryStatus,
          if (retryAfter != null) 'retryAfter': retryAfter,
        },
        'history': [],
      };

  @override
  Future<Map<String, dynamic>> load(String customerId) {
    loadCalls++;
    if (remainingLoadFailures > 0) {
      remainingLoadFailures--;
      return Future.error(Exception('Disposable simulated request failure'));
    }
    return loadCompleter?.future ?? Future.value(snapshot);
  }

  @override
  Future<Map<String, dynamic>> challenge(
    String customerId, {
    required String action,
    required String reason,
    required String currentPassword,
    String channel = 'EMAIL',
  }) async {
    challengeCalls++;
    challengePayload = {
      'action': action,
      'reason': reason,
      'currentPassword': currentPassword,
      'channel': channel,
    };
    return {
      'challengeId': 'challenge-1',
      'expiresAt': '2025-02-01T11:00:00Z',
      'message': 'A code was sent to the customer.',
      if (channel == 'PHONE')
        'customerEntryUrl':
            'https://api.servicepay.ng/api/account-recovery/page#challenge=550e8400-e29b-41d4-a716-446655440000&action=PHONE_OTP',
    };
  }

  @override
  Future<Map<String, dynamic>> requestContactVerification(
    String customerId, {
    required String reason,
    required String currentPassword,
  }) async {
    contactReviewCalls++;
    return {
      'requestId': 'review-1',
      'status': 'IDENTITY_VERIFICATION_REQUIRED',
      'message': 'Identity review has been requested.',
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
  test('real HTTP client accepts the production flat recovery contracts',
      () async {
    SharedPreferences.setMockInitialValues(
        {'auth_token': 'disposable-test-token'});
    final calls = <String>[];
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer disposable-test-token');
      calls.add(request.url.path);
      final payload = request.url.path.endsWith('/challenge')
          ? {
              'success': true,
              'challengeId': 'test-challenge',
              'expiresAt': 123,
              if (request.body.contains('"channel":"PHONE"'))
                'customerEntryUrl':
                    'https://api.servicepay.ng/api/account-recovery/page#challenge=550e8400-e29b-41d4-a716-446655440000&action=PHONE_OTP',
            }
          : request.url.path.endsWith('/contact-verification')
              ? {
                  'success': true,
                  'requestId': 'review-1',
                  'status': 'IDENTITY_VERIFICATION_REQUIRED',
                  'message': 'Identity verification required.'
                }
              : request.url.path.endsWith('/verify')
                  ? jsonDecode(request.body)['otp'] == '654321'
                      ? {
                          'success': true,
                          'action': 'PHONE_VERIFICATION',
                          'verified': true,
                          'requiresLogin': true,
                        }
                      : {
                          'success': true,
                          'action': 'PIN_RECOVERY',
                          'token': List<String>.filled(64, 'a').join(),
                        }
                  : {
                      'success': true,
                      'customer': {'id': 'cust-1'},
                      'channelAvailable': false,
                      'permissions': ['VIEW_ACCOUNT_RECOVERY'],
                      'diagnostics': {'ordinaryLockSupported': false}
                    };
      return http.Response(jsonEncode(payload), 200);
    });
    final api = AccountSecurityRecoveryApi(
        client: client, baseUrl: 'https://example.invalid/api');
    final snapshot = await api.load('cust-1');
    expect(snapshot['channelAvailable'], false);
    expect((snapshot['customer'] as Map)['id'], 'cust-1');
    final challenge = await api.challenge('cust-1',
        action: 'PASSWORD_RESET',
        reason: 'Disposable HTTP contract verification',
        currentPassword: 'test-only');
    expect(challenge['challengeId'], 'test-challenge');
    final phoneChallenge = await api.challenge('cust-1',
        action: 'PASSWORD_RESET',
        reason: 'Disposable phone recovery contract',
        currentPassword: 'test-only',
        channel: 'PHONE');
    expect(phoneChallenge['challengeId'], 'test-challenge');
    expect(phoneChallenge['customerEntryUrl'],
        startsWith('https://api.servicepay.ng/api/account-recovery/page#'));
    final review = await api.requestContactVerification('cust-1',
        reason: 'Disposable identity review contract',
        currentPassword: 'test-only');
    expect(review['status'], 'IDENTITY_VERIFICATION_REQUIRED');
    final verified = await api.verify('cust-1',
        challengeId: 'test-challenge',
        otp: '123456',
        currentPassword: 'test-only');
    expect(verified['action'], 'PIN_RECOVERY');
    expect(verified['token'], hasLength(64));
    final phoneVerified = await api.verify('cust-1',
        challengeId: 'test-challenge',
        otp: '654321',
        currentPassword: 'test-only');
    expect(phoneVerified['action'], 'PHONE_VERIFICATION');
    expect(phoneVerified['verified'], true);
    expect(phoneVerified['requiresLogin'], true);
    expect(calls, [
      '/api/admin/account-recovery/cust-1',
      '/api/admin/account-recovery/cust-1/challenge',
      '/api/admin/account-recovery/cust-1/challenge',
      '/api/admin/account-recovery/cust-1/contact-verification',
      '/api/admin/account-recovery/cust-1/verify',
      '/api/admin/account-recovery/cust-1/verify'
    ]);
    client.close();
  });

  test('real HTTP client rejects unsuccessful recovery responses', () async {
    SharedPreferences.setMockInitialValues(
        {'auth_token': 'disposable-test-token'});
    final client = MockClient((request) async => http.Response(
        jsonEncode({'success': false, 'message': 'Not permitted.'}), 403));
    final api = AccountSecurityRecoveryApi(
        client: client, baseUrl: 'https://example.invalid/api');
    await expectLater(api.load('cust-1'), throwsException);
    client.close();
  });

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
      'Retry loading reloads once, shows progress and restores diagnostics',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final api = _RecoveryApi(
      permissions: const ['VIEW_ACCOUNT_RECOVERY'],
      remainingLoadFailures: 1,
      loadCompleter: pending,
    );
    await tester.pumpWidget(_app(
      api: api,
      localPermissions: const {'VIEW_ACCOUNT_RECOVERY'},
    ));
    await tester.pumpAndSettle();
    expect(api.loadCalls, 1);
    expect(find.text('Unable to load account security details. Please retry.'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('recovery-retry')));
    await tester.pump();
    expect(api.loadCalls, 2);
    expect(find.text('Loading security details'), findsOneWidget);
    expect(find.text('Unable to load account security details. Please retry.'),
        findsNothing);
    pending.complete(api.snapshot);
    await tester.pumpAndSettle();
    expect(find.text('Ada Okafor'), findsOneWidget);
    expect(find.byKey(const Key('recovery-retry')), findsNothing);
    expect(api.challengeCalls, 0);
    expect(api.verifyCalls, 0);
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

  testWidgets(
      'phone OTP initiation is customer-private and has no Admin OTP entry',
      (tester) async {
    final api = _RecoveryApi(
      permissions: const ['VIEW_ACCOUNT_RECOVERY', 'INITIATE_PASSWORD_RESET'],
      phoneVerified: true,
      smsAvailable: true,
    );
    await tester.pumpWidget(_app(
      api: api,
      localPermissions: const {
        'VIEW_ACCOUNT_RECOVERY',
        'INITIATE_PASSWORD_RESET',
      },
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('080****0000'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('recovery-channel')));
    await tester.tap(find.byKey(const Key('recovery-channel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phone OTP').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recovery-reason')),
        'Customer confirmed phone recovery request');
    await tester.enterText(
        find.byKey(const Key('recovery-admin-current-password')),
        'admin-fresh');
    await tester.pump();
    await tester
        .ensureVisible(find.byKey(const Key('recovery-send-phone-otp')));
    await tester.tap(find.byKey(const Key('recovery-send-phone-otp')));
    await tester.pumpAndSettle();
    expect(api.challengePayload?['channel'], 'PHONE');
    expect(api.challengePayload?['action'], 'PASSWORD_RESET');
    expect(find.byKey(const Key('recovery-customer-otp')), findsNothing);
    expect(find.byKey(const Key('recovery-verify-challenge')), findsNothing);
    expect(
        find.byKey(const Key('recovery-admin-verify-password')), findsNothing);
    expect(find.textContaining('verify privately'), findsOneWidget);
    expect(
        find.byKey(const Key('recovery-customer-entry-url')), findsOneWidget);
    expect(
      find.byKey(const Key('recovery-phone-url-safety')),
      findsOneWidget,
    );
  });

  testWidgets('phone verified does not imply SMS availability', (tester) async {
    final api = _RecoveryApi(
      permissions: const ['VIEW_ACCOUNT_RECOVERY', 'INITIATE_PASSWORD_RESET'],
      phoneVerified: true,
      smsAvailable: false,
      emailVerified: false,
      emailAvailable: false,
    );
    await tester.pumpWidget(_app(
      api: api,
      localPermissions: const {
        'VIEW_ACCOUNT_RECOVERY',
        'INITIATE_PASSWORD_RESET',
      },
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('SMS unavailable'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('recovery-channel')));
    await tester.tap(find.byKey(const Key('recovery-channel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phone OTP').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('recovery-send-phone-otp')),
          )
          .onPressed,
      isNull,
    );
    expect(api.challengeCalls, 0);
  });

  testWidgets(
      'phone PIN recovery is enabled only by explicit method flag and keeps OTP private',
      (tester) async {
    final api = _RecoveryApi(
      permissions: const ['VIEW_ACCOUNT_RECOVERY', 'INITIATE_PIN_RECOVERY'],
      phoneVerified: true,
      smsAvailable: true,
      phonePinRecoveryAvailable: true,
    );
    await tester.pumpWidget(_app(
      api: api,
      localPermissions: const {
        'VIEW_ACCOUNT_RECOVERY',
        'INITIATE_PIN_RECOVERY',
      },
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('recovery-action')));
    await tester.tap(find.byKey(const Key('recovery-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PIN recovery').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('recovery-channel')));
    await tester.tap(find.byKey(const Key('recovery-channel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phone OTP').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recovery-reason')),
        'Customer requested phone-based PIN recovery');
    await tester.enterText(
        find.byKey(const Key('recovery-admin-current-password')), 'admin-pass');
    await tester.pump();
    await tester
        .ensureVisible(find.byKey(const Key('recovery-send-phone-otp')));
    await tester.tap(find.byKey(const Key('recovery-send-phone-otp')));
    await tester.pumpAndSettle();

    expect(api.challengePayload?['action'], 'PIN_RECOVERY');
    expect(api.challengePayload?['channel'], 'PHONE');
    expect(find.byKey(const Key('recovery-customer-otp')), findsNothing);
    expect(
        find.byKey(const Key('recovery-customer-entry-url')), findsOneWidget);
  });

  testWidgets('phone PIN recovery remains unavailable without explicit flag',
      (tester) async {
    final api = _RecoveryApi(
      permissions: const ['VIEW_ACCOUNT_RECOVERY', 'INITIATE_PIN_RECOVERY'],
      phoneVerified: true,
      smsAvailable: true,
    );
    await tester.pumpWidget(_app(
      api: api,
      localPermissions: const {
        'VIEW_ACCOUNT_RECOVERY',
        'INITIATE_PIN_RECOVERY',
      },
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('recovery-action')));
    await tester.tap(find.byKey(const Key('recovery-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PIN recovery').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recovery-channel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phone OTP').last);
    await tester.pumpAndSettle();
    expect(api.challengeCalls, 0);
    expect(find.text('Email recovery'), findsWidgets);
    expect(find.byKey(const Key('recovery-send-phone-otp')).hitTestable(),
        findsNothing);
  });

  testWidgets(
      'active provider lease explains retry time and blocks email and phone requests',
      (tester) async {
    final retryAfter = DateTime.now().add(const Duration(minutes: 7));
    final api = _RecoveryApi(
      permissions: const ['VIEW_ACCOUNT_RECOVERY', 'INITIATE_PASSWORD_RESET'],
      phoneVerified: true,
      smsAvailable: true,
      recoveryStatus: 'AWAITING_PROVIDER_EXPIRY',
      retryAfter: retryAfter.toUtc().toIso8601String(),
    );
    await tester.pumpWidget(_app(
      api: api,
      localPermissions: const {
        'VIEW_ACCOUNT_RECOVERY',
        'INITIATE_PASSWORD_RESET',
      },
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery-provider-lease-notice')),
        findsOneWidget);
    expect(find.textContaining('five-minute code has expired'), findsOneWidget);
    expect(find.textContaining('after '), findsOneWidget);

    await tester.enterText(find.byKey(const Key('recovery-reason')),
        'Customer requested account recovery');
    await tester.enterText(
        find.byKey(const Key('recovery-admin-current-password')), 'admin-pass');
    await tester.pump();
    final emailButton = tester
        .widget<FilledButton>(find.byKey(const Key('recovery-send-challenge')));
    expect(emailButton.onPressed, isNull);

    await tester.ensureVisible(find.byKey(const Key('recovery-channel')));
    await tester.tap(find.byKey(const Key('recovery-channel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phone OTP').last);
    await tester.pumpAndSettle();
    final phoneButton = tester
        .widget<FilledButton>(find.byKey(const Key('recovery-send-phone-otp')));
    expect(phoneButton.onPressed, isNull);
    expect(api.challengeCalls, 0);
  });

  testWidgets(
      'no verified contacts gives exact gate and audited identity handoff',
      (tester) async {
    final api = _RecoveryApi(
      permissions: const ['VIEW_ACCOUNT_RECOVERY', 'INITIATE_PASSWORD_RESET'],
      emailVerified: false,
      emailAvailable: false,
      phoneVerified: false,
      smsAvailable: true,
    );
    await tester.pumpWidget(_app(
      api: api,
      localPermissions: const {
        'VIEW_ACCOUNT_RECOVERY',
        'INITIATE_PASSWORD_RESET',
      },
    ));
    await tester.pumpAndSettle();
    expect(
      find.text(
          'Customer identity verification is required before account recovery.'),
      findsOneWidget,
    );
    await tester.enterText(
        find.byKey(const Key('recovery-admin-current-password')),
        'fresh-admin');
    await tester.enterText(find.byKey(const Key('recovery-reason')),
        'Customer contacts need independent review');
    await tester.pump();
    await tester.ensureVisible(
        find.byKey(const Key('recovery-request-identity-review')));
    await tester.tap(find.byKey(const Key('recovery-request-identity-review')));
    await tester.pumpAndSettle();
    expect(api.contactReviewCalls, 1);
    expect(api.challengeCalls, 0);
    expect(find.text('Identity review has been requested.'), findsOneWidget);
    expect(find.textContaining('does not verify a contact'), findsOneWidget);
  });
}
