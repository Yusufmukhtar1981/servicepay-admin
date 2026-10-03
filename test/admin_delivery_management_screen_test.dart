import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_delivery_api.dart';
import 'package:servicepay_app/admin/admin_dashboard_screen.dart';
import 'package:servicepay_app/admin/admin_delivery_management_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdminDeliveryApi implements AdminDeliveryApiClient {
  _FakeAdminDeliveryApi({
    this.failFirstRiderLoad = false,
    this.emptyRiders = false,
    this.assignmentError = '',
    this.ridersOverride,
  });

  final bool failFirstRiderLoad;
  final bool emptyRiders;
  final String assignmentError;
  final List<Map<String, dynamic>>? ridersOverride;
  int riderLoadCount = 0;
  int assignmentCount = 0;
  bool assigned = false;

  final Map<String, dynamic> delivery = <String, dynamic>{
    '_id': 'delivery-1',
    'trackingNumber': 'SP-DELIVERY-1',
    'status': 'PENDING',
    'pickupAddress': 'Pickup address',
    'pickupState': 'LAGOS',
    'deliveryAddress': 'Delivery address',
    'deliveryState': 'OGUN',
    'senderName': 'Sender One',
    'senderPhone': '08010000001',
    'receiverName': 'Receiver One',
    'receiverPhone': '08020000002',
    'packageName': 'Documents',
    'packageDescription': 'Sealed envelope',
    'packageWeight': 0.5,
    'deliveryFee': 2450,
    'paymentStatus': 'PAID',
    'paidAt': '2026-01-02T03:04:05.000Z',
    'createdAt': '2026-01-01T03:04:05.000Z',
    'assignedAt': '2026-01-01T04:04:05.000Z',
    'riderName': 'Rider Detail Name',
    'riderPhone': '08030000003',
    'customerId': <String, dynamic>{
      'fullName': 'Customer One',
      'phone': '08040000004',
      'email': 'private-customer@example.test',
    },
    'idempotencyKey': 'private-idempotency-value',
    'adminNote': 'private admin note',
    'riderCommissionAmount': 999,
  };

  final Map<String, dynamic> rider = <String, dynamic>{
    '_id': 'rider-1',
    'riderId': 'SP-RIDER-1',
    'fullName': 'Rider One',
    'vehicleType': 'MOTORCYCLE',
    'availabilityStatus': 'ONLINE',
  };

  @override
  Future<List<Map<String, dynamic>>> getDeliveries({
    String status = 'ALL',
  }) async {
    if (assigned && status == 'ALL') return <Map<String, dynamic>>[];
    return <Map<String, dynamic>>[delivery];
  }

  @override
  Future<List<Map<String, dynamic>>> getAvailableRiders(
    String deliveryId,
  ) async {
    expect(deliveryId, 'delivery-1');
    riderLoadCount += 1;
    if (failFirstRiderLoad && riderLoadCount == 1) {
      throw const AdminDeliveryApiException('Unable to load available riders.');
    }
    if (emptyRiders) return <Map<String, dynamic>>[];
    return ridersOverride ?? <Map<String, dynamic>>[rider];
  }

  @override
  Future<Map<String, dynamic>> reassignRider({
    required String deliveryId,
    required String riderId,
  }) async {
    expect(deliveryId, 'delivery-1');
    expect(riderId, 'rider-1');
    assignmentCount += 1;
    return <String, dynamic>{
      ...delivery,
      'status': 'ASSIGNED',
      'assignedRiderId': rider,
    };
  }

  @override
  Future<Map<String, dynamic>> assignRider({
    required String deliveryId,
    required String riderId,
  }) async {
    expect(deliveryId, 'delivery-1');
    expect(riderId, 'rider-1');
    assignmentCount += 1;
    if (assignmentError.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      throw AdminDeliveryApiException(assignmentError, statusCode: 409);
    }
    assigned = true;
    return <String, dynamic>{
      ...delivery,
      'status': 'ASSIGNED',
      'assignedRiderId': rider,
    };
  }
}

void main() {
  testWidgets('admin dashboard opens real Delivery Management',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      const MaterialApp(home: AdminDashboardScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fintech Control Center'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Deliveries');
    await tester.pumpAndSettle();
    final Finder deliveriesModule = find.text('Deliveries').last;
    await tester.ensureVisible(deliveriesModule);
    await tester.tap(deliveriesModule);
    await tester.pumpAndSettle();
    expect(find.byType(AdminDeliveryManagementScreen), findsOneWidget);
    expect(find.text('Delivery Management is coming soon.'), findsNothing);
  });

  test('available-riders client accepts a successful empty riders array',
      () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(
        request.url.toString(),
        'https://api.servicepay.ng/api/admin/deliveries/delivery-1/available-riders',
      );
      expect(request.headers['Authorization'], 'Bearer admin-token');
      return http.Response(
        jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{
            'riders': <Map<String, dynamic>>[],
            'count': 0,
          },
          'riders': <Map<String, dynamic>>[],
        }),
        200,
      );
    });
    final AdminDeliveryApi api = AdminDeliveryApi(
      client: client,
      tokenLoader: () async => 'admin-token',
    );

    final List<Map<String, dynamic>> riders =
        await api.getAvailableRiders('delivery-1');
    expect(riders, isEmpty);
  });

  testWidgets('admin selects and assigns an available rider',
      (WidgetTester tester) async {
    final _FakeAdminDeliveryApi api = _FakeAdminDeliveryApi();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDeliveryManagementScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SP-DELIVERY-1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assign-rider-delivery-1')));
    await tester.pumpAndSettle();

    expect(find.text('Rider One'), findsOneWidget);
    await tester.tap(find.byKey(const Key('available-rider-rider-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-rider-assignment')));
    await tester.pumpAndSettle();

    expect(api.assignmentCount, 1);
    expect(find.text('Rider assigned successfully.'), findsOneWidget);
    expect(find.text('No deliveries'), findsOneWidget);
  });

  testWidgets('delivery details show operational fields without private data',
      (WidgetTester tester) async {
    final _FakeAdminDeliveryApi api = _FakeAdminDeliveryApi();
    await tester.pumpWidget(
      MaterialApp(home: AdminDeliveryManagementScreen(api: api)),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('delivery-details-delivery-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delivery-details-title')), findsOneWidget);
    for (final String value in <String>[
      'Pickup address',
      'LAGOS',
      'Sender One',
      '08010000001',
      'Receiver One',
      '08020000002',
      'Documents',
      'Sealed envelope',
      'Rider Detail Name',
      '08030000003',
      'PENDING',
      '2450',
      'PAID',
      '2026-01-02T03:04:05.000Z',
      'SP-DELIVERY-1',
    ]) {
      expect(
        find.text(value),
        findsWidgets,
        reason: 'Expected details value $value',
      );
    }
    expect(find.text('private-idempotency-value'), findsNothing);
    expect(find.text('private admin note'), findsNothing);
    expect(find.text('private-customer@example.test'), findsNothing);
    expect(find.text('999'), findsNothing);
    expect(api.assignmentCount, 0);
  });

  testWidgets('failed rider loading can be retried inside the modal',
      (WidgetTester tester) async {
    final _FakeAdminDeliveryApi api =
        _FakeAdminDeliveryApi(failFirstRiderLoad: true);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDeliveryManagementScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('assign-rider-delivery-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rider-load-error')), findsOneWidget);

    await tester.tap(find.byKey(const Key('rider-load-retry')));
    await tester.pumpAndSettle();
    expect(api.riderLoadCount, 2);
    expect(find.text('Rider One'), findsOneWidget);
    expect(find.byKey(const Key('confirm-rider-assignment')), findsOneWidget);
  });

  testWidgets('empty rider results render a clear modal state',
      (WidgetTester tester) async {
    final _FakeAdminDeliveryApi api = _FakeAdminDeliveryApi(emptyRiders: true);
    await tester.pumpWidget(
      MaterialApp(home: AdminDeliveryManagementScreen(api: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-rider-delivery-1')));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'No verified active riders are available right now. Refresh or try again later.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm-rider-assignment')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('online riders sort first and eligible offline rider stays selectable',
      (WidgetTester tester) async {
    final _FakeAdminDeliveryApi api = _FakeAdminDeliveryApi(
      ridersOverride: <Map<String, dynamic>>[
        <String, dynamic>{
          '_id': 'offline-rider',
          'fullName': 'Offline Rider',
          'riderId': 'SP-OFF-1',
          'availabilityStatus': 'OFFLINE',
        },
        <String, dynamic>{
          '_id': 'online-rider',
          'fullName': 'Online Rider',
          'riderId': 'SP-ON-1',
          'availabilityStatus': 'ONLINE',
        },
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: AdminDeliveryManagementScreen(api: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-rider-delivery-1')));
    await tester.pumpAndSettle();

    final Finder online = find.byKey(const Key('available-rider-online-rider'));
    final Finder offline =
        find.byKey(const Key('available-rider-offline-rider'));
    expect(online, findsOneWidget);
    expect(offline, findsOneWidget);
    expect(tester.getTopLeft(online).dy, lessThan(tester.getTopLeft(offline).dy));
    expect(find.text('ONLINE'), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
  });

  testWidgets('assignment error stays visible and permits one safe retry',
      (WidgetTester tester) async {
    final _FakeAdminDeliveryApi api = _FakeAdminDeliveryApi(
      assignmentError: 'This delivery already has a rider assigned.',
    );
    await tester.pumpWidget(
      MaterialApp(home: AdminDeliveryManagementScreen(api: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-rider-delivery-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('available-rider-rider-1')));
    await tester.pump();

    final Finder confirm = find.byKey(const Key('confirm-rider-assignment'));
    await tester.tap(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(api.assignmentCount, 1);
    expect(
      find.text('This delivery already has a rider assigned.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });
}
