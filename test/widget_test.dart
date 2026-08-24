import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:servicepay_app/admin/admin_empowerment_screen.dart';
import 'package:servicepay_app/admin/admin_kyc_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Admin empowerment organization management', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'test-admin-token',
      });
    });

    testWidgets(
      'approves a PENDING organization with an ACTIVE status payload',
      (tester) async {
        final client = RecordingHttpClient(
          organizations: [
            organization('Pending Org', 'PENDING'),
          ],
        );

        await openOrganizationDetails(tester, client);

        await tester.tap(find.text('Approve / Verify'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Approve / Verify').last);
        await tester.pumpAndSettle();

        expect(client.lastPatchPath, '/api/empowerment/organizations/org-1/status');
        expect(client.lastPatchPayload, {'status': 'ACTIVE'});
      },
    );

    testWidgets(
      'rejects a PENDING organization with a REJECTED status payload',
      (tester) async {
        final client = RecordingHttpClient(
          organizations: [
            organization('Pending Org', 'PENDING'),
          ],
        );

        await openOrganizationDetails(tester, client);

        await tester.tap(find.text('Reject').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reject').last);
        await tester.pumpAndSettle();

        expect(client.lastPatchPath, '/api/empowerment/organizations/org-1/status');
        expect(client.lastPatchPayload, {'status': 'REJECTED'});
      },
    );

    testWidgets(
      'suspends an ACTIVE organization with a SUSPENDED status payload',
      (tester) async {
        final client = RecordingHttpClient(
          organizations: [
            organization('Active Org', 'ACTIVE'),
          ],
        );

        await openOrganizationDetails(tester, client);

        await tester.tap(find.text('Suspend'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Suspend').last);
        await tester.pumpAndSettle();

        expect(client.lastPatchPath, '/api/empowerment/organizations/org-1/status');
        expect(client.lastPatchPayload, {'status': 'SUSPENDED'});
      },
    );

    testWidgets(
      'reactivates a SUSPENDED organization with an ACTIVE status payload',
      (tester) async {
        final client = RecordingHttpClient(
          organizations: [
            organization('Suspended Org', 'SUSPENDED'),
          ],
        );

        await openOrganizationDetails(tester, client);

        await tester.tap(find.text('Reactivate'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reactivate').last);
        await tester.pumpAndSettle();

        expect(client.lastPatchPath, '/api/empowerment/organizations/org-1/status');
        expect(client.lastPatchPayload, {'status': 'ACTIVE'});
      },
    );

    testWidgets(
      'lists only ACTIVE organizations in Create Program',
      (tester) async {
        final client = RecordingHttpClient(
          organizations: [
            organization('Active Org', 'ACTIVE'),
            organization('Pending Org', 'PENDING', id: 'org-2'),
            organization('Suspended Org', 'SUSPENDED', id: 'org-3'),
          ],
        );

        await pumpAdminScreen(tester, client);
        await tester.scrollUntilVisible(
          find.text('Create and manage empowerment programs'),
          400,
        );
        await tester.tap(find.text('Create and manage empowerment programs'));
        await tester.pumpAndSettle();

        expect(
          find.text('Only ACTIVE / verified organizations can run programs.'),
          findsOneWidget,
        );

        await tester.tap(
          find.byType(DropdownButtonFormField<Map<String, dynamic>>),
        );
        await tester.pumpAndSettle();

        expect(find.text('Active Org'), findsOneWidget);
        expect(find.text('Pending Org'), findsNothing);
        expect(find.text('Suspended Org'), findsNothing);
      },
    );

    testWidgets(
      'verifies a beneficiary through the protected verification endpoint',
      (tester) async {
        final client = RecordingHttpClient(
          organizations: const [],
          programs: [program()],
          beneficiaries: [beneficiary()],
        );

        await openBeneficiaryDetails(tester, client);

        await tester.tap(find.text('Verify Beneficiary'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Verify Beneficiary').last);
        await tester.pumpAndSettle();

        expect(
          client.lastPatchPath,
          '/api/empowerment/beneficiaries/beneficiary-1/verify',
        );
        expect(
          client.lastPatchPayload,
          {'verificationStatus': 'VERIFIED'},
        );
      },
    );

    testWidgets(
      'hides financial and approval statuses before verification',
      (tester) async {
        final client = RecordingHttpClient(
          organizations: const [],
          programs: [program()],
          beneficiaries: [beneficiary()],
        );

        await openBeneficiaryDetails(tester, client);
        await tester.tap(find.text('Update Application Status'));
        await tester.pumpAndSettle();

        expect(find.text('SUBMITTED'), findsNothing);
        expect(find.text('UNDER REVIEW'), findsOneWidget);
        expect(find.text('APPROVED'), findsNothing);
        expect(find.text('PAYMENT PENDING'), findsNothing);
        expect(find.text('PAID'), findsNothing);
        expect(find.text('FAILED'), findsNothing);
        expect(find.text('REVERSED'), findsNothing);
      },
    );

    testWidgets(
      'does not offer approval before a verified application reaches review',
      (tester) async {
        final client = RecordingHttpClient(
          organizations: const [],
          programs: [program()],
          beneficiaries: [
            beneficiary(
              applicationStatus: 'SUBMITTED',
              verificationStatus: 'VERIFIED',
            ),
          ],
        );

        await openBeneficiaryDetails(tester, client);
        await tester.tap(find.text('Update Application Status'));
        await tester.pumpAndSettle();

        expect(find.text('UNDER REVIEW'), findsOneWidget);
        expect(find.text('APPROVED'), findsNothing);
      },
    );

    testWidgets(
      'offers approval only for a verified application under review',
      (tester) async {
        final client = RecordingHttpClient(
          organizations: const [],
          programs: [program()],
          beneficiaries: [
            beneficiary(
              applicationStatus: 'UNDER_REVIEW',
              verificationStatus: 'VERIFIED',
            ),
          ],
        );

        await openBeneficiaryDetails(tester, client);
        await tester.tap(find.text('Update Application Status'));
        await tester.pumpAndSettle();

        expect(find.text('APPROVED'), findsOneWidget);
      },
    );

    testWidgets(
      'recognizes verified KYC nested on the persisted customer record',
      (tester) async {
        final client = RecordingHttpClient(
          organizations: const [],
          programs: [program()],
          beneficiaries: [
            beneficiary(
              applicationStatus: 'UNDER_REVIEW',
              verificationStatus: 'PENDING',
            )..['user'] = {'kycVerified': true},
          ],
        );

        await openBeneficiaryDetails(tester, client);
        await tester.tap(find.text('Update Application Status'));
        await tester.pumpAndSettle();

        expect(find.text('APPROVED'), findsOneWidget);
      },
    );

    testWidgets(
      'recognizes a verified nested customer KYC status',
      (tester) async {
        final client = RecordingHttpClient(
          organizations: const [],
          programs: [program()],
          beneficiaries: [
            beneficiary(
              applicationStatus: 'UNDER_REVIEW',
              verificationStatus: 'PENDING',
            )..['customer'] = {
                'kyc': {'status': 'VERIFIED'},
              },
          ],
        );

        await openBeneficiaryDetails(tester, client);
        await tester.tap(find.text('Update Application Status'));
        await tester.pumpAndSettle();

        expect(find.text('APPROVED'), findsOneWidget);
      },
    );
  });

  group('Head Office admin KYC review', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'test-admin-token',
        'user_role': 'HEAD_OFFICE',
      });
    });

    testWidgets(
      'searches with an encoded query and renders KYC metadata and details',
      (tester) async {
        final client = KycRecordingHttpClient(
          records: [kycRecord()],
        );

        await pumpKycScreen(tester, client);
        expect(find.text('Jane Customer'), findsOneWidget);
        expect(find.text('08000000000'), findsOneWidget);
        expect(find.text('jane@example.com'), findsOneWidget);
        expect(find.text('NIN: 12345678901'), findsOneWidget);
        expect(find.text('BVN: 10987654321'), findsOneWidget);
        expect(client.lastGetHeaders['authorization'], 'Bearer test-admin-token');

        await tester.enterText(find.byType(TextField), 'Jane Customer & Co');
        await tester.tap(find.widgetWithText(FilledButton, 'Search'));
        await tester.pumpAndSettle();

        expect(client.lastGetUri.queryParameters['search'], 'Jane Customer & Co');
        expect(client.lastGetUri.path, '/api/admin/kyc');

        await tester.tap(find.text('Jane Customer').first);
        await tester.pumpAndSettle();

        expect(find.text('Submitted NIN'), findsOneWidget);
        expect(find.text('Verification method'), findsOneWidget);
        expect(find.text('Document Url'), findsOneWidget);
        expect(find.text('Open'), findsOneWidget);
      },
    );

    testWidgets(
      'manual verification validates both identifiers and sends exact payload',
      (tester) async {
        final client = KycRecordingHttpClient(
          records: [kycRecord()],
          refreshedRecords: [verifiedKycRecord()],
        );

        await pumpKycScreen(tester, client);
        await tester.tap(find.text('Jane Customer'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Manual Verify / Approve'),
          500,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Manual Verify / Approve'));
        await tester.pumpAndSettle();

        expect(client.lastPatchUri.path, '/api/admin/kyc/kyc-1/status');
        expect(
          client.lastPatchPayload,
          {'status': 'VERIFIED', 'manualOverride': true},
        );
        expect(client.lastPatchHeaders['authorization'], 'Bearer test-admin-token');
        expect(client.getCount, greaterThanOrEqualTo(2));
        expect(find.text('MANUAL_ADMIN_OVERRIDE'), findsOneWidget);
        expect(find.text('Head Office Admin'), findsOneWidget);
        expect(find.text('2026-08-24T12:00:00.000Z'), findsOneWidget);
      },
    );

    testWidgets(
      'does not call the server or report success for invalid identifiers',
      (tester) async {
        final client = KycRecordingHttpClient(
          records: [
            kycRecord(
              nin: '1234567890',
            ),
          ],
        );

        await pumpKycScreen(tester, client);
        await tester.tap(find.text('Jane Customer'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Manual Verify / Approve'),
          500,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Manual Verify / Approve'));
        await tester.pumpAndSettle();

        expect(client.patchCount, 0);
        expect(
          find.text(
            'Manual verification requires both NIN and BVN to be exactly 11 digits.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'keeps the detail open and shows an error when the server rejects override',
      (tester) async {
        final client = KycRecordingHttpClient(
          records: [kycRecord()],
          patchStatusCode: 422,
          patchResponse: {
            'success': false,
            'message': 'KYC provider requirements not met.',
          },
        );

        await pumpKycScreen(tester, client);
        await tester.tap(find.text('Jane Customer'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Manual Verify / Approve'),
          500,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Manual Verify / Approve'));
        await tester.pumpAndSettle();

        expect(client.patchCount, 1);
        expect(find.text('KYC provider requirements not met.'), findsOneWidget);
        expect(find.text('Manual Verify / Approve'), findsOneWidget);
      },
    );

    testWidgets(
      'does not report approval when the required server refresh fails',
      (tester) async {
        final client = KycRecordingHttpClient(
          records: [kycRecord()],
          refreshStatusCode: 500,
        );

        await pumpKycScreen(tester, client);
        await tester.tap(find.text('Jane Customer'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Manual Verify / Approve'),
          500,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Manual Verify / Approve'));
        await tester.pumpAndSettle();

        expect(client.patchCount, 1);
        expect(
          find.text(
            'KYC was updated, but the latest server state could not be loaded. Please refresh and confirm it before continuing.',
          ),
          findsOneWidget,
        );
        expect(find.text('Manual Verify / Approve'), findsOneWidget);
      },
    );

    testWidgets(
      'does not report approval when refreshed server data is still pending',
      (tester) async {
        final client = KycRecordingHttpClient(
          records: [kycRecord()],
          refreshedRecords: [kycRecord()],
        );

        await pumpKycScreen(tester, client);
        await tester.tap(find.text('Jane Customer'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Manual Verify / Approve'),
          500,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Manual Verify / Approve'));
        await tester.pumpAndSettle();

        expect(client.patchCount, 1);
        expect(
          find.text(
            'KYC was updated, but the refreshed record does not confirm manual verification. Please refresh and reconcile it before continuing.',
          ),
          findsOneWidget,
        );
        expect(find.text('Manual Verify / Approve'), findsOneWidget);
      },
    );

    testWidgets(
      'submits only one manual override while an approval is in progress',
      (tester) async {
        final client = KycRecordingHttpClient(
          records: [kycRecord()],
          refreshedRecords: [verifiedKycRecord()],
          patchDelay: const Duration(seconds: 1),
        );

        await pumpKycScreen(tester, client);
        await tester.tap(find.text('Jane Customer'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Manual Verify / Approve'),
          500,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Manual Verify / Approve'));
        await tester.pump();
        await tester.tap(
          find.text('Manual Verify / Approve'),
          warnIfMissed: false,
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        expect(client.patchCount, 1);
      },
    );

    testWidgets(
      'does not expose the KYC workflow outside Head Office',
      (tester) async {
        final client = KycRecordingHttpClient(records: [kycRecord()]);

        await tester.pumpWidget(
          MaterialApp(
            home: AdminKycScreen(
              httpClient: client,
              headOfficeOverride: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Head Office access is required for KYC review.'), findsOneWidget);
        expect(find.text('Search customers'), findsNothing);
        expect(find.text('Manual Verify / Approve'), findsNothing);
        expect(client.getCount, 0);
      },
    );
  });
}

Map<String, dynamic> organization(
  String name,
  String status, {
  String id = 'org-1',
}) {
  return {
    '_id': id,
    'name': name,
    'status': status,
  };
}

Map<String, dynamic> program() {
  return {
    '_id': 'program-1',
    'name': 'Youth Grant',
    'status': 'OPEN',
  };
}

Map<String, dynamic> beneficiary({
  String applicationStatus = 'UNDER_REVIEW',
  String verificationStatus = 'PENDING',
}) {
  return {
    '_id': 'beneficiary-1',
    'fullName': 'Pending Beneficiary',
    'phone': '08000000000',
    'applicationStatus': applicationStatus,
    'verificationStatus': verificationStatus,
    'createdAt': '2026-08-24T00:00:00.000Z',
  };
}

Map<String, dynamic> kycRecord({
  String nin = '12345678901',
  String bvn = '10987654321',
}) {
  return {
    '_id': 'kyc-1',
    'fullName': 'Jane Customer',
    'phone': '08000000000',
    'email': 'jane@example.com',
    'status': 'PENDING',
    'nin': nin,
    'bvn': bvn,
    'tier': 'TIER_2',
    'verificationMethod': 'PROVIDER',
    'documentUrl': 'https://example.com/document.pdf',
  };
}

Map<String, dynamic> verifiedKycRecord() {
  return {
    ...kycRecord(),
    'status': 'VERIFIED',
    'verificationMethod': 'MANUAL_ADMIN_OVERRIDE',
    'verifiedBy': 'Head Office Admin',
    'verifiedAt': '2026-08-24T12:00:00.000Z',
  };
}

Future<void> pumpAdminScreen(
  WidgetTester tester,
  RecordingHttpClient client,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AdminEmpowermentScreen(httpClient: client),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpKycScreen(
  WidgetTester tester,
  KycRecordingHttpClient client,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AdminKycScreen(
        httpClient: client,
        headOfficeOverride: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openOrganizationDetails(
  WidgetTester tester,
  RecordingHttpClient client,
) async {
  await pumpAdminScreen(tester, client);
  await tester.scrollUntilVisible(
    find.text('Government, NGO and private organizations'),
    400,
  );
  await tester.tap(find.text('Government, NGO and private organizations'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(client.organizations.first['name'] as String));
  await tester.pumpAndSettle();
}

Future<void> openBeneficiaryDetails(
  WidgetTester tester,
  RecordingHttpClient client,
) async {
  await pumpAdminScreen(tester, client);
  await tester.scrollUntilVisible(
    find.text('Review applications and beneficiaries'),
    400,
  );
  await tester.tap(find.text('Review applications and beneficiaries'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(client.programs.first['name'] as String));
  await tester.pumpAndSettle();
  await tester.tap(find.text(client.beneficiaries.first['fullName'] as String));
  await tester.pumpAndSettle();
}

class RecordingHttpClient extends http.BaseClient {
  RecordingHttpClient({
    required this.organizations,
    this.programs = const [],
    this.beneficiaries = const [],
  });

  final List<Map<String, dynamic>> organizations;
  final List<Map<String, dynamic>> programs;
  final List<Map<String, dynamic>> beneficiaries;
  final List<RecordedRequest> requests = [];

  String? get lastPatchPath {
    for (final request in requests.reversed) {
      if (request.method == 'PATCH') {
        return request.url.path;
      }
    }
    return null;
  }

  Map<String, dynamic>? get lastPatchPayload {
    for (final request in requests.reversed) {
      if (request.method == 'PATCH') {
        return jsonDecode(request.body) as Map<String, dynamic>;
      }
    }
    return null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    requests.add(
      RecordedRequest(
        method: request.method,
        url: request.url,
        body: body,
      ),
    );

    dynamic responseBody;
    var statusCode = 200;

    if (request.url.path.endsWith('/empowerment/organizations')) {
      responseBody = {'organizations': organizations};
    } else if (request.url.path.endsWith('/empowerment/programs')) {
      responseBody = {'programs': programs};
    } else if (request.url.path.contains('/programs/') &&
        request.url.path.endsWith('/beneficiaries')) {
      responseBody = {'beneficiaries': beneficiaries};
    } else if (request.url.path.endsWith('/empowerment/dashboard-summary')) {
      responseBody = {
        'success': true,
        'summary': {},
        'recentActivity': {},
      };
    } else if (request.method == 'PATCH' &&
        request.url.path.contains('/empowerment/organizations/')) {
      responseBody = {
        'success': true,
        'message': 'Status updated successfully.',
      };
    } else if (request.method == 'PATCH' &&
        request.url.path.contains('/empowerment/beneficiaries/')) {
      responseBody = {
        'success': true,
        'message': 'Beneficiary updated successfully.',
      };
    } else {
      statusCode = 404;
      responseBody = {'success': false, 'message': 'Unexpected test request.'};
    }

    final responseBytes = utf8.encode(jsonEncode(responseBody));
    return http.StreamedResponse(
      Stream<List<int>>.value(responseBytes),
      statusCode,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

class RecordedRequest {
  const RecordedRequest({
    required this.method,
    required this.url,
    required this.body,
    this.headers = const {},
  });

  final String method;
  final Uri url;
  final String body;
  final Map<String, String> headers;
}

class KycRecordingHttpClient extends http.BaseClient {
  KycRecordingHttpClient({
    required this.records,
    this.refreshedRecords,
    this.patchStatusCode = 200,
    this.patchResponse,
    this.refreshStatusCode = 200,
    this.patchDelay,
  });

  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>>? refreshedRecords;
  final int patchStatusCode;
  final Map<String, dynamic>? patchResponse;
  final int refreshStatusCode;
  final Duration? patchDelay;
  final List<RecordedRequest> requests = [];
  int getCount = 0;
  int patchCount = 0;

  Uri get lastGetUri {
    return requests.lastWhere((request) => request.method == 'GET').url;
  }

  Map<String, String> get lastGetHeaders {
    final request = requests.lastWhere((item) => item.method == 'GET');
    return {
      for (final entry in request.headers.entries) entry.key.toLowerCase(): entry.value,
    };
  }

  Uri get lastPatchUri {
    return requests.lastWhere((request) => request.method == 'PATCH').url;
  }

  Map<String, dynamic> get lastPatchPayload {
    final request = requests.lastWhere((item) => item.method == 'PATCH');
    return jsonDecode(request.body) as Map<String, dynamic>;
  }

  Map<String, String> get lastPatchHeaders {
    final request = requests.lastWhere((item) => item.method == 'PATCH');
    return {
      for (final entry in request.headers.entries) entry.key.toLowerCase(): entry.value,
    };
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final headers = Map<String, String>.from(request.headers);
    requests.add(
      RecordedRequest(
        method: request.method,
        url: request.url,
        body: body,
        headers: headers,
      ),
    );

    dynamic responseBody;
    var statusCode = 200;
    if (request.method == 'GET' && request.url.path == '/api/admin/kyc') {
      getCount++;
      if (getCount > 1 && refreshStatusCode >= 400) {
        statusCode = refreshStatusCode;
        responseBody = {
          'success': false,
          'message': 'Unable to reload KYC records.',
        };
      } else {
        responseBody = {
          'success': true,
          'applications': getCount > 1 && refreshedRecords != null
              ? refreshedRecords
              : records,
        };
      }
    } else if (request.method == 'PATCH' &&
        request.url.path == '/api/admin/kyc/kyc-1/status') {
      patchCount++;
      if (patchDelay != null) {
        await Future<void>.delayed(patchDelay!);
      }
      statusCode = patchStatusCode;
      responseBody = patchResponse ??
          {
            'success': true,
            'message': 'KYC verified.',
          };
    } else {
      statusCode = 404;
      responseBody = {
        'success': false,
        'message': 'Unexpected KYC request.',
      };
    }

    final responseBytes = utf8.encode(jsonEncode(responseBody));
    return http.StreamedResponse(
      Stream<List<int>>.value(responseBytes),
      statusCode,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}