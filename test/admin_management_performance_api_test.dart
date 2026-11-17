import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:servicepay_app/admin/admin_management_performance_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manager and report calls carry exact query and admin bearer token',
      () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'Bearer session-1'});
    final List<http.Request> requests = <http.Request>[];
    final api = AdminManagementPerformanceApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': <String, dynamic>{'items': <dynamic>[], 'totalPages': 1}
          }),
          200,
        );
      }),
    );

    await api.managers(role: 'STATE_MANAGER', search: ' Ada ', page: 2);
    await api.report(
      managerId: 'manager/1',
      period: 'CUSTOM',
      from: '2026-05-01',
      to: '2026-05-14',
    );

    expect(requests[0].url.path, '/api/admin/management-performance/managers');
    expect(requests[0].url.queryParameters, {
      'role': 'STATE_MANAGER',
      'search': 'Ada',
      'page': '2',
      'limit': '25',
    });
    expect(requests[1].url.path, '/api/admin/management-performance/report');
    expect(requests[1].url.queryParameters, {
      'managerId': 'manager/1',
      'period': 'CUSTOM',
      'from': '2026-05-01',
      'to': '2026-05-14',
    });
    expect(
        requests.every((request) =>
            request.headers['authorization'] == 'Bearer session-1'),
        isTrue);
  });

  test('exports preserve binary bytes and validate PDF/XLSX content types',
      () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'session'});
    http.Request? request;
    int exportCount = 0;
    final api = AdminManagementPerformanceApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((value) async {
        request = value;
        exportCount++;
        return http.Response.bytes(
          exportCount == 1 ? <int>[0, 1, 2, 255] : <int>[8, 7, 6, 5],
          200,
          headers: <String, String>{
            'content-type': exportCount == 1
                ? 'application/pdf'
                : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'x-report-generated-at': '2026-05-15T10:00:00Z',
          },
        );
      }),
    );
    final AdminManagementPerformanceFile file = await api.export(
      managerId: 'm-9',
      period: 'TODAY',
      from: '2026-05-15',
      to: '2026-05-15',
      format: 'pdf',
    );
    expect(request!.url.path, '/api/admin/management-performance/export');
    expect(request!.url.queryParameters['format'], 'pdf');
    expect(file.bytes, <int>[0, 1, 2, 255]);
    expect(file.contentType, 'application/pdf');
    expect(file.generatedAt, '2026-05-15T10:00:00Z');
    final AdminManagementPerformanceFile workbook = await api.export(
      managerId: 'm-9',
      period: 'TODAY',
      from: '2026-05-15',
      to: '2026-05-15',
      format: 'xlsx',
    );
    expect(workbook.bytes, <int>[8, 7, 6, 5]);
    expect(
      workbook.contentType,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  });

  test('missing session and server 401 are surfaced without leaking requests',
      () async {
    SharedPreferences.setMockInitialValues({});
    int requests = 0;
    final api = AdminManagementPerformanceApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      api.managers(role: 'AGENT'),
      throwsA(isA<AdminManagementPerformanceException>()
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
    expect(requests, 0);

    SharedPreferences.setMockInitialValues({'auth_token': 'expired'});
    final unauthorized = AdminManagementPerformanceApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((_) async =>
          http.Response(jsonEncode({'message': 'Session expired'}), 401)),
    );
    await expectLater(
      unauthorized.report(
        managerId: 'm',
        period: 'TODAY',
        from: '2026-05-15',
        to: '2026-05-15',
      ),
      throwsA(isA<AdminManagementPerformanceException>()
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
  });
}
