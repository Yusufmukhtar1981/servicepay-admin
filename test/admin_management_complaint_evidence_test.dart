import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/admin_management_complaint_evidence.dart';

void main() {
  testWidgets('manager evidence shows actual category and reporting manager',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AdminManagementComplaintEvidence(ticket: {
      'managementIssueCategory': 'DEBIT_NO_SERVICE',
      'createdBy': {'fullName': 'Synthetic Manager', 'role': 'AGENT'},
      'managementAttachments': <Map<String, dynamic>>[],
    }))));
    expect(find.text('Management customer complaint'), findsOneWidget);
    expect(find.text('DEBIT NO SERVICE'), findsOneWidget);
    expect(find.textContaining('Synthetic Manager'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('legacy tickets remain unchanged and arbitrary URLs are ignored',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AdminManagementComplaintEvidence(ticket: {}))));
    expect(find.text('Management customer complaint'), findsNothing);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AdminManagementComplaintEvidence(ticket: {
      'managementIssueCategory': 'OTHER',
      'managementAttachments': [
        {'name': 'unsafe.svg', 'dataUrl': 'https://external.invalid/image.svg'}
      ],
    }))));
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
