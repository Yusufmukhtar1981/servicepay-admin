import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/expense_management/expense_api.dart';
import 'package:servicepay_app/admin/expense_management/expense_common.dart';

const String _base = 'https://admin.test.invalid/api';

http.Response _ok(Map<String, dynamic> data) => http.Response(
      jsonEncode(<String, dynamic>{'success': true, 'data': data}),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );

ExpenseManagementApi _api(MockClientHandler handler, {List<String>? saved}) => ExpenseManagementApi(
      client: MockClient(handler),
      baseUrl: _base,
      tokenLoader: () async => 'test-session',
      downloadAdapter: (List<int> bytes, String name, String type) async => saved?.add('$name|$type|${bytes.length}'),
    );

void main() {
  test('create sends flat payload, auth and a valid idempotency key', () async {
    late http.Request captured;
    final ExpenseManagementApi api = _api((http.Request r) async {
      captured = r;
      return _ok(<String, dynamic>{'item': <String, dynamic>{'id': 'a' * 24}, 'idempotent': false});
    });
    final String key = ExpenseIdempotency.newKey('exp');
    await api.createExpense(<String, dynamic>{'title': 'Diesel', 'amount': '1250.50'}, key);
    expect(captured.method, 'POST');
    expect(captured.url.toString(), '$_base/admin/expense-management/expenses');
    expect(captured.headers['Authorization'], 'Bearer test-session');
    expect(captured.headers['Idempotency-Key'], key);
    expect(ExpenseIdempotency.pattern.hasMatch(key), isTrue);
    expect(jsonDecode(captured.body), <String, dynamic>{'title': 'Diesel', 'amount': '1250.50'});
  });

  test('connection loss on a write is reported as outcome unknown', () async {
    final ExpenseManagementApi api = _api((http.Request r) async => throw http.ClientException('reset'));
    await expectLater(
      api.createExpense(<String, dynamic>{'title': 'x'}, ExpenseIdempotency.newKey()),
      throwsA(isA<ExpenseApiException>().having((ExpenseApiException e) => e.outcomeUnknown, 'outcomeUnknown', isTrue)),
    );
  });

  test('403 and 409 surface server messages and classification', () async {
    final ExpenseManagementApi api = _api((http.Request r) async => http.Response(
        jsonEncode(<String, dynamic>{'success': false, 'message': 'Missing expenses.approve', 'code': 'FORBIDDEN'}), 403));
    try {
      await api.listExpenses(<String, String>{});
      fail('expected');
    } on ExpenseApiException catch (e) {
      expect(e.isForbidden, isTrue);
      expect(e.message, 'Missing expenses.approve');
    }
    final ExpenseManagementApi conflict = _api((http.Request r) async => http.Response('{"success":false,"code":"STALE"}', 409));
    try {
      await conflict.expenseAction('a' * 24, action: 'APPROVE', expectedVersion: 1, reason: 'ok', idempotencyKey: ExpenseIdempotency.newKey());
      fail('expected');
    } on ExpenseApiException catch (e) {
      expect(e.isConflict, isTrue);
      expect(e.isDefinitiveRejection, isTrue);
    }
  });

  test('PAY requires and sends confirmation flag with payment details', () async {
    late Map<String, dynamic> body;
    final ExpenseManagementApi api = _api((http.Request r) async {
      body = jsonDecode(r.body) as Map<String, dynamic>;
      return _ok(<String, dynamic>{'item': <String, dynamic>{}, 'idempotent': false});
    });
    expect(
      () => api.expenseAction('a' * 24, action: 'PAY', expectedVersion: 2, reason: 'paid', idempotencyKey: ExpenseIdempotency.newKey()),
      throwsA(isA<ExpenseApiException>()),
    );
    await api.expenseAction('a' * 24,
        action: 'PAY',
        expectedVersion: 2,
        reason: 'Paid by transfer',
        idempotencyKey: ExpenseIdempotency.newKey(),
        payment: <String, dynamic>{'method': 'BANK_TRANSFER', 'reference': 'TRX-1', 'date': '2025-01-03', 'evidenceDocumentIds': <String>[]});
    expect(body['confirmExternalPayment'], isTrue);
    expect(body['payment']['reference'], 'TRX-1');
    expect(body.containsKey('confirmExternalReversal'), isFalse);
  });

  test('report download keeps server filename and rejects JSON errors', () async {
    final List<String> saved = <String>[];
    final ExpenseManagementApi api = _api((http.Request r) async {
      expect(r.url.queryParameters['type'], 'vendor');
      expect(r.url.queryParameters['format'], 'xlsx');
      expect(r.url.queryParameters['from'], '2025-01-01');
      return http.Response.bytes(<int>[1, 2, 3], 200, headers: <String, String>{
        'content-type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'content-disposition': 'attachment; filename="Vendor-Report.xlsx"',
      });
    }, saved: saved);
    final String name = await api.downloadReport(
        format: 'xlsx', type: 'vendor', filters: <String, String>{'from': '2025-01-01', 'to': '2025-01-31'});
    expect(name, 'Vendor-Report.xlsx');
    expect(saved.single, startsWith('Vendor-Report.xlsx|'));

    final ExpenseManagementApi bad = _api((http.Request r) async =>
        http.Response('{"success":false,"message":"Not ready"}', 200, headers: <String, String>{'content-type': 'application/json'}), saved: saved);
    await expectLater(
      bad.downloadReport(format: 'pdf', type: 'daily', filters: <String, String>{'from': '2025-01-01', 'to': '2025-01-02'}),
      throwsA(isA<ExpenseApiException>()),
    );
    expect(saved.length, 1);
  });

  test('upload validates type and size before any request', () async {
    int calls = 0;
    final ExpenseManagementApi api = _api((http.Request r) async {
      calls++;
      return _ok(<String, dynamic>{});
    });
    await expectLater(
      api.uploadDocument(ExpenseDocumentUpload(bytes: <int>[1], filename: 'x.exe', idempotencyKey: ExpenseIdempotency.newKey())),
      throwsA(isA<ExpenseApiException>()),
    );
    await expectLater(
      api.uploadDocument(ExpenseDocumentUpload(bytes: List<int>.filled(11, 0), filename: 'a.pdf', idempotencyKey: ExpenseIdempotency.newKey()), maxBytes: 10),
      throwsA(isA<ExpenseApiException>()),
    );
    expect(calls, 0);
  });

  test('access ignores wildcard and requires HEAD_OFFICE for policy', () {
    final ExpenseAccess wildcard = ExpenseAccess.fromReadiness(<String, dynamic>{
      'permissions': <String>['*', 'finance.view'],
      'actor': <String, dynamic>{'id': 'u1', 'role': 'HEAD_OFFICE'},
    });
    expect(wildcard.has(ExpensePermissions.view), isFalse);
    expect(wildcard.canManagePolicy, isFalse);
    final ExpenseAccess scoped = ExpenseAccess.fromReadiness(<String, dynamic>{
      'permissions': <String>['expenses.manage_policy'],
      'actor': <String, dynamic>{'id': 'u2', 'role': 'FINANCE_OFFICER'},
    });
    expect(scoped.canManagePolicy, isFalse);
    expect(money(12345678), 'NGN 123,456.78');
    expect(money(null), 'Unavailable');
    expect(amountValidator('0'), isNotNull);
    expect(amountValidator('1250.505'), isNotNull);
    expect(amountValidator('1250.50'), isNull);
  });
}

