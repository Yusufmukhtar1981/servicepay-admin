import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';
import 'customer_export_api.dart';

class CustomerIntelligenceApi {
  CustomerIntelligenceApi({
    http.Client? client,
    this.baseUrl = AdminApiConfiguration.baseUrl,
    Future<String?> Function()? tokenLoader,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _tokenLoader = tokenLoader ?? _loadToken;

  final http.Client _client;
  final bool _ownsClient;
  final String baseUrl;
  final Future<String?> Function() _tokenLoader;
  void close() {
    if (_ownsClient) _client.close();
  }

  static Future<String?> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in const [
      'auth_token',
      'token',
      'access_token',
      'accessToken',
      'jwt_token',
      'jwt',
      'admin_token',
    ]) {
      final value = prefs.getString(key)?.trim() ?? '';
      if (value.isNotEmpty) {
        return value.toLowerCase().startsWith('bearer ')
            ? value.substring(7)
            : value;
      }
    }
    return null;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final root = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$root/admin/customer-intelligence$path')
        .replace(queryParameters: query);
  }

  Future<String> _token() async {
    final value = await _tokenLoader();
    if (value == null || value.trim().isEmpty) {
      throw const CustomerIntelligenceException(
          'Your admin session has expired. Please sign in again.',
          statusCode: 401);
    }
    return value.toLowerCase().startsWith('bearer ')
        ? value.substring(7)
        : value;
  }

  Map<String, String> _query(Map<String, dynamic> values) => Map.fromEntries(
        values.entries
            .where(
                (entry) => entry.value != null && '${entry.value}'.isNotEmpty)
            .map((entry) => MapEntry(entry.key, '${entry.value}')),
      );

  Future<dynamic> _get(String path, Map<String, dynamic> query) async {
    final token = await _token();
    final response = await _client.get(_uri(path, _query(query)), headers: {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    }).timeout(const Duration(seconds: 30));
    return _decodeResponse(response);
  }

  Future<dynamic> _send(String method, String path, Map<String, dynamic> body,
      {bool binary = false}) async {
    final token = await _token();
    final headers = <String, String>{
      'Accept': binary ? '*/*' : 'application/json',
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final response = method == 'PUT'
        ? await _client.put(_uri(path),
            headers: headers, body: jsonEncode(body))
        : await _client.post(_uri(path),
            headers: headers, body: jsonEncode(body));
    return _decodeResponse(response, allowBinary: binary);
  }

  dynamic _decodeResponse(http.Response response, {bool allowBinary = false}) {
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      body = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body is Map ? body['message']?.toString() : null;
      throw CustomerIntelligenceException(
          message?.trim().isNotEmpty == true
              ? message!.trim()
              : 'Unable to complete the customer intelligence request.',
          statusCode: response.statusCode);
    }
    if (allowBinary) return response;
    if (body is! Map || body['success'] != true || body['data'] is! Map) {
      throw const CustomerIntelligenceException(
          'The server returned an invalid customer intelligence response.');
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> customers(Map<String, dynamic> filters) async =>
      await _get('/customers', filters) as Map<String, dynamic>;

  Future<Map<String, dynamic>> customer(String id,
          {int page = 1, int limit = 20}) async =>
      await _get('/customers/${Uri.encodeComponent(id)}',
          {'page': page, 'limit': limit}) as Map<String, dynamic>;

  Future<Map<String, dynamic>> performance(Map<String, dynamic> filters,
          {required String dimension, int page = 1, int limit = 20}) async =>
      await _get('/performance', {
        ...filters,
        'dimension': dimension,
        'page': page,
        'limit': limit
      }) as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateSettings(
          Map<String, dynamic> settings) async =>
      await _send('PUT', '/settings', settings) as Map<String, dynamic>;

  Future<CustomerExportFile> export({
    required Map<String, dynamic> filters,
    required List<String> ids,
    required bool allFiltered,
    required String format,
    required String action,
  }) async {
    if (!const {'csv', 'xlsx', 'pdf'}.contains(format)) {
      throw const CustomerIntelligenceException('Choose CSV, Excel, or PDF.');
    }
    final response = await _send(
      'POST',
      '/export',
      {
        'filters': filters,
        if (allFiltered) 'allFiltered': true else 'ids': ids,
        'format': format,
        'action': action,
      },
      binary: true,
    ) as http.Response;
    if (response.bodyBytes.isEmpty) {
      throw const CustomerIntelligenceException('The export file was empty.');
    }
    final contentType = response.headers.entries
        .where((e) => e.key.toLowerCase() == 'content-type')
        .map((e) => e.value.split(';').first.trim().toLowerCase())
        .firstOrNull;
    final valid = switch (format) {
      'pdf' => contentType == 'application/pdf' &&
          _starts(response.bodyBytes, [0x25, 0x50, 0x44, 0x46, 0x2d]),
      'xlsx' => contentType ==
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' &&
          _starts(response.bodyBytes, [0x50, 0x4b, 0x03, 0x04]),
      _ => const {'text/csv', 'application/csv'}.contains(contentType) &&
          _csvHeader(response.bodyBytes),
    };
    if (!valid) {
      throw const CustomerIntelligenceException(
          'The server returned an invalid contact export file.');
    }
    final rawName = response.headers.entries
        .where((e) => e.key.toLowerCase() == 'content-disposition')
        .map((e) => e.value)
        .firstOrNull;
    final candidate =
        RegExp(r'filename="?([^";]+)').firstMatch(rawName ?? '')?.group(1) ??
            'Servicepay-Customer-Contacts.$format';
    final safe = candidate.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final filename =
        safe.toLowerCase().endsWith('.$format') ? safe : 'contacts.$format';
    return CustomerExportFile(
        bytes: response.bodyBytes, filename: filename, format: format);
  }

  Future<Map<String, dynamic>> campaignPreview({
    required Map<String, dynamic> filters,
    required List<String> ids,
    required bool allFiltered,
    required String purpose,
    required String message,
  }) async =>
      await _send('POST', '/campaign-preview', {
        'filters': filters,
        if (allFiltered) 'allFiltered': true else 'ids': ids,
        'purpose': purpose,
        'message': message,
      }) as Map<String, dynamic>;

  bool _starts(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  bool _csvHeader(List<int> bytes) {
    try {
      final end = bytes.indexOf(10);
      var header = utf8.decode(bytes.sublist(0, end < 0 ? bytes.length : end),
          allowMalformed: false);
      if (header.startsWith('\uFEFF')) header = header.substring(1);
      return header.trimRight() == 'Full Name,Phone Number,Email Address' ||
          header.trimRight() == '"Full Name","Phone Number","Email Address"';
    } catch (_) {
      return false;
    }
  }
}

class CustomerIntelligenceException implements Exception {
  const CustomerIntelligenceException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
