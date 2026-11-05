import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/admin_manual_refunds_api.dart';
import 'package:servicepay_app/admin/admin_transactions_screen.dart';

void main() {
  group('AdminManualRefundsApi', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'user_id': 'admin-42',
      });
    });

    test('uses same-origin API contract and exact idempotency key', () async {
      final List<http.Request> requests = <http.Request>[];
      final MockClient client = MockClient((http.Request request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'refund': <String, dynamic>{'id': 'rf-1'}
          }),
          200,
        );
      });
      final AdminManualRefundsApi api = AdminManualRefundsApi(
        client: client,
        baseUrl: 'https://staging.example/api/',
        tokenProvider: () async => 'test-token',
      );

      await api.refund(
        'payment/42',
        reason: 'Verified duplicate debit',
        idempotencyKey: 'stable-key-1',
      );

      final http.Request request = requests.single;
      expect(request.url.toString(),
          'https://staging.example/api/admin/manual-refunds/transactions/payment%2F42/refund');
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.headers['X-Idempotency-Key'], 'stable-key-1');
      expect(jsonDecode(request.body), <String, dynamic>{
        'reason': 'Verified duplicate debit',
        'confirmation': true,
        'idempotencyKey': 'stable-key-1',
      });
      expect(jsonDecode(request.body), isNot(contains('amount')));
      client.close();
    });

    test('loads detail and paginated history at required paths', () async {
      final List<Uri> urls = <Uri>[];
      final MockClient client = MockClient((http.Request request) async {
        urls.add(request.url);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'items': <dynamic>[],
            'page': 3,
            'pages': 4
          }),
          200,
        );
      });
      final AdminManualRefundsApi api = AdminManualRefundsApi(
        client: client,
        baseUrl: 'https://staging.example/api',
        tokenProvider: () async => 'test-token',
      );
      await api.transaction('tx-1');
      await api.history(page: 3);
      expect(urls[0].path, '/api/admin/manual-refunds/transactions/tx-1');
      expect(urls[1].path, '/api/admin/manual-refunds/history');
      expect(urls[1].queryParameters['page'], '3');
      client.close();
    });

    test('lost response retries the persisted immutable reason and key',
        () async {
      final List<http.Request> requests = <http.Request>[];
      int calls = 0;
      final MockClient client = MockClient((http.Request request) async {
        requests.add(request);
        calls++;
        if (calls == 1) throw const SocketException('connection closed');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'refund': <String, dynamic>{
              'id': 'refund-1',
              'status': 'SUCCESSFUL',
            },
            'replayed': true,
          }),
          200,
        );
      });
      final AdminManualRefundsApi api = AdminManualRefundsApi(
        client: client,
        baseUrl: 'https://staging.example/api',
        tokenProvider: () async => 'session-token',
      );

      await expectLater(
        api.submitRefund('tx-lost', reason: 'First immutable reason'),
        throwsA(isA<ManualRefundApiException>()),
      );
      final ManualRefundIntent? saved = await api.loadIntent('tx-lost');
      expect(saved, isNotNull);
      expect(saved!.reason, 'First immutable reason');

      // Deliberately supply changed text: a pending key must retain its original
      // request body so the backend requestHash cannot be changed on retry.
      await api.submitRefund('tx-lost', reason: 'Changed reason is ignored');
      expect(requests, hasLength(2));
      expect(requests[0].body, requests[1].body);
      expect(requests[0].headers['X-Idempotency-Key'],
          requests[1].headers['X-Idempotency-Key']);
      expect(jsonDecode(requests[1].body)['reason'], 'First immutable reason');
      expect(await api.loadIntent('tx-lost'), isNull);
      client.close();
    });

    test('unauthorized response is safe and clears a confirmed rejected intent',
        () async {
      const String secret = 'do-not-print-this-token';
      final MockClient client =
          MockClient((http.Request _) async => http.Response(
              jsonEncode(<String, dynamic>{
                'success': false,
                'message': 'Forbidden',
              }),
              403));
      final AdminManualRefundsApi api = AdminManualRefundsApi(
        client: client,
        baseUrl: 'https://staging.example/api',
        tokenProvider: () async => secret,
      );
      await expectLater(
        api.submitRefund('tx-forbidden', reason: 'Review debit evidence'),
        throwsA(
          isA<ManualRefundApiException>()
              .having((ManualRefundApiException error) => error.message,
                  'message', contains('transactions.refund'))
              .having((ManualRefundApiException error) => error.message,
                  'message', isNot(contains(secret))),
        ),
      );
      expect(await api.loadIntent('tx-forbidden'), isNull);
      client.close();
    });
  });

  group('ManualRefundDialog', () {
    Map<String, dynamic> detail({
      bool eligible = true,
      String status = 'PENDING',
      String providerStatus = 'FAILED',
    }) =>
        <String, dynamic>{
          'id': 'tx-1',
          'reference': 'SP-REF-1',
          'serviceType': 'AIRTIME',
          'amount': 1200,
          'status': status,
          'createdAt': '2025-01-01T10:00:00Z',
          'customer': <String, dynamic>{
            'name': 'Ada Customer',
            'phone': '08000000000'
          },
          'walletDebitStatus': 'DEBITED',
          'verifiedDebitAmount': 1200,
          'providerStatus': providerStatus,
          'refund': <String, dynamic>{
            'eligible': eligible,
            'blockers': <String>[]
          },
        };

    Future<void> pumpDialog(
      WidgetTester tester, {
      required bool eligible,
      required bool canExecute,
      required Future<String?> Function(String) submit,
      String status = 'PENDING',
      String providerStatus = 'FAILED',
      String initialReason = '',
      bool reasonLocked = false,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ManualRefundDialog(
            transaction: detail(
              eligible: eligible,
              status: status,
              providerStatus: providerStatus,
            ),
            canExecute: canExecute,
            initialReason: initialReason,
            reasonLocked: reasonLocked,
            formatMoney: (double value) => '₦${value.toStringAsFixed(2)}',
            formatText: (dynamic value) => '$value',
            formatDate: (dynamic value) => '$value',
            onSubmit: submit,
          ),
        ),
      ));
    }

    testWidgets(
        'shows specified investigation details and only eligible execution',
        (WidgetTester tester) async {
      await pumpDialog(tester,
          eligible: true, canExecute: true, submit: (_) async => null);
      expect(find.text('Payment investigation'), findsOneWidget);
      expect(find.text('Ada Customer'), findsOneWidget);
      expect(find.text('08000000000'), findsOneWidget);
      expect(find.text('Wallet debit status'), findsOneWidget);
      expect(find.text('Verified debit amount'), findsOneWidget);
      expect(find.text('Provider status'), findsOneWidget);
      expect(find.text('Refund Customer'), findsNWidgets(2));
      expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 500);
    });

    testWidgets(
        'does not offer refund when ineligible or execution is unavailable',
        (WidgetTester tester) async {
      await pumpDialog(tester,
          eligible: false, canExecute: true, submit: (_) async => null);
      expect(find.text('Refund Customer'), findsNothing);
      expect(find.textContaining('not eligible'), findsOneWidget);
      await pumpDialog(tester,
          eligible: true, canExecute: false, submit: (_) async => null);
      expect(find.text('Refund Customer'), findsNothing);
      expect(find.textContaining('transactions.refund'), findsOneWidget);
    });

    testWidgets('requires a valid reason and explicit confirmation',
        (WidgetTester tester) async {
      int calls = 0;
      await pumpDialog(tester, eligible: true, canExecute: true,
          submit: (_) async {
        calls++;
        return null;
      });
      await tester.ensureVisible(find.text('Refund Customer').last);
      await tester.tap(find.text('Refund Customer').last);
      await tester.pump();
      expect(calls, 0);
      expect(find.textContaining('10–500'), findsNWidgets(2));
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(
          find.byType(TextField), 'Verified duplicate debit');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text('Refund Customer').last);
      await tester.tap(find.text('Refund Customer').last);
      await tester.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets('provider processing requires authorized reconciliation',
        (WidgetTester tester) async {
      final Map<String, dynamic> processing =
          detail(providerStatus: 'PROCESSING');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ManualRefundDialog(
            transaction: processing,
            canExecute: true,
            formatMoney: (double value) => '$value',
            formatText: (dynamic value) => '$value',
            formatDate: (dynamic value) => '$value',
            onSubmit: (_) async => null,
          ),
        ),
      ));
      expect(find.textContaining('Authorized reconciliation is required'),
          findsOneWidget);
      expect(find.text('Refund Customer'), findsNothing);
    });

    testWidgets('uncertain failure leaves the dialog available for retry',
        (WidgetTester tester) async {
      int calls = 0;
      await pumpDialog(tester, eligible: true, canExecute: true,
          submit: (_) async {
        calls++;
        return 'Request could not be confirmed.';
      });
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(
          find.byType(TextField), 'Verified duplicate debit');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text('Refund Customer').last);
      await tester.tap(find.text('Refund Customer').last);
      await tester.pumpAndSettle();
      expect(find.text('Request could not be confirmed.'), findsOneWidget);
      expect(find.text('Refund Customer'), findsNWidgets(2));
      expect(calls, 1);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    });

    testWidgets('successful and already-refunded transactions cannot refund',
        (WidgetTester tester) async {
      await pumpDialog(
        tester,
        eligible: true,
        canExecute: true,
        status: 'SUCCESSFUL',
        submit: (_) async => null,
      );
      expect(find.text('Refund Customer'), findsNothing);
      expect(find.textContaining('Only a transaction currently marked PENDING'),
          findsOneWidget);
      await pumpDialog(
        tester,
        eligible: true,
        canExecute: true,
        status: 'REFUNDED',
        submit: (_) async => null,
      );
      expect(find.text('Refund Customer'), findsNothing);
    });

    testWidgets('unknown provider status requires reconciliation',
        (WidgetTester tester) async {
      await pumpDialog(
        tester,
        eligible: true,
        canExecute: true,
        providerStatus: 'UNRECOGNIZED',
        submit: (_) async => null,
      );
      expect(find.textContaining('Authorized reconciliation is required'),
          findsOneWidget);
      expect(find.text('Refund Customer'), findsNothing);
    });

    testWidgets('provider success blocks an inconsistent eligible response',
        (WidgetTester tester) async {
      await pumpDialog(
        tester,
        eligible: true,
        canExecute: true,
        providerStatus: 'SUCCESS',
        submit: (_) async => null,
      );
      expect(find.text('Refund Customer'), findsNothing);
      expect(find.textContaining('did not confirm a failed payment'),
          findsOneWidget);
    });

    testWidgets('double tap submits only once and locks the attempted reason',
        (WidgetTester tester) async {
      final Completer<String?> completion = Completer<String?>();
      int calls = 0;
      await pumpDialog(
        tester,
        eligible: true,
        canExecute: true,
        submit: (_) {
          calls++;
          return completion.future;
        },
      );
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(
          find.byType(TextField), 'Verified duplicate debit');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text('Refund Customer').last);
      await tester.tap(find.text('Refund Customer').last);
      await tester.pump();
      await tester.tap(find.text('Refund Customer').last, warnIfMissed: false);
      await tester.pump();
      expect(calls, 1);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      completion.complete('Request could not be confirmed.');
      await tester.pumpAndSettle();
    });

    testWidgets('390px mobile viewport lays out without overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      await pumpDialog(
        tester,
        eligible: true,
        canExecute: true,
        submit: (_) async => null,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Payment investigation'), findsOneWidget);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('restored uncertain intent locks reason and exposes retry',
        (WidgetTester tester) async {
      await pumpDialog(
        tester,
        eligible: true,
        canExecute: true,
        initialReason: 'Original persisted reason',
        reasonLocked: true,
        submit: (_) async => 'Request could not be confirmed.',
      );
      expect(find.text('Original persisted reason'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      expect(find.text('Refund Customer'), findsNWidgets(2));
    });
  });
}
