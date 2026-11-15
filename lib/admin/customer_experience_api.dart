import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Persist successfully before EVERY submission, including a retry after a
/// failed preference write. The preferences cache alone is not durability.
Future<void> persistCashbackRequest(
    String preferenceKey, Map<String, dynamic> pending) async {
  final prefs = await SharedPreferences.getInstance();
  final encoded = jsonEncode(pending);
  if (!await prefs.setString(preferenceKey, encoded)) {
    throw StateError('Unable to safely save this cashback request. No credit was submitted.');
  }
  await prefs.reload();
  if (prefs.getString(preferenceKey) != encoded) {
    throw StateError('Cashback retry protection could not be verified. No credit was submitted.');
  }
}

int? parseCashbackAmount(String text) {
  final value = text.trim().replaceAll(',', '');
  if (!RegExp(r'^\d{1,8}(?:\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final minor = int.parse(parts.first) * 100 +
      int.parse(parts.length == 1 ? '00' : parts.last.padRight(2, '0'));
  return minor > 0 && minor <= 1000000000 ? minor : null;
}

class CustomerExperienceApi {
  CustomerExperienceApi({http.Client? client, String? baseUrl})
      : baseUrl = _experienceBase(baseUrl ??
            const String.fromEnvironment(
              'SERVICEPAY_API_BASE_URL',
              defaultValue: 'https://api.servicepay.ng/api',
            )),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  static String _experienceBase(String value) {
    final root = value.replaceFirst(RegExp(r'/$'), '');
    return root.endsWith('/customer-experience')
        ? root
        : '$root/customer-experience';
  }

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  Future<Map<String, dynamic>> access() => _get('/admin/access');

  Future<Map<String, dynamic>> customers({String query = '', int page = 1}) =>
      _get('/admin/customers', <String, String>{
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'page': '$page',
      });

  Future<Map<String, dynamic>> cashback(String customerId) =>
      _get('/admin/customers/${Uri.encodeComponent(customerId)}/cashback');

  Future<Map<String, dynamic>> credit({
    required String customerId,
    required int amountMinor,
    required String description,
    required String requestKey,
  }) async {
    final token = await _token();
    final response = await _client.post(
      Uri.parse(
          '$baseUrl/admin/customers/${Uri.encodeComponent(customerId)}/cashback'),
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        'X-Idempotency-Key': requestKey,
      },
      body: jsonEncode(<String, dynamic>{
        'amountMinor': amountMinor,
        'description': description.trim(),
      }),
    );
    return _decode(response.body, response.statusCode);
  }

  Future<Map<String, dynamic>> report({
    String customerId = '',
    String start = '',
    String end = '',
    String minMinor = '',
    String maxMinor = '',
    int page = 1,
  }) =>
      _get('/admin/cashback', <String, String>{
        if (customerId.isNotEmpty) 'customerId': customerId,
        if (start.isNotEmpty) 'start': start,
        if (end.isNotEmpty) 'end': end,
        if (minMinor.isNotEmpty) 'minMinor': minMinor,
        if (maxMinor.isNotEmpty) 'maxMinor': maxMinor,
        'page': '$page',
      });

  Future<String> reportCsv({
    String customerId = '',
    String start = '',
    String end = '',
    String minMinor = '',
    String maxMinor = '',
  }) async {
    final response = await _client.get(
      _uri('/admin/cashback', <String, String>{
        if (customerId.isNotEmpty) 'customerId': customerId,
        if (start.isNotEmpty) 'start': start,
        if (end.isNotEmpty) 'end': end,
        if (minMinor.isNotEmpty) 'minMinor': minMinor,
        if (maxMinor.isNotEmpty) 'maxMinor': maxMinor,
        'page': '1',
        'format': 'csv',
      }),
      headers: <String, String>{
        'Accept': 'text/csv',
        if ((await _token()).isNotEmpty)
          'Authorization': 'Bearer ${await _token()}',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CustomerExperienceAdminException(
          _message(response.body, 'Unable to download cashback report.'),
          response.statusCode);
    }
    return response.body;
  }

  Future<Uint8List> statement({
    required String customerId,
    required String start,
    required String end,
  }) async {
    final response = await _client.get(
      _uri('/admin/customers/${Uri.encodeComponent(customerId)}/statement',
          {'start': start, 'end': end}),
      headers: <String, String>{
        'Accept': 'application/pdf, application/json',
        if ((await _token()).isNotEmpty)
          'Authorization': 'Bearer ${await _token()}',
      },
    );
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        response.headers['content-type']
                ?.toLowerCase()
                .contains('application/pdf') !=
            true) {
      throw CustomerExperienceAdminException(
          _message(utf8.decode(response.bodyBytes, allowMalformed: true),
              'Unable to prepare customer statement.'),
          response.statusCode);
    }
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> appUpdate() => _get('/admin/app-update');

  Future<Map<String, dynamic>> saveAppUpdate(
      Map<String, dynamic> update) async {
    final token = await _token();
    final response = await _client.put(
      Uri.parse('$baseUrl/admin/app-update'),
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(update),
    );
    return _decode(response.body, response.statusCode);
  }

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? query]) async {
    final response = await _client.get(
      _uri(path, query),
      headers: <String, String>{
        'Accept': 'application/json',
        if ((await _token()).isNotEmpty)
          'Authorization': 'Bearer ${await _token()}',
      },
    );
    return _decode(response.body, response.statusCode);
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return <String>[
      'auth_token',
      'token',
      'access_token',
      'accessToken',
      'jwt_token',
      'jwt',
      'admin_token'
    ]
        .map((key) => prefs.getString(key)?.trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '')
        .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
  }

  Map<String, dynamic> _decode(String body, int status) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {}
    final result = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (status < 200 || status >= 300 || result['success'] == false) {
      throw CustomerExperienceAdminException(
          _message(body, 'Customer experience request failed.'), status);
    }
    return result;
  }

  String _message(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {}
    return fallback;
  }

  String newIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class CustomerExperienceAdminException implements Exception {
  const CustomerExperienceAdminException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
