import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/edupay_api.dart';
import 'package:servicepay_app/school/edupay_school_api.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_token': 'token',
      }));

  test('uses final readiness and explicit payout lifecycle routes', () async {
    final requests = <http.Request>[];
    final api = EduPayApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
            jsonEncode(<String, dynamic>{'success': true, 'ready': true}), 200);
      }),
    );
    await api.readiness();
    await api.processSettlement('set-1');
    await api.requerySettlement('set-1');
    expect(requests.map((r) => '${r.method} ${r.url.path}'), <String>[
      'GET /api/admin/edupay/readiness',
      'POST /api/admin/edupay/settlements/set-1/process',
      'POST /api/admin/edupay/settlements/set-1/requery',
    ]);
    expect(requests[1].url.path, isNot(contains('confirm')));
  });

  test('uses versioned settlement-account verification contract', () async {
    late http.Request request;
    final api = EduPayApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((value) async {
        request = value;
        return http.Response(
            jsonEncode(<String, dynamic>{'success': true}), 200);
      }),
    );
    await api.verifySettlementAccount('school-1',
        accountId: 'account-1', version: 3);
    expect(request.method, 'POST');
    expect(request.url.path,
        '/api/admin/edupay/schools/school-1/settlement-account/verify');
    expect(jsonDecode(request.body),
        <String, dynamic>{'accountId': 'account-1', 'version': 3});
  });

  test('uses current school review, private asset, duty and feature contracts',
      () async {
    final requests = <http.Request>[];
    final api = EduPayApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode(<String, dynamic>{'success': true}), 200);
      }),
    );
    await api.schoolAction('school-1', 'SUSPEND', note: 'Policy review');
    await api.schoolDetail('school-1');
    await api.privateSchoolDocuments('school-1');
    await api.eligibleDutyUsers();
    await api.enableFeature('edupay', 'checklist complete');
    expect(requests.map((r) => '${r.method} ${r.url.path}'), <String>[
      'PATCH /api/admin/edupay/schools/school-1',
      'GET /api/admin/edupay/schools/school-1',
      'GET /api/admin/edupay/schools/school-1/private-assets',
      'GET /api/admin/edupay/duties/eligible-users',
      'PATCH /api/feature-control/admin/edupay',
    ]);
    expect(jsonDecode(requests[0].body),
        {'action': 'SUSPEND', 'note': 'Policy review'});
    expect(jsonDecode(requests[4].body),
        {'enabled': true, 'reason': 'checklist complete'});
  });

  test('school application preserves required field names and data URLs', () async {
    late http.Request request;
    final api = EduPaySchoolApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((value) async {
        request = value;
        return http.Response(jsonEncode(<String, dynamic>{'success': true}), 200);
      }),
    );
    final payload = <String, dynamic>{
      'schoolType': 'Secondary', 'state': 'Lagos', 'lga': 'Ikeja',
      'password': 'not-a-real-secret', 'bankName': 'Bank', 'bankCode': '001',
      'accountNumber': '0123456789', 'accountName': 'School',
      'logo': 'data:image/png;base64,AA==',
      'supportingDocuments': <String>['data:application/pdf;base64,AA=='],
      'authorizedRepresentative': 'Representative',
    };
    await api.request('POST', '/edupay/schools/apply', payload);
    expect(request.url.path, '/api/edupay/schools/apply');
    expect(jsonDecode(request.body), payload);
  });

  test('multipart school application names logo and supporting documents',
      () async {
    late http.Request request;
    final api = EduPaySchoolApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((value) async {
        request = value;
        return http.Response(jsonEncode({'success': true,
          'application': {'status': 'PENDING_REVIEW'}}), 201);
      }),
    );
    await api.applySchool(fields: {
      'name': 'School', 'registrationNumber': 'REG-1', 'contactPerson': 'Contact',
      'schoolType': 'Secondary', 'state': 'Lagos', 'lga': 'Ikeja',
      'address': 'Address', 'phone': '08000000000', 'email': 'a@b.test',
      'password': 'secret', 'bankName': 'Bank', 'bankCode': '001',
      'accountNumber': '0123456789', 'accountName': 'School',
      'authorizedRepresentative': 'Contact',
    }, logo: PlatformFile(name: 'logo.png', size: 2, bytes: Uint8List.fromList([1, 2])),
      supportingDocuments: [PlatformFile(name: 'licence.pdf', size: 2,
        bytes: Uint8List.fromList([3, 4]))]);
    expect(request.headers['content-type'], startsWith('multipart/form-data; boundary='));
    final body = utf8.decode(request.bodyBytes);
    expect(body, contains('name="accountName"'));
    expect(body, contains('name="logo"; filename="logo.png"'));
    expect(body, contains('name="supportingDocuments"; filename="licence.pdf"'));
  });

  test('school academic chain uses backend keys and GET resources', () async {
    final requests = <http.Request>[];
    final api = EduPaySchoolApi(baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'success': true, 'terms': [], 'classes': [], 'fees': []}), 200);
      }));
    await api.terms();
    await api.classes();
    await api.fees();
    await api.createTerm({'name': 'Term 1', 'session': 'session-1'});
    expect(requests.map((r) => '${r.method} ${r.url.path}'), [
      'GET /api/edupay/school/terms', 'GET /api/edupay/school/classes',
      'GET /api/edupay/school/fees', 'POST /api/edupay/school/terms']);
    expect(jsonDecode(requests.last.body), {'name': 'Term 1', 'session': 'session-1'});
  });
}
