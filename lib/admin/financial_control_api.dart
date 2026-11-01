import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';
import 'revenue_download_stub.dart'
    if (dart.library.html) 'revenue_download_web.dart' as download_adapter;
import 'financial_control_document_stub.dart'
    if (dart.library.html) 'financial_control_document_web.dart'
    as document_adapter;

typedef FinancialTokenLoader = Future<String?> Function();
typedef FinancialDownloadAdapter = Future<void> Function(
  List<int> bytes,
  String filename,
  String contentType,
);
typedef FinancialPdfAdapter = Future<void> Function(
  List<int> bytes,
  String filename,
  String contentType,
  FinancialDownloadAdapter fallback,
);

class FinancialControlApi {
  FinancialControlApi({
    http.Client? client,
    this.baseUrl = AdminApiConfiguration.baseUrl,
    FinancialTokenLoader? tokenLoader,
    FinancialDownloadAdapter? downloadAdapter,
    FinancialPdfAdapter? pdfAdapter,
  })  : _client = client ?? http.Client(),
        _tokenLoader = tokenLoader ?? _loadToken,
        _download = downloadAdapter ?? download_adapter.downloadRevenueFile,
        _openPdf = pdfAdapter ?? document_adapter.openFinancialPdf;

  final http.Client _client;
  final String baseUrl;
  final FinancialTokenLoader _tokenLoader;
  final FinancialDownloadAdapter _download;
  final FinancialPdfAdapter _openPdf;

  @visibleForTesting
  static const Duration requestTimeout = Duration(seconds: 30);

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
    return Uri.parse('$root/admin/revenue/financial-control$path')
        .replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> summary({
    required Map<String, String> filters,
  }) =>
      _getJson('/summary', filters);

  Future<Map<String, dynamic>> expenses({
    required Map<String, String> filters,
  }) =>
      _getJson('/expenses', filters);

  Future<Map<String, dynamic>> createExpense(
    Map<String, dynamic> expense,
  ) async {
    final String token = await _requiredToken();
    final http.Response response = await _client
        .post(
          _uri('/expenses'),
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(expense),
        )
        .timeout(requestTimeout);
    return _decodeEnvelope(response);
  }

  Future<void> downloadReport({
    required String format,
    required Map<String, String> filters,
  }) async {
    if (!const <String>{'csv', 'pdf'}.contains(format)) {
      throw const FinancialControlException('Choose CSV or PDF.');
    }
    await _downloadResponse(
      _uri('/report', <String, String>{...filters, 'format': format}),
      fallbackName: 'ServicePay-Financial-Control.$format',
      openPdf: format == 'pdf',
    );
  }

  Future<void> downloadSupportingDocument({
    required String id,
    required String name,
  }) async {
    final String encodedId = Uri.encodeComponent(id);
    await _downloadResponse(
      _uri('/expenses/$encodedId/document'),
      fallbackName: name,
    );
  }

  Future<void> _downloadResponse(
    Uri uri, {
    required String fallbackName,
    bool openPdf = false,
  }) async {
    final String token = await _requiredToken();
    final http.Response response = await _client.get(
      uri,
      headers: <String, String>{
        'Accept': '*/*',
        'Authorization': 'Bearer $token',
      },
    ).timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwResponse(response.statusCode, _jsonBody(response.body));
    }
    if (response.bodyBytes.isEmpty) {
      throw const FinancialControlException('The downloaded file was empty.');
    }
    final String disposition = _header(response, 'content-disposition') ?? '';
    final RegExpMatch? match =
        RegExp(r'''filename\*?=(?:UTF-8'')?["']?([^"';]+)["']?''')
            .firstMatch(disposition);
    final String filename = Uri.decodeComponent(
      match?.group(1)?.trim() ?? fallbackName,
    );
    final String contentType =
        _header(response, 'content-type') ?? 'application/octet-stream';
    if (openPdf) {
      await _openPdf(response.bodyBytes, filename, contentType, _download);
    } else {
      await _download(response.bodyBytes, filename, contentType);
    }
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
      throw const FinancialControlException(
        'The financial control service returned an invalid response.',
      );
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<String> _requiredToken() async {
    final String? token = await _tokenLoader();
    if (token == null || token.trim().isEmpty) {
      throw const FinancialControlException(
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
      400 => 'Review the dates and filters, then try again.',
      401 => 'Your admin session has expired. Please sign in again.',
      403 => 'You are not authorized to access Financial Control Center.',
      404 => 'The financial control service is not available.',
      409 => 'This expense reference may already have been recorded.',
      413 => 'The supporting document exceeds the permitted size.',
      429 => 'Too many requests. Try again shortly.',
      _ => 'Unable to complete the financial control request.',
    };
    final String? message =
        body is Map ? body['message']?.toString().trim() : null;
    throw FinancialControlException(
      message?.isNotEmpty == true ? message! : fallback,
      statusCode: status,
    );
  }
}

class FinancialControlException implements Exception {
  const FinancialControlException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
