import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_feature_controls_api.dart';
import 'package:servicepay_app/admin/admin_feature_controls_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> feature(
  String key, {
  bool enabled = true,
  bool visible = true,
  bool protected = false,
  String category = 'Payments',
}) =>
    <String, dynamic>{
      'key': key,
      'displayName': key[0].toUpperCase() + key.substring(1),
      'category': category,
      'description': '$key access',
      'enabled': enabled,
      'visible': visible,
      'maintenanceMode': false,
      'protected': protected,
    };

Map<String, dynamic> registryBody(List<Map<String, dynamic>> features) =>
    <String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'features': features,
        'metrics': <String, int>{
          'total': features.length,
          'enabled': features.where((item) => item['enabled'] == true).length,
          'disabled': features.where((item) => item['enabled'] != true).length,
          'hidden': features.where((item) => item['visible'] == false).length,
          'maintenance': 0,
        },
        'sync': <String, dynamic>{
          'healthy': true,
          'source': 'DATABASE_SETTINGS',
          'realtime': false,
        },
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Feature Controls never writes before explicit confirmation',
      (tester) async {
    var putCount = 0;
    Map<String, dynamic>? putBody;
    final client = MockClient((request) async {
      if (request.method == 'PUT') {
        putCount += 1;
        putBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode(<String, dynamic>{'success': true}), 200);
      }
      return http.Response(
        jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{
            'featureToggles': <String, bool>{
              'airtime': true,
              'delivery': false,
            },
          },
        }),
        200,
      );
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'test-token',
      'user_role': 'HEAD_OFFICE',
      'admin_effective_permissions': <String>[
        'feature_control.view',
        'feature_control.manage',
      ],
    });

    await tester.pumpWidget(MaterialApp(
      home: AdminFeatureControlsScreen(
        api: AdminFeatureControlsApi(client: client),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Feature Control Center'), findsOneWidget);
    final airtimeSwitch = find.byKey(
      const ValueKey<String>('feature-control-enabled-airtime'),
      skipOffstage: false,
    );
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -500),
    );
    await tester.pump();
    await tester.tap(airtimeSwitch);
    await tester.pump();
    expect(putCount, 0);
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -500),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('feature-control-reason')),
      'Scheduled service maintenance',
    );
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pump();
    await tester.tap(find.text('SAVE FEATURE CONTROLS'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm feature-control changes'), findsOneWidget);
    expect(putCount, 0);
    await tester.tap(find.text('CONFIRM CHANGES'));
    await tester.pumpAndSettle();
    expect(putCount, 1);
    expect(putBody?['reason'], 'Scheduled service maintenance');
    expect(
      (putBody?['fintechControl'] as Map)['featureToggles'],
      <String, bool>{'airtime': false, 'delivery': false},
    );
  });

  testWidgets('Feature Controls is read-only outside Head Office',
      (tester) async {
    final client = MockClient((request) async => http.Response(
          jsonEncode(registryBody(<Map<String, dynamic>>[feature('airtime')])),
          200,
        ));
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'test-token',
      'user_role': 'ADMIN',
    });
    await tester.pumpWidget(MaterialApp(
      home: AdminFeatureControlsScreen(
        api: AdminFeatureControlsApi(client: client),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('read-only access'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byType(SwitchListTile, skipOffstage: false).first,
          )
          .onChanged,
      isNull,
    );
  });

  test('registry API parses the final settings contract', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'test-token',
    });
    http.BaseRequest? request;
    final client = MockClient((value) async {
      request = value;
      return http.Response(
        jsonEncode(registryBody(<Map<String, dynamic>>[
          <String, dynamic>{
            ...feature('wallet', protected: true, category: 'Money'),
            'effectiveEnabled': true,
          },
        ])),
        200,
      );
    });
    final api = AdminFeatureControlsApi(client: client);
    final registry = await api.loadRegistry();
    expect(request?.method, 'GET');
    expect(request?.url.path, '/api/settings/admin/feature-control/registry');
    expect(registry.features.single.key, 'wallet');
    expect(registry.features.single.isProtected, isTrue);
    expect(registry.metrics['enabled'], 1);
    expect(registry.sync['realtime'], isFalse);
  });

  test('PATCH, bulk, and audit APIs use the final request contract', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'test-token',
    });
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'PATCH') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': feature('wallet', enabled: false, protected: true),
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/audit')) {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': <String, dynamic>{'entries': <dynamic>[]},
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode(registryBody(<Map<String, dynamic>>[])),
        200,
      );
    });
    final api = AdminFeatureControlsApi(client: client);
    await api.patchFeature(
      'wallet',
      <String, dynamic>{
        'enabled': false,
        'scheduledDisabledAt': DateTime.utc(2026, 6, 18, 2),
        'scheduledEnabledAt': DateTime.utc(2026, 6, 18, 3),
      },
      'Disable wallet for an approved maintenance window.',
      protectedConfirmation: true,
      confirmationText: 'wallet',
    );
    await api.bulk(
      <String>['airtime', 'data'],
      'DISABLE',
      'Disable selected services for provider maintenance.',
    );
    await api.audit(featureKey: 'wallet');
    expect(requests[0].method, 'PATCH');
    expect(requests[0].url.path, '/api/settings/admin/feature-control/wallet');
    expect(jsonDecode(requests[0].body), <String, dynamic>{
      'reason': 'Disable wallet for an approved maintenance window.',
      'feature': <String, dynamic>{
        'enabled': false,
        'scheduledDisabledAt': '2026-06-18T02:00:00.000Z',
        'scheduledEnabledAt': '2026-06-18T03:00:00.000Z',
      },
      'protectedConfirmation': true,
      'confirmationText': 'wallet',
    });
    expect(requests[1].method, 'POST');
    expect(requests[1].url.path, '/api/settings/admin/feature-control/bulk');
    expect(jsonDecode(requests[1].body), <String, dynamic>{
      'keys': <String>['airtime', 'data'],
      'action': 'DISABLE',
      'reason': 'Disable selected services for provider maintenance.',
    });
    expect(requests[2].url.queryParameters, <String, String>{
      'featureKey': 'wallet',
    });
  });

  testWidgets('registry search filters feature cards', (tester) async {
    final client = MockClient((request) async => http.Response(
          jsonEncode(registryBody(<Map<String, dynamic>>[
            feature('airtime'),
            feature('wallet', protected: true, category: 'Money'),
          ])),
          200,
        ));
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'test-token',
      'user_role': 'ADMIN',
    });
    await tester.pumpWidget(MaterialApp(
      home: AdminFeatureControlsScreen(
        api: AdminFeatureControlsApi(client: client),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('feature-control-enabled-airtime'),
          skipOffstage: false),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(
        of: find.byType(SearchBar),
        matching: find.byType(EditableText),
      ),
      'wallet',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('feature-control-enabled-airtime'),
          skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('feature-control-enabled-wallet'),
          skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('protected changes require the exact confirmation key',
      (tester) async {
    Map<String, dynamic>? patchBody;
    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        patchBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': feature('wallet', enabled: false, protected: true),
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode(registryBody(<Map<String, dynamic>>[
          feature('wallet', protected: true),
        ])),
        200,
      );
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'test-token',
      'user_role': 'SERVICEPAY_SUPER_ADMIN',
    });
    await tester.pumpWidget(MaterialApp(
      home: AdminFeatureControlsScreen(
        api: AdminFeatureControlsApi(client: client),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -500),
    );
    await tester.pump();
    await tester.tap(find.byKey(
      const ValueKey<String>('feature-control-enabled-wallet'),
      skipOffstage: false,
    ));
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -500),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('feature-control-reason')),
      'Approved wallet maintenance window.',
    );
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pump();
    await tester.tap(find.text('SAVE FEATURE CONTROLS'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm feature-control changes'), findsOneWidget);
    await tester.tap(find.text('CONFIRM CHANGES'));
    await tester.pump();
    expect(find.text('Confirm feature-control changes'), findsOneWidget);
    expect(patchBody, isNull);
    await tester.enterText(
      find.byKey(
          const ValueKey<String>('feature-control-protected-confirmation')),
      'wallet',
    );
    await tester.tap(find.text('CONFIRM CHANGES'));
    await tester.pumpAndSettle();
    expect(patchBody?['protectedConfirmation'], isTrue);
    expect(patchBody?['confirmationText'], 'wallet');
  });
}
