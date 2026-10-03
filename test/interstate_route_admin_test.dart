import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/logistics/logistics_api.dart';
import 'package:servicepay_app/logistics/admin_logistics_setup_screen.dart';

class _RoutesApi extends LogisticsApi {
  final List<Map<String, dynamic>> routes = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> writes = <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> list(String scope, String resource,
          {Map<String, String>? query}) async =>
      resource == 'routes'
          ? List<Map<String, dynamic>>.from(routes)
          : <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> listBranches() async =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          '_id': 'branch-kano',
          'name': 'Kano',
          'state': 'KANO',
          'status': 'ACTIVE',
        },
        <String, dynamic>{
          '_id': 'branch-abuja',
          'name': 'Abuja',
          'state': 'FCT',
          'status': 'ACTIVE',
        },
      ];

  @override
  Future<Map<String, dynamic>> request(String method, String path,
      {Map<String, String>? query, Map<String, dynamic>? body}) async {
    writes.add(<String, dynamic>{
      'method': method,
      'path': path,
      'body': body ?? <String, dynamic>{},
    });
    if (method == 'POST') {
      routes.add(<String, dynamic>{
        '_id': 'route-kano-fct',
        ...?body,
        'originBranchId': <String, dynamic>{
          '_id': 'branch-kano',
          'name': 'Kano',
          'state': 'KANO',
        },
        'destinationBranchId': <String, dynamic>{
          '_id': 'branch-abuja',
          'name': 'Abuja',
          'state': 'FCT',
        },
      });
    } else if (method == 'PATCH' && body?['customerVisible'] != null) {
      routes.first['customerVisible'] = body!['customerVisible'];
    }
    return <String, dynamic>{'success': true};
  }
}

void main() {
  testWidgets(
      'route branch selection auto-names route; create hidden then toggle visibility',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final _RoutesApi api = _RoutesApi();
    await tester.pumpWidget(MaterialApp(
      home: AdminLogisticsSetupScreen(resource: 'routes', api: api),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create First Interstate Route'));
    await tester.pumpAndSettle();

    Future<void> chooseBranch(String name, int selectionIndex) async {
      final Finder placeholders = find.text('Choose a real ServicePay branch');
      await tester.tap(find.ancestor(
          of: placeholders.at(selectionIndex),
          matching: find.byType(ListTile)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    await chooseBranch('Kano', 0);
    await chooseBranch('Abuja', 0);
    final TextField routeName =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Route name'));
    expect(routeName.controller!.text, 'Kano to Abuja');
    await tester.enterText(
        find.widgetWithText(TextField, 'Base price (₦)'), '2400');
    await tester.enterText(
        find.widgetWithText(TextField, 'Maximum included weight (kg)'), '5');
    await tester.enterText(
        find.widgetWithText(TextField, 'Additional price per kg (₦)'), '300');
    await tester.tap(find.text('Create route'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> created = api.writes
        .firstWhere((Map<String, dynamic> row) => row['method'] == 'POST');
    expect(created['body']['name'], 'Kano to Abuja');
    expect(created['body']['customerVisible'], isFalse);
    expect(created['body']['weightPricingMode'], 'EXCESS_OVER_MAXIMUM');
    expect(created['body']['maximumWeightKg'], 5);
    expect(api.routes, hasLength(1));

    final Finder visibilitySwitch =
        find.byKey(const Key('route-visible-route-kano-fct'));
    await tester.ensureVisible(visibilitySwitch);
    await tester.tap(visibilitySwitch);
    await tester.pumpAndSettle();
    final Map<String, dynamic> visibilityWrite = api.writes
        .lastWhere((Map<String, dynamic> row) => row['method'] == 'PATCH');
    expect(visibilityWrite['body'], <String, dynamic>{'customerVisible': true});
    await tester.pumpAndSettle();
    await tester.tap(visibilitySwitch);
    await tester.pumpAndSettle();
    expect(
      api.writes.lastWhere(
          (Map<String, dynamic> row) => row['method'] == 'PATCH')['body'],
      <String, dynamic>{'customerVisible': false},
    );
  });
}
