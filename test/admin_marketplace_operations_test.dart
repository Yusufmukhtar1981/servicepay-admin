import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_marketplace_operations_api.dart';
import 'package:servicepay_app/admin/admin_marketplace_operations_screens.dart';

void main() {
  workflowTests();
  deliveryRecipientTests();
  test('percent and bps conversion', () {
    expect(percentToBps('3'), 300);
    expect(percentToBps('2.5%'), 250);
    expect(percentToBps('101'), isNull);
    expect(percentToBps(''), isNull);
    expect(bpsToPercent(300), '3');
    expect(bpsToPercent(null), '');
  });

  test('fulfillment transitions mirror server', () {
    expect(mpNextFulfillmentStatus('PAID', 'DELIVERY', 'PAID', 'HELD'), 'ACCEPTED');
    expect(mpNextFulfillmentStatus('READY', 'PICKUP', 'PAID', 'HELD'), isNull);
    expect(mpNextFulfillmentStatus('READY', 'DELIVERY', 'PAID', 'HELD'), 'SHIPPED');
    expect(mpNextFulfillmentStatus('DELIVERED', 'DELIVERY', 'PAID', 'SETTLED'), isNull);
  });

  test('settings save sends confirmation, version and bps', () async {
    late Map body;
    final api = AdminMarketplaceOperationsApi(
      baseUrl: 'http://preview/api',
      tokenReader: () async => 't',
      client: MockClient((req) async {
        body = jsonDecode(req.body) as Map;
        expect(req.url.toString(), 'http://preview/api/admin/marketplace/settings');
        return http.Response(jsonEncode({'success': true, 'canManage': true, 'settings': {...body, 'version': 4}}), 200);
      }),
    );
    final saved = await api.saveSettings(
      const MarketplaceSettings(enabled: true, defaultRateBps: 300, merchantOverrides: [], categoryOverrides: [],
          deliveryEnabled: false, deliveryFee: null, version: 3),
      expectedVersion: 3, reason: 'Approved by Head Office board');
    expect(body['confirmation'], 'CONFIRM_MARKETPLACE_POLICY');
    expect(body['expectedVersion'], 3);
    expect(body['defaultRateBps'], 300);
    expect(saved.settings.version, 4);
  });

  test('real API error message is surfaced', () async {
    final api = AdminMarketplaceOperationsApi(
      baseUrl: 'http://preview/api', tokenReader: () async => null,
      client: MockClient((_) async => http.Response(jsonEncode({'success': false, 'message': 'Storage not provisioned'}), 503)));
    expect(() => api.analytics(), throwsA(predicate((e) => e.toString() == 'Storage not provisioned')));
  });

  testWidgets('merchant profile shows six tabs and unavailable wallet', (tester) async {
    final api = AdminMarketplaceOperationsApi(
      baseUrl: 'http://preview/api', tokenReader: () async => null,
      client: MockClient((_) async => http.Response(jsonEncode({
        'success': true,
        'merchant': {'_id': 'm1', 'storeName': 'Mama Tunde Foods', 'status': 'ACTIVE'},
        'products': [], 'orders': [], 'transactions': [],
        'summary': {'totalSales': 1250.5},
        'verification': {'status': 'PENDING', 'documents': []},
        'paymentDetails': {'available': false, 'message': 'Bank details not configured.'},
        'wallet': {'available': false, 'message': 'No separate merchant wallet.'},
      }), 200)));
    await tester.pumpWidget(MaterialApp(home: AdminMarketplaceMerchantProfileScreen(merchantId: 'm1', api: api)));
    await tester.pumpAndSettle();
    for (final t in ['Overview', 'Business Information', 'Products', 'Orders', 'Transactions', 'Verification']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('No separate merchant wallet.'), findsOneWidget);
  });
}

AdminMarketplaceOperationsApi _api(Future<http.Response> Function(http.Request) h) =>
    AdminMarketplaceOperationsApi(baseUrl: 'http://preview/api', tokenReader: () async => 'mock', client: MockClient(h));

http.Response _ok(Object b) => http.Response(jsonEncode(b), 200);

void workflowTests() {
  testWidgets('merchant listing renders and filters by status', (tester) async {
    final seen = <Uri>[];
    final api = _api((req) async {
      seen.add(req.url);
      return _ok({
        'success': true,
        'merchants': [
          {'_id': 'm1', 'storeName': 'Ibadan Spice House', 'status': 'ACTIVE', 'state': 'Oyo', 'user': {'fullName': 'Adaeze Okafor'}}
        ],
        'pagination': {'page': 1, 'pages': 1, 'total': 1, 'limit': 20},
      });
    });
    await tester.pumpWidget(MaterialApp(home: AdminMarketplaceMerchantsScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Ibadan Spice House'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'SUSPENDED'));
    await tester.pumpAndSettle();
    expect(seen.last.queryParameters['status'], 'SUSPENDED');
  });

  testWidgets('read-only settings disable editing and hide submit', (tester) async {
    final api = _api((_) async => _ok({
          'success': true,
          'canManage': false,
          'settings': {'enabled': false, 'defaultRateBps': 300, 'merchantOverrides': [], 'categoryOverrides': [],
            'deliveryEnabled': false, 'deliveryFee': null, 'version': 2},
        }));
    await tester.pumpWidget(MaterialApp(home: AdminMarketplaceSettingsScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Read only'), findsOneWidget);
    expect(find.text('Review and submit policy'), findsNothing);
    final field = tester.widget<TextField>(find.descendant(of: find.byKey(const Key('mp-default-rate')), matching: find.byType(TextField)));
    expect(field.enabled, isFalse);
    expect(field.controller!.text, '3');
  });

  testWidgets('merchant wallet balance and KYC metadata shown', (tester) async {
    final api = _api((_) async => _ok({
          'success': true,
          'merchant': {'_id': 'm1', 'storeName': 'Ibadan Spice House', 'status': 'ACTIVE'},
          'products': [], 'orders': [], 'transactions': [], 'summary': {},
          'verification': {'status': 'VERIFIED', 'kycStatus': 'APPROVED', 'kycLevel': 2, 'kycId': 'k77',
            'documents': [{'type': 'ID_FRONT', 'status': 'SUBMITTED', 'path': '/admin/kyc/k77/document/ID_FRONT'}]},
          'paymentDetails': {'available': false, 'message': 'Marketplace payout bank details have not been configured.'},
          'wallet': {'available': true, 'balance': 48250.75, 'currency': 'NGN', 'type': 'EXISTING_MAIN_WALLET',
            'message': 'Existing main wallet; not a separate Marketplace-only balance.'},
        }));
    await tester.pumpWidget(MaterialApp(home: AdminMarketplaceMerchantProfileScreen(merchantId: 'm1', api: api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('48,250.75'), findsOneWidget);
    expect(find.text('Existing main wallet; not a separate Marketplace-only balance.'), findsOneWidget);
    await tester.ensureVisible(find.text('Verification'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verification'));
    await tester.pumpAndSettle();
    Finder sel(String t) => find.byWidgetPredicate((w) => w is SelectableText && w.data == t);
    expect(sel('APPROVED'), findsOneWidget);
    expect(sel('2'), findsOneWidget);
    expect(sel('k77'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
  });

  test('KYC document uses auth header and rejects foreign paths', () async {
    late http.Request captured;
    final api = _api((req) async {
      captured = req;
      return http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'image/png'});
    });
    final doc = await api.kycDocument('/admin/kyc/k77/document/ID_FRONT');
    expect(captured.url.toString(), 'http://preview/api/admin/kyc/k77/document/ID_FRONT');
    expect(captured.headers['Authorization'], 'Bearer mock');
    expect(doc.bytes, [1, 2, 3]);
    expect(() => api.kycDocument('https://evil.example/x'), throwsA(isA<MarketplaceApiException>()));
  });
}

void deliveryRecipientTests() {
  test('deliveryFeeRecipient serializes and stays optional', () {
    final legacy = MarketplaceSettings.fromJson({'enabled': false, 'deliveryEnabled': false, 'version': 1});
    expect(legacy.deliveryFeeRecipient, isNull);
    expect(legacy.toJson().containsKey('deliveryFeeRecipient'), isTrue);
    expect(legacy.toJson()['deliveryFeeRecipient'], isNull);
    final set = MarketplaceSettings.fromJson({'deliveryEnabled': true, 'deliveryFee': 1500, 'deliveryFeeRecipient': 'merchant', 'version': 2});
    expect(set.deliveryFeeRecipient, 'MERCHANT');
    expect(set.toJson()['deliveryFeeRecipient'], 'MERCHANT');
  });

  test('paid delivery requires explicit supported recipient', () {
    expect(MarketplaceSettings.validateDeliveryRecipient(deliveryEnabled: true, deliveryFee: 1500, recipient: null), isNotNull);
    expect(MarketplaceSettings.validateDeliveryRecipient(deliveryEnabled: true, deliveryFee: 1500, recipient: 'MERCHANT'), isNull);
    expect(MarketplaceSettings.validateDeliveryRecipient(deliveryEnabled: true, deliveryFee: 0, recipient: null), isNull);
    expect(MarketplaceSettings.validateDeliveryRecipient(deliveryEnabled: false, deliveryFee: 1500, recipient: null), isNull);
    expect(MarketplaceSettings.validateDeliveryRecipient(deliveryEnabled: true, deliveryFee: 1500, recipient: 'COURIER'), isNotNull);
  });

  testWidgets('recipient dropdown appears unselected for paid delivery', (tester) async {
    final api = _api((_) async => _ok({
          'success': true,
          'canManage': true,
          'settings': {'enabled': false, 'defaultRateBps': 300, 'merchantOverrides': [], 'categoryOverrides': [],
            'deliveryEnabled': true, 'deliveryFee': 1500, 'deliveryFeeRecipient': null, 'version': 3},
        }));
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AdminMarketplaceSettingsScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mp-delivery-recipient')), findsOneWidget);
    expect(find.text('Not selected'), findsOneWidget);
    await tester.tap(find.text('Review and submit policy'));
    await tester.pumpAndSettle();
    expect(find.text('Choose who receives the delivery fee before enabling paid delivery.'), findsOneWidget);
    expect(find.text('Submit marketplace policy'), findsNothing);
  });
}
