import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/customer_export_api.dart';

String _mime(String format) => switch (format) {
      'csv' => 'text/csv; charset=utf-8',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => 'application/pdf',
    };

List<int> _fixture(String format) => switch (format) {
      'csv' => utf8.encode(
          '\uFEFF"Full Name","Phone Number","Email Address"\r\n'),
      'xlsx' => <int>[0x50, 0x4B, 0x03, 0x04, 0x00],
      _ => utf8.encode('%PDF-1.7\n'),
    };

void main() {
  test('customer picker uses configured root, bearer token, and cursor query',
      () async {
    http.Request? captured;
    final CustomerExportApi api = CustomerExportApi(
      baseUrl: 'https://admin-preview.test/api/',
      tokenLoader: () async => 'Bearer staff-secret',
      client: MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'customers': <dynamic>[
              <String, dynamic>{
                'id': 'c-2',
                'fullName': 'Amina Bello',
                'phone': '08000000000',
                'email': 'amina@example.test',
              }
            ],
            'nextCursor': 'c-2',
          }),
          200,
        );
      }),
    );

    final Map<String, dynamic> result =
        await api.customers(query: 'amina', after: 'c-1', limit: 50);

    expect(captured!.url.path, '/api/admin/customer-exports/customers');
    expect(captured!.url.queryParameters, <String, String>{
      'q': 'amina',
      'after': 'c-1',
      'limit': '50',
    });
    expect(captured!.headers['authorization'], 'Bearer staff-secret');
    expect(result['nextCursor'], 'c-2');
  });

  for (final String format in <String>['csv', 'xlsx', 'pdf']) {
    for (final String scope in <String>['all', 'filtered', 'selected']) {
      test('generates $format export for $scope scope', () async {
        http.Request? captured;
        final CustomerExportApi api = CustomerExportApi(
          baseUrl: 'https://admin-preview.test/api',
          tokenLoader: () async => 'staff-secret',
          client: MockClient((http.Request request) async {
            captured = request;
            return http.Response.bytes(
              _fixture(format),
              200,
              headers: <String, String>{'content-type': _mime(format)},
            );
          }),
        );

        final CustomerExportFile file = await api.generate(
          format: format,
          scope: scope,
          query: scope == 'filtered' ? 'kano' : '',
          ids: scope == 'selected' ? <String>['c-1', 'c-2'] : <String>[],
          action: format == 'pdf' ? 'print' : 'download',
        );
        final Map<String, dynamic> body =
            jsonDecode(captured!.body) as Map<String, dynamic>;

        expect(captured!.method, 'POST');
        expect(captured!.url.path, '/api/admin/customer-exports/download');
        expect(captured!.headers['authorization'], 'Bearer staff-secret');
        expect(body['format'], format);
        expect(body['scope'], scope);
        expect(body['query'], scope == 'filtered' ? 'kano' : '');
        expect(body['ids'], scope == 'selected' ? <String>['c-1', 'c-2'] : []);
        expect(file.filename, 'Servicepay-Customers.$format');
        expect(file.bytes, _fixture(format));
      });
    }
  }

  test('does not send request without an authenticated token', () async {
    bool requested = false;
    final CustomerExportApi api = CustomerExportApi(
      tokenLoader: () async => null,
      client: MockClient((http.Request _) async {
        requested = true;
        return http.Response('', 200);
      }),
    );

    await expectLater(
      api.customers(),
      throwsA(isA<CustomerExportException>()
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
    expect(requested, isFalse);
  });

  for (final int status in <int>[400, 403, 429]) {
    test('surfaces an actionable error for HTTP $status', () async {
      final CustomerExportApi api = CustomerExportApi(
        tokenLoader: () async => 'token',
        client: MockClient((http.Request _) async =>
            http.Response('{"message":"Request rejected."}', status)),
      );
      await expectLater(
        api.generate(
          format: 'csv',
          scope: 'selected',
          query: '',
          ids: <String>[],
          action: 'download',
        ),
        throwsA(isA<CustomerExportException>()
            .having((e) => e.statusCode, 'statusCode', status)
            .having((e) => e.message, 'message', 'Request rejected.')),
      );
    });
  }

  test('rejects empty binary response', () async {
    final CustomerExportApi api = CustomerExportApi(
      tokenLoader: () async => 'token',
      client: MockClient((http.Request _) async => http.Response('', 200)),
    );
    await expectLater(
      api.generate(
        format: 'csv',
        scope: 'all',
        query: '',
        ids: <String>[],
        action: 'download',
      ),
      throwsA(isA<CustomerExportException>()),
    );
  });

  test('rejects a 200 HTML login page instead of treating it as an export',
      () async {
    final CustomerExportApi api = CustomerExportApi(
      tokenLoader: () async => 'token',
      client: MockClient((http.Request _) async => http.Response(
            '<html>Sign in</html>',
            200,
            headers: <String, String>{'content-type': 'text/html'},
          )),
    );
    await expectLater(
      api.generate(
        format: 'pdf',
        scope: 'all',
        query: '',
        ids: <String>[],
        action: 'download',
      ),
      throwsA(isA<CustomerExportException>().having(
        (CustomerExportException error) => error.message,
        'message',
        'The server returned an invalid PDF export file.',
      )),
    );
  });

  test('rejects a mismatched format signature', () async {
    final CustomerExportApi api = CustomerExportApi(
      tokenLoader: () async => 'token',
      client: MockClient((http.Request _) async => http.Response.bytes(
            utf8.encode('%PDF-1.7'),
            200,
            headers: <String, String>{'content-type': 'text/csv'},
          )),
    );
    await expectLater(
      api.generate(
        format: 'csv',
        scope: 'all',
        query: '',
        ids: <String>[],
        action: 'download',
      ),
      throwsA(isA<CustomerExportException>()),
    );
  });
}
