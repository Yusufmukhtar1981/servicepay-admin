import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminAnnouncementsApi {
  AdminAnnouncementsApi({http.Client? client, String? baseUrl})
      : baseUrl = (baseUrl ??
                const String.fromEnvironment('SERVICEPAY_API_BASE_URL',
                    defaultValue: 'https://api.servicepay.ng/api'))
            .replaceFirst(RegExp(r'/$'), ''),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  Future<Map<String, dynamic>> list() => _request('GET', '');
  Future<Map<String, dynamic>> summary() => _request('GET', '/summary');
  Future<Map<String, dynamic>> create(Map<String, dynamic> payload) =>
      _request('POST', '', payload: payload);
  Future<Map<String, dynamic>> update(
          String id, Map<String, dynamic> payload) =>
      _request('PATCH', '/${Uri.encodeComponent(id)}', payload: payload);
  Future<Map<String, dynamic>> remove(String id) =>
      _request('DELETE', '/${Uri.encodeComponent(id)}');
  Future<Map<String, dynamic>> updateStatus(String id, bool active) =>
      _request('PATCH', '/${Uri.encodeComponent(id)}/status',
          payload: {'isActive': active});

  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, dynamic>? payload}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = [
      'auth_token',
      'token',
      'access_token',
      'accessToken',
      'jwt_token',
      'jwt'
    ]
        .map((key) => prefs.getString(key)?.trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final uri = Uri.parse('$baseUrl/announcements/admin$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (payload != null) 'Content-Type': 'application/json',
    };
    late http.Response response;
    final body = payload == null ? null : jsonEncode(payload);
    if (method == 'POST') {
      response = await _client.post(uri, headers: headers, body: body);
    } else if (method == 'PATCH') {
      response = await _client.patch(uri, headers: headers, body: body);
    } else if (method == 'DELETE') {
      response = await _client.delete(uri, headers: headers);
    } else {
      response = await _client.get(uri, headers: headers);
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {}
    final result = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (result.containsKey('success') && result['success'] != true)) {
      throw Exception(result['message']?.toString() ??
          'Unable to complete the announcement request.');
    }
    return result;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
