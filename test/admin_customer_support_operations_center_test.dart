import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:servicepay_app/admin/admin_customer_support_operations_center.dart';
import 'package:servicepay_app/admin/admin_customer_support_screen.dart';
import 'package:servicepay_app/admin/admin_staff_workspace_api.dart';

class _SupportApi extends AdminStaffWorkspaceApi {
  _SupportApi() : super(baseUrl: 'https://support.test');

  String lastCustomerQuery = '';
  String lastTransactionQuery = '';
  String lastTransactionStatus = '';
  String lastLinkedTransaction = '';
  String lastAccountQuery = '';
  bool failSummaryOnce = false;
  bool failTicketOnce = false;
  bool canManageTeam = true;
  int summaryCalls = 0;
  int customerCalls = 0;
  final List<String> ticketKeys = <String>[];
  final Map<String, dynamic> customerRecord = {
    'id': 'cust-7',
    'fullName': 'Ada Okafor',
    'phone': '+2348012345678',
    'email': 'ada@example.test',
    'status': 'ACTIVE',
    'kycStatus': 'VERIFIED',
    'walletBalance': 4250,
  };

  @override
  Future<Map<String, dynamic>> supportSummary() async {
    summaryCalls++;
    if (failSummaryOnce && summaryCalls == 1) {
      throw Exception('Support metrics are temporarily unavailable.');
    }
    return {
      'data': {
        'totalCustomers': 18432,
        'pendingTransactions': 17,
        'failedTransactions': 9,
        'openComplaints': 12,
        'resolvedTickets': 146,
        'averageResolutionSeconds': 5100,
        'averageFirstResponseSeconds': 84,
        'activeSupportAgents': 6,
        'canManageTeam': canManageTeam,
        'dayTimezone': 'UTC',
        'timingNotice': 'Timings reflect recorded ticket events.',
        'todaySupportActivity': 14,
        'team': [
          {
            'id': 'agent-1',
            'name': 'Nneka Eze',
            'assigned': 13,
            'resolved': 8,
            'averageResolutionSeconds': 3400,
            'averageFirstResponseSeconds': 67,
          }
        ],
      }
    };
  }

  @override
  Future<Map<String, dynamic>> customers({
    String query = '',
    int page = 1,
    int limit = 20,
  }) async {
    lastCustomerQuery = query;
    return {
      'data': {
        'items': query.isEmpty ? [] : [customerRecord],
        'total': query.isEmpty ? 0 : 1,
      }
    };
  }

  @override
  Future<Map<String, dynamic>> customer(String id) async {
    customerCalls++;
    return {
      'data': {
        'customer': customerRecord,
        'transactions': [
          {
            'id': 'tx-1',
            'reference': 'SP-REF-8041',
            'type': 'TRANSFER',
            'status': 'FAILED',
            'amount': 1800,
            'providerStatus': 'DECLINED',
            'errorCode': 'P04',
            'diagnostic': 'Receiving institution did not confirm.',
          }
        ],
        'tickets': [
          {
            'id': 'case-1',
            'caseReference': 'SUP-001',
            'subject': 'Transfer not received',
            'status': 'ESCALATED',
            'priority': 'HIGH',
          }
        ],
        'virtualAccount': {
          'status': 'ACTIVE',
          'bankName': 'ServicePay partner bank',
          'maskedAccountNumber': '**** 2084',
          'updatedAt': '2025-02-17T10:00:00Z',
        },
      }
    };
  }

  @override
  Future<Map<String, dynamic>> transactions({
    String status = '',
    String type = '',
    int page = 1,
    int limit = 20,
    String query = '',
    String customerId = '',
  }) async {
    lastTransactionQuery = query;
    lastTransactionStatus = status;
    return {
      'data': {
        'items': [
          {
            'id': 'tx-1',
            'reference': 'SP-REF-8041',
            'customerId': 'cust-7',
            'type': 'TRANSFER',
            'status': 'FAILED',
            'amount': 1800,
          }
        ],
        'total': 1,
      }
    };
  }

  @override
  Future<Map<String, dynamic>> virtualAccounts({
    String query = '',
    String status = '',
    int page = 1,
    int limit = 20,
  }) async {
    lastAccountQuery = query;
    return {
      'data': {
        'items': [
          {
            'id': 'va-1',
            'fullName': 'Ada Okafor',
            'status': 'ACTIVE',
            'bankName': 'ServicePay partner bank',
            'maskedAccountNumber': '**** 2084',
          }
        ],
        'total': 1,
      }
    };
  }

  @override
  Future<Map<String, dynamic>> createTicket({
    required String customerId,
    required String subject,
    required String description,
    required String category,
    required String priority,
    required String idempotencyKey,
    String? transactionId,
  }) async {
    ticketKeys.add(idempotencyKey);
    lastLinkedTransaction = transactionId ?? '';
    if (failTicketOnce && ticketKeys.length == 1) {
      throw Exception('Case service is temporarily unavailable.');
    }
    return {'success': true};
  }
}

Future<void> _setWidth(WidgetTester tester, double width) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
}

Widget _app(_SupportApi api) => MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff087b55),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: CustomerSupportOperationsCenter(api: api),
    );

void main() {
  test('assignment access respects support role but preserves Head Office', () {
    expect(
      canManageSupportAssignmentsForRole(
        staffRoleName: 'CUSTOMER_SUPPORT',
        adminRole: 'STAFF',
      ),
      isFalse,
    );
    expect(
      canManageSupportAssignmentsForRole(
        staffRoleName: 'SUPPORT_MANAGER',
        adminRole: 'STAFF',
      ),
      isTrue,
    );
    expect(
      canManageSupportAssignmentsForRole(
        staffRoleName: 'CUSTOMER_SUPPORT',
        adminRole: 'HEAD_OFFICE',
      ),
      isTrue,
    );
  });

  testWidgets('customer investigation works at phone width', (tester) async {
    await _setWidth(tester, 390);
    final api = _SupportApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('Support Operations Center'), findsOneWidget);
    expect(find.text('18,432'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Ada');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.lastCustomerQuery, 'Ada');
    expect(find.text('Ada Okafor'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Ada Okafor'));
    await tester.pumpAndSettle();
    expect(api.customerCalls, 1);
    final detail = find.byKey(const ValueKey('customer-detail'));
    expect(detail, findsOneWidget);
    await tester.drag(detail, const Offset(0, -280));
    await tester.pumpAndSettle();
    expect(find.text('₦4,250.00'), findsOneWidget);
    expect(find.textContaining('**** 2084'), findsOneWidget);
    await tester.drag(detail, const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(find.text('Recent transactions'), findsOneWidget);
    await tester.drag(detail, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.textContaining('ESCALATED'), findsOneWidget);
    await tester.drag(detail, const Offset(0, 1300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create support case'));
    await tester.pumpAndSettle();
    final dialogFields = find.byType(TextField);
    await tester.enterText(dialogFields.first, 'Transfer investigation');
    await tester.enterText(
        dialogFields.at(1), 'Customer has not received funds.');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create case'));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('case creation retries with the same intent key', (tester) async {
    final api = _SupportApi()..failTicketOnce = true;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ada');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Ada Okafor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create support case'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).first, 'Transfer investigation');
    await tester.enterText(
      find.byType(TextField).at(1),
      'Customer has not received funds.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create case'));
    await tester.pumpAndSettle();
    expect(
        find.text('Case service is temporarily unavailable.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.ticketKeys, hasLength(2));
    expect(api.ticketKeys[0], api.ticketKeys[1]);
    expect(find.text('Support case created.'), findsOneWidget);
  });

  testWidgets('transactions, virtual accounts and report work at desktop width',
      (tester) async {
    await _setWidth(tester, 1280);
    final api = _SupportApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    final transactionSearch = find.byType(TextField).first;
    await tester.enterText(transactionSearch, 'SP-REF-8041');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.lastTransactionQuery, 'SP-REF-8041');
    expect(find.text('SP-REF-8041'), findsWidgets);

    await tester.tap(find.text('Virtual accounts'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ada');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.lastAccountQuery, 'Ada');
    expect(find.textContaining('**** 2084'), findsOneWidget);

    await tester.tap(find.text('Team & reports'));
    await tester.pumpAndSettle();
    expect(find.text('Nneka Eze'), findsOneWidget);
    await tester.tap(find.text('Generate report'));
    await tester.pumpAndSettle();
    expect(find.text('Support operations report'), findsOneWidget);
    final report = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(report.data, contains('Average resolution seconds'));
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('metrics errors are useful and can be retried', (tester) async {
    final api = _SupportApi()
      ..failSummaryOnce = true
      ..canManageTeam = false;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(
      find.text('Support metrics are temporarily unavailable.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Support metrics are temporarily unavailable.'),
        findsNothing);
    expect(find.text('18,432'), findsOneWidget);
    expect(find.text('Team & reports'), findsNothing);
  });

  testWidgets('transaction investigation links the exact record to a complaint',
      (tester) async {
    await _setWidth(tester, 1280);
    final api = _SupportApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'SP-REF-8041');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'SP-REF-8041'));
    await tester.pumpAndSettle();
    expect(find.text('Transaction investigation'), findsOneWidget);
    await tester.tap(find.text('Create linked complaint'));
    await tester.pumpAndSettle();
    expect(find.text('tx-1'), findsOneWidget);
    final description = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.labelText == 'What happened?');
    await tester.enterText(description, 'Please review the provider outcome.');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create case')).onPressed, isNotNull);
    await tester.tap(find.text('Create case'));
    await tester.pumpAndSettle();
    expect(api.lastLinkedTransaction, 'tx-1');
    expect(api.ticketKeys, hasLength(1));
    await tester.binding.setSurfaceSize(null);
  });
}
