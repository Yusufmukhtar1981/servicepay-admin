import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/pending_resolution_api.dart';
import 'package:servicepay_app/admin/pending_resolution_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows live totals and a composed empty state', (tester) async {
    final _PendingApi api = _PendingApi();
    await tester.pumpWidget(
      MaterialApp(
        home: PendingResolutionScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pending Transactions Resolution Center'), findsOneWidget);
    expect(find.text('Live operating picture'), findsOneWidget);
    expect(find.text('1,238'), findsOneWidget);
    expect(find.textContaining('not all provider settlements'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('No transactions match these filters'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No transactions match these filters'), findsOneWidget);
  });
}

class _PendingApi extends PendingResolutionApi {
  _PendingApi() : super(tokenProvider: _token);

  static Future<String?> _token() async => 'widget-token';

  @override
  Future<Map<String, dynamic>> summary() async => <String, dynamic>{
        'success': true,
        'data': <String, dynamic>{
          'generatedAt': '2026-04-21T10:00:00Z',
          'totalPending': 1238,
          'pendingAmount': 108420.75,
          'below5Minutes': 18,
          'above5Minutes': 96,
          'above30Minutes': 20,
          'above1Hour': 4,
          'resolvedCount': 73,
          'refundedAmount': 4812.50,
          'notice': 'Provider response latency is elevated.',
          'monitor': <String, dynamic>{
            'checkedAt': '2026-04-21T09:59:00Z',
            'healthy': false,
            'notice': 'One provider is delayed.',
          },
        },
      };

  @override
  Future<Map<String, dynamic>> transactions({
    int page = 1,
    int limit = 20,
    String search = '',
    String type = '',
    String from = '',
    String to = '',
    String minAmount = '',
    String maxAmount = '',
    String duration = 'ALL',
    String status = 'PENDING',
  }) async =>
      <String, dynamic>{
        'success': true,
        'data': <String, dynamic>{
          'items': <dynamic>[],
          'page': page,
          'limit': limit,
          'total': 0,
          'pages': 1,
          'generatedAt': '2026-04-21T10:00:00Z',
        },
      };
}
