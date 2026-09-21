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
  setUp(
    () => SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'token',
      'school_auth_token': 'school-token',
      'school_id': 'school-1',
    }),
  );

  test('first-time setup uses academic session and term routes', () async {
    final requests = <http.Request>[];
    final api = EduPaySchoolApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/academic/sessions')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'session': <String, dynamic>{'_id': 'session-1'},
            }),
            201,
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{'success': true}),
          201,
        );
      }),
    );

    await api.createAcademicPortalSession(<String, dynamic>{
      'name': '2026/2027',
      'status': 'ACTIVE',
    });
    await api.createAcademicPortalTerm(<String, dynamic>{
      'name': 'First Term',
      'session': 'session-1',
      'status': 'ACTIVE',
    });

    expect(
      requests.map((request) => '${request.method} ${request.url.path}'),
      <String>[
        'POST /api/edupay/school/academic/sessions',
        'POST /api/edupay/school/academic/terms',
      ],
    );
    expect(jsonDecode(requests[0].body), <String, dynamic>{
      'name': '2026/2027',
      'status': 'ACTIVE',
    });
    expect(jsonDecode(requests[1].body), <String, dynamic>{
      'name': 'First Term',
      'session': 'session-1',
      'status': 'ACTIVE',
    });
  });

  test(
    'loads and resolves canonical parent student links without exposing ids',
    () async {
      final requests = <http.Request>[];
      final api = EduPaySchoolApi(
        baseUrl: 'https://example.test/api',
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'success': true,
                'links': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'childToken': 'child-token',
                    'childName': 'Abba Kano',
                    'className': 'Primary 1',
                    'parentDisplay': 'Parent · ***1234',
                    'linkStatus': 'UNRESOLVED',
                    'candidates': <Map<String, dynamic>>[
                      <String, dynamic>{
                        'candidateToken': 'candidate-token',
                        'studentId': 'ADMIN 001',
                        'fullName': 'Abba Kano',
                        'className': 'Primary 1',
                      },
                    ],
                  },
                ],
                'summary': <String, dynamic>{'unresolved': 1},
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'link': <String, dynamic>{
                'childToken': 'child-token',
                'childName': 'Abba Kano',
                'className': 'Primary 1',
                'parentDisplay': 'Parent · ***1234',
                'linkStatus': 'RESOLVED',
                'candidates': const <dynamic>[],
              },
            }),
            200,
          );
        }),
      );

      final result = await api.academicStudentLinks();
      expect(result.links.single.childName, 'Abba Kano');
      expect(result.links.single.candidates.single.studentId, 'ADMIN 001');
      final resolved = await api.resolveAcademicStudentLink(
        childToken: result.links.single.childToken,
        candidateToken: result.links.single.candidates.single.candidateToken,
      );
      expect(resolved.linkStatus, 'RESOLVED');
      expect(requests.map((r) => '${r.method} ${r.url.path}'), <String>[
        'GET /api/edupay/school/academic/student-links',
        'PATCH /api/edupay/school/academic/student-links/resolve',
      ]);
      expect(jsonDecode(requests[1].body), <String, dynamic>{
        'childToken': 'child-token',
        'candidateToken': 'candidate-token',
      });
      expect(requests[1].body, isNot(contains('_id')));
    },
  );

  test('uses final readiness and explicit payout lifecycle routes', () async {
    final requests = <http.Request>[];
    final api = EduPayApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, dynamic>{'success': true, 'ready': true}),
          200,
        );
      }),
    );
    await api.readiness();
    await api.processSettlement('set-1');
    await api.requerySettlement('set-1');
    await api.saveSettings(<String, dynamic>{
      'schoolCommissionRate': 5,
      'settlementMethod': 'DEDUCT_COMMISSION',
    });
    expect(requests.map((r) => '${r.method} ${r.url.path}'), <String>[
      'GET /api/admin/edupay/readiness',
      'POST /api/admin/edupay/settlements/set-1/process',
      'POST /api/admin/edupay/settlements/set-1/requery',
      'PATCH /api/admin/edupay/settings',
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
          jsonEncode(<String, dynamic>{'success': true}),
          200,
        );
      }),
    );
    await api.verifySettlementAccount(
      'school-1',
      accountId: 'account-1',
      version: 3,
    );
    expect(request.method, 'POST');
    expect(
      request.url.path,
      '/api/admin/edupay/schools/school-1/settlement-account/verify',
    );
    expect(jsonDecode(request.body), <String, dynamic>{
      'accountId': 'account-1',
      'version': 3,
    });
  });

  test(
    'uses current school review, private asset, duty and feature contracts',
    () async {
      final requests = <http.Request>[];
      final api = EduPayApi(
        baseUrl: 'https://example.test/api',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, dynamic>{'success': true}),
            200,
          );
        }),
      );
      await api.schoolAction('school-1', 'SUSPEND', note: 'Policy review');
      await api.schoolDetail('school-1');
      await api.privateSchoolDocuments('school-1');
      await api.schoolRequests();
      await api.schoolRequestDetail('request-1');
      await api.schoolRequestAction(
        'request-1',
        'REJECT',
        rejectionReason: 'Incomplete application',
      );
      await api.eligibleDutyUsers();
      await api.configureDuties(<String, String>{
        'account.manage': 'officer-1',
        'account.verify': 'officer-2',
        'settlement.process': 'officer-3',
      });
      await api.enableFeature('edupay', 'checklist complete');
      expect(requests.map((r) => '${r.method} ${r.url.path}'), <String>[
        'PATCH /api/admin/edupay/schools/school-1',
        'GET /api/admin/edupay/schools/school-1',
        'GET /api/admin/edupay/schools/school-1/private-assets',
        'GET /api/admin/edupay/school-requests',
        'GET /api/admin/edupay/school-requests/request-1',
        'PATCH /api/admin/edupay/school-requests/request-1',
        'GET /api/admin/edupay/duties/eligible-users',
        'PUT /api/admin/edupay/duties',
        'PATCH /api/feature-control/admin/edupay',
      ]);
      expect(jsonDecode(requests[0].body), {
        'action': 'SUSPEND',
        'note': 'Policy review',
      });
      expect(jsonDecode(requests[5].body), {
        'action': 'REJECT',
        'rejectionReason': 'Incomplete application',
      });
      expect(jsonDecode(requests[7].body), {
        'assignments': {
          'account.manage': 'officer-1',
          'account.verify': 'officer-2',
          'settlement.process': 'officer-3',
        },
      });
      expect(jsonDecode(requests[8].body), {
        'enabled': true,
        'reason': 'checklist complete',
        'confirmationText': 'edupay',
      });
    },
  );

  test(
    'school request approval sends representative authority confirmation',
    () async {
      late http.Request request;
      final api = EduPayApi(
        baseUrl: 'https://example.test/api',
        client: MockClient((value) async {
          request = value;
          return http.Response(
            jsonEncode(<String, dynamic>{'success': true}),
            200,
          );
        }),
      );
      await api.schoolRequestAction(
        'request-approve',
        'APPROVE',
        representativeAuthorityConfirmed: true,
      );
      expect(request.method, 'PATCH');
      expect(
        request.url.path,
        '/api/admin/edupay/school-requests/request-approve',
      );
      expect(jsonDecode(request.body), {
        'action': 'APPROVE',
        'representativeAuthorityConfirmed': true,
      });
    },
  );

  test(
    'school application preserves required field names and data URLs',
    () async {
      late http.Request request;
      final api = EduPaySchoolApi(
        baseUrl: 'https://example.test/api',
        client: MockClient((value) async {
          request = value;
          return http.Response(
            jsonEncode(<String, dynamic>{'success': true}),
            200,
          );
        }),
      );
      final payload = <String, dynamic>{
        'schoolType': 'Secondary',
        'state': 'Lagos',
        'lga': 'Ikeja',
        'password': 'not-a-real-secret',
        'bankName': 'Bank',
        'bankCode': '001',
        'accountNumber': '0123456789',
        'accountName': 'School',
        'logo': 'data:image/png;base64,AA==',
        'supportingDocuments': <String>['data:application/pdf;base64,AA=='],
        'authorizedRepresentative': 'Representative',
      };
      await api.request('POST', '/edupay/schools/apply', payload);
      expect(request.url.path, '/api/edupay/schools/apply');
      expect(jsonDecode(request.body), payload);
    },
  );

  test(
    'multipart school application names logo and supporting documents',
    () async {
      late http.Request request;
      final api = EduPaySchoolApi(
        baseUrl: 'https://example.test/api',
        client: MockClient((value) async {
          request = value;
          return http.Response(
            jsonEncode({
              'success': true,
              'application': {'status': 'PENDING_REVIEW'},
            }),
            201,
          );
        }),
      );
      await api.applySchool(
        fields: {
          'name': 'School',
          'registrationNumber': 'REG-1',
          'contactPerson': 'Contact',
          'schoolType': 'Secondary',
          'state': 'Lagos',
          'lga': 'Ikeja',
          'address': 'Address',
          'phone': '08000000000',
          'email': 'a@b.test',
          'password': 'secret',
          'bankName': 'Bank',
          'bankCode': '001',
          'accountNumber': '0123456789',
          'accountName': 'School',
          'authorizedRepresentative': 'Contact',
        },
        logo: PlatformFile(
          name: 'logo.png',
          size: 2,
          bytes: Uint8List.fromList([1, 2]),
        ),
        supportingDocuments: [
          PlatformFile(
            name: 'licence.pdf',
            size: 2,
            bytes: Uint8List.fromList([3, 4]),
          ),
        ],
      );
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      final body = utf8.decode(request.bodyBytes);
      expect(body, contains('name="accountName"'));
      expect(body, contains('name="logo"; filename="logo.png"'));
      expect(
        body,
        contains('name="supportingDocuments"; filename="licence.pdf"'),
      );
    },
  );

  test('school academic chain uses backend keys and GET resources', () async {
    final requests = <http.Request>[];
    final api = EduPaySchoolApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'success': true, 'terms': [], 'classes': [], 'fees': []}),
          200,
        );
      }),
    );
    await api.terms();
    await api.classes();
    await api.fees();
    await api.createTerm({'name': 'Term 1', 'session': 'session-1'});
    await api.updateAcademicSession('session-1', {'status': 'CLOSED'});
    await api.updateAcademicTerm('term-1', {'status': 'ACTIVE'});
    await api.createFee({
      'amount': 100000,
      'session': 'session-1',
      'term': 'term-1',
      'classLevel': 'class-1',
    });
    expect(requests.map((r) => '${r.method} ${r.url.path}'), [
      'GET /api/edupay/school/terms',
      'GET /api/edupay/school/classes',
      'GET /api/edupay/school/fees',
      'POST /api/edupay/school/terms',
      'PATCH /api/edupay/school/academic/sessions/session-1',
      'PATCH /api/edupay/school/academic/terms/term-1',
      'POST /api/edupay/school/fees',
    ]);
    expect(jsonDecode(requests[3].body), {
      'name': 'Term 1',
      'session': 'session-1',
    });
    expect(jsonDecode(requests.last.body), {
      'amount': 100000,
      'session': 'session-1',
      'term': 'term-1',
      'classLevel': 'class-1',
    });
  });

  test('school savings visibility is read-only and tenant-derived', () async {
    final requests = <http.Request>[];
    final api = EduPaySchoolApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((value) async {
        requests.add(value);
        return http.Response(
          jsonEncode({
            'success': true,
            'summary': {'activePlans': 1},
            'plans': [
              {
                'student': 'Student',
                'target': 1000,
                'saved': 250,
                'status': 'ACTIVE',
              },
            ],
            'history': const [],
          }),
          200,
        );
      }),
    );
    final result = await api.savings();
    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/api/edupay/school/savings');
    expect(request.url.queryParameters.containsKey('schoolId'), isFalse);
    expect(result['plans'], isA<List>());
  });

  test(
    'admin savings methods use server-side filters and never expose ids',
    () async {
      final requests = <http.Request>[];
      final api = EduPayApi(
        baseUrl: 'https://example.test/api',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'success': true,
              'summary': {
                'activePlans': 1,
                'totalSaved': 250,
                'completedPlans': 0,
              },
              'plans': [
                {
                  'parent': 'Parent',
                  'student': 'Student',
                  'school': 'School',
                  'target': 1000,
                  'saved': 250,
                  'remaining': 750,
                  'status': 'ACTIVE',
                },
              ],
            }),
            200,
          );
        }),
      );
      final result = await api.adminPlans(
        search: 'Student',
        status: 'ACTIVE',
        dateFrom: '2026-01-01',
        dateTo: '2026-01-31',
      );
      await api.adminTransactions(status: 'COMPLETED');
      expect(result['plans'], isA<List>());
      expect(requests.first.method, 'GET');
      expect(requests.first.url.path, '/api/admin/edupay/plans');
      expect(requests.first.url.queryParameters, {
        'search': 'Student',
        'status': 'ACTIVE',
        'dateFrom': '2026-01-01',
        'dateTo': '2026-01-31',
      });
      expect(requests.every((request) => request.method != 'POST'), isTrue);
      expect(
        requests.every((request) => !request.url.path.contains('/_id')),
        isTrue,
      );
    },
  );

  test(
    'Student Activity Center uses school-scoped activity contracts',
    () async {
      final requests = <http.Request>[];
      final api = EduPaySchoolApi(
        baseUrl: 'https://example.test/api',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'success': true}), 200);
        }),
      );
      await api.activityCenter('dashboard');
      await api.activityAction('attendance', {
        'studentId': 'student-1',
        'status': 'Present',
      });
      await api.bulkAttendance({
        'date': '2026-01-12',
        'status': 'Present',
        'classId': 'class-1',
      });
      await api.updateActivity('assignment-1', {'title': 'Updated'});
      await api.publishResult('result-1');
      await api.createGuardianInvite('student-1');
      await api.verifyGuardian({
        'studentId': 'student-1',
        'guardianId': 'guardian-1',
      });
      expect(requests.map((r) => '${r.method} ${r.url.path}'), [
        'GET /api/edupay/activity-center/school/records',
        'POST /api/edupay/activity-center/school/attendance',
        'POST /api/edupay/activity-center/school/attendance/bulk',
        'PATCH /api/edupay/activity-center/school/records/assignment-1',
        'POST /api/edupay/activity-center/school/records/result-1/publish',
        'POST /api/edupay/activity-center/school/guardians/invites',
        'POST /api/edupay/activity-center/school/guardians/verify',
      ]);
      expect(requests[0].url.queryParameters['type'], 'dashboard');
      expect(jsonDecode(requests[1].body), {
        'studentId': 'student-1',
        'status': 'Present',
      });
    },
  );

  test(
    'Activity Center preserves backend forbidden errors for role-denied writes',
    () async {
      final api = EduPaySchoolApi(
        baseUrl: 'https://example.test/api',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'success': false, 'message': 'Forbidden'}),
            403,
          ),
        ),
      );
      expect(
        () => api.activityAction('results', {'studentId': 'student-1'}),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Forbidden'),
          ),
        ),
      );
    },
  );

  test('academic current actions send ACTIVE and isCurrent', () async {
    final requests = <http.Request>[];
    final api = EduPaySchoolApi(
      baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );
    await api.updateAcademicSession('session-1', {
      'status': 'ACTIVE',
      'isCurrent': true,
    });
    await api.updateAcademicTerm('term-1', {
      'status': 'ACTIVE',
      'isCurrent': true,
    });
    expect(jsonDecode(requests[0].body), {
      'status': 'ACTIVE',
      'isCurrent': true,
    });
    expect(jsonDecode(requests[1].body), {
      'status': 'ACTIVE',
      'isCurrent': true,
    });
  });

  test(
    'admin fee approval and rejection use audited lifecycle route',
    () async {
      final requests = <http.Request>[];
      final api = EduPayApi(
        baseUrl: 'https://example.test/api',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'success': true}), 200);
        }),
      );
      await api.approveFee('fee-1');
      await api.rejectFee(
        'fee-2',
        'Amount does not match the official circular.',
      );
      expect(requests.map((r) => '${r.method} ${r.url.path}'), [
        'PATCH /api/admin/edupay/fees/fee-1',
        'PATCH /api/admin/edupay/fees/fee-2',
      ]);
      expect(jsonDecode(requests[0].body), {'action': 'APPROVE'});
      expect(jsonDecode(requests[1].body), {
        'action': 'REJECT',
        'note': 'Amount does not match the official circular.',
      });
    },
  );
}
