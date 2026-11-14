import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/business_network/business_network_admin_api.dart';
import 'package:servicepay_app/admin/business_network/business_pricing_management.dart';

Map<String, dynamic> pricingResponse() => <String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'customerPricing': 'Managed in Admin DATA Pricing',
        'airtime': <String, dynamic>{
          'configurable': false,
          'reason': 'Provider pre-purchase cost has not been verified.',
        },
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'code': 'plan-01',
            'pricingCode': 'DATA-1GB',
            'name': '1 GB bundle',
            'networkCode': '01',
            'provider': 'Verified Provider',
            'providerCost': 100,
            'revision': 7,
            'customer': <String, dynamic>{
              'sellingPrice': 120,
              'enabled': true,
            },
            'categories': <String, dynamic>{
              'AGENT': <String, dynamic>{
                'configured': true,
                'enabled': true,
                'sellingPrice': 145,
                'maximumProviderCost': 110,
                'effectivePrice': 145,
                'margin': 45,
                'available': true,
                'inherited': false,
              },
              'MERCHANT': <String, dynamic>{
                'configured': false,
                'enabled': false,
                'effectivePrice': 130,
                'margin': 30,
                'available': true,
                'inherited': true,
              },
            },
          },
        ],
      },
    };

Map<String, dynamic> airtimeResponse() => <String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'revision': 3,
        'provider': 'Verified Provider',
        'providerCost': null,
        'margin': null,
        'customerMarkupBps': 125,
        'costWarning': 'Provider discounts and invoice cost are not known.',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'network': '01',
            'name': 'MTN',
            'categories': <String, dynamic>{
              'AGENT': <String, dynamic>{
                'enabled': true,
                'markupBps': 175,
                'updatedBy': 'Head Office',
                'updatedAt': '2025-03-01T12:00:00Z',
              },
            },
          },
        ],
      },
    };

http.Response responseFor(http.Request request) => http.Response(
      jsonEncode(request.url.path.endsWith('/airtime-pricing')
          ? airtimeResponse()
          : pricingResponse()),
      200,
    );

BusinessNetworkAdminApi apiFor(http.Client client) => BusinessNetworkAdminApi(
      client: client,
      tokenProvider: () async => 'test-token',
      baseUrl: 'https://example.test/api',
    );

void main() {
  testWidgets('customer price is read-only and Airtime shows the API reason',
      (WidgetTester tester) async {
    final MockClient client = MockClient((http.Request request) async =>
        responseFor(request));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BusinessPricingManagement(api: apiFor(client))),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('Customer price · ₦120'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Customer price · ₦120'), findsOneWidget);
    expect(
      find.textContaining('Use the existing Admin DATA Pricing screen'),
      findsOneWidget,
    );
    expect(find.text('Customer markup · 125 bps (read-only)'), findsOneWidget);
    expect(find.textContaining('Provider cost · unknown until invoice'),
        findsOneWidget);
    expect(find.text('Provider discounts and invoice cost are not known.'),
        findsOneWidget);
    expect(find.text('Inherits customer markup'), findsOneWidget);
    expect(find.text('Independent rule'), findsOneWidget);
    expect(find.text('Provider cost · unknown until invoice'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('pricing-price-plan-01-CUSTOMER')),
      findsNothing,
    );
    expect(
      tester
          .widget<TextField>(
              find.byKey(const ValueKey<String>('airtime-markup-01-MERCHANT')))
          .controller
          ?.text,
      '125',
    );
    client.close();
  });

  testWidgets('pricing requires a reason and reports server save errors',
      (WidgetTester tester) async {
    var putCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      if (request.method == 'PUT') {
        putCount += 1;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': false,
            'message': 'Pricing revision is stale.',
          }),
          409,
        );
      }
      return responseFor(request);
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BusinessPricingManagement(api: apiFor(client))),
    ));
    await tester.pumpAndSettle();

    final Finder agentSave =
        find.byKey(const ValueKey<String>('pricing-save-plan-01-AGENT'));
    await tester.scrollUntilVisible(
      agentSave,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(agentSave);
    await tester.pumpAndSettle();
    await tester.tap(agentSave);
    await tester.pumpAndSettle();
    expect(putCount, 0);
    expect(find.text('Add a reason before saving pricing.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('business-pricing-reason')),
      'Approved provider cost review',
    );
    tester.testTextInput.hide();
    await tester.pump();
    await tester.ensureVisible(agentSave);
    await tester.pumpAndSettle();
    await tester.tap(agentSave);
    await tester.pumpAndSettle();
    expect(putCount, 1);
    expect(find.text('Pricing revision is stale.'), findsOneWidget);
    client.close();
  });

  testWidgets('Airtime markup save uses basis points and requires a reason',
      (WidgetTester tester) async {
    var putCount = 0;
    Map<String, dynamic>? submitted;
    final MockClient client = MockClient((http.Request request) async {
      if (request.method == 'PUT') {
        putCount += 1;
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{'saved': true},
        }), 200);
      }
      return responseFor(request);
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BusinessPricingManagement(api: apiFor(client))),
    ));
    await tester.pumpAndSettle();

    final Finder save =
        find.byKey(const ValueKey<String>('airtime-save-01-AGENT'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(putCount, 0);
    expect(find.text('Add a reason before saving pricing.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('business-pricing-reason')),
      'Approved markup schedule',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('airtime-markup-01-AGENT')),
      '0',
    );
    tester.testTextInput.hide();
    await tester.pump();
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(putCount, 1);
    expect(submitted?['revision'], 3);
    expect(submitted?['reason'], 'Approved markup schedule');
    expect(submitted?['changes'], <dynamic>[
      <String, dynamic>{
        'network': '01',
        'category': 'AGENT',
        'enabled': true,
        'markupBps': 0,
      },
    ]);
    client.close();
  });
}
