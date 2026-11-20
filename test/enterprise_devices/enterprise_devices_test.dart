import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepay_app/admin/enterprise_devices/enterprise_devices_api.dart';
import 'package:servicepay_app/admin/enterprise_devices/enterprise_devices_screen.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'Bearer abc',
    }),
  );

  test('navigation and action access', () {
    bool view(String r, Set<String> p) =>
        canAccessEnterpriseDevicesNavigation(role: r, permissions: p);
    bool manage(String r, Set<String> p) =>
        canManageEnterpriseDevices(role: r, permissions: p);
    bool enroll(String r, Set<String> p) =>
        canEnrollEnterpriseDevices(role: r, permissions: p);
    expect(view('HEAD_OFFICE', <String>{}), isTrue);
    expect(manage('HEAD_OFFICE', <String>{}), isTrue);
    expect(enroll('HEAD_OFFICE', <String>{}), isTrue);
    expect(view('STAFF', <String>{}), isFalse);
    expect(view('STAFF', <String>{'*'}), isFalse);
    expect(view('STAFF', <String>{'enterprise.devices.manage'}), isFalse);
    expect(manage('STAFF', <String>{'enterprise.devices.manage'}), isFalse);
    expect(view('STAFF', <String>{'enterprise.devices.view'}), isTrue);
    expect(manage('STAFF', <String>{'enterprise.devices.view'}), isFalse);
    expect(enroll('STAFF', <String>{'enterprise.devices.view'}), isFalse);
    const Set<String> vm = <String>{
      'enterprise.devices.view',
      'enterprise.devices.manage',
    };
    expect(manage('STAFF', vm), isTrue);
    expect(enroll('STAFF', vm), isFalse);
    expect(
      enroll('STAFF', <String>{
        'enterprise.devices.view',
        'enterprise.devices.enroll',
      }),
      isTrue,
    );
  });

  test('client sends bearer token and unwraps data', () async {
    late http.Request seen;
    final api = EnterpriseDevicesApi(
      baseUrl: 'https://x/api/admin/enterprise-devices',
      client: MockClient((http.Request r) async {
        seen = r;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'devices': [], 'total': 0, 'page': 1, 'pages': 1},
          }),
          200,
        );
      }),
    );
    final data = await api.search(q: 'tec', status: 'AVAILABLE');
    expect(seen.headers['Authorization'], 'Bearer abc');
    expect(seen.url.path, '/api/admin/enterprise-devices/search');
    expect(jsonDecode(seen.body)['status'], 'AVAILABLE');
    expect(data['total'], 0);
  });

  test('503 maps to provisioning-required', () async {
    final api = EnterpriseDevicesApi(
      baseUrl: 'https://x',
      client: MockClient((_) async => http.Response('', 503)),
    );
    expect(
      api.overview(),
      throwsA(
        isA<EnterpriseDevicesException>().having(
          (e) => e.provisioningRequired,
          'prov',
          isTrue,
        ),
      ),
    );
  });

  test('ASSIGNED status is rejected client-side', () {
    final api = EnterpriseDevicesApi(
      baseUrl: 'https://x',
      client: MockClient((_) async => http.Response('', 500)),
    );
    expect(
      () => api.setStatus(
        '1',
        status: 'ASSIGNED',
        expectedVersion: 1,
        reason: 'abcde',
      ),
      throwsA(isA<EnterpriseDevicesException>()),
    );
  });

  test('missing session fails without request', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    var called = false;
    final api = EnterpriseDevicesApi(
      baseUrl: 'https://x',
      client: MockClient((_) async {
        called = true;
        return http.Response('', 200);
      }),
    );
    await expectLater(
      api.overview(),
      throwsA(isA<EnterpriseDevicesException>()),
    );
    expect(called, isFalse);
  });

  test('request id is a v4 UUID', () {
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(newEnterpriseRequestId()),
      isTrue,
    );
  });

  testWidgets('overview shows provisioning message on 503', (
    WidgetTester t,
  ) async {
    final api = EnterpriseDevicesApi(
      baseUrl: 'https://x',
      client: MockClient((_) async => http.Response('', 503)),
    );
    await t.pumpWidget(
      MaterialApp(home: EnterpriseDevicesScreen(canManage: true, api: api)),
    );
    await t.pumpAndSettle();
    expect(find.text('Provisioning required'), findsOneWidget);
    expect(find.text('SERVICEPAY ENTERPRISE DEVICES'), findsOneWidget);
  });

  testWidgets('register validates required fields', (WidgetTester t) async {
    var posts = 0;
    final api = EnterpriseDevicesApi(
      baseUrl: 'https://x',
      client: MockClient((r) async {
        if (r.method == 'POST') posts++;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'stats': {}},
          }),
          200,
        );
      }),
    );
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(home: EnterpriseDevicesScreen(canManage: true, api: api)),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Register').first);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ed-reg-imei1')), '123');
    await t.ensureVisible(find.byKey(const Key('ed-reg-submit')));
    await t.tap(find.byKey(const Key('ed-reg-submit')));
    await t.pumpAndSettle();
    expect(find.text('IMEI must be 15 digits'), findsOneWidget);
    expect(posts, 0);
  });

  testWidgets('enroll controls follow enroll access, not manage', (
    WidgetTester t,
  ) async {
    final api = EnterpriseDevicesApi(
      baseUrl: 'https://x',
      client: MockClient((http.Request r) async {
        final Map<String, dynamic> data = r.url.path.endsWith('/search')
            ? {
                'devices': [
                  {
                    '_id': 'd1',
                    'deviceId': 'SPD-0001',
                    'status': 'AVAILABLE',
                    'imei1': '***********1234',
                    'serialNumber': '****89',
                    'version': 2,
                  },
                ],
                'total': 1,
                'page': 1,
                'pages': 1,
              }
            : r.url.path.endsWith('/d1')
                ? {
                    'device': {
                      '_id': 'd1',
                      'deviceId': 'SPD-0001',
                      'status': 'AVAILABLE',
                      'version': 2,
                      'companion': {'enrolled': true, 'revoked': false},
                    },
                    'assignments': [
                      {
                        'staff': {'name': 'Amaka Obi', 'role': 'STAFF'},
                        'assignedBy': 'Head Office',
                        'reason': 'Field',
                        'startedAt': '2025-01-02T10:00:00Z',
                        'endedAt': null,
                      },
                    ],
                    'audit': [
                      {
                        'actor': 'Ibrahim Musa',
                        'action': 'DEVICE_REGISTERED',
                        'reason': 'New stock',
                        'metadata': {'state': 'Kano'},
                        'createdAt': '2025-01-01T09:00:00Z',
                      },
                    ],
                  }
                : {'stats': {}};
        return http.Response(jsonEncode({'success': true, 'data': data}), 200);
      }),
    );
    t.view.physicalSize = const Size(1400, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: EnterpriseDevicesScreen(
          canManage: true,
          canEnroll: false,
          api: api,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('All Devices').first);
    await t.pumpAndSettle();
    await t.tap(find.text('SPD-0001'));
    await t.pumpAndSettle();
    expect(find.text('Assign'), findsOneWidget);
    expect(find.byKey(const Key('ed-enroll')), findsNothing);
    expect(find.byKey(const Key('ed-revoke')), findsNothing);
    expect(find.text('DEVICE_REGISTERED'), findsOneWidget);
    expect(find.text('By Ibrahim Musa'), findsOneWidget);
    expect(find.textContaining('Amaka Obi (STAFF)'), findsOneWidget);
    expect(find.text('Assigned by Head Office'), findsOneWidget);
  });

  testWidgets(
      '390px mobile: list filters and register form lay out without overflow',
      (WidgetTester t) async {
    final api = EnterpriseDevicesApi(
      baseUrl: 'https://x',
      client: MockClient((http.Request r) async {
        final Object data = r.url.path.endsWith('/search')
            ? {
                'devices': [
                  {
                    '_id': 'd1',
                    'deviceId': 'SPD-0001',
                    'manufacturer': 'Samsung',
                    'model': 'Galaxy A15 5G Enterprise Edition',
                    'status': 'LOST_STOLEN',
                    'imei1': '***********1234',
                    'serialNumber': '****89',
                    'department': 'Field Operations and Collections',
                    'assignedStaff': {
                      '_id': 's1',
                      'name': 'Oluwaseun Adebayo-Williams',
                      'role': 'STAFF'
                    },
                  }
                ],
                'total': 1,
                'page': 1,
                'pages': 1,
              }
            : {'stats': {}};
        return http.Response(jsonEncode({'success': true, 'data': data}), 200);
      }),
    );
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
        MaterialApp(home: EnterpriseDevicesScreen(canManage: true, api: api)));
    await t.pumpAndSettle();

    // Narrow layout uses the horizontal section tabs.
    await t.tap(find.widgetWithText(ChoiceChip, 'All Devices'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ed-search')), findsOneWidget);
    expect(find.text('Manufacturer'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    await t.drag(find.byType(ListView).last, const Offset(0, -300));
    await t.pumpAndSettle();
    expect(find.textContaining('SPD-0001'), findsWidgets);

    await t.dragUntilVisible(find.widgetWithText(ChoiceChip, 'Register'),
        find.byType(ListView).first, const Offset(-120, 0));
    await t.tap(find.widgetWithText(ChoiceChip, 'Register'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ed-reg-imei1')), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('ed-reg-submit')));
    await t.tap(find.byKey(const Key('ed-reg-submit')));
    await t.pumpAndSettle();
    expect(find.text('Required'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
