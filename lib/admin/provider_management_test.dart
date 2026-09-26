// ignore_for_file: depend_on_referenced_packages, invalid_use_of_visible_for_testing_member

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main_navigation.dart';
import 'provider_management_api.dart';
import 'provider_management_screen.dart';

Map<String, dynamic> _provider({
  required String key,
  required bool enabled,
  required bool available,
  String? reason,
}) =>
    <String, dynamic>{
      'provider': key,
      'enabled': enabled,
      'available': available,
      if (reason != null) 'reason': reason,
    };

Map<String, dynamic> _service({
  required String name,
  String? primary = 'NELLOBYTES',
  String? fallback,
  String? current = 'NELLOBYTES',
  bool fallbackSupported = false,
  List<Map<String, dynamic>>? providers,
}) =>
    <String, dynamic>{
      'service': name,
      'primaryProvider': primary,
      'fallbackProvider': fallback,
      'currentProvider': current,
      'fallbackSupported': fallbackSupported,
      'providers': providers ??
          <Map<String, dynamic>>[
            _provider(key: 'NELLOBYTES', enabled: true, available: true),
            _provider(
              key: 'TELECOM_ABODE',
              enabled: false,
              available: false,
              reason: 'Telecom Abode service is not verified.',
            ),
          ],
      'updatedAt': '2025-01-02T03:04:05Z',
      'updatedBy': 'Head Office',
    };

List<Map<String, dynamic>> _allFourServices() => <Map<String, dynamic>>[
      _service(
        name: 'AIRTIME',
        primary: 'CLUBKONNECT',
        current: 'CLUBKONNECT',
        fallbackSupported: false,
        providers: <Map<String, dynamic>>[
          _provider(key: 'CLUBKONNECT', enabled: true, available: true),
          _provider(
            key: 'TELECOM_ABODE',
            enabled: false,
            available: false,
            reason: 'Telecom Abode service is not verified.',
          ),
        ],
      ),
      _service(
        name: 'DATA',
        primary: 'CLUBKONNECT',
        current: 'CLUBKONNECT',
        fallbackSupported: false,
        providers: <Map<String, dynamic>>[
          _provider(key: 'CLUBKONNECT', enabled: true, available: true),
          _provider(
            key: 'TELECOM_ABODE',
            enabled: false,
            available: false,
            reason: 'Telecom Abode service is not verified.',
          ),
        ],
      ),
      _service(name: 'ELECTRICITY', fallbackSupported: false),
      _service(
        name: 'CABLE',
        primary: null,
        current: null,
        providers: <Map<String, dynamic>>[
          _provider(
            key: 'NELLOBYTES',
            enabled: false,
            available: false,
            reason: 'No cable purchase route is configured.',
          ),
          _provider(
            key: 'TELECOM_ABODE',
            enabled: false,
            available: false,
            reason: 'Cable service is not verified.',
          ),
        ],
      ),
    ];

void main() {
  const String endpoint =
      'https://api.servicepay.ng/api/admin/fintech-operations/provider-management';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'test-session-token',
    });
  });

  test('GET parses four service items in canonical order', () async {
    late http.Request request;
    final ProviderManagementApi api = ProviderManagementApi(
      client: MockClient((http.Request incoming) async {
        request = incoming;
        final List<Map<String, dynamic>> unordered =
            _allFourServices().reversed.toList();
        return http.Response(jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{'items': unordered},
        }), 200);
      }),
    );

    final List<ProviderService> services = await api.loadServices();
    expect(request.url.toString(), endpoint);
    expect(request.headers['authorization'], 'Bearer test-session-token');
    expect(services.map((ProviderService item) => item.service),
        <String>['AIRTIME', 'DATA', 'ELECTRICITY', 'CABLE']);
    expect(services.first.providers.first['provider'], 'CLUBKONNECT');
    expect(services.first.configurationReported, isTrue);
    expect(services.first.primaryProvider, 'CLUBKONNECT');
    expect(services.first.currentProvider, 'CLUBKONNECT');
    expect(services[1].fallbackSupported, isFalse);
  });

  test('unreturned services are explicit and never fabricated as inactive', () async {
    final ProviderManagementApi api = ProviderManagementApi(
      client: MockClient((http.Request _) async => http.Response(
        jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{
            'items': <Map<String, dynamic>>[
              _service(name: 'ELECTRICITY'),
              _service(
                name: 'CABLE',
                primary: null,
                current: null,
                providers: <Map<String, dynamic>>[],
              ),
            ],
          },
        }),
        200,
      )),
    );

    final List<ProviderService> services = await api.loadServices();
    expect(services.first.service, 'AIRTIME');
    expect(services.first.configurationReported, isFalse);
    expect(services.first.currentProvider, isNull);
    expect(services.first.providers.first.containsKey('enabled'), isFalse);
    expect(services[1].configurationReported, isFalse);
  });

  test('PATCH uses the collection path and includes service in the body',
      () async {
    late http.Request request;
    final ProviderManagementApi api = ProviderManagementApi(
      client: MockClient((http.Request incoming) async {
        request = incoming;
        return http.Response('{"success":true}', 200);
      }),
    );

    await api.updateProvider(
      service: 'AIRTIME',
      action: 'setPrimary',
      provider: 'CLUBKONNECT',
    );

    expect(request.method, 'PATCH');
    expect(request.url.toString(), endpoint);
    expect(jsonDecode(request.body), <String, String>{
      'service': 'AIRTIME',
      'action': 'setPrimary',
      'provider': 'CLUBKONNECT',
    });
  });

  testWidgets('shows legacy AIRTIME/DATA and locks Telecom Abode', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final List<http.Request> patches = <http.Request>[];
    final ProviderManagementApi api = ProviderManagementApi(
      client: MockClient((http.Request request) async {
        if (request.method == 'PATCH') {
          patches.add(request);
          return http.Response('{"success":true}', 200);
        }
        return http.Response(jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{'items': _allFourServices()},
        }), 200);
      }),
    );

    await tester.pumpWidget(MaterialApp(home: ProviderManagementScreen(api: api)));
    await tester.pumpAndSettle();

    for (final String service in <String>[
      'Airtime',
      'Data',
      'Electricity',
      'Cable',
    ]) {
      expect(find.text(service), findsOneWidget);
    }
    expect(find.textContaining('PRIMARY'), findsNWidgets(4));
    expect(find.textContaining('FALLBACK'), findsNWidgets(4));
    expect(find.textContaining('CURRENT'), findsNWidgets(4));
    expect(find.textContaining('Telecom Abode actions are not supported yet.'),
        findsNWidgets(4));

    final Finder airtime = find.byKey(const ValueKey<String>('service-AIRTIME'));
    final Finder data = find.byKey(const ValueKey<String>('service-DATA'));
    expect(find.descendant(of: airtime, matching: find.text('Enabled')),
        findsOneWidget);
    expect(find.descendant(of: airtime, matching: find.text('Available')),
        findsOneWidget);
    expect(find.descendant(of: data, matching: find.text('ClubKonnect / Nellobyte')),
        findsOneWidget);
    expect(find.text('READ ONLY'), findsNWidgets(2));
    expect(
      find.text(
        'Existing purchases continue through ClubKonnect. The backend rejects routing-control changes, so these controls are read-only.',
      ),
      findsNWidgets(2),
    );

    final List<OutlinedButton> airtimeButtons = tester.widgetList<OutlinedButton>(
      find.descendant(
        of: airtime,
        matching: find.byWidgetPredicate((Widget widget) => widget is OutlinedButton),
      ),
    ).toList();
    expect(airtimeButtons, hasLength(6));
    expect(
      airtimeButtons.every((OutlinedButton button) => button.onPressed == null),
      isTrue,
    );
    final List<OutlinedButton> dataButtons = tester.widgetList<OutlinedButton>(
      find.descendant(
        of: data,
        matching: find.byWidgetPredicate((Widget widget) => widget is OutlinedButton),
      ),
    ).toList();
    expect(dataButtons, hasLength(6));
    expect(
      dataButtons.every((OutlinedButton button) => button.onPressed == null),
      isTrue,
    );
    await tester.tap(
      find.descendant(
        of: airtime,
        matching:
            find.byWidgetPredicate((Widget widget) => widget is OutlinedButton),
      ).first,
      warnIfMissed: false,
    );
    await tester.tap(
      find.descendant(
        of: data,
        matching:
            find.byWidgetPredicate((Widget widget) => widget is OutlinedButton),
      ).first,
      warnIfMissed: false,
    );
    expect(tester.takeException(), isNull);
    expect(patches, isEmpty);
  });

  testWidgets('confirms electricity live-provider disable before PATCH', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final List<http.Request> patches = <http.Request>[];
    final ProviderManagementApi api = ProviderManagementApi(
      client: MockClient((http.Request request) async {
        if (request.method == 'PATCH') {
          patches.add(request);
          return http.Response('{"success":true}', 200);
        }
        return http.Response(jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{'items': _allFourServices()},
        }), 200);
      }),
    );

    await tester.pumpWidget(MaterialApp(home: ProviderManagementScreen(api: api)));
    await tester.pumpAndSettle();
    final Finder electricity =
        find.byKey(const ValueKey<String>('service-ELECTRICITY'));

    final Finder electricityButtons = find.descendant(
      of: electricity,
      matching: find.byWidgetPredicate((Widget widget) => widget is OutlinedButton),
    );
    final List<OutlinedButton> electricityActions =
        tester.widgetList<OutlinedButton>(electricityButtons).toList();
    expect(electricityActions, hasLength(6));
    expect(electricityActions[2].onPressed, isNull); // Fallback unsupported.
    expect(electricityActions[1].onPressed, isNotNull); // Primary route supported.
    await tester.tap(electricityButtons.first);
    await tester.pumpAndSettle();
    expect(find.text('Disable live provider?'), findsOneWidget);
    expect(
      find.text(
        'NELLOBYTES is enabled and available for Electricity. Disabling it may stop new Electricity purchases. Transactions already admitted may still finish.',
      ),
      findsOneWidget,
    );
    expect(patches, isEmpty);
    await tester.tap(find.text('Confirm disable'));
    await tester.pumpAndSettle();
    expect(patches, hasLength(1));
    expect(jsonDecode(patches.first.body), <String, String>{
      'service': 'ELECTRICITY',
      'action': 'disable',
      'provider': 'NELLOBYTES',
    });
  });

  testWidgets('unreported service cards never claim disabled/unavailable', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ProviderManagementApi api = ProviderManagementApi(
      client: MockClient((http.Request _) async => http.Response(
        jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{
            'items': <Map<String, dynamic>>[
              _service(name: 'ELECTRICITY'),
              _service(
                name: 'CABLE',
                primary: null,
                current: null,
                providers: <Map<String, dynamic>>[],
              ),
            ],
          },
        }),
        200,
      )),
    );
    await tester.pumpWidget(MaterialApp(home: ProviderManagementScreen(api: api)));
    await tester.pumpAndSettle();
    final Finder airtime = find.byKey(const ValueKey<String>('service-AIRTIME'));
    expect(find.descendant(of: airtime, matching: find.text('Not reported')),
        findsNWidgets(4));
    expect(
      find.text(
        'Provider status and routing configuration were not returned by the backend. Controls are locked until confirmed.',
      ),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: airtime,
        matching: find.byType(OutlinedButton),
      ),
      findsNothing,
    );
  });

  test('Provider Management navigation is Head Office-only', () {
    expect(canAccessProviderManagementNavigation(role: ' HEAD OFFICE '), isTrue);
    expect(canAccessProviderManagementNavigation(role: 'HEAD_OFFICE'), isTrue);
    expect(canAccessProviderManagementNavigation(role: 'ADMIN'), isFalse);
    expect(canAccessProviderManagementNavigation(role: 'SUPER_ADMIN'), isFalse);
    expect(
      canAccessProviderManagementNavigation(role: 'HEAD_OFFICE_ADMIN'),
      isFalse,
    );
  });

  test('service locks follow the backend purchase-route support boundary', () {
    expect(
      providerManagementActionIsLocked(
        service: 'AIRTIME',
        provider: 'CLUBKONNECT',
        available: true,
      ),
      isTrue,
    );
    expect(
      providerManagementActionIsLocked(
        service: 'DATA',
        provider: 'CLUBKONNECT',
        available: true,
      ),
      isTrue,
    );
    expect(
      providerManagementActionIsLocked(
        service: 'ELECTRICITY',
        provider: 'NELLOBYTES',
        available: true,
      ),
      isFalse,
    );
    expect(
      providerManagementActionIsLocked(
        service: 'ELECTRICITY',
        provider: 'TELECOM_ABODE',
        available: false,
      ),
      isTrue,
    );
  });
}