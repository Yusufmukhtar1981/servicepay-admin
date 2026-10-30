import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:servicepay_app/admin/admin_ai_support_center_screen.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/admin_support_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QueueClient extends http.BaseClient {
  _QueueClient(this.responses);
  final Map<String, http.Response> responses;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];
  final List<String> bodies = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    bodies.add(utf8.decode(await request.finalize().toBytes()));
    final String key =
        request.method == 'PUT' && request.url.path.endsWith('/ai-settings')
            ? 'PUT /ai-settings'
            : request.url.path.split('/').last;
    final response = responses[key]!;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'admin-test-session',
    });
  });

  testWidgets('AI Support view permission blocks every AI endpoint',
      (tester) async {
    final client = _QueueClient(<String, http.Response>{});
    final api = AdminSupportApi(
      client: client,
      aiBaseUrlOverride: 'https://staging.servicepay.invalid/api',
    );
    await tester.pumpWidget(MaterialApp(
      home: AdminAiSupportCenterScreen(
        api: api,
        initialAccess:
            const AdminAccess(role: 'STAFF', permissions: <String>{}),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('do not have permission'), findsOneWidget);
    expect(client.requests, isEmpty);
  });

  testWidgets('metrics persist and voice setting remains quality gated',
      (tester) async {
    final client = _QueueClient(<String, http.Response>{
      'ai-metrics': http.Response('{"data":{"conversations":6}}', 200),
      'ai-settings': http.Response(
        '{"data":{"enabled":true,"retentionDays":30,"dailyBudgetUsd":2,"englishVoiceEnabled":true,"englishVoiceVerified":false}}',
        200,
      ),
      'ai-conversations': http.Response(
        '{"data":{"items":[],"page":1,"pages":1}}',
        200,
      ),
      'ai-knowledge':
          http.Response('{"data":{"articles":[],"revision":2}}', 200),
      'PUT /ai-settings': http.Response(
        '{"data":{"enabled":true,"retentionDays":30,"dailyBudgetUsd":2,"englishVoiceEnabled":false,"englishVoiceVerified":false}}',
        200,
      ),
    });
    final api = AdminSupportApi(
      client: client,
      aiBaseUrlOverride: 'https://staging.servicepay.invalid/api',
    );
    await tester.pumpWidget(MaterialApp(
      home: AdminAiSupportCenterScreen(
        api: api,
        initialAccess: const AdminAccess(
          role: 'HEAD_OFFICE',
          permissions: <String>{
            AdminPermissions.supportView,
            AdminPermissions.supportResolve,
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('6'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save controls'));
    await tester.tap(find.text('Save controls'));
    await tester.pumpAndSettle();

    final saved = jsonDecode(client.bodies.last) as Map<String, dynamic>;
    expect(saved['englishVoiceEnabled'], isFalse);
    expect(saved['hausaVoiceEnabled'], isFalse);
    await tester.drag(find.byType(ListView).first, const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.text('6'), findsOneWidget);
  });
}
