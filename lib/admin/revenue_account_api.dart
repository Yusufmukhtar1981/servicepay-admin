import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';
import 'revenue_download_stub.dart'
    if (dart.library.html) 'revenue_download_web.dart' as download_adapter;

typedef RevenueTokenLoader = Future<String?> Function();
typedef RevenueDownloadAdapter = Future<void> Function(
  List<int> bytes,
  String filename,
  String contentType,
);

class RevenueAccountApi {
  RevenueAccountApi({
    http.Client? client,
    this.baseUrl = AdminApiConfiguration.baseUrl,
    RevenueTokenLoader? tokenLoader,
    RevenueDownloadAdapter? downloadAdapter,
  })  : _client = client ?? http.Client(),
        _tokenLoader = tokenLoader ?? _loadToken,
        _download = downloadAdapter ?? download_adapter.downloadRevenueFile;

  final http.Client _client;
  final String baseUrl;
  final RevenueTokenLoader _tokenLoader;
  final RevenueDownloadAdapter _download;

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

  @visibleForTesting
  static const Duration requestTimeout = Duration(seconds: 30);

  Uri _uri(String path, [Map<String, String>? query]) {
    final String root = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$root/admin/revenue$path')
        .replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> summary(
          {Map<String, String> filters = const {}}) =>
      _getJson('/summary', filters);

  Future<Map<String, dynamic>> transactions({
    Map<String, String> filters = const {},
  }) =>
      _getJson('/transactions', filters);

  Future<Map<String, dynamic>> ledger(
          {Map<String, String> filters = const {}}) =>
      _getJson('/ledger', filters);

  Future<Map<String, dynamic>> reconcile() async {
    final String token = await _requiredToken();
    final http.Response response = await _client
        .post(
          _uri('/reconcile'),
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{}),
        )
        .timeout(requestTimeout);
    return _decodeEnvelope(response);
  }

  Future<void> export({
    required String format,
    Map<String, String> filters = const {},
  }) async {
    if (!const <String>{'csv', 'xlsx', 'pdf'}.contains(format)) {
      throw const RevenueAccountException('Choose CSV, Excel, or PDF.');
    }
    final String token = await _requiredToken();
    final http.Response response = await _client.get(
      _uri('/export', <String, String>{...filters, 'format': format}),
      headers: <String, String>{
        'Accept': '*/*',
        'Authorization': 'Bearer $token',
      },
    ).timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwResponse(response.statusCode, _jsonBody(response.body));
    }
    if (response.bodyBytes.isEmpty) {
      throw const RevenueAccountException('The export file was empty.');
    }
    final String disposition = _header(response, 'content-disposition') ?? '';
    final RegExpMatch? match =
        RegExp(r'''filename\*?=(?:UTF-8'')?["']?([^"';]+)["']?''')
            .firstMatch(disposition);
    final String filename = Uri.decodeComponent(
      match?.group(1)?.trim() ?? 'ServicePay-Revenue.$format',
    );
    final String contentType =
        _header(response, 'content-type') ?? 'application/octet-stream';
    await _download(response.bodyBytes, filename, contentType);
  }

  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> query,
  ) async {
    final String token = await _requiredToken();
    final http.Response response = await _client.get(
      _uri(path, query),
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(requestTimeout);
    return _decodeEnvelope(response);
  }

  Map<String, dynamic> _decodeEnvelope(http.Response response) {
    final dynamic body = _jsonBody(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwResponse(response.statusCode, body);
    }
    if (body is! Map || body['success'] != true || body['data'] is! Map) {
      throw const RevenueAccountException(
        'The revenue service returned an invalid response.',
      );
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<String> _requiredToken() async {
    final String? token = await _tokenLoader();
    if (token == null || token.trim().isEmpty) {
      throw const RevenueAccountException(
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

  String? _header(http.Response response, String name) {
    for (final MapEntry<String, String> entry in response.headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  Never _throwResponse(int status, dynamic body) {
    final String fallback = switch (status) {
      400 => 'Review the filters and try again.',
      401 => 'Your admin session has expired. Please sign in again.',
      403 => 'You are not authorized to access Revenue Account.',
      404 => 'The revenue service is not available.',
      429 => 'Too many requests. Try again shortly.',
      _ => 'Unable to complete the revenue request.',
    };
    final String? message =
        body is Map ? body['message']?.toString().trim() : null;
    throw RevenueAccountException(
      message?.isNotEmpty == true ? message! : fallback,
      statusCode: status,
    );
  }
}

class RevenueAccountException implements Exception {
  const RevenueAccountException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
