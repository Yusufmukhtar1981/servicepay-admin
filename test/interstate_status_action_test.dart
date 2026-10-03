import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/logistics/logistics_api.dart';
import 'package:servicepay_app/logistics/logistics_operations_screens.dart';

class _StatusApi extends LogisticsApi {
  String status = 'RECEIVED_AT_SERVICEPAY';
  int updates = 0;
  int detailCalls = 0;

  @override
  Future<Map<String, dynamic>> request(String method, String path,
          {Map<String, String>? query, Map<String, dynamic>? body}) async =>
      <String, dynamic>{
        'overview': <String, dynamic>{'shipments': 1}
      };

  @override
  Future<List<Map<String, dynamic>>> list(String scope, String resource,
          {Map<String, String>? query}) async =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          '_id': 'shipment-42',
          'trackingNumber': 'SPX-42',
          'orderType': 'INTERSTATE',
          'status': status,
          'originState': 'KANO',
          'destinationState': 'FCT',
        },
      ];

  @override
  Future<Map<String, dynamic>> shipmentDetail(String id,
      {String scope = 'admin'}) async {
    detailCalls++;
    final bool awaiting = status == 'AWAITING_PICKUP';
    return <String, dynamic>{
      'shipment': <String, dynamic>{
        '_id': id,
        'trackingNumber': 'SPX-42',
        'status': status,
        'originState': 'KANO',
        'destinationState': 'FCT',
        'receiver': <String, dynamic>{'name': 'Aisha Bello'},
        'parcel': <String, dynamic>{'description': 'Office papers'},
        'quote': <String, dynamic>{'total': 1800},
      },
      'history': <Map<String, dynamic>>[
        <String, dynamic>{
          'status': status,
          'createdAt': '2026-06-10T12:30:00Z',
          'changedByName': 'Operations staff',
        },
      ],
      'assignmentHistory': <Map<String, dynamic>>[],
      'allowedStatusTransitions': <Map<String, dynamic>>[
        <String, dynamic>{
          'status': awaiting ? 'PICKED_UP' : 'AWAITING_PICKUP',
          'label': awaiting ? 'Picked up' : 'Awaiting pickup',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> updateShipmentStatus(
      String id, String nextStatus,
      {String scope = 'admin'}) async {
    updates++;
    status = nextStatus;
    return <String, dynamic>{
      'shipment': <String, dynamic>{'_id': id, 'status': status},
    };
  }
}

void main() {
  testWidgets(
      'shipment details update status is clickable and refreshes history',
      (WidgetTester tester) async {
    final _StatusApi api = _StatusApi();
    await tester.pumpWidget(MaterialApp(home: AdminLogisticsScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shipments'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('interstate-details-shipment-42')));
    await tester.pumpAndSettle();

    final Finder updateButton = find.byKey(const Key('shipment-update-status'));
    expect(updateButton, findsOneWidget);
    await tester.tap(updateButton);
    await tester.pumpAndSettle();
    expect(find.text('Awaiting pickup'), findsOneWidget);
    await tester.tap(find.text('Awaiting pickup'));
    await tester.pumpAndSettle();

    expect(api.updates, 1);
    expect(api.status, 'AWAITING_PICKUP');
    expect(find.text('Status: AWAITING PICKUP'), findsOneWidget);
    expect(api.detailCalls, 2);
    expect(find.text('Status history'), findsOneWidget);
    expect(find.byKey(const Key('shipment-update-status')), findsOneWidget);
  });
}
