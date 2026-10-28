import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_customer_360_api.dart';
import 'package:servicepay_app/admin/admin_customer_360_screen.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/customer_profile_admin.dart';
import 'package:servicepay_app/admin/customer_virtual_account_admin.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _customerId = 'customer-va-1';

Map<String, dynamic> _snapshot({
  bool canGenerate = false,
  bool canRetry = false,
  Map<String, dynamic>? virtualAccount,
  List<Map<String, dynamic>>? history,
  String? cursor,
}) =>
    {
      'customer': {
        'fullName': 'Ada Okafor',
        'phone': '08030000000',
        'email': 'ada@example.test',
      },
      'virtualAccount': virtualAccount,
      'eligibility': {
        'canGenerate': canGenerate,
        'canRetry': canRetry,
        'requiresReconciliation': false,
        'reason': canGenerate
            ? 'Eligible after customer request was verified.'
            : 'No provider request is currently eligible.',
      },
      'history': history ?? <Map<String, dynamic>>[],
      'nextCursor': cursor,
      'lookupSupported': false,
    };

class _FakeVirtualAccountApi extends AdminCustomerVirtualAccountApi {
  _FakeVirtualAccountApi(this.snapshot)
      : super(client: MockClient((_) async => http.Response('{}', 200)));

  Map<String, dynamic> snapshot;
  final List<String?> cursors = [];
  final List<Map<String, String>> posts = [];
  Future<void> Function()? onGenerate;
  Object? generationError;
  Map<String, dynamic>? generationResult;

  @override
  Future<Map<String, dynamic>> load({
    required String customerId,
    String? before,
  }) async {
    cursors.add(before);
    return snapshot;
  }

  @override
  Future<Map<String, dynamic>> generate({
    required String customerId,
    required String reason,
    required String requestId,
  }) async {
    posts.add({'reason': reason, 'requestId': requestId});
    if (onGenerate != null) await onGenerate!();
    if (generationError != null) throw generationError!;
    if (generationResult != null) {
      snapshot = generationResult!;
      return snapshot;
    }
    snapshot = _snapshot(
      virtualAccount: {
        'provider': 'Managed Bank',
        'accountNumber': '0123456789',
        'accountName': 'Ada Okafor',
        'bankName': 'Unity Bank',
        'bankCode': '090123',
        'status': 'ACTIVE',
        'createdAt': '2026-04-10T11:00:00Z',
        'updatedAt': '2026-04-10T11:00:00Z',
      },
      history: [
        {
          'id': 'evt-1',
          'action': 'VIRTUAL_ACCOUNT_GENERATED',
          'actorName': 'Mariam Bello',
          'reason': reason,
          'createdAt': '2026-04-10T11:00:00Z',
          'outcome': 'SUCCEEDED',
          'requestId': requestId,
        }
      ],
    );
    return snapshot;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'session-token'});
  });

  Future<void> pumpAccount(
    WidgetTester tester,
    _FakeVirtualAccountApi api, {
    double width = 900,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: AdminCustomerVirtualAccountAdmin(
        customerId: _customerId,
        api: api,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('backend eligibility controls actions; legacy failed is not enough',
      (tester) async {
    final api = _FakeVirtualAccountApi(_snapshot());
    await pumpAccount(tester, api);
    final action = tester.widget<FilledButton>(
      find.byKey(const Key('virtual-account-request')),
    );
    expect(action.onPressed, isNull);
    expect(find.textContaining('No account number is recorded.'), findsOneWidget);
    expect(find.text('No provider request is currently eligible.'), findsOneWidget);
    expect(api.posts, isEmpty);
  });

  testWidgets('generation requires explicit reason and confirmation then posts once',
      (tester) async {
    final api = _FakeVirtualAccountApi(_snapshot(canGenerate: true));
    await pumpAccount(tester, api);
    await tester.tap(find.byKey(const Key('virtual-account-request')));
    await tester.pumpAndSettle();
    expect(find.text('Generate virtual account?'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const Key('virtual-account-confirm')),
    );
    expect(confirm.onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('virtual-account-reason')),
      'Customer requested a dedicated account',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('virtual-account-confirm')));
    await tester.pumpAndSettle();
    expect(api.posts, hasLength(1));
    expect(api.posts.single['reason'], 'Customer requested a dedicated account');
    expect(
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(api.posts.single['requestId']!),
      isTrue,
    );
    expect(find.text('0123456789'), findsOneWidget);
    expect(find.text('Ada Okafor'), findsWidgets);
    await tester.drag(find.byKey(const Key('virtual-account-scroll')),
        const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('Generation history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server errors preserve intent and never automatically repeat POST',
      (tester) async {
    final api = _FakeVirtualAccountApi(_snapshot(canGenerate: true))
      ..generationError = Exception('Provider is temporarily unavailable.');
    await pumpAccount(tester, api);
    await tester.tap(find.byKey(const Key('virtual-account-request')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('virtual-account-reason')),
      'Customer requested new account',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('virtual-account-confirm')));
    await tester.pumpAndSettle();
    expect(api.posts, hasLength(1));
    expect(find.byKey(const Key('virtual-account-uncertain')), findsOneWidget);
    expect(find.textContaining('Provider is temporarily unavailable.'),
        findsOneWidget);
    expect(find.byKey(const Key('virtual-account-request')), findsNothing);
    await tester.tap(find.byKey(const Key('virtual-account-review-refresh')));
    await tester.pumpAndSettle();
    expect(api.posts, hasLength(1));
    expect(api.cursors, [null, null, null]);
  });

  testWidgets('HTTP success with pending account state is not called created',
      (tester) async {
    final api = _FakeVirtualAccountApi(_snapshot(canGenerate: true))
      ..generationResult = _snapshot(
        virtualAccount: {
          'provider': 'Managed Bank',
          'accountNumber': '',
          'accountName': '',
          'bankName': '',
          'bankCode': '',
          'status': 'PENDING',
          'failureReason': '',
        },
        history: [
          {
            'id': 'evt-pending',
            'action': 'VIRTUAL_ACCOUNT_GENERATION_REQUESTED',
            'actorName': 'Mariam Bello',
            'reason': 'Customer request confirmed',
            'createdAt': '2026-04-10T11:00:00Z',
            'outcome': 'REQUEST_RECORDED',
            'requestId': 'pending-request-id',
          }
        ],
      );
    await pumpAccount(tester, api);
    await tester.tap(find.byKey(const Key('virtual-account-request')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('virtual-account-reason')),
      'Customer request confirmed',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('virtual-account-confirm')));
    await tester.pumpAndSettle();
    expect(api.posts, hasLength(1));
    expect(find.byKey(const Key('virtual-account-uncertain')), findsOneWidget);
    expect(find.textContaining('active account is not confirmed'), findsOneWidget);
    expect(find.text('PENDING'), findsOneWidget);
    expect(find.byKey(const Key('virtual-account-request')), findsNothing);
    expect(find.text('0123456789'), findsNothing);
  });

  testWidgets('retry is available only by canRetry and remains single-flight',
      (tester) async {
    final completer = Completer<void>();
    final api = _FakeVirtualAccountApi(
      _snapshot(
        canRetry: true,
        virtualAccount: {
          'provider': 'Managed Bank',
          'accountNumber': '',
          'accountName': '',
          'bankName': '',
          'bankCode': '',
          'status': 'FAILED',
          'failureReason': 'Provider did not confirm account creation.',
        },
      ),
    )..onGenerate = () => completer.future;
    await pumpAccount(tester, api);
    expect(find.text('Retry Failed Generation'), findsOneWidget);
    await tester.tap(find.byKey(const Key('virtual-account-request')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('virtual-account-reason')),
      'Retry after configuration was verified',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('virtual-account-confirm')));
    await tester.pump();
    expect(api.posts, hasLength(1));
    final action = tester.widget<FilledButton>(
      find.byKey(const Key('virtual-account-request')),
    );
    expect(action.onPressed, isNull);
    completer.complete();
    await tester.pumpAndSettle();
    expect(api.posts, hasLength(1));
    expect(find.text('0123456789'), findsOneWidget);
  });

  testWidgets('history pagination and copy controls use canonical details',
      (tester) async {
    final api = _FakeVirtualAccountApi(
      _snapshot(
        virtualAccount: {
          'provider': 'Managed Bank',
          'accountNumber': '0123456789',
          'accountName': 'Ada Okafor',
          'bankName': 'Unity Bank',
          'bankCode': '090123',
          'status': 'ACTIVE',
          'createdAt': '2026-04-10T11:00:00Z',
          'updatedAt': '2026-04-10T11:00:00Z',
        },
        history: [
          {
            'id': 'evt-first',
            'action': 'VIRTUAL_ACCOUNT_GENERATED',
            'actorName': 'Mariam Bello',
            'reason': 'Customer request verified',
            'createdAt': '2026-04-10T11:00:00Z',
            'outcome': 'SUCCEEDED',
          }
        ],
        cursor: 'cursor-page-2',
      ),
    );
    await pumpAccount(tester, api, width: 390);
    await tester.drag(find.byKey(const Key('virtual-account-scroll')),
        const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(find.text('Ada Okafor'), findsWidgets);
    expect(find.text('Unity Bank'), findsOneWidget);
    expect(find.textContaining('Provider lookup is not supported.'), findsOneWidget);
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text']?.toString();
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.byKey(const Key('copy-account-number')));
    await tester.pumpAndSettle();
    expect(copiedText, '0123456789');
    await tester.ensureVisible(find.byKey(const Key('virtual-account-load-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('virtual-account-load-more')));
    await tester.pumpAndSettle();
    expect(api.cursors, [null, 'cursor-page-2']);
    expect(find.byKey(const Key('virtual-account-history-evt-first')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Customer360 keeps profile controls and exposes virtual account to Head Office',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'session-token'});
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/customer360/search')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'items': [
                {
                  'id': _customerId,
                  'fullName': 'Ada Okafor',
                  'phone': '08030000000',
                  'email': 'ada@example.test',
                  'status': 'ACTIVE',
                }
              ]
            }
          }),
          200,
        );
      }
      if (path.endsWith('/customer360/$_customerId')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'profile': {
                'id': _customerId,
                'fullName': 'Ada Okafor',
                'phone': '08030000000',
                'email': 'ada@example.test',
                'role': 'CUSTOMER',
                'status': 'ACTIVE',
              },
              'capabilities': {},
              'usage': [],
            }
          }),
          200,
        );
      }
      if (path.endsWith('/timeline') || path.endsWith('/transactions')) {
        return http.Response(
          '{"success":true,"data":{"items":[],"pagination":{"page":1,"totalPages":1}}}',
          200,
        );
      }
      if (path.endsWith('/profile/contact-proposal')) {
        return http.Response('{"success":true,"data":{"proposal":null}}', 200);
      }
      return http.Response('{"success":true,"data":{"history":[]}}', 200);
    });
    final c360 = AdminCustomer360Api(client: client);
    final profile = AdminCustomerProfileApi(
      client: client,
      baseUrl: 'https://unit.test/api',
    );
    final virtual = _FakeVirtualAccountApi(_snapshot());
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: AdminCustomer360Screen(
        api: c360,
        profileApi: profile,
        virtualAccountApi: virtual,
        access: const AdminAccess(role: 'HEAD_OFFICE', permissions: {}),
      ),
    ));
    await tester.enterText(find.byType(TextField).first, 'Ada');
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    final customerTile = find.widgetWithText(ListTile, 'Ada Okafor');
    await tester.ensureVisible(customerTile);
    await tester.tap(customerTile);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer360-edit-profile')), findsOneWidget);
    expect(find.byKey(const Key('customer360-profile-history')), findsOneWidget);
    final accountAction = find.byKey(const Key('customer360-virtual-account'));
    await tester.drag(find.byType(ListView).first, const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.tap(accountAction);
    await tester.pumpAndSettle();
    expect(find.text('Customer virtual account'), findsOneWidget);
    expect(find.text('Ada Okafor'), findsWidgets);
    Navigator.of(tester.element(find.text('Customer virtual account'))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    profile.dispose();
    c360.close();
  });
}
