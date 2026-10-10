import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_data_pricing_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _plan({
  required String code,
  required String name,
  String provider = 'ClubKonnect',
  String dataType = 'SME',
  bool active = false,
  bool canEnable = true,
  double sellingPrice = 280,
  bool available = true,
}) =>
    <String, dynamic>{
      'code': code,
      'name': name,
      'networkCode': 'MTN',
      'provider': provider,
      'providerPlanId': 'provider-$code',
      'providerPrice': 250,
      'sellingPrice': sellingPrice,
      'priced': true,
      'active': active,
      'margin': sellingPrice - 250,
      'dataVolume': '1GB',
      'validity': '30 days',
      'dataType': dataType,
      'available': available,
      'canEnable': canEnable,
    };

Future<void> _mount(
  WidgetTester tester,
  MockClient client, {
  Size size = const Size(900, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  SharedPreferences.setMockInitialValues(<String, Object>{
    'auth_token': 'admin-test-token',
  });
  await tester.pumpWidget(MaterialApp(
    home: AdminDataPricingScreen(
      client: client,
      baseUrl: 'https://admin.test/api',
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search filters catalog rows and network selector reloads',
      (WidgetTester tester) async {
    final List<String> loadedPaths = <String>[];
    final MockClient client = MockClient((http.Request request) async {
      loadedPaths.add(request.url.path);
      final List<Map<String, dynamic>> plans = request.url.path.endsWith('/MTN')
          ? <Map<String, dynamic>>[
              _plan(code: 'A1', name: 'Everyday 1GB'),
              _plan(code: 'A2', name: 'Night data 2GB', dataType: 'Direct'),
            ]
          : <Map<String, dynamic>>[
              _plan(
                  code: 'B1', name: 'Airtel Bundle', provider: 'Airtel source'),
            ];
      return http.Response(jsonEncode(<String, dynamic>{'plans': plans}), 200);
    });
    await _mount(tester, client);

    expect(find.text('Everyday 1GB'), findsOneWidget);
    expect(find.text('Night data 2GB'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'night');
    await tester.pumpAndSettle();
    expect(find.text('Everyday 1GB'), findsNothing);
    expect(find.text('Night data 2GB'), findsOneWidget);
    expect(find.text('1 shown'), findsOneWidget);

    await tester.tap(find.text('Airtel').first);
    await tester.pumpAndSettle();
    expect(loadedPaths.last, '/api/clubkonnect/admin/data-pricing/Airtel');
    expect(find.text('Airtel Bundle'), findsNothing,
        reason: 'The existing search filter remains applied across networks.');
  });

  testWidgets(
      'enable all confirms exact eligible count and sends canonical codes',
      (WidgetTester tester) async {
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'plans': <Map<String, dynamic>>[
              _plan(code: 'mtn-sme-1gb', name: 'SME 1GB'),
              _plan(
                code: 'mtn-unsupported',
                name: 'Legacy bundle',
                canEnable: false,
                available: false,
              ),
              _plan(
                code: 'mtn-active',
                name: 'Already active',
                active: true,
              ),
            ],
          }),
          200,
        );
      }
      return http.Response('{"success":true}', 200);
    });
    await _mount(tester, client);

    expect(find.text('Enable all (1)'), findsOneWidget);
    await tester.tap(find.text('Enable all (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Enable all 1 plan?'), findsOneWidget);
    expect(find.textContaining('exactly 1 DATA plan'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requests.where((http.Request request) => request.method == 'PATCH'),
        isEmpty);

    await tester.tap(find.text('Enable all (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enable all'));
    await tester.pumpAndSettle();
    final http.Request patch = requests
        .singleWhere((http.Request request) => request.method == 'PATCH');
    expect(
      patch.url.path,
      '/api/clubkonnect/admin/data-pricing/MTN/availability',
    );
    expect(patch.headers['authorization'], 'Bearer admin-test-token');
    expect(jsonDecode(patch.body), <String, dynamic>{
      'planCodes': <String>['mtn-sme-1gb'],
      'active': true,
      'confirmed': true,
    });
  });

  testWidgets(
      'editing a disabled plan sends sellingPrice only and keeps it disabled',
      (WidgetTester tester) async {
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'plans': <Map<String, dynamic>>[
              _plan(
                code: 'inactive-plan',
                name: 'Inactive 1GB',
                active: false,
                canEnable: false,
                available: false,
                sellingPrice: 300,
              ),
            ],
          }),
          200,
        );
      }
      return http.Response('{"success":true}', 200);
    });
    await _mount(tester, client);

    expect(find.text('Disabled'), findsOneWidget);
    final Finder priceField = find.widgetWithText(TextField, 'Selling price');
    await tester.enterText(priceField, '315');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final http.Request put =
        requests.singleWhere((http.Request request) => request.method == 'PUT');
    expect(
        put.url.path, '/api/clubkonnect/admin/data-pricing/MTN/inactive-plan');
    expect(jsonDecode(put.body), <String, dynamic>{'sellingPrice': 315.0});
    expect(find.text('Disabled'), findsOneWidget,
        reason: 'Price updates do not implicitly turn a plan on.');
    expect(find.text('Enable plan'), findsOneWidget);
  });

  testWidgets('selection sends an action only for selected visible rows',
      (WidgetTester tester) async {
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'plans': <Map<String, dynamic>>[
              _plan(code: 'mtn-on', name: 'Active plan', active: true),
              _plan(code: 'mtn-off', name: 'Inactive plan'),
            ],
          }),
          200,
        );
      }
      return http.Response('{"success":true}', 200);
    });
    await _mount(tester, client);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Disable selected'));
    await tester.pumpAndSettle();
    expect(find.text('Disable selected 1 plan?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Disable selected'));
    await tester.pumpAndSettle();

    final http.Request patch = requests
        .singleWhere((http.Request request) => request.method == 'PATCH');
    expect(jsonDecode(patch.body), <String, dynamic>{
      'planCodes': <String>['mtn-on'],
      'active': false,
      'confirmed': true,
    });
  });
}
