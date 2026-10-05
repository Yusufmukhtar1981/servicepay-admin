import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/admin_delivery_pricing_api.dart';
import 'package:servicepay_app/admin/admin_delivery_pricing_screen.dart';

class _PricingApi implements AdminDeliveryPricingApiClient {
  int loads = 0;
  int updates = 0;
  int statusChanges = 0;
  bool failLoad = false;
  bool conflict = false;
  bool includeRoutes = true;
  final List<Map<String, dynamic>> created = <Map<String, dynamic>>[];
  final List<String> changedRouteIds = <String>[];

  Map<String, dynamic> get snapshot => <String, dynamic>{
        'success': true,
        'intraState': <String, dynamic>{
          'price': 1500,
          'version': 4,
          'updatedAt': '2026-04-01T09:00:00Z',
        },
        'routes': includeRoutes
            ? <Map<String, dynamic>>[
                _route('kano-abuja', 'KANO', 'FCT'),
                _route('abuja-kano', 'FCT', 'KANO'),
              ]
            : <Map<String, dynamic>>[],
        'branches': <Map<String, dynamic>>[
          <String, dynamic>{
            '_id': 'kano-branch',
            'name': 'Kano depot',
            'state': 'KANO',
            'status': 'ACTIVE'
          },
          <String, dynamic>{
            '_id': 'fct-branch',
            'name': 'Abuja depot',
            'state': 'FCT',
            'status': 'ACTIVE'
          },
        ],
        'summary': <String, dynamic>{'activeRoutes': 2, 'inactiveRoutes': 0},
        'audit': <Map<String, dynamic>>[],
      };

  static Map<String, dynamic> _route(
          String id, String origin, String destination) =>
      <String, dynamic>{
        '_id': id,
        'name': '$origin to $destination',
        'originState': origin,
        'destinationState': destination,
        'originBranchId': 'branch',
        'destinationBranchId': 'branch-dest',
        'baseFare': 5000,
        'pricingMode': 'CALCULATED',
        'status': 'ACTIVE',
        'isArchived': false,
        'updatedAt': '2026-04-01T09:00:00Z',
      };

  @override
  Future<Map<String, dynamic>> getPricing() async {
    loads++;
    if (failLoad) {
      throw const AdminDeliveryPricingApiException('Network unavailable.');
    }
    return snapshot;
  }

  @override
  Future<Map<String, dynamic>> updateIntraStatePrice({
    required num price,
    required int expectedVersion,
  }) async {
    updates++;
    if (conflict) {
      throw const AdminDeliveryPricingApiException(
        'Pricing changed since review.',
        statusCode: 409,
      );
    }
    return <String, dynamic>{'success': true};
  }

  @override
  Future<Map<String, dynamic>> createRoute(Map<String, dynamic> body) async {
    created.add(body);
    return <String, dynamic>{'success': true};
  }

  @override
  Future<Map<String, dynamic>> updateRoutePrice({
    required String routeId,
    required num baseFare,
    required String expectedUpdatedAt,
  }) async {
    updates++;
    changedRouteIds.add(routeId);
    if (conflict) {
      throw const AdminDeliveryPricingApiException(
        'Route was updated by another operator.',
        statusCode: 409,
      );
    }
    return <String, dynamic>{'success': true};
  }

  @override
  Future<Map<String, dynamic>> setRouteActive({
    required String routeId,
    required bool active,
  }) async {
    statusChanges++;
    return <String, dynamic>{'success': true};
  }

  @override
  Future<Map<String, dynamic>> deleteRoute({
    required String routeId,
    required String expectedUpdatedAt,
  }) async =>
      <String, dynamic>{'success': true};
}

void main() {
  testWidgets('load failure presents Retry and successfully reloads',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final _PricingApi api = _PricingApi()..failLoad = true;
    await tester
        .pumpWidget(MaterialApp(home: AdminDeliveryPricingScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Pricing could not be loaded'), findsOneWidget);
    expect(find.text('Network unavailable.'), findsOneWidget);
    api.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.loads, 2);
    expect(find.text('Intra-State price'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('canceling edit confirmation does not send price mutation',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final _PricingApi api = _PricingApi();
    await tester
        .pumpWidget(MaterialApp(home: AdminDeliveryPricingScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate').first);
    await tester.pumpAndSettle();
    expect(find.text('Deactivate route?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(api.statusChanges, 0);
    expect(api.loads, 1);
  });

  testWidgets('new route uses selected real branches and reverse checkbox',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final _PricingApi api = _PricingApi()..includeRoutes = false;
    await tester
        .pumpWidget(MaterialApp(home: AdminDeliveryPricingScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add route'));
    await tester.pumpAndSettle();
    final Finder branchDropdowns =
        find.byType(DropdownButtonFormField<Map<String, dynamic>>);
    await tester.tap(branchDropdowns.at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kano depot · KANO').last);
    await tester.pumpAndSettle();
    await tester.tap(branchDropdowns.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abuja depot · FCT').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Fixed price (₦)'), '5100');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Maximum included weight (kg)'),
        '6');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Standard delivery time'),
        '2-3 business days');
    await tester.tap(find.text('Apply same price to reverse route'));
    await tester.tap(find.text('Review route'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create route'));
    await tester.pumpAndSettle();

    expect(api.created, hasLength(1));
    expect(api.created.single['originBranchId'], 'kano-branch');
    expect(api.created.single['destinationBranchId'], 'fct-branch');
    expect(api.created.single['originState'], 'KANO');
    expect(api.created.single['destinationState'], 'FCT');
    expect(api.created.single['maximumWeightKg'], 6);
    expect(api.created.single['standardDeliveryTime'], '2-3 business days');
    expect(api.created.single['applySamePriceToReverse'], isTrue);
    expect(api.created.single['pricingMode'], 'FIXED');
    expect(api.created.single['minimumWeightKg'], 0);
    expect(api.created.single['pricePerAdditionalKg'], 0);
  });

  testWidgets('mobile pricing view renders summary and route controls',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final _PricingApi api = _PricingApi();
    await tester
        .pumpWidget(MaterialApp(home: AdminDeliveryPricingScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Delivery pricing'), findsOneWidget);
    expect(find.text('Active routes'), findsOneWidget);
    expect(find.text('Inactive routes'), findsOneWidget);
    expect(find.text('Intra-State price'), findsOneWidget);
    expect(find.text('Add route'), findsOneWidget);
  });
}
