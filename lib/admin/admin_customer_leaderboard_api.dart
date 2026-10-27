import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminCustomerLeaderboardApi {
  AdminCustomerLeaderboardApi({http.Client? client, String? baseUrl})
      : baseUrl = (baseUrl ??
                const String.fromEnvironment('SERVICEPAY_API_BASE_URL',
                    defaultValue: 'https://api.servicepay.ng/api'))
            .replaceFirst(RegExp(r'/$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    var token = (prefs.getString('auth_token') ?? '').trim();
    if (token.toLowerCase().startsWith('bearer ')) {
      token = token.substring(7).trim();
    }
    if (token.isEmpty) {
      throw const FormatException('Admin session not found. Sign in again.');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token'
    };
  }

  Future<Map<String, dynamic>> _json(String method, String path,
      {Map<String, String>? query, Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl/customer-leaderboard$path')
        .replace(queryParameters: query);
    final headers = await _headers();
    final response = method == 'PATCH'
        ? await _client
            .patch(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 30))
        : await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 30));
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    final result = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = response.statusCode == 409
          ? 'Settings changed elsewhere. Reload the current rules before saving.'
          : result['message']?.toString() ??
              'Customer leaderboard request failed.';
      throw AdminCustomerLeaderboardException(message, response.statusCode);
    }
    if (result['success'] != true) {
      throw const AdminCustomerLeaderboardException(
          'Unexpected leaderboard response.');
    }
    return result;
  }

  Future<Map<String, dynamic>> settings() => _json('GET', '/admin/settings');
  Future<Map<String, dynamic>> history() => _json('GET', '/admin/history');
  Future<Map<String, dynamic>> report(String month, int limit, String sort) =>
      _json('GET', '/admin',
          query: {'month': month, 'limit': '$limit', 'sort': sort});
  Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> body) =>
      _json('PATCH', '/admin/settings', body: body);
  Future<String> export(String month, int limit, String sort) async {
    final uri = Uri.parse('$baseUrl/customer-leaderboard/admin/export').replace(
        queryParameters: {'month': month, 'limit': '$limit', 'sort': sort});
    final response = await _client
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AdminCustomerLeaderboardException(
          'Could not export this report.', response.statusCode);
    }
    return response.body;
  }
}

class AdminCustomerLeaderboardException implements Exception {
  const AdminCustomerLeaderboardException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
