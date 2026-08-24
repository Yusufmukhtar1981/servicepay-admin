import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:servicepay_app/admin/admin_empowerment_screen.dart';
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
  });

  final String method;
  final Uri url;
  final String body;
}