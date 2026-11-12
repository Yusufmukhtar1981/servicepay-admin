import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/customer_intelligence_api.dart';
import 'package:servicepay_app/admin/customer_intelligence_screen.dart';

void main() {
  group('CustomerIntelligenceApi', () {
    test('sends authenticated customer filters to documented endpoint',
        () async {
      Uri? requested;
      String? auth;
      final client = MockClient((request) async {
        requested = request.url;
        auth = request.headers['Authorization'];
        return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'items': [],
                'pagination': {'page': 1, 'limit': 20, 'total': 0},
                'summary': {'customers': 0}
              }
            }),
            200);
      });
      final api = CustomerIntelligenceApi(
        client: client,
        baseUrl: 'https://unit.test/api/',
        tokenLoader: () async => 'Bearer test-token',
      );
      final result = await api.customers({'q': 'Ada', 'category': 'FREQUENT'});
      expect(requested!.path, '/api/admin/customer-intelligence/customers');
      expect(requested!.queryParameters['q'], 'Ada');
      expect(requested!.queryParameters['category'], 'FREQUENT');
      expect(auth, 'Bearer test-token');
      expect(result['pagination']['total'], 0);
      client.close();
    });

    test('validates contact-only export payload and returns safe filename',
        () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/admin/customer-intelligence/export');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['allFiltered'], isTrue);
        expect(body['format'], 'csv');
        return http.Response.bytes(
          utf8.encode(
              'Full Name,Phone Number,Email Address\nAda,0800,a@test.ng'),
          200,
          headers: {
            'content-type': 'text/csv; charset=utf-8',
            'content-disposition': 'attachment; filename="contacts.csv"',
          },
        );
      });
      final api = CustomerIntelligenceApi(
          client: client,
          baseUrl: 'https://unit.test/api',
          tokenLoader: () async => 'token');
      final file = await api.export(
        filters: {'range': '30d'},
        ids: const [],
        allFiltered: true,
        format: 'csv',
        action: 'download',
      );
      expect(file.filename, 'contacts.csv');
      expect(file.format, 'csv');
      expect(file.bytes, isNotEmpty);
      client.close();
    });

    test('campaign preview never requests dispatch', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.url.path,
            '/api/admin/customer-intelligence/campaign-preview');
        expect(body['purpose'], 'WELCOME');
        expect(body.containsKey('allFiltered'), isTrue);
        return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'purpose': 'WELCOME',
                'message': 'Draft',
                'selectedCount': 3,
                'dispatchEnabled': false,
                'warning': 'Preview only',
                'excludedOptOuts': null
              }
            }),
            200);
      });
      final api = CustomerIntelligenceApi(
          client: client,
          baseUrl: 'https://unit.test/api',
          tokenLoader: () async => 'token');
      final preview = await api.campaignPreview(
        filters: const {},
        ids: const [],
        allFiltered: true,
        purpose: 'WELCOME',
        message: 'Draft',
      );
      expect(preview['dispatchEnabled'], isFalse);
      expect(preview['excludedOptOuts'], isNull);
      client.close();
    });

    test('surfaces API authorization errors', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({'success': false, 'message': 'Customer access denied'}),
          403));
      final api = CustomerIntelligenceApi(
        client: client,
        baseUrl: 'https://unit.test/api',
        tokenLoader: () async => 'token',
      );
      await expectLater(
        api.customers(const {}),
        throwsA(isA<CustomerIntelligenceException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', 'Customer access denied')),
      );
      client.close();
    });
  });

  testWidgets('renders distinct categories, overlay tabs, and safe scope',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'items': [],
              'pagination': {
                'page': 1,
                'limit': 20,
                'total': 0,
                'totalPages': 0
              },
              'summary': {
                'customers': 0,
                'active': 0,
                'retained': 0,
                'retentionRate': 0,
                'reactivated': 0,
                'frequent': 0,
                'regular': 0,
                'occasional': 0,
                'declining': 0,
                'inactive': 0,
                'never': 0,
                'newCustomers': 0,
                'previousActive': 0
              },
              'topCount': [],
              'topVolume': [],
              'trend': [],
              'settings': {
                'frequentMin': 10,
                'regularMin': 4,
                'activityDays': 30,
                'inactiveDays': 60,
                'newDays': 30
              },
              'capabilities': {
                'canExport': false,
                'canConfigure': false,
                'canPrepareCampaign': false
              },
              'definitions': {}
            }
          }),
          200,
        ));
    final api = CustomerIntelligenceApi(
      client: client,
      baseUrl: 'https://unit.test/api',
      tokenLoader: () async => 'test',
    );
    await tester.pumpWidget(MaterialApp(
      home: CustomerIntelligenceScreen(
        api: api,
        access: const AdminAccess(role: 'SUPPORT', permissions: {}),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Frequent'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Frequent'), findsOneWidget);
    expect(find.text('Regular'), findsOneWidget);
    expect(find.text('Occasional'), findsOneWidget);
    expect(find.text('Declining'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('Never'), findsOneWidget);
    expect(find.text('New customers'), findsOneWidget);
    expect(find.text('Top count'), findsOneWidget);
    expect(find.text('Top volume'), findsOneWidget);
    expect(find.textContaining('NO FINANCIAL AUTHORITY'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('No customers match these filters.'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No customers match these filters.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('exports selected visible IDs with filters that produced list',
      (tester) async {
    Map<String, dynamic>? exportBody;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        exportBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(
              'Full Name,Phone Number,Email Address\nAda,0800,a@test.ng'),
          200,
          headers: {
            'content-type': 'text/csv',
            'content-disposition': 'attachment; filename="contacts.csv"',
          },
        );
      }
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'items': [
              {
                '_id': 'cust-a',
                'fullName': 'Ada North',
                'phone': '0800',
                'email': 'ada@example.ng',
                'state': 'Lagos',
                'lga': 'Ikeja',
                'category': 'REGULAR',
                'recentCount': 2,
                'successful': {'count': 2, 'value': 1500},
              }
            ],
            'pagination': {'page': 1, 'limit': 20, 'total': 1, 'totalPages': 1},
            'summary': {
              'customers': 1,
              'active': 1,
              'retained': 0,
              'retentionRate': 0,
              'reactivated': 0,
              'frequent': 0,
              'regular': 1,
              'occasional': 0,
              'declining': 0,
              'inactive': 0,
              'never': 0,
              'newCustomers': 0,
              'newRegistrations': 0,
              'previousActive': 0,
            },
            'topCount': [],
            'topVolume': [],
            'trend': [],
            'settings': {},
            'definitions': {},
            'capabilities': {
              'canExport': true,
              'canConfigure': false,
              'canPrepareCampaign': false,
            },
          }
        }),
        200,
      );
    });
    final api = CustomerIntelligenceApi(
      client: client,
      baseUrl: 'https://unit.test/api',
      tokenLoader: () async => 'token',
    );
    await tester.pumpWidget(MaterialApp(
      home: CustomerIntelligenceScreen(
        api: api,
        access: const AdminAccess(role: 'SUPPORT', permissions: {}),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Ada North'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.byType(Checkbox).first,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    final searchField = find.byType(TextField).first;
    await tester.ensureVisible(searchField);
    await tester.enterText(searchField, 'not applied');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('CSV contacts'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('CSV contacts'));
    await tester.pumpAndSettle();

    expect(exportBody?['ids'], ['cust-a']);
    expect(exportBody?['allFiltered'], isNull);
    expect((exportBody?['filters'] as Map)['q'], '');
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });
}
