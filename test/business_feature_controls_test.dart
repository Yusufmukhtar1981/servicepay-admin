import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/business_network/business_feature_controls.dart';
import 'package:servicepay_app/admin/business_network/business_network_admin_api.dart';

Map<String, dynamic> controlsResponse() => <String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'revision': 18,
        'states': <String>[
          'ENABLED',
          'DISABLED',
          'COMING_SOON',
          'MAINTENANCE',
        ],
        'provider': 'ServicePay',
        'features': <Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'payouts',
            'label': 'Wallet payouts',
            'ready': false,
            'categories': <String, String>{
              'CUSTOMER': 'DISABLED',
              'AGENT': 'DISABLED',
            },
            'reason': 'Payout rail is being verified.',
          },
          <String, dynamic>{
            'key': 'wallet-history',
            'label': 'Wallet history',
            'ready': true,
            'history': true,
            'categories': <String, String>{'MERCHANT': 'ENABLED'},
          },
        ],
      },
    };

BusinessNetworkAdminApi apiFor(http.Client client) => BusinessNetworkAdminApi(
      client: client,
      tokenProvider: () async => 'test-token',
      baseUrl: 'https://example.test/api',
    );

void main() {
  testWidgets(
      'unsupported capabilities cannot be enabled and history stays enabled',
      (WidgetTester tester) async {
    final MockClient client = MockClient((http.Request request) async {
      if (request.url.path.endsWith('/configuration-history')) {
        return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{'items': <dynamic>[]},
            }),
            200);
      }
      return http.Response(jsonEncode(controlsResponse()), 200);
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BusinessFeatureControls(api: apiFor(client))),
    ));
    await tester.pumpAndSettle();

    final Finder payout = find.byKey(
      const ValueKey<String>('feature-AGENT-payouts'),
    );
    await tester.ensureVisible(payout);
    await tester.tap(payout);
    await tester.pumpAndSettle();
    expect(find.text('Enabled').evaluate().length, 1);
    expect(find.text('Coming soon'), findsOneWidget);
    await tester.tap(find.text('Coming soon'));
    await tester.pumpAndSettle();

    final Finder history = find.byKey(
      const ValueKey<String>('feature-MERCHANT-wallet-history'),
    );
    await tester.ensureVisible(history);
    final DropdownButtonFormField<String> historyField =
        tester.widget<DropdownButtonFormField<String>>(history);
    expect(historyField.initialValue, 'ENABLED');
    expect(historyField.onChanged, isNull);
    expect(find.text('This capability has history and remains enabled.'),
        findsOneWidget);
    client.close();
  });

  testWidgets('feature changes require a reason and expose save errors',
      (WidgetTester tester) async {
    var putCount = 0;
    Map<String, dynamic>? submitted;
    final MockClient client = MockClient((http.Request request) async {
      if (request.method == 'PUT') {
        putCount += 1;
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': false,
            'message': 'Configuration revision is stale.',
          }),
          409,
        );
      }
      return http.Response(jsonEncode(controlsResponse()), 200);
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BusinessFeatureControls(api: apiFor(client))),
    ));
    await tester.pumpAndSettle();

    final Finder payout = find.byKey(
      const ValueKey<String>('feature-AGENT-payouts'),
    );
    await tester.scrollUntilVisible(
      payout,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(payout);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coming soon'));
    await tester.pumpAndSettle();

    final Finder save =
        find.byKey(const ValueKey<String>('business-feature-save'));
    await tester.scrollUntilVisible(
      save,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(putCount, 0);
    expect(find.text('Add a reason before saving capability changes.'),
        findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('business-feature-reason')),
      'Provider readiness review',
    );
    tester.testTextInput.hide();
    await tester.pump();
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(putCount, 1);
    expect(submitted?['revision'], 18);
    expect(submitted?['features']['AGENT']['payouts'], 'COMING_SOON');
    expect(find.text('Configuration revision is stale.'), findsOneWidget);
    client.close();
  });
}
