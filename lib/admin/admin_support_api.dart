import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminSupportApi {
  AdminSupportApi({http.Client? client, String? aiBaseUrlOverride})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      aiApiBaseUrl = aiBaseUrlOverride ?? configuredAiApiBaseUrl;
  static const baseUrl = 'https://api.servicepay.ng/api/admin/support';
  static const configuredAiApiBaseUrl = String.fromEnvironment(
    'SERVICEPAY_API_BASE_URL',
    defaultValue: '',
  );
  final http.Client _client;
  final bool _ownsClient;
  final String aiApiBaseUrl;

  Future<Map<String, dynamic>> metrics() => _request('GET', 'metrics');
  Future<Map<String, dynamic>> aiMetrics() => _aiRequest('GET', 'ai-metrics');
  Future<Map<String, dynamic>> aiSettings() =>
      _aiRequest('GET', 'ai-settings');
  Future<Map<String, dynamic>> saveAiSettings(
    Map<String, dynamic> payload,
  ) =>
      _aiRequest('PUT', 'ai-settings', payload: payload);
  Future<Map<String, dynamic>> aiConversations({
    int page = 1,
    int limit = 20,
  }) =>
      _aiRequest(
        'GET',
        'ai-conversations',
        query: {'page': '$page', 'limit': '$limit'},
      );
  Future<Map<String, dynamic>> aiConversation(String id) =>
      _aiRequest('GET', 'ai-conversations/${Uri.encodeComponent(id)}');
  Future<Map<String, dynamic>> aiKnowledge() =>
      _aiRequest('GET', 'ai-knowledge');
  Future<Map<String, dynamic>> saveAiKnowledge(
    Map<String, dynamic> payload,
  ) =>
      _aiRequest('PUT', 'ai-knowledge', payload: payload);

  Future<Map<String, dynamic>> _aiRequest(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? payload,
  }) {
    if (aiApiBaseUrl.trim().isEmpty) {
      throw StateError(
        'Set SERVICEPAY_API_BASE_URL to the staging or local API before using AI Support administration.',
      );
    }
    final root = aiApiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final apiRoot = root.endsWith('/api') ? root : '$root/api';
    return _request(
      method,
      path,
      query: query,
      payload: payload,
      baseOverride: '$apiRoot/admin/support',
    );
  }
  Future<Map<String, dynamic>> tickets({
    String search = '',
    String status = '',
    String priority = '',
    String category = '',
    String assignedTo = '',
    int page = 1,
    int limit = 20,
  }) => _request(
    'GET',
    'tickets',
    query: {
      'search': search,
      'status': status,
      'priority': priority,
      'category': category,
      'assignedTo': assignedTo,
      'page': '$page',
      'limit': '$limit',
    }..removeWhere((k, v) => v.isEmpty),
  );
  Future<Map<String, dynamic>> ticket(String id) =>
      _request('GET', 'tickets/${Uri.encodeComponent(id)}');
  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> changes,
  ) =>
      _request('PATCH', 'tickets/${Uri.encodeComponent(id)}', payload: changes);
  Future<Map<String, dynamic>> reply(
    String id,
    String message, {
    required String idempotencyKey,
  }) => _request(
    'POST',
    'tickets/${Uri.encodeComponent(id)}/replies',
    payload: {'message': message.trim(), 'idempotencyKey': idempotencyKey},
  );
  Future<Map<String, dynamic>> note(
    String id,
    String note, {
    required String idempotencyKey,
  }) => _request(
    'POST',
    'tickets/${Uri.encodeComponent(id)}/notes',
    payload: {'body': note.trim(), 'idempotencyKey': idempotencyKey},
  );
  Future<List<Map<String, dynamic>>> staff(String search) async {
    final data = await _request(
      'GET',
      'staff',
      query: search.isEmpty ? null : {'search': search},
    );
    final nested = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'])
        : data;
    final raw = nested['staff'] ?? nested['users'] ?? nested['items'];
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? payload,
    String? baseOverride,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    String token =
        prefs.getString('auth_token')?.trim() ??
        prefs.getString('token')?.trim() ??
        '';
    token = token.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
    if (token.isEmpty) {
      throw Exception(
        'Your login session was not found. Please sign in again.',
      );
    }
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (payload != null) 'Content-Type': 'application/json',
    };
    final uri = Uri.parse('${baseOverride ?? baseUrl}/$path')
        .replace(queryParameters: query);
    final r = switch (method) {
      'PUT' =>
        await _client
            .put(uri, headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 30)),
      'PATCH' =>
        await _client
            .patch(uri, headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 30)),
      'POST' =>
        await _client
            .post(uri, headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 30)),
      _ =>
        await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 30)),
    };
    dynamic raw;
    try {
      raw = jsonDecode(r.body);
    } catch (_) {}
    final data = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    if (r.statusCode < 200 || r.statusCode >= 300 || data['success'] == false) {
      throw Exception((data['message'] ?? 'Support action failed.').toString());
    }
    return data;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
