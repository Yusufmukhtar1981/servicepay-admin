import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_customer_withdrawals_api.dart';
import 'package:servicepay_app/admin/admin_customer_withdrawals_screen.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/main_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'Bearer customer-withdrawal-test-token',
    });
  });

  test('API sends manual completed-transfer attestation and expected details',
      () async {
    final List<http.Request> requests = <http.Request>[];
    final AdminCustomerWithdrawalsApi api = AdminCustomerWithdrawalsApi(
      baseUrl: 'https://example.test/api/',
      client: MockClient((http.Request request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'withdrawals': <dynamic>[],
          }),
          200,
        );
      }),
    );

    await api.list(status: 'pending');
    await api.list(status: 'ALL');
    await api.markPaid(
      'request/42',
      payoutReference: ' transfer-123 ',
      adminNote: ' paid from company bank ',
      manualPaymentConfirmed: true,
      expectedAmount: 5000,
      expectedAccountNumber: '0012345678',
    );
    await api.reject('request-43', reason: 'Invalid beneficiary details');

    expect(
      requests[0].url.toString(),
      'https://example.test/api/withdrawals/admin?status=PENDING',
    );
    expect(requests[0].headers['authorization'],
        'Bearer customer-withdrawal-test-token');
    expect(requests[1].url.path, '/api/withdrawals/admin');
    expect(
      requests[2].url.path,
      '/api/withdrawals/admin/request%2F42/approve',
    );
    expect(jsonDecode(requests[2].body), <String, dynamic>{
      'payoutReference': 'transfer-123',
      'adminNote': 'paid from company bank',
      'manualPaymentConfirmed': true,
      'expectedAmount': 5000,
      'expectedAccountNumber': '0012345678',
    });
    expect(requests[3].url.path, '/api/withdrawals/admin/request-43/reject');
    expect(jsonDecode(requests[3].body), <String, dynamic>{
      'adminNote': 'Invalid beneficiary details',
    });
    api.close();
  });

  test('API rejects unattested or malformed manual payment requests', () {
    final AdminCustomerWithdrawalsApi api = AdminCustomerWithdrawalsApi(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(
      () => api.markPaid(
        'request-1',
        payoutReference: 'bank-ref',
        adminNote: '',
        manualPaymentConfirmed: false,
        expectedAmount: 100,
        expectedAccountNumber: '0011223344',
      ),
      throwsArgumentError,
    );
    expect(
      () => api.markPaid(
        'request-1',
        payoutReference: ' ',
        adminNote: '',
        manualPaymentConfirmed: true,
        expectedAmount: 100,
        expectedAccountNumber: '0011223344',
      ),
      throwsArgumentError,
    );
    api.close();
  });

  test('server errors are surfaced rather than treated as paid', () async {
    final AdminCustomerWithdrawalsApi api = AdminCustomerWithdrawalsApi(
      client: MockClient((_) async => http.Response(
            jsonEncode(<String, dynamic>{
              'success': false,
              'message': 'Transfer status is uncertain; leave pending.',
            }),
            503,
          )),
    );
    await expectLater(
      api.markPaid(
        'request-1',
        payoutReference: 'ref',
        adminNote: '',
        manualPaymentConfirmed: true,
        expectedAmount: 100,
        expectedAccountNumber: '0011223344',
      ),
      throwsA(
        isA<Exception>().having(
          (Exception error) => error.toString(),
          'message',
          contains('Transfer status is uncertain; leave pending.'),
        ),
      ),
    );
    api.close();
  });

  test('customer withdrawal navigation is Head Office-only', () {
    expect(
      canAccessCustomerWithdrawalsNavigation(
        role: 'HEAD_OFFICE',
        permissions: <String>{},
      ),
      isTrue,
    );
    const List<String> forbiddenAliases = <String>[
      'ADMIN',
      'SUPER_ADMIN',
      'HEAD_OFFICE_ADMIN',
      'SERVICEPAY_SUPER_ADMIN',
    ];
    const List<Set<String>> elevatedPermissions = <Set<String>>[
      <String>{AdminPermissions.withdrawalsView},
      <String>{'*'},
      <String>{AdminPermissions.withdrawalsView, '*'},
    ];
    for (final String role in forbiddenAliases) {
      for (final Set<String> permissions in elevatedPermissions) {
        expect(
          canAccessCustomerWithdrawalsNavigation(
            role: role,
            permissions: permissions,
          ),
          isFalse,
          reason: '$role must not inherit customer withdrawal access',
        );
        expect(
          AdminMainNavigation.visibleDestinationLabels(
            AdminAccess(role: role, permissions: permissions),
          ),
          isNot(contains('Customer Withdrawals')),
        );
      }
    }
    expect(
      AdminMainNavigation.visibleDestinationLabels(
        const AdminAccess(role: 'HEAD_OFFICE', permissions: <String>{}),
      ),
      contains('Customer Withdrawals'),
    );
  });

  testWidgets(
      'queue filters, searches, and requires manual transfer attestation',
      (WidgetTester tester) async {
    final _FakeCustomerWithdrawalsApi api = _FakeCustomerWithdrawalsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminCustomerWithdrawalsScreen(
          api: api,
          initialAccess: const AdminAccess(
            role: 'HEAD_OFFICE',
            permissions: <String>{},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.requestedStatuses, <String>['PENDING']);
    expect(find.text('Ada Example • ₦5000.00'), findsOneWidget);
    expect(find.text('Mark paid'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'ada');
    await tester.pump();
    expect(find.text('Ada Example • ₦5000.00'), findsOneWidget);

    await tester.tap(find.text('Mark paid'));
    await tester.pumpAndSettle();
    expect(find.textContaining('transfer the funds manually'), findsOneWidget);
    expect(
        find.textContaining('Beneficiary account: 0012345678'), findsOneWidget);
    expect(find.textContaining('₦5000.00'), findsWidgets);

    final Finder confirm = find.text('Confirm transfer already completed');
    expect(
      tester
          .widget<FilledButton>(
            find
                .ancestor(
                  of: confirm,
                  matching: find.byType(FilledButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Payout / bank transfer reference'),
      'transfer-88',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find
                .ancestor(
                  of: confirm,
                  matching: find.byType(FilledButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find
                .ancestor(
                  of: confirm,
                  matching: find.byType(FilledButton),
                )
                .first,
          )
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(api.markPaidReference, 'transfer-88');
    expect(api.manualPaymentConfirmed, isTrue);
    expect(api.expectedAmount, 5000);
    expect(api.expectedAccountNumber, '0012345678');
    expect(find.text('APPROVED'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approved').last);
    await tester.pumpAndSettle();
    expect(api.requestedStatuses.last, 'APPROVED');
  });

  testWidgets('failed action and failed refresh leave request pending', (
    WidgetTester tester,
  ) async {
    final _FakeCustomerWithdrawalsApi api = _FakeCustomerWithdrawalsApi()
      ..failMarkPaid = true;
    await tester.pumpWidget(
      MaterialApp(
        home: AdminCustomerWithdrawalsScreen(
          api: api,
          initialAccess: const AdminAccess(
            role: 'HEAD_OFFICE',
            permissions: <String>{},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    api.failNextList = true;
    await tester.tap(find.byTooltip('Refresh queue'));
    await tester.pumpAndSettle();
    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('Queue refresh temporarily failed.'), findsOneWidget);
    await tester.tap(find.text('Retry refresh'));
    await tester.pumpAndSettle();
    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('Queue refresh temporarily failed.'), findsNothing);

    await tester.tap(find.text('Mark paid'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Payout / bank transfer reference'),
      'uncertain-transfer',
    );
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    final Finder confirm = find.text('Confirm transfer already completed');
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('Server did not confirm the manual-payment action.'),
        findsOneWidget);
    expect(find.text('Mark paid'), findsOneWidget);
  });

  testWidgets('rejection collects a reason through the existing refund flow', (
    WidgetTester tester,
  ) async {
    final _FakeCustomerWithdrawalsApi api = _FakeCustomerWithdrawalsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminCustomerWithdrawalsScreen(
          api: api,
          initialAccess: const AdminAccess(
            role: 'HEAD_OFFICE',
            permissions: <String>{},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(find.textContaining('returns the held withdrawal amount'),
        findsOneWidget);
    final Finder rejectButton = find.text('Reject request');
    expect(
      tester
          .widget<FilledButton>(
            find
                .ancestor(
                  of: rejectButton,
                  matching: find.byType(FilledButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason for rejection'),
      'Beneficiary name mismatch',
    );
    await tester.ensureVisible(rejectButton);
    await tester.pumpAndSettle();
    await tester.tap(rejectButton);
    await tester.pumpAndSettle();
    expect(api.rejectionReason, 'Beneficiary name mismatch');
    expect(find.text('PENDING'), findsOneWidget);
  });

  testWidgets('only exact Head Office role can access the queue', (
    WidgetTester tester,
  ) async {
    final _FakeCustomerWithdrawalsApi api = _FakeCustomerWithdrawalsApi();
    const List<String> forbiddenRoles = <String>[
      'STAFF',
      'ADMIN',
      'SUPER_ADMIN',
      'HEAD_OFFICE_ADMIN',
      'SERVICEPAY_SUPER_ADMIN',
    ];
    const List<Set<String>> elevatedPermissions = <Set<String>>[
      <String>{AdminPermissions.withdrawalsView},
      <String>{'*'},
      <String>{AdminPermissions.withdrawalsView, '*'},
    ];
    for (final String role in forbiddenRoles) {
      for (final Set<String> permissions in elevatedPermissions) {
        await tester.pumpWidget(
          MaterialApp(
            home: AdminCustomerWithdrawalsScreen(
              api: api,
              initialAccess: AdminAccess(
                role: role,
                permissions: permissions,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('You do not have permission to view customer withdrawals.'),
          findsOneWidget,
          reason: '$role must not access the Head Office-only queue',
        );
      }
    }
    expect(api.requestedStatuses, isEmpty);
  });
}

class _FakeCustomerWithdrawalsApi extends AdminCustomerWithdrawalsApi {
  final List<String> requestedStatuses = <String>[];
  String? markPaidReference;
  bool? manualPaymentConfirmed;
  num? expectedAmount;
  String? expectedAccountNumber;
  String? rejectionReason;
  bool failMarkPaid = false;
  bool failNextList = false;
  bool hasBeenPaid = false;

  @override
  Future<List<Map<String, dynamic>>> list({String status = ''}) async {
    requestedStatuses.add(status);
    if (failNextList) {
      failNextList = false;
      throw Exception('Queue refresh temporarily failed.');
    }
    return <Map<String, dynamic>>[
      <String, dynamic>{
        '_id': 'withdrawal-1',
        'status': hasBeenPaid ? 'APPROVED' : 'PENDING',
        'amount': 5000,
        'bankName': 'Example Bank',
        'accountNumber': '0012345678',
        'accountName': 'Ada Example',
        'reference': 'request-ref-1',
        'user': <String, dynamic>{
          'fullName': 'Ada Example',
          'phone': '08000000000',
          'email': 'ada@example.test',
        },
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> markPaid(
    String id, {
    required String payoutReference,
    required String adminNote,
    required bool manualPaymentConfirmed,
    required num expectedAmount,
    required String expectedAccountNumber,
  }) async {
    if (failMarkPaid) {
      throw Exception('Server did not confirm the manual-payment action.');
    }
    markPaidReference = payoutReference;
    this.manualPaymentConfirmed = manualPaymentConfirmed;
    this.expectedAmount = expectedAmount;
    this.expectedAccountNumber = expectedAccountNumber;
    hasBeenPaid = true;
    return <String, dynamic>{'success': true};
  }

  @override
  Future<Map<String, dynamic>> reject(
    String id, {
    required String reason,
  }) async {
    rejectionReason = reason;
    return <String, dynamic>{'success': true};
  }
}
