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

void main() {
  const String endpoint =
      'https://api.servicepay.ng/api/admin/fintech-operations/provider-management';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'test-session-token',
    });
  });

  test('GET parses data.items and provider keys', () async {
    late http.Request request;
    final ProviderManagementApi api = ProviderManagementApi(
      client: MockClient((http.Request incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'service': 'airtime',
                  'primaryProvider': 'NELLOBYTES',
                  'fallbackProvider': null,
                  'currentProvider': 'NELLOBYTES',
                  'providers': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'provider': 'NELLOBYTES',
                      'label': 'Nellobyte',
                      'enabled': true,
                      'available': true,
                    },
                  ],
                  'updatedAt': '2025-01-02T03:04:05Z',
                  'updatedBy': 'Head Office',
                },
              ],
            },
          }),
          200,
        );
      }),
    );

    final List<ProviderService> services = await api.loadServices();
    expect(request.url.toString(), endpoint);
    expect(request.headers['authorization'], 'Bearer test-session-token');
    expect(services, hasLength(1));
    expect(services.single.providers.single['provider'], 'NELLOBYTES');
    expect(services.single.primaryProvider, 'NELLOBYTES');
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
      service: 'mobile airtime',
      action: 'setPrimary',
      provider: 'NELLOBYTES',
    );

    expect(request.method, 'PATCH');
    expect(request.url.toString(), endpoint);
    expect(jsonDecode(request.body), <String, String>{
      'service': 'mobile airtime',
      'action': 'setPrimary',
      'provider': 'NELLOBYTES',
    });
  });

  testWidgets(
      'ELECTRICITY keeps Nellobytes actions live and locks only Telecom Abode',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
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
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'service': 'ELECTRICITY',
                  'primaryProvider': 'NELLOBYTES',
                  'fallbackProvider': 'TELECOM_ABODE',
                  'currentProvider': 'NELLOBYTES',
                  'fallbackSupported': false,
                  'providers': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'provider': 'NELLOBYTES',
                      'label': 'Nellobyte',
                      'enabled': true,
                      'available': true,
                    },
                    <String, dynamic>{
                      'provider': 'TELECOM_ABODE',
                      'label': 'Telecom Abode',
                      'enabled': false,
                      'available': false,
                      'reason': 'Unsupported route',
                    },
                  ],
                  'updatedAt': '2025-01-02T03:04:05Z',
                  'updatedBy': 'Head Office',
                },
              ],
            },
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: ProviderManagementScreen(api: api)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ClubKonnect / Nellobyte'), findsOneWidget);
    expect(find.text('PRIMARY  ClubKonnect / Nellobyte'), findsOneWidget);
    expect(find.text('Telecom Abode actions are not supported yet.'),
        findsOneWidget);
    expect(
      find.text(
        'Fallback provider selection is not supported for this service.',
      ),
      findsOneWidget,
    );

    expect(find.text('Disable'), findsOneWidget);
    final List<OutlinedButton> buttons = tester
        .widgetList<OutlinedButton>(
          find.byWidgetPredicate((Widget widget) => widget is OutlinedButton),
        )
        .toList();
    expect(buttons, hasLength(6));
    expect(find.text('Enable'), findsOneWidget);
    // Nellobyte Disable and Set Primary remain actionable; fallback is
    // unsupported, and the Telecom Abode row is wholly locked.
    for (int index = 0; index < 2; index++) {
      expect(buttons[index].onPressed, isNotNull);
    }
    for (int index = 2; index < 6; index++) {
      expect(buttons[index].onPressed, isNull);
    }

    await tester.tap(find.text('Disable'));
    await tester.pumpAndSettle();
    expect(find.text('Disable active provider?'), findsOneWidget);
    expect(
      find.text(
        'NELLOBYTES is the current electricity provider. Disabling it will stop new electricity purchases until another provider is active.',
      ),
      findsOneWidget,
    );
    expect(patches, isEmpty);
    await tester.tap(find.text('Disable provider'));
    await tester.pumpAndSettle();
    expect(patches, hasLength(1));
    expect(patches.single.url.toString(), endpoint);
    expect(jsonDecode(patches.single.body), <String, String>{
      'service': 'ELECTRICITY',
      'action': 'disable',
      'provider': 'NELLOBYTES',
    });
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
}