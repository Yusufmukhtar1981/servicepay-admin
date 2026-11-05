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
  testWidgets('staff retain read-only details when refund access is forbidden',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(<String, dynamic>{
          'success': false,
          'message': 'Head Office access required',
        }),
        403,
      );
    });
    final AdminManualRefundsApi api = AdminManualRefundsApi(
      client: client,
      baseUrl: 'https://staging.example/api',
      tokenProvider: () async => 'test-token',
    );
    await tester.pumpWidget(
      MaterialApp(home: AdminTransactionsScreen(refundsApi: api)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(AdminTransactionsScreen));
    await state.showTransactionDetails(<String, dynamic>{
      '_id': 'tx-view-only',
      'reference': 'READ-ONLY-TRANSACTION',
      'serviceType': 'DATA',
      'status': 'PENDING',
      'amount': 125,
    });
    await tester.pumpAndSettle();
    expect(find.text('READ-ONLY-TRANSACTION'), findsWidgets);
    expect(find.text('Refund Customer'), findsNothing);
    expect(requests.length, 1);
    expect(requests.single.method, 'GET');
    expect(find.textContaining('Showing existing read-only'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    client.close();
  });

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
        providerRiskAcknowledged: true,
      );

      final http.Request request = requests.single;
      expect(request.url.toString(),
          'https://staging.example/api/admin/manual-refunds/transactions/payment%2F42/refund');
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.headers['X-Idempotency-Key'], 'stable-key-1');
      expect(jsonDecode(request.body), <String, dynamic>{
        'reason': 'Verified duplicate debit',
        'confirmation': true,
        'providerRiskAcknowledged': true,
        'idempotencyKey': 'stable-key-1',
      });
      expect(jsonDecode(request.body), isNot(contains('amount')));
      client.close();
    });

    test('does not POST a refund without provider risk acknowledgement',
        () async {
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
        baseUrl: 'https://staging.example/api',
        tokenProvider: () async => 'test-token',
      );

      await expectLater(
        api.submitRefund(
          'tx-no-risk',
          reason: 'Reviewed the wallet debit',
          providerRiskAcknowledged: false,
        ),
        throwsA(isA<ManualRefundApiException>()),
      );
      await expectLater(
        api.refund(
          'tx-no-risk',
          reason: 'Reviewed the wallet debit',
          idempotencyKey: 'no-risk-key',
          providerRiskAcknowledged: false,
        ),
        throwsA(isA<ManualRefundApiException>()),
      );
      expect(requests, isEmpty);
      expect(await api.loadIntent('tx-no-risk'), isNull);
      client.close();
    });

    test('failed intent persistence prevents a refund POST', () async {
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
        baseUrl: 'https://staging.example/api',
        tokenProvider: () async => 'test-token',
        intentWriter: (String _, String __) async => false,
      );

      await expectLater(
        api.submitRefund(
          'tx-write-failure',
          reason: 'Reviewed the wallet debit',
          providerRiskAcknowledged: true,
        ),
        throwsA(isA<ManualRefundApiException>()),
      );
      expect(requests, isEmpty);
      client.close();
    });

    test('legacy saved intent needs fresh risk acknowledgement and keeps key',
        () async {
      final List<http.Request> requests = <http.Request>[];
      final MockClient client = MockClient((http.Request request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'refund': <String, dynamic>{'id': 'rf-legacy'}
          }),
          200,
        );
      });
      final AdminManualRefundsApi api = AdminManualRefundsApi(
        client: client,
        baseUrl: 'https://staging.example/api',
        tokenProvider: () async => 'test-token',
      );
      await api.saveIntent(
        'tx-legacy',
        const ManualRefundIntent(
          reason: 'Original review reason',
          idempotencyKey: 'legacy-stable-key',
          providerRiskAcknowledged: false,
        ),
      );
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String storageKey =
          prefs.getKeys().singleWhere((String key) => key.contains('tx-legacy'));
      await prefs.setString(
        storageKey,
        jsonEncode(<String, String>{
          'reason': 'Original review reason',
          'idempotencyKey': 'legacy-stable-key',
        }),
      );

      await expectLater(
        api.submitRefund(
          'tx-legacy',
          reason: 'New text does not replace saved text',
          providerRiskAcknowledged: false,
        ),
        throwsA(isA<ManualRefundApiException>()),
      );
      expect(requests, isEmpty);
      await api.submitRefund(
        'tx-legacy',
        reason: 'New text does not replace saved text',
        providerRiskAcknowledged: true,
      );
      expect(requests, hasLength(1));
      expect(requests.single.headers['X-Idempotency-Key'], 'legacy-stable-key');
      final Map<String, dynamic> body =
          jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['reason'], 'Original review reason');
      expect(body['providerRiskAcknowledged'], isTrue);
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
        api.submitRefund(
          'tx-lost',
          reason: 'First immutable reason',
          providerRiskAcknowledged: true,
        ),
        throwsA(isA<ManualRefundApiException>()),
      );
      final ManualRefundIntent? saved = await api.loadIntent('tx-lost');
      expect(saved, isNotNull);
      expect(saved!.reason, 'First immutable reason');
      expect(saved.providerRiskAcknowledged, isTrue);

      // Deliberately supply changed text: a pending key must retain its original
      // request body so the backend requestHash cannot be changed on retry.
      await api.submitRefund(
        'tx-lost',
        reason: 'Changed reason is ignored',
        providerRiskAcknowledged: true,
      );
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
        api.submitRefund(
          'tx-forbidden',
          reason: 'Review debit evidence',
          providerRiskAcknowledged: true,
        ),
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
      List<String> blockers = const <String>[],
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
            'blockers': blockers,
          },
        };

    Future<void> pumpDialog(
      WidgetTester tester, {
      required bool eligible,
      required bool canExecute,
      required Future<String?> Function(String, bool) submit,
      String status = 'PENDING',
      String providerStatus = 'FAILED',
      String initialReason = '',
      bool reasonLocked = false,
      bool initialProviderRiskAcknowledged = false,
      List<String> blockers = const <String>[],
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ManualRefundDialog(
            transaction: detail(
              eligible: eligible,
              status: status,
              providerStatus: providerStatus,
              blockers: blockers,
            ),
            canExecute: canExecute,
            initialReason: initialReason,
            reasonLocked: reasonLocked,
            initialProviderRiskAcknowledged: initialProviderRiskAcknowledged,
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
          eligible: true, canExecute: true, submit: (_, __) async => null);
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
          eligible: false, canExecute: true, submit: (_, __) async => null);
      expect(find.text('Refund Customer'), findsNothing);
      expect(find.textContaining('not eligible'), findsOneWidget);
      await pumpDialog(tester,
          eligible: true, canExecute: false, submit: (_, __) async => null);
      expect(find.text('Refund Customer'), findsNothing);
      expect(find.textContaining('transactions.refund'), findsOneWidget);
      await pumpDialog(
        tester,
        eligible: true,
        canExecute: true,
        blockers: const <String>['Wallet debit not verified'],
        submit: (_, __) async => null,
      );
      expect(find.text('Refund Customer'), findsNothing);
      expect(find.textContaining('eligibility blockers'), findsOneWidget);
      await pumpDialog(
        tester,
        eligible: true,
        canExecute: true,
        status: 'COMPLETED',
        submit: (_, __) async => null,
      );
      expect(find.text('Refund Customer'), findsNothing);
    });

    testWidgets('requires a valid reason and explicit confirmation',
        (WidgetTester tester) async {
      int calls = 0;
      await pumpDialog(tester, eligible: true, canExecute: true,
          submit: (_, __) async {
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
      await tester.ensureVisible(find.byType(Checkbox).first);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.ensureVisible(find.text('Refund Customer').last);
      await tester.tap(find.text('Refund Customer').last);
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.ensureVisible(find.byType(Checkbox).last);
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      await tester.ensureVisible(find.text('Refund Customer').last);
      await tester.tap(find.text('Refund Customer').last);
      await tester.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets('provider processing is allowed with the exact risk warning',
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
            onSubmit: (_, __) async => null,
          ),
        ),
      ));
      expect(
        find.text(
            'Provider outcome has not been confirmed. This manual refund may result in a financial loss if the service was delivered.'),
        findsOneWidget,
      );
      expect(find.text('Refund Customer'), findsNWidgets(2));
    });

    testWidgets('uncertain failure leaves the dialog available for retry',
        (WidgetTester tester) async {
      int calls = 0;
      await pumpDialog(tester, eligible: true, canExecute: true,
          submit: (_, __) async {
        calls++;
        return 'Request could not be confirmed.';
      });
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(
          find.byType(TextField), 'Verified duplicate debit');
      await tester.ensureVisible(find.byType(Checkbox).first);
      await tester.tap(find.byType(Checkbox).first);
      await tester.ensureVisible(find.byType(Checkbox).last);
      await tester.tap(find.byType(Checkbox).last);
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
        submit: (_, __) async => null,
      );
      expect(find.text('Refund Customer'), findsNothing);
      expect(find.textContaining('Only a transaction currently marked PENDING'),
          findsOneWidget);
      await pumpDialog(
        tester,
        eligible: true,
        canExecute: true,
        status: 'REFUNDED',
        submit: (_, __) async => null,
      );
      expect(find.text('Refund Customer'), findsNothing);
    });

    testWidgets('unknown eligible outcome submits after both acknowledgements',
        (WidgetTester tester) async {
      bool? submittedRiskAcknowledgement;
      await pumpDialog(
        tester,
        eligible: true,
        canExecute: true,
        providerStatus: 'UNRECOGNIZED',
        submit: (String _, bool riskAcknowledged) async {
          submittedRiskAcknowledgement = riskAcknowledged;
          return null;
        },
      );
      expect(
        find.text(
            'Provider outcome has not been confirmed. This manual refund may result in a financial loss if the service was delivered.'),
        findsOneWidget,
      );
      expect(find.text('Refund Customer'), findsNWidgets(2));
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(
          find.byType(TextField), 'Reviewed wallet debit evidence');
      await tester.ensureVisible(find.byType(Checkbox).first);
      await tester.tap(find.byType(Checkbox).first);
      await tester.ensureVisible(find.byType(Checkbox).last);
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      await tester.ensureVisible(find.text('Refund Customer').last);
      await tester.tap(find.text('Refund Customer').last);
      await tester.pumpAndSettle();
      expect(submittedRiskAcknowledgement, isTrue);
    });

    testWidgets('provider success blocks an inconsistent eligible response',
        (WidgetTester tester) async {
      for (final String status in <String>[
        'SUCCESS',
        'SUCCESSFUL',
        'COMPLETED',
        'DELIVERED',
      ]) {
        await pumpDialog(
          tester,
          eligible: true,
          canExecute: true,
          providerStatus: status,
          submit: (_, __) async => null,
        );
        expect(find.text('Refund Customer'), findsNothing);
        expect(find.textContaining('successful delivery'), findsOneWidget);
      }
    });

    testWidgets('double tap submits only once and locks the attempted reason',
        (WidgetTester tester) async {
      final Completer<String?> completion = Completer<String?>();
      int calls = 0;
      await pumpDialog(
        tester,
        eligible: true,
        canExecute: true,
        submit: (_, __) {
          calls++;
          return completion.future;
        },
      );
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(
          find.byType(TextField), 'Verified duplicate debit');
      await tester.ensureVisible(find.byType(Checkbox).first);
      await tester.tap(find.byType(Checkbox).first);
      await tester.ensureVisible(find.byType(Checkbox).last);
      await tester.tap(find.byType(Checkbox).last);
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
        submit: (_, __) async => null,
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
        submit: (_, __) async => 'Request could not be confirmed.',
      );
      expect(find.text('Original persisted reason'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      expect(find.text('Refund Customer'), findsNWidgets(2));
    });
  });
}
