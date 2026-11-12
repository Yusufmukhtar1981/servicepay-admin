import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';

class ExecutiveControlApi {
  ExecutiveControlApi({
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
        return value.replaceFirst(
            RegExp(r'^Bearer\s+', caseSensitive: false), '');
      }
    }
    return null;
  }

  Uri _uri(String endpoint, Map<String, dynamic> query) {
    final root = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final parameters = <String, String>{};
    query.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        parameters[key] = value.toString();
      }
    });
    return Uri.parse('$root/admin/executive-control/$endpoint')
        .replace(queryParameters: parameters);
  }

  Future<Map<String, String>> _headers({bool binary = false}) async {
    final token = (await _tokenLoader())?.trim() ?? '';
    if (token.isEmpty) {
      throw const ExecutiveControlException(
        'Your admin session has expired. Sign in again.',
        statusCode: 401,
      );
    }
    return {
      'Accept': binary ? '*/*' : 'application/json',
      'Authorization':
          'Bearer ${token.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')}',
    };
  }

  Future<Map<String, dynamic>> get(
    String endpoint,
    Map<String, dynamic> query,
  ) async {
    final response = await _client
        .get(_uri(endpoint, query), headers: await _headers())
        .timeout(const Duration(seconds: 30));
    final decoded = _decode(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true ||
        decoded['data'] is! Map) {
      throw ExecutiveControlException(
        decoded['message']?.toString() ?? 'Unable to load this section.',
        statusCode: response.statusCode,
      );
    }
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<ExecutiveReportFile> report({
    required String kind,
    required String format,
    required Map<String, dynamic> filters,
  }) async {
    final response = await _client
        .get(_uri('report', {...filters, 'kind': kind, 'format': format}),
            headers: await _headers(binary: true))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = _decode(response);
      throw ExecutiveControlException(
        decoded['message']?.toString() ?? 'Report export was not authorized.',
        statusCode: response.statusCode,
      );
    }
    final type = response.headers.entries
        .where((e) => e.key.toLowerCase() == 'content-type')
        .map((e) => e.value.split(';').first.trim().toLowerCase())
        .firstOrNull;
    final valid = switch (format) {
      'pdf' => type == 'application/pdf' &&
          _starts(response.bodyBytes, const [0x25, 0x50, 0x44, 0x46, 0x2d]),
      'xlsx' => type ==
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' &&
          _starts(response.bodyBytes, const [0x50, 0x4b, 0x03, 0x04]),
      _ => const {'text/csv', 'application/csv'}.contains(type) &&
          response.bodyBytes.isNotEmpty,
    };
    if (!valid) {
      throw const ExecutiveControlException(
          'The server returned an invalid report file.');
    }
    final disposition = response.headers.entries
        .where((e) => e.key.toLowerCase() == 'content-disposition')
        .map((e) => e.value)
        .firstOrNull;
    final rawName =
        RegExp(r'filename="?([^";]+)').firstMatch(disposition ?? '')?.group(1);
    final filename = (rawName ?? 'ServicePay-$kind.$format')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return ExecutiveReportFile(
      bytes: response.bodyBytes,
      contentType: type!,
      filename: filename.toLowerCase().endsWith('.$format')
          ? filename
          : 'ServicePay-$kind.$format',
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  bool _starts(List<int> value, List<int> prefix) {
    if (value.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (value[i] != prefix[i]) return false;
    }
    return true;
  }
}

class ExecutiveReportFile {
  const ExecutiveReportFile({
    required this.bytes,
    required this.contentType,
    required this.filename,
  });
  final List<int> bytes;
  final String contentType;
  final String filename;
}

class ExecutiveControlException implements Exception {
  const ExecutiveControlException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
