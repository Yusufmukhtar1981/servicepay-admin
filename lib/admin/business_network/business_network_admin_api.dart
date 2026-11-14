import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../admin_api_configuration.dart';

class BusinessNetworkAdminApi {
  BusinessNetworkAdminApi(
      {http.Client? client,
      Future<String?> Function()? tokenProvider,
      String? baseUrl})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _tokenProvider = tokenProvider ?? _storedToken,
        baseUrl = baseUrl ?? AdminApiConfiguration.baseUrl;

  final http.Client _client;
  final bool _ownsClient;
  final Future<String?> Function() _tokenProvider;
  final String baseUrl;
  static Future<String?> _storedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ??
        prefs.getString('token') ??
        prefs.getString('access_token');
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _request('GET', path, query: query);
  Future<dynamic> post(String path, Map<String, dynamic> body) =>
      _request('POST', path, body: body);
  Future<dynamic> put(String path, Map<String, dynamic> body) =>
      _request('PUT', path, body: body);
  Future<dynamic> patch(String path, Map<String, dynamic> body) =>
      _request('PATCH', path, body: body);
  Future<String> csv(String path, {Map<String, String>? query}) async {
    final response = await _send(
      'GET',
      path,
      query: query,
      accept: 'text/csv, application/csv',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BusinessNetworkAdminException(_message(response));
    }
    return response.body;
  }

  Future<dynamic> getProfileBranches(String profileId) => _request(
        'GET',
        'profiles/${Uri.encodeComponent(profileId)}/branches',
        admin: false,
      );
  Future<dynamic> createProfileBranch(
          String profileId, Map<String, dynamic> body) =>
      _request('POST', 'profiles/${Uri.encodeComponent(profileId)}/branches',
          body: body, admin: false);
  Future<dynamic> updateProfileBranch(
          String profileId, String branchId, Map<String, dynamic> body) =>
      _request(
        'PATCH',
        'profiles/${Uri.encodeComponent(profileId)}/branches/${Uri.encodeComponent(branchId)}',
        body: body,
        admin: false,
      );
  Future<dynamic> getProfileStaff(String profileId) => _request(
        'GET',
        'profiles/${Uri.encodeComponent(profileId)}/staff',
        admin: false,
      );
  Future<dynamic> inviteProfileStaff(
          String profileId, Map<String, dynamic> body) =>
      _request('POST', 'profiles/${Uri.encodeComponent(profileId)}/staff',
          body: body, admin: false);
  Future<dynamic> updateProfileStaff(
          String staffId, Map<String, dynamic> body) =>
      _request('PATCH', 'staff/${Uri.encodeComponent(staffId)}',
          body: body, admin: false);

  Future<http.Response> _send(String method, String path,
      {Map<String, String>? query,
      Map<String, dynamic>? body,
      bool admin = true,
      String accept = 'application/json'}) async {
    final raw = (await _tokenProvider())?.trim() ?? '';
    if (raw.isEmpty) {
      throw const BusinessNetworkAdminException(
          'Your session has expired. Sign in again.');
    }
    final token =
        raw.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
    final uri = Uri.parse(
      '$baseUrl/business-network/${admin ? 'admin/' : ''}$path',
    ).replace(queryParameters: query);
    final headers = <String, String>{
      'Accept': accept,
      'Authorization': 'Bearer $token'
    };
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }
    switch (method) {
      case 'GET':
        return _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 25));
      case 'POST':
        return _client
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 25));
      case 'PUT':
        return _client
            .put(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 25));
      case 'PATCH':
        return _client
            .patch(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 25));
      default:
        throw ArgumentError.value(method, 'method');
    }
  }

  Future<dynamic> _request(String method, String path,
      {Map<String, String>? query,
      Map<String, dynamic>? body,
      bool admin = true}) async {
    final response =
        await _send(method, path, query: query, body: body, admin: admin);
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw BusinessNetworkAdminException(
          'Unreadable server response (${response.statusCode}).');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded is! Map ||
        decoded['success'] != true) {
      throw BusinessNetworkAdminException(decoded is Map
          ? (decoded['message']?.toString() ??
              'Request denied (${response.statusCode}).')
          : 'Request denied (${response.statusCode}).');
    }
    return decoded['data'];
  }

  String _message(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {
      // Use the status response below for non-JSON export errors.
    }
    return 'Report export failed (${response.statusCode}).';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class BusinessNetworkAdminException implements Exception {
  const BusinessNetworkAdminException(this.message);
  final String message;
  @override
  String toString() => message;
}
