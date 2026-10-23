import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';

class CustomerExportApi {
  CustomerExportApi({
    http.Client? client,
    this.baseUrl = AdminApiConfiguration.baseUrl,
    Future<String?> Function()? tokenLoader,
  })  : _client = client ?? http.Client(),
        _tokenLoader = tokenLoader ?? _loadToken;

  final http.Client _client;
  final String baseUrl;
  final Future<String?> Function() _tokenLoader;

  static Future<String?> _loadToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for (final String key in const <String>[
      'auth_token',
      'token',
      'access_token',
      'accessToken',
      'jwt_token',
      'jwt',
      'admin_token',
    ]) {
      final String value = prefs.getString(key)?.trim() ?? '';
      if (value.isNotEmpty) {
        return value.toLowerCase().startsWith('bearer ')
            ? value.substring(7)
            : value;
      }
    }
    return null;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final String root = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$root$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> customers({
    String query = '',
    String? after,
    int limit = 50,
  }) async {
    final String token = await _requiredToken();
    final http.Response response = await _client.get(
      _uri('/admin/customer-exports/customers', <String, String>{
        'q': query,
        'limit': '$limit',
        if (after != null && after.isNotEmpty) 'after': after,
      }),
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 30));
    final dynamic body = _jsonBody(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _checkResponse(response.statusCode, body);
    }
    if (body is! Map || body['success'] != true) {
      throw const CustomerExportException('Unable to load customers.');
    }
    return Map<String, dynamic>.from(body);
  }

  Future<CustomerExportFile> generate({
    required String format,
    required String scope,
    required String query,
    required List<String> ids,
    required String action,
  }) async {
    final String token = await _requiredToken();
    final http.Response response = await _client
        .post(
          _uri('/admin/customer-exports/download'),
          headers: <String, String>{
            'Accept': '*/*',
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'format': format,
            'scope': scope,
            'query': query,
            'ids': ids,
            'action': action,
          }),
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _checkResponse(response.statusCode, _jsonBody(response.body));
    }
    if (response.bodyBytes.isEmpty) {
      throw const CustomerExportException('The export file was empty.');
    }
    _validateExportPayload(format, response);
    return CustomerExportFile(
      bytes: response.bodyBytes,
      filename: 'Servicepay-Customers.$format',
      format: format,
    );
  }

  void _validateExportPayload(String format, http.Response response) {
    String? rawContentType;
    for (final MapEntry<String, String> entry in response.headers.entries) {
      if (entry.key.toLowerCase() == 'content-type') {
        rawContentType = entry.value;
        break;
      }
    }
    final String contentType =
        rawContentType?.split(';').first.trim().toLowerCase() ?? '';
    final List<int> bytes = response.bodyBytes;
    switch (format) {
      case 'pdf':
        if (contentType != 'application/pdf' ||
            !_startsWith(bytes, const <int>[0x25, 0x50, 0x44, 0x46, 0x2D])) {
          throw const CustomerExportException(
            'The server returned an invalid PDF export file.',
          );
        }
        return;
      case 'xlsx':
        if (contentType !=
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
            !_startsWith(bytes, const <int>[0x50, 0x4B, 0x03, 0x04])) {
          throw const CustomerExportException(
            'The server returned an invalid Excel export file.',
          );
        }
        return;
      case 'csv':
        if (!const <String>{
              'text/csv',
              'application/csv',
            }.contains(contentType) ||
            !_hasCsvHeader(bytes)) {
          throw const CustomerExportException(
            'The server returned an invalid CSV export file.',
          );
        }
        return;
      default:
        throw const CustomerExportException(
          'Choose CSV, Excel, or PDF for the export.',
        );
    }
  }

  bool _startsWith(List<int> value, List<int> prefix) {
    if (value.length < prefix.length) return false;
    for (int index = 0; index < prefix.length; index++) {
      if (value[index] != prefix[index]) return false;
    }
    return true;
  }

  bool _hasCsvHeader(List<int> bytes) {
    try {
      String csv = utf8.decode(bytes, allowMalformed: false);
      if (csv.startsWith('\uFEFF')) csv = csv.substring(1);
      final String header = csv.split(RegExp(r'\r?\n')).first.trimRight();
      return header == 'Full Name,Phone Number,Email Address';
    } on FormatException {
      return false;
    }
  }

  Future<String> _requiredToken() async {
    final String? token = await _tokenLoader();
    if (token == null || token.trim().isEmpty) {
      throw const CustomerExportException(
        'Your admin session has expired. Please sign in again.',
        statusCode: 401,
      );
    }
    return token.toLowerCase().startsWith('bearer ')
        ? token.substring(7)
        : token;
  }

  dynamic _jsonBody(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  Never _checkResponse(int statusCode, dynamic body) {
    final String fallback = switch (statusCode) {
      400 => 'Check the export selection and try again.',
      401 || 403 => 'You are not authorized to export these customers.',
      429 => 'An export is already being prepared. Try again shortly.',
      _ => 'Unable to complete the customer export.',
    };
    final String? message =
        body is Map ? body['message']?.toString().trim() : null;
    throw CustomerExportException(
      message?.isNotEmpty == true ? message! : fallback,
      statusCode: statusCode,
    );
  }
}

class CustomerExportFile {
  const CustomerExportFile({
    required this.bytes,
    required this.filename,
    required this.format,
  });

  final List<int> bytes;
  final String filename;
  final String format;
}

class CustomerExportException implements Exception {
  const CustomerExportException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class ExportCustomer {
  const ExportCustomer({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
  });

  final String id;
  final String fullName;
  final String phone;
  final String email;

  factory ExportCustomer.fromJson(Map<String, dynamic> json) => ExportCustomer(
        id: '${json['id'] ?? ''}',
        fullName: '${json['fullName'] ?? ''}',
        phone: '${json['phone'] ?? ''}',
        email: '${json['email'] ?? ''}',
      );
}
