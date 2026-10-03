import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/main_navigation.dart';
import 'package:servicepay_app/logistics/admin_office_shipment_screen.dart';
import 'package:servicepay_app/logistics/logistics_api.dart';
import 'package:servicepay_app/logistics/logistics_operations_screens.dart';

class _OfficeApi extends LogisticsApi {
  int created = 0;
  Map<String, dynamic>? createdBody;

  @override
  Future<List<Map<String, dynamic>>> officeRoutes(
          {String scope = 'admin'}) async =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          '_id': 'route-1',
          'originState': 'LAGOS',
          'destinationState': 'OGUN',
          'active': true,
        },
      ];

  @override
  Future<Map<String, dynamic>> officeQuote(
          Map<String, dynamic> shipment,
          {String scope = 'admin'}) async =>
      <String, dynamic>{
        'quote': <String, dynamic>{'total': 3820},
      };

  @override
  Future<Map<String, dynamic>> createOfficeShipment(
          Map<String, dynamic> shipment,
          {String scope = 'admin'}) async {
    created += 1;
    createdBody = shipment;
    return <String, dynamic>{
      'success': true,
      'shipment': <String, dynamic>{
        '_id': 'shipment-1',
        'trackingNumber': 'SP-INT-20260920-X7K9Q2',
        'status': 'RECEIVED_AT_ORIGIN_HUB',
        'paymentStatus': 'UNPAID',
      },
      'receipt': <String, dynamic>{'url': '/private-receipt'},
    };
  }
}

class _RiderLogisticsApi extends LogisticsApi {
  @override
  Future<List<Map<String, dynamic>>> list(
    String scope,
    String resource, {
    Map<String, String>? query,
  }) async =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          '_id': 'rider-shipment-1',
          'trackingNumber': 'SP-INT-RIDER-1',
          'status': 'OUT_FOR_DELIVERY',
          'receiver': <String, dynamic>{
            'name': 'Tunde Bello',
            'phone': '08032223333',
            'address': '12 Unity Road',
          },
        },
      ];

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async =>
      <String, dynamic>{
        'shipment': <String, dynamic>{
          '_id': 'rider-shipment-1',
          'trackingNumber': 'SP-INT-RIDER-1',
          'status': 'OUT_FOR_DELIVERY',
          'originState': 'LAGOS',
          'destinationState': 'OGUN',
          'sender': <String, dynamic>{'name': 'Ada Okafor'},
          'receiver': <String, dynamic>{
            'name': 'Tunde Bello',
            'phone': '08032223333',
            'address': '12 Unity Road',
          },
          'parcel': <String, dynamic>{
            'description': 'Printed documents',
            'quantity': 1,
            'weightKg': 0.8,
          },
        },
        'history': <Map<String, dynamic>>[
          <String, dynamic>{'status': 'OUT_FOR_DELIVERY'},
        ],
      };
}

void main() {
  test('logistics navigation is exposed only by its staff permission',
      () {
    final AdminAccess branchAccess = AdminAccess(
      role: 'BRANCH',
      permissions: <String>{AdminPermissions.logisticsView},
    );
    final AdminAccess unrelatedAccess = AdminAccess(
      role: 'BRANCH',
      permissions: <String>{AdminPermissions.staffView},
    );
    expect(
      AdminMainNavigation.visibleDestinationLabels(branchAccess),
      contains('Interstate Logistics'),
    );
    expect(
      AdminMainNavigation.visibleDestinationLabels(unrelatedAccess),
      isNot(contains('Interstate Logistics')),
    );
  });

  test('branch office quote uses the branch-scoped logistics contract',
      () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path,
          '/api/branches/logistics/interstate/office-quote');
      expect(request.headers['Authorization'], 'Bearer branch-token');
      return http.Response('{"quote":{"total":1200}}', 200);
    });
    final LogisticsApi api = LogisticsApi(
      client: client,
      tokenLoader: () async => 'branch-token',
    );
    final Map<String, dynamic> result = await api.officeQuote(
      <String, dynamic>{'routeId': 'r1'},
      scope: 'branch',
    );
    expect(LogisticsApi.map(result['quote'])['total'], 1200);
  });

  testWidgets('rider opens Interstate operational tracking and receiver details',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RiderInterstateDeliveriesScreen(api: _RiderLogisticsApi()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('SP-INT-RIDER-1'), findsOneWidget);
    await tester.tap(find.text('SP-INT-RIDER-1'));
    await tester.pumpAndSettle();
    expect(find.text('INTERSTATE'), findsOneWidget);
    expect(find.text('Tracking: SP-INT-RIDER-1'), findsOneWidget);
    expect(find.text('Destination: OGUN'), findsOneWidget);
    expect(find.text('Receiver phone: 08032223333'), findsOneWidget);
    expect(find.text('Parcel: Printed documents'), findsOneWidget);
    expect(find.text('OUT FOR DELIVERY'), findsWidgets);
  });

  testWidgets('office registers parcel without rider and immediately shows tracking',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    final _OfficeApi api = _OfficeApi();
    await tester.pumpWidget(MaterialApp(
      home: AdminOfficeShipmentScreen(api: api),
    ));
    await tester.pumpAndSettle();

    final Finder routeDropdown =
        find.byType(DropdownButtonFormField<Map<String, dynamic>>).first;
    await tester.tap(routeDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('LAGOS → OGUN').last);
    await tester.pumpAndSettle();
    Future<void> enter(String label, String text) async {
      final String key = switch (label) {
        'Sender name' => 'senderName',
        'Sender phone' => 'senderPhone',
        'Sender email' => 'senderEmail',
        'Receiver name' => 'receiverName',
        'Receiver phone' => 'receiverPhone',
        'Receiver address' => 'receiverAddress',
        'Parcel description' => 'description',
        'Quantity' => 'quantity',
        'Weight (kg)' => 'weight',
        _ => label,
      };
      final Finder field = find.byKey(Key('office-field-$key'));
      await tester.ensureVisible(field);
      await tester.enterText(field, text);
    }

    await enter('Sender name', 'Ada Okafor');
    await enter('Sender phone', '08031112222');
    await enter('Sender email', 'ada@example.test');
    await enter('Receiver name', 'Tunde Bello');
    await enter('Receiver phone', '08032223333');
    await enter('Receiver address', '12 Unity Road');
    await enter('Parcel description', 'Printed documents');
    await enter('Quantity', '1');
    await enter('Weight (kg)', '0.8');
    await tester.tap(find.text('I confirm this parcel contains no prohibited items.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calculate charge'));
    await tester.pumpAndSettle();
    expect(find.textContaining('₦3820'), findsOneWidget);
    await tester.tap(find.byKey(const Key('office-create-shipment')));
    await tester.pumpAndSettle();

    expect(api.created, 1);
    expect(api.createdBody, isNot(contains('riderId')));
    expect(api.createdBody!['pickupMethod'], 'BRANCH_DROP_OFF');
    expect(api.createdBody!['prohibitedItemsAcknowledged'], isTrue);
    expect(find.text('SP-INT-20260920-X7K9Q2'), findsOneWidget);
    expect(find.text('Shipment registered'), findsNWidgets(2));
    expect(find.text('Print receipt'), findsOneWidget);
    expect(find.text('Download receipt'), findsOneWidget);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}