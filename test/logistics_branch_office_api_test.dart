import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/logistics/logistics_api.dart';

void main() {
  test('branch office route and rider calls use canonical branch endpoints',
      () async {
    final requests = <http.Request>[];
    final api = LogisticsApi(
      baseUrl: 'https://example.test/api',
      tokenLoader: () async => 'branch-token',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/riders')) {
          return http.Response(
              jsonEncode(<String, dynamic>{
                'success': true,
                'riders': <Map<String, dynamic>>[
                  <String, dynamic>{'_id': 'rider-1', 'fullName': 'Rider One'}
                ],
              }),
              200);
        }
        return http.Response('{"success":true}', 200);
      }),
    );

    final routes = await api.officeRoutes(scope: 'branch');
    final riders =
        await api.shipmentRiders('shipment-1', 'DESTINATION', scope: 'branch');
    await api.assignShipmentRider('shipment-1', 'rider-1', 'DESTINATION',
        scope: 'branch');

    expect(routes, isEmpty);
    expect(riders.single['_id'], 'rider-1');
    expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        <String>[
          'GET /api/branch/logistics/interstate/routes',
          'GET /api/branch/logistics/interstate/shipments/shipment-1/riders',
          'POST /api/branch/logistics/interstate/shipments/shipment-1/assign-rider',
        ]);
    expect(requests[1].url.queryParameters, <String, String>{
      'leg': 'DESTINATION',
    });
    expect(jsonDecode(requests[2].body), <String, dynamic>{
      'riderId': 'rider-1',
      'leg': 'DESTINATION',
    });
  });
}
