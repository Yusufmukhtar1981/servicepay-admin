import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';

/// Read-only operational intelligence plus carefully scoped support actions.
/// Financial mutations are deliberately not exposed by this client.
class AdminStaffWorkspaceApi {
  AdminStaffWorkspaceApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrl = baseUrl ?? defaultBaseUrl;

  static const String defaultBaseUrl =
      '${AdminApiConfiguration.baseUrl}/admin/staff-workspace';
  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<Map<String, dynamic>> overview() => _request('GET', 'overview');

  /// Requests idempotent creation of the two standard workspace roles.
  /// No scope, activation, or permission overrides are sent from the client.
  Future<Map<String, dynamic>> provisionRoles() =>
      _request('POST', 'provision-roles', payload: <String, dynamic>{});

  Future<Map<String, dynamic>> staffHistory(String staffId) => _request(
        'GET',
        'staff/${Uri.encodeComponent(staffId)}/history',
      );

  Future<Map<String, dynamic>> customers({
    String query = '',
    int page = 1,
    int limit = 20,
  }) =>
      _request('GET', 'customers', query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'page': '$page',
        'limit': '$limit',
      });

  Future<Map<String, dynamic>> customer(String id) =>
      _request('GET', 'customers/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> transactions({
    String status = '',
    String type = '',
    int page = 1,
    int limit = 20,
  }) =>
      _request('GET', 'transactions', query: {
        if (status.isNotEmpty) 'status': status,
        if (type.isNotEmpty) 'type': type,
        'page': '$page',
        'limit': '$limit',
      });

  Future<Map<String, dynamic>> createTicket({
    required String customerId,
    required String subject,
    required String description,
    required String category,
    required String priority,
    required String idempotencyKey,
    String? transactionId,
  }) =>
      _request('POST', 'tickets', payload: {
        'customerId': customerId,
        'subject': subject,
        'description': description,
        'category': category,
        'priority': priority,
        'idempotencyKey': idempotencyKey,
        if (transactionId != null && transactionId.isNotEmpty)
          'transactionId': transactionId,
      });

  Future<Map<String, dynamic>> escalateTicket(
    String id,
    String reason,
  ) =>
      _request('POST', 'tickets/${Uri.encodeComponent(id)}/escalate',
          payload: {'reason': reason});

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? payload,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String token =
        (prefs.getString('auth_token') ?? prefs.getString('token') ?? '')
            .trim()
            .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
    if (token.isEmpty) {
      throw Exception(
          'Your login session was not found. Please sign in again.');
    }
    final Uri uri =
        Uri.parse('$_baseUrl/$path').replace(queryParameters: query);
    final Map<String, String> headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (payload != null) 'Content-Type': 'application/json',
    };
    final http.Response response = method == 'POST'
        ? await _client
            .post(uri, headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 30))
        : await _client.get(uri, headers: headers).timeout(
              const Duration(seconds: 30),
            );
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    final Map<String, dynamic> result = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        result['success'] == false) {
      throw Exception(
        '${result['message'] ?? 'Workspace request failed.'}',
      );
    }
    return result;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
