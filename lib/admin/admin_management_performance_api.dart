import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminManagementPerformanceApi {
  AdminManagementPerformanceApi({
    http.Client? client,
    String? baseUrl,
    Future<SharedPreferences> Function()? preferencesLoader,
  })  : baseUrl = (baseUrl ??
                const String.fromEnvironment('SERVICEPAY_API_BASE_URL',
                    defaultValue: 'https://api.servicepay.ng/api'))
            .replaceFirst(RegExp(r'/$'), ''),
        _client = client ?? http.Client(),
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final String baseUrl;
  final http.Client _client;
  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<Map<String, dynamic>> managers({
    required String role,
    String search = '',
    int page = 1,
    int limit = 25,
  }) =>
      _json('/admin/management-performance/managers', <String, String>{
        'role': role,
        'search': search.trim(),
        'page': '$page',
        'limit': '$limit',
      });

  Future<Map<String, dynamic>> report({
    required String managerId,
    required String period,
    required String from,
    required String to,
  }) =>
      _json('/admin/management-performance/report', <String, String>{
        'managerId': managerId,
        'period': period,
        'from': from,
        'to': to,
      });

  Future<AdminManagementPerformanceFile> export({
    required String managerId,
    required String period,
    required String from,
    required String to,
    required String format,
  }) async {
    final String token = await _token();
    final Uri uri =
        Uri.parse('$baseUrl/admin/management-performance/export').replace(
      queryParameters: <String, String>{
        'managerId': managerId,
        'period': period,
        'from': from,
        'to': to,
        'format': format,
      },
    );
    final http.Response response = await _client
        .get(uri, headers: _headers(token, accept: '*/*'))
        .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AdminManagementPerformanceException(
        response.statusCode,
        _errorMessage(response.body, response.statusCode),
      );
    }
    final String contentType =
        response.headers['content-type']?.split(';').first.trim() ?? '';
    final String expected = format == 'pdf'
        ? 'application/pdf'
        : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (contentType != expected || response.bodyBytes.isEmpty) {
      throw const AdminManagementPerformanceException(
          502, 'The server returned an invalid report file.');
    }
    return AdminManagementPerformanceFile(
      bytes: response.bodyBytes,
      contentType: expected,
      generatedAt: response.headers['x-report-generated-at'],
      format: format,
    );
  }

  Future<Map<String, dynamic>> _json(
      String path, Map<String, String> query) async {
    final String token = await _token();
    final Uri uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final http.Response response = await _client
        .get(uri, headers: _headers(token))
        .timeout(const Duration(seconds: 30));
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AdminManagementPerformanceException(
        response.statusCode,
        _errorMessage(response.body, response.statusCode),
      );
    }
    if (decoded is! Map || decoded['success'] != true) {
      throw const AdminManagementPerformanceException(
          502, 'The performance service returned an unexpected response.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Map<String, String> _headers(String token,
          {String accept = 'application/json'}) =>
      <String, String>{
        'Accept': accept,
        'Authorization': 'Bearer $token',
      };

  Future<String> _token() async {
    final SharedPreferences prefs = await _preferencesLoader();
    String token = (prefs.getString('auth_token') ?? '').trim();
    if (token.toLowerCase().startsWith('bearer ')) {
      token = token.substring(7).trim();
    }
    if (token.isEmpty) {
      throw const AdminManagementPerformanceException(
          401, 'Your session has expired. Sign in again.');
    }
    return token;
  }

  String _errorMessage(String body, int statusCode) {
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map && '${decoded['message'] ?? ''}'.trim().isNotEmpty) {
        return '${decoded['message']}'.trim();
      }
    } catch (_) {
      // Keep the status-specific safe fallback below.
    }
    return statusCode == 401
        ? 'Your session has expired. Sign in again.'
        : 'Unable to load management performance (HTTP $statusCode).';
  }
}

class AdminManagementPerformanceFile {
  const AdminManagementPerformanceFile({
    required this.bytes,
    required this.contentType,
    required this.format,
    this.generatedAt,
  });

  final List<int> bytes;
  final String contentType;
  final String format;
  final String? generatedAt;

  String get filename => 'servicepay-management-performance.$format';
}

class AdminManagementPerformanceException implements Exception {
  const AdminManagementPerformanceException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}
