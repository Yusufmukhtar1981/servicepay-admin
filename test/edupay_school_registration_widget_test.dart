import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/school/school_registration_screen.dart';
import 'package:servicepay_app/school/edupay_school_api.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

class _FakeSchoolApi extends EduPaySchoolApi {
  _FakeSchoolApi() : super(baseUrl: 'https://test.invalid');
  Map<String, String>? fields;
  PlatformFile? logo;
  List<PlatformFile>? documents;
  @override
  Future<Map<String, dynamic>> applySchool({
    required Map<String, String> fields,
    PlatformFile? logo,
    List<PlatformFile> supportingDocuments = const [],
  }) async {
    this.fields = fields;
    this.logo = logo;
    documents = supportingDocuments;
    return {'success': true, 'application': {'status': 'PENDING_REVIEW'}};
  }
}

void main() {
  testWidgets('school registration exposes staged required details', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SchoolRegistrationScreen()));
    expect(find.text('Register Your School'), findsOneWidget);
    expect(find.text('School type'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'School name'), 'Test School');
    await tester.enterText(find.widgetWithText(TextFormField, 'Registration Number'), 'REG-1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contact Person'), 'Contact');
    await tester.enterText(find.widgetWithText(TextFormField, 'School type'), 'Secondary');
    await tester.enterText(find.widgetWithText(TextFormField, 'School address'), 'Address');
    await tester.enterText(find.widgetWithText(TextFormField, 'State'), 'Lagos');
    await tester.enterText(find.widgetWithText(TextFormField, 'LGA'), 'Ikeja');
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Authorized representative'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Authorized representative'), 'Rep');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'school@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '08000000000');
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Bank name'), findsOneWidget);
    expect(find.text('Add supporting document (0)'), findsOneWidget);
  });

  testWidgets('submits every required field and shows stable success copy', (tester) async {
    final fake = _FakeSchoolApi();
    final logo = PlatformFile(name: 'logo.png', size: 2,
        bytes: Uint8List.fromList([1, 2]));
    final document = PlatformFile(name: 'licence.pdf', size: 2,
        bytes: Uint8List.fromList([3, 4]));
    await tester.pumpWidget(MaterialApp(home: SchoolRegistrationScreen(
      api: fake, initialLogo: logo, initialDocuments: [document])));
    Future<void> fill(String label, String value) async {
      await tester.enterText(find.widgetWithText(TextFormField, label), value);
    }
    await fill('School name', 'Test School');
    await fill('Registration Number', 'REG-1');
    await fill('Contact Person', 'Contact');
    await fill('School type', 'Secondary');
    await fill('School address', 'Address');
    await fill('State', 'Lagos');
    await fill('LGA', 'Ikeja');
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pump();
    await fill('Authorized representative', 'Rep');
    await fill('Email', 'school@example.com');
    await fill('Phone number', '08000000000');
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pump();
    await fill('Password', 'secret1');
    await fill('Bank name', 'Bank');
    await fill('Bank code', '001');
    await fill('Account number', '0123456789');
    await fill('Account name', 'Test School Account');
    await tester.ensureVisible(find.text('Submit application'));
    await tester.tap(find.text('Submit application'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(fake.fields, containsPair('accountName', 'Test School Account'));
    expect(fake.fields, containsPair('registrationNumber', 'REG-1'));
    expect(fake.fields, containsPair('authorizedRepresentative', 'Rep'));
    expect(fake.logo?.name, 'logo.png');
    expect(fake.documents?.single.name, 'licence.pdf');
    expect(find.text('Application Submitted Successfully.'), findsOneWidget);
    expect(find.text('Application Submitted Successfully. Your school registration is being reviewed by Servicepay. You will be notified when it is approved.'), findsOneWidget);
  });
}