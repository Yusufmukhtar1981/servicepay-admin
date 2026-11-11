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
  Future<Map<String, dynamic>> enterprise({String period = 'day'}) =>
      _request('GET', 'enterprise', query: {'period': period});

  Future<Map<String, dynamic>> operationalHub() =>
      _request('GET', 'operational-hub');

  Future<Map<String, dynamic>> directory({
    required String role,
    String? parentId,
    String query = '',
    int page = 1,
    int limit = 20,
  }) =>
      _request('GET', 'directory', query: {
        'role': role,
        if (parentId != null && parentId.isNotEmpty) 'parentId': parentId,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'page': '$page',
        'limit': '$limit',
      });

  Future<Map<String, dynamic>> activity({
    String period = 'day',
    int page = 1,
  }) =>
      _request('GET', 'activity', query: {'period': period, 'page': '$page'});

  Future<Map<String, dynamic>> updateCustomerProfile(
    String id, {
    required String fullName,
    required String address,
    required String reason,
  }) =>
      _request(
        'PATCH',
        'customers/${Uri.encodeComponent(id)}/profile',
        payload: {
          'fullName': fullName,
          'address': address,
          'reason': reason,
        },
      );

  Future<Map<String, dynamic>> marketplaceOperations({
    required String kind,
    String query = '',
    int page = 1,
  }) =>
      _request('GET', 'marketplace-operations', query: {
        'kind': kind,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'page': '$page',
      });

  Future<Map<String, dynamic>> updateMarketplaceSellerStatus(
    String id, {
    required String status,
    required String expectedStatus,
    required String reason,
  }) =>
      _request(
        'POST',
        'marketplace-sellers/${Uri.encodeComponent(id)}/status',
        payload: {
          'status': status,
          'expectedStatus': expectedStatus,
          'reason': reason,
        },
      );

  Future<Map<String, dynamic>> transactionDetail(String id) =>
      _request('GET', 'transactions/${Uri.encodeComponent(id)}/detail');

  Future<Map<String, dynamic>> updateCustomerStatus(
    String id, {
    required String status,
    required String reason,
  }) =>
      _request(
        'POST',
        'customers/${Uri.encodeComponent(id)}/status',
        payload: {'status': status, 'reason': reason},
      );

  Future<Map<String, dynamic>> updateServiceStatus(
    String key, {
    required bool enabled,
    required String reason,
  }) =>
      _request(
        'POST',
        'services/${Uri.encodeComponent(key)}/status',
        payload: {'enabled': enabled, 'reason': reason},
      );

  Future<WorkspaceExport> export({
    required String period,
    required String format,
    String? operationalType,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String token =
        (prefs.getString('auth_token') ?? prefs.getString('token') ?? '')
            .trim()
            .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
    if (token.isEmpty) {
      throw Exception(
          'Your login session was not found. Please sign in again.');
    }
    final Uri uri = Uri.parse(operationalType == null
        ? '$_baseUrl/enterprise/export' : '$_baseUrl/operational-report').replace(
      queryParameters: {'period': period, 'format': format,
        if (operationalType != null) 'type': operationalType},
    );
    final http.Response response = await _client.get(
      uri,
      headers: {
        'Accept': '*/*',
        'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
      final message = decoded is Map ? decoded['message']?.toString() : null;
      throw Exception(message?.isNotEmpty == true
          ? message!
          : 'Report export failed (${response.statusCode}).');
    }
    final String disposition = response.headers['content-disposition'] ?? '';
    final RegExpMatch? match =
        RegExp(r'filename="?([^";]+)"?', caseSensitive: false)
            .firstMatch(disposition);
    final String filename = match?.group(1) ?? 'servicepay-operations.$format';
    return WorkspaceExport(
      bytes: response.bodyBytes,
      contentType:
          response.headers['content-type'] ?? 'application/octet-stream',
      filename: filename,
    );
  }

  Future<Map<String, dynamic>> supportSummary() =>
      _request('GET', 'support-summary');

  Future<Map<String, dynamic>> reliability({int page = 1}) => _request(
        'GET',
        'transaction-reliability',
        query: {'page': '$page', 'limit': '20'},
      );

  Future<Map<String, dynamic>> virtualAccounts({
    String query = '',
    String status = '',
    int page = 1,
    int limit = 20,
  }) =>
      _request('GET', 'virtual-accounts', query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (status.isNotEmpty) 'status': status,
        'page': '$page',
        'limit': '$limit',
      });

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
    String status = '',
    String kycStatus = '',
    int page = 1,
    int limit = 20,
  }) =>
      _request('GET', 'customers', query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (status.isNotEmpty) 'status': status,
        if (kycStatus.isNotEmpty) 'kycStatus': kycStatus,
        'page': '$page',
        'limit': '$limit',
      });

  Future<Map<String, dynamic>> customer(String id) =>
      _request('GET', 'customers/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> transactions({
    String status = '',
    String type = '',
    String query = '',
    String customerId = '',
    String from = '',
    String to = '',
    String minAmount = '',
    String maxAmount = '',
    int page = 1,
    int limit = 20,
  }) =>
      _request('GET', 'transactions', query: {
        if (status.isNotEmpty) 'status': status,
        if (type.isNotEmpty) 'type': type,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (customerId.isNotEmpty) 'customerId': customerId,
        if (from.isNotEmpty) 'from': from,
        if (to.isNotEmpty) 'to': to,
        if (minAmount.isNotEmpty) 'minAmount': minAmount,
        if (maxAmount.isNotEmpty) 'maxAmount': maxAmount,
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
    final http.Response response = switch (method) {
      'POST' => await _client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 30)),
      'PATCH' => await _client
          .patch(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 30)),
      _ => await _client.get(uri, headers: headers).timeout(
            const Duration(seconds: 30),
          ),
    };
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
        result['success'] != true) {
      throw Exception(
        '${result['message'] ?? 'Workspace returned an invalid response.'}',
      );
    }
    if (result['data'] is! Map) {
      throw Exception('Workspace returned an invalid response.');
    }
    return result;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class WorkspaceExport {
  const WorkspaceExport({
    required this.bytes,
    required this.contentType,
    required this.filename,
  });
  final List<int> bytes;
  final String contentType;
  final String filename;
}
