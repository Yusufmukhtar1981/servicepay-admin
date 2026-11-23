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
          <String, dynamic>{
            'code': 'plan-02',
            'pricingCode': 'DATA-500MB',
            'name': '500 MB bundle',
            'networkCode': '01',
            'provider': 'Verified Provider',
            'providerCost': 50,
            'revision': 9,
            'customer': <String, dynamic>{
              'sellingPrice': 60,
              'enabled': true,
            },
            'categories': <String, dynamic>{
              'AGENT': <String, dynamic>{
                'configured': false,
                'enabled': false,
                'effectivePrice': 70,
                'margin': 20,
                'available': true,
                'inherited': true,
              },
              'MERCHANT': <String, dynamic>{
                'configured': true,
                'enabled': true,
                'sellingPrice': 85,
                'maximumProviderCost': 60,
                'effectivePrice': 85,
                'margin': 35,
                'available': true,
                'inherited': false,
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
                'configured': true,
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

void useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> revealPricingReason(WidgetTester tester) async {
  tester.testTextInput.hide();
  await tester.pump();
  await tester.ensureVisible(
      find.byKey(const ValueKey<String>('business-pricing-reason')));
}

void main() {
  testWidgets('customer price is read-only and Airtime shows the API reason',
      (WidgetTester tester) async {
    useTallViewport(tester);
    final MockClient client = MockClient((http.Request request) async =>
        responseFor(request));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BusinessPricingManagement(api: apiFor(client))),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.textContaining('Customer price · ₦120'));
    expect(find.textContaining('Customer price · ₦120'), findsOneWidget);
    expect(
      find.textContaining('Use the existing Admin DATA Pricing screen'),
      findsNWidgets(2),
    );
    expect(find.text('Customer markup · 125 bps (read-only)'), findsOneWidget);
    expect(find.textContaining('Provider cost · unknown until invoice'),
        findsOneWidget);
    expect(find.text('Provider discounts and invoice cost are not known.'),
        findsOneWidget);
    expect(find.text('Not configured · unavailable'), findsOneWidget);
    expect(find.text('Inherits customer markup'), findsNothing);
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
    useTallViewport(tester);
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
    await tester.ensureVisible(agentSave);
    await tester.pumpAndSettle();
    await tester.tap(agentSave);
    await tester.pumpAndSettle();
    expect(putCount, 0);
    expect(find.text('Add a reason before saving pricing.'), findsOneWidget);

    await revealPricingReason(tester);
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

  testWidgets('Save all batches only changed Data rules and keeps defaults out',
      (WidgetTester tester) async {
    useTallViewport(tester);
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

    final Finder saveAll =
        find.byKey(const ValueKey<String>('business-pricing-save-all'));
    await tester.ensureVisible(saveAll);
    expect(
      tester.widget<FilledButton>(saveAll).onPressed,
      isNull,
      reason: 'A fresh load must not turn inherited defaults into edits.',
    );
    Future<void> edit(String key, String value) async {
      final Finder field = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }

    await edit('pricing-price-plan-01-AGENT', '155');
    await edit('pricing-ceiling-plan-02-MERCHANT', '75');
    await tester.ensureVisible(saveAll);
    expect(tester.widget<FilledButton>(saveAll).onPressed, isNotNull);
    await tester.pumpAndSettle();
    await tester.tap(saveAll);
    await tester.pumpAndSettle();
    expect(putCount, 0);
    expect(find.text('Add a reason before saving pricing.'), findsOneWidget);

    final Finder reason =
        find.byKey(const ValueKey<String>('business-pricing-reason'));
    await revealPricingReason(tester);
    await tester.enterText(
      reason,
      'Approved batch price review',
    );
    tester.testTextInput.hide();
    await tester.pump();
    await tester.ensureVisible(saveAll);
    await tester.pumpAndSettle();
    await tester.tap(saveAll);
    await tester.pumpAndSettle();

    expect(putCount, 1);
    expect(submitted?['network'], '01');
    expect(submitted?['reason'], 'Approved batch price review');
    final List<dynamic> changes = submitted?['changes'] as List<dynamic>;
    expect(changes, hasLength(2));
    expect(changes[0], <String, dynamic>{
      'code': 'plan-01',
      'category': 'AGENT',
      'revision': 7,
      'rule': <String, dynamic>{
        'enabled': true,
        'sellingPrice': 155.0,
        'maximumProviderCost': 110.0,
      },
    });
    expect(changes[1], <String, dynamic>{
      'code': 'plan-02',
      'category': 'MERCHANT',
      'revision': 9,
      'rule': <String, dynamic>{
        'enabled': true,
        'sellingPrice': 85.0,
        'maximumProviderCost': 75.0,
      },
    });
    expect(find.text('Saved 2 Data pricing changes.'), findsOneWidget);
    client.close();
  });

  testWidgets('Save all validates every draft before any batch write',
      (WidgetTester tester) async {
    useTallViewport(tester);
    var putCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      if (request.method == 'PUT') {
        putCount += 1;
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

    Future<void> edit(String key, String value) async {
      final Finder field = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }

    await edit('pricing-price-plan-01-AGENT', '155');
    await edit('pricing-ceiling-plan-02-MERCHANT', '90');
    final Finder reason =
        find.byKey(const ValueKey<String>('business-pricing-reason'));
    await revealPricingReason(tester);
    await tester.enterText(reason, 'Validate full batch');
    tester.testTextInput.hide();
    await tester.pump();
    final Finder saveAll =
        find.byKey(const ValueKey<String>('business-pricing-save-all'));
    await tester.ensureVisible(saveAll);
    await tester.pumpAndSettle();
    await tester.tap(saveAll);
    await tester.pumpAndSettle();

    expect(putCount, 0);
    expect(
      find.textContaining(
        'MERCHANT · 500 MB bundle selling price must cover its provider-cost ceiling.',
      ),
      findsOneWidget,
    );
    client.close();
  });

  testWidgets('Airtime markup save uses basis points and requires a reason',
      (WidgetTester tester) async {
    useTallViewport(tester);
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
