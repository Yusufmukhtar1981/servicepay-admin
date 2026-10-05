import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_delivery_pricing_api.dart';

void main() {
  test('uses configured API root, admin bearer token, and pricing contract',
      () async {
    final List<http.Request> requests = <http.Request>[];
    final AdminDeliveryPricingApi api = AdminDeliveryPricingApi(
      baseUrl: 'https://preview.servicepay.test/api/',
      tokenLoader: () async => 'Bearer staff-token',
      client: MockClient((http.Request request) async {
        requests.add(request);
        return http.Response(
            jsonEncode(<String, dynamic>{'success': true}), 200);
      }),
    );

    await api.getPricing();
    await api.updateIntraStatePrice(price: 1550, expectedVersion: 8);
    await api.createRoute(<String, dynamic>{
      'originBranchId': 'branch-kano',
      'destinationBranchId': 'branch-fct',
      'originState': 'KANO',
      'destinationState': 'FCT',
      'baseFare': 5000,
      'pricingMode': 'FIXED',
      'maximumWeightKg': 8,
      'minimumWeightKg': 0,
      'pricePerAdditionalKg': 0,
      'standardDeliveryTime': 'Operator entered schedule',
      'customerVisible': true,
      'status': 'ACTIVE',
      'applySamePriceToReverse': true,
      'confirmed': true,
    });
    await api.updateRoutePrice(
      routeId: 'route/1',
      baseFare: 5600,
      expectedUpdatedAt: '2026-04-01T09:00:00Z',
    );
    await api.setRouteActive(routeId: 'route/1', active: false);
    await api.deleteRoute(
      routeId: 'route/1',
      expectedUpdatedAt: '2026-04-01T09:00:00Z',
    );

    expect(requests.map((http.Request r) => r.url.path), <String>[
      '/api/admin/logistics/interstate/pricing',
      '/api/admin/logistics/interstate/pricing/intra-state',
      '/api/admin/logistics/interstate/routes',
      '/api/admin/logistics/interstate/routes/route%2F1/price',
      '/api/admin/logistics/interstate/routes/route%2F1/deactivate',
      '/api/admin/logistics/interstate/routes/route%2F1',
    ]);
    expect(
        requests.every((http.Request r) =>
            r.headers['authorization'] == 'Bearer staff-token'),
        isTrue);
    expect(jsonDecode(requests[1].body), <String, dynamic>{
      'price': 1550,
      'expectedVersion': 8,
      'confirmed': true,
    });
    expect(jsonDecode(requests[2].body)['applySamePriceToReverse'], isTrue);
    expect(jsonDecode(requests[3].body), <String, dynamic>{
      'baseFare': 5600,
      'pricingMode': 'FIXED',
      'expectedUpdatedAt': '2026-04-01T09:00:00Z',
      'confirmed': true,
    });
    expect(jsonDecode(requests[4].body), <String, dynamic>{'confirmed': true});
    expect(jsonDecode(requests[5].body), <String, dynamic>{
      'confirmed': true,
      'expectedUpdatedAt': '2026-04-01T09:00:00Z',
    });
  });

  test('rejects a 200 response with success false', () async {
    final AdminDeliveryPricingApi api = AdminDeliveryPricingApi(
      baseUrl: 'https://preview.servicepay.test/api',
      tokenLoader: () async => 'admin-token',
      client: MockClient((http.Request _) async => http.Response(
            jsonEncode(<String, dynamic>{
              'success': false,
              'message': 'Pricing version is stale.',
            }),
            200,
          )),
    );

    await expectLater(
      api.updateIntraStatePrice(price: 1600, expectedVersion: 2),
      throwsA(isA<AdminDeliveryPricingApiException>()
          .having((e) => e.message, 'message', 'Pricing version is stale.')),
    );
  });

  test('surfaces stale update conflicts instead of reporting success',
      () async {
    final AdminDeliveryPricingApi api = AdminDeliveryPricingApi(
      baseUrl: 'https://preview.servicepay.test/api',
      tokenLoader: () async => 'admin-token',
      client: MockClient((http.Request _) async => http.Response(
            jsonEncode(<String, dynamic>{
              'message': 'Route was updated by another operator.'
            }),
            409,
          )),
    );

    await expectLater(
      api.updateRoutePrice(
        routeId: 'r-1',
        baseFare: 2700,
        expectedUpdatedAt: 'stale',
      ),
      throwsA(isA<AdminDeliveryPricingApiException>()
          .having((e) => e.statusCode, 'statusCode', 409)
          .having((e) => e.isConflict, 'isConflict', isTrue)
          .having((e) => e.message, 'message', contains('another operator'))),
    );
  });

  test('route prices remain direction-specific endpoints', () async {
    final List<String> paths = <String>[];
    final AdminDeliveryPricingApi api = AdminDeliveryPricingApi(
      baseUrl: 'https://preview.servicepay.test/api',
      tokenLoader: () async => 'admin-token',
      client: MockClient((http.Request request) async {
        paths.add(request.url.path);
        return http.Response('{}', 200);
      }),
    );

    await api.updateRoutePrice(
      routeId: 'kano-abuja',
      baseFare: 5300,
      expectedUpdatedAt: 'v1',
    );
    await api.updateRoutePrice(
      routeId: 'abuja-kano',
      baseFare: 6100,
      expectedUpdatedAt: 'v2',
    );

    expect(
        paths,
        containsAll(<String>[
          '/api/admin/logistics/interstate/routes/kano-abuja/price',
          '/api/admin/logistics/interstate/routes/abuja-kano/price',
        ]));
  });
}
