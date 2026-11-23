import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../admin_api_configuration.dart';
import '../revenue_download_stub.dart'
    if (dart.library.html) '../revenue_download_web.dart' as download_adapter;

typedef ExpenseTokenLoader = Future<String?> Function();
typedef ExpenseDownloadAdapter = Future<void> Function(
  List<int> bytes,
  String filename,
  String contentType,
);

/// Error returned by the expense management service. [outcomeUnknown] is
/// true when a write may or may not have reached the server (timeout or
/// connection loss); the caller must keep its idempotency key.
class ExpenseApiException implements Exception {
  const ExpenseApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.outcomeUnknown = false,
  });
  final String message;
  final int? statusCode;
  final String? code;
  final bool outcomeUnknown;

  bool get isConflict => statusCode == 409;
  bool get isForbidden => statusCode == 403;

  /// A definitive server rejection: the same key must not be reused with a
  /// changed body, so a fresh key may be generated for the next attempt.
  bool get isDefinitiveRejection =>
      !outcomeUnknown &&
      statusCode != null &&
      statusCode! >= 400 &&
      statusCode! < 500 &&
      statusCode != 408 &&
      statusCode != 429;

  @override
  String toString() => message;
}

/// Generates operation keys matching the server rule
/// `^[a-zA-Z0-9_-]{16,100}$`.
abstract final class ExpenseIdempotency {
  static const String _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  static final RegExp pattern = RegExp(r'^[a-zA-Z0-9_-]{16,100}$');

  static String newKey([String prefix = 'exp']) {
    final Random random = Random.secure();
    final String body = List<String>.generate(
      32,
      (_) => _alphabet[random.nextInt(_alphabet.length)],
    ).join();
    return '${prefix}_$body';
  }
}

class ExpenseDocumentUpload {
  const ExpenseDocumentUpload({
    required this.bytes,
    required this.filename,
    required this.idempotencyKey,
  });
  final List<int> bytes;
  final String filename;
  final String idempotencyKey;
}

class ExpenseManagementApi {
  ExpenseManagementApi({
    http.Client? client,
    this.baseUrl = AdminApiConfiguration.baseUrl,
    ExpenseTokenLoader? tokenLoader,
    ExpenseDownloadAdapter? downloadAdapter,
  })  : _client = client ?? http.Client(),
        _tokenLoader = tokenLoader ?? _loadToken,
        _download = downloadAdapter ?? download_adapter.downloadRevenueFile;

  final http.Client _client;
  final String baseUrl;
  final ExpenseTokenLoader _tokenLoader;
  final ExpenseDownloadAdapter _download;

  @visibleForTesting
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 90);
  static const int defaultMaxDocumentBytes = 8 * 1024 * 1024;
  static const Map<String, String> allowedDocumentTypes = <String, String>{
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
  };

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
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  Uri uri(String path, [Map<String, String>? query]) {
    final String root = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final Map<String, String>? cleaned = query == null
        ? null
        : (Map<String, String>.from(query)
          ..removeWhere((String _, String v) => v.trim().isEmpty));
    return Uri.parse('$root/admin/expense-management$path').replace(
      queryParameters: cleaned == null || cleaned.isEmpty ? null : cleaned,
    );
  }

  // ---------------- Reads ----------------
  Future<Map<String, dynamic>> readiness() => _get('/readiness');
  Future<Map<String, dynamic>> references() => _get('/references');
  Future<Map<String, dynamic>> policy() => _get('/policy');
  Future<Map<String, dynamic>> categories() => _get('/categories');
  Future<Map<String, dynamic>> vendors() => _get('/vendors');
  Future<Map<String, dynamic>> listExpenses(Map<String, String> filters) =>
      _get('/expenses', filters);
  Future<Map<String, dynamic>> expense(String id) =>
      _get('/expenses/${Uri.encodeComponent(id)}');
  Future<Map<String, dynamic>> expenseAudit(String id,
          {int page = 1, int pageSize = 50}) =>
      _get('/expenses/${Uri.encodeComponent(id)}/audit', <String, String>{
        'page': '$page',
        'pageSize': '$pageSize',
      });
  Future<Map<String, dynamic>> audit(Map<String, String> query) =>
      _get('/audit', query);
  Future<Map<String, dynamic>> summary(Map<String, String> filters) =>
      _get('/summary', filters);

  // ---------------- Writes ----------------
  Future<Map<String, dynamic>> savePolicy({
    required int expectedVersion,
    required List<Map<String, dynamic>> approvalSteps,
    required String reason,
    required String idempotencyKey,
  }) =>
      _send('PUT', '/policy', idempotencyKey, <String, dynamic>{
        'expectedVersion': expectedVersion,
        'approvalSteps': approvalSteps,
        'reason': reason,
      });

  /// [kind] is `categories` or `vendors`.
  Future<Map<String, dynamic>> createCatalogItem(
    String kind,
    Map<String, dynamic> fields,
    String idempotencyKey,
  ) {
    _checkKind(kind);
    return _send('POST', '/$kind', idempotencyKey, fields);
  }

  Future<Map<String, dynamic>> updateCatalogItem(
    String kind,
    String id, {
    required int expectedVersion,
    required Map<String, dynamic> fields,
    required String reason,
    required String idempotencyKey,
  }) {
    _checkKind(kind);
    return _send('PATCH', '/$kind/${Uri.encodeComponent(id)}', idempotencyKey,
        <String, dynamic>{
          ...fields,
          'expectedVersion': expectedVersion,
          'reason': reason,
        });
  }

  Future<Map<String, dynamic>> createExpense(
    Map<String, dynamic> expense,
    String idempotencyKey,
  ) =>
      _send('POST', '/expenses', idempotencyKey, expense);

  Future<Map<String, dynamic>> updateExpense(
    String id, {
    required Map<String, dynamic> expense,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) =>
      _send('PATCH', '/expenses/${Uri.encodeComponent(id)}', idempotencyKey,
          <String, dynamic>{
            'expense': expense,
            'expectedVersion': expectedVersion,
            'reason': reason,
          });

  Future<Map<String, dynamic>> expenseAction(
    String id, {
    required String action,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
    String? comments,
    Map<String, dynamic>? payment,
    Map<String, dynamic>? reversal,
  }) {
    if (action == 'PAY' && payment == null) {
      throw const ExpenseApiException('Payment details are required.');
    }
    if (action == 'REVERSE' && reversal == null) {
      throw const ExpenseApiException('Reversal evidence is required.');
    }
    return _send(
        'POST',
        '/expenses/${Uri.encodeComponent(id)}/actions',
        idempotencyKey, <String, dynamic>{
      'action': action,
      'expectedVersion': expectedVersion,
      'reason': reason,
      if (comments != null && comments.trim().isNotEmpty)
        'comments': comments.trim(),
      if (action == 'PAY') ...<String, dynamic>{
        'payment': payment,
        'confirmExternalPayment': true,
      },
      if (action == 'REVERSE') ...<String, dynamic>{
        'reversal': reversal,
        'confirmExternalReversal': true,
      },
    });
  }

  /// Validates type and size locally, then uploads once. Never retried
  /// automatically; the caller retains [ExpenseDocumentUpload.idempotencyKey].
  Future<Map<String, dynamic>> uploadDocument(
    ExpenseDocumentUpload upload, {
    int maxBytes = defaultMaxDocumentBytes,
  }) async {
    final String ext = upload.filename.contains('.')
        ? upload.filename.split('.').last.toLowerCase()
        : '';
    final String? mime = allowedDocumentTypes[ext];
    if (mime == null) {
      throw const ExpenseApiException(
          'Only PDF, JPEG and PNG documents can be uploaded.');
    }
    if (upload.bytes.isEmpty) {
      throw const ExpenseApiException('The selected file is empty.');
    }
    if (upload.bytes.length > maxBytes) {
      throw ExpenseApiException(
          'The file exceeds the ${(maxBytes / 1048576).toStringAsFixed(0)} MiB limit.');
    }
    _checkKey(upload.idempotencyKey);
    final String token = await _requiredToken();
    final http.MultipartRequest request =
        http.MultipartRequest('POST', uri('/documents'))
          ..headers.addAll(<String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
            'Idempotency-Key': upload.idempotencyKey,
          })
          ..files.add(http.MultipartFile.fromBytes(
            'file',
            upload.bytes,
            filename: upload.filename,
            contentType: MediaType.parse(mime),
          ));
    final http.Response response = await _guard(
      () async => http.Response.fromStream(await _client.send(request)),
      write: true,
      timeout: uploadTimeout,
    );
    final Map<String, dynamic> data = _decode(response);
    final dynamic document = data['document'];
    if (document is! Map || document['id'] == null) {
      throw const ExpenseApiException(
          'The upload response did not include a stored document.',
          outcomeUnknown: true);
    }
    return Map<String, dynamic>.from(document);
  }

  // ---------------- Downloads ----------------
  Future<String> downloadDocument(String id, {String fallbackName = 'document'}) =>
      _downloadFile(
        uri('/documents/${Uri.encodeComponent(id)}/download'),
        fallbackName,
        const <String>{'application/pdf', 'image/jpeg', 'image/png'},
      );

  /// Read-only legacy Financial Control expense records.
  Future<Map<String, dynamic>> legacyExpenses({required String from, required String to}) =>
      _get('/legacy-expenses', <String, String>{'from': from, 'to': to});

  Future<String> downloadLegacyDocument(String id, {String fallbackName = 'legacy-receipt'}) =>
      _downloadFile(
        uri('/legacy-expenses/${Uri.encodeComponent(id)}/document'),
        fallbackName,
        const <String>{'application/pdf', 'image/jpeg', 'image/png'},
      );

  static const Set<String> reportTypes = <String>{
    'daily',
    'weekly',
    'monthly',
    'annual',
    'department',
    'vendor',
    'approval',
  };

  Future<String> downloadReport({
    required String format,
    required String type,
    required Map<String, String> filters,
  }) {
    if (!const <String>{'pdf', 'xlsx'}.contains(format)) {
      throw const ExpenseApiException('Choose PDF or Excel.');
    }
    if (!reportTypes.contains(type)) {
      throw const ExpenseApiException('Choose a report type.');
    }
    if ((filters['from'] ?? '').isEmpty || (filters['to'] ?? '').isEmpty) {
      throw const ExpenseApiException('Select a report date range.');
    }
    return _downloadFile(
      uri('/reports', <String, String>{
        ...filters,
        'format': format,
        'type': type,
      }),
      'ServicePay-Expense-$type-report.$format',
      format == 'pdf'
          ? const <String>{'application/pdf'}
          : const <String>{
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              'application/octet-stream',
            },
    );
  }

  Future<String> _downloadFile(
    Uri target,
    String fallbackName,
    Set<String> allowedTypes,
  ) async {
    final String token = await _requiredToken();
    final http.Response response = await _guard(
      () => _client.get(target, headers: <String, String>{
        'Accept': '*/*',
        'Authorization': 'Bearer $token',
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwResponse(response.statusCode, _json(response.body));
    }
    final String contentType =
        (_header(response, 'content-type') ?? '').split(';').first.trim().toLowerCase();
    if (contentType.isEmpty ||
        contentType.contains('json') ||
        contentType.contains('html') ||
        !allowedTypes.contains(contentType)) {
      final dynamic body = _json(response.body);
      if (body is Map && body['success'] == false) {
        _throwResponse(response.statusCode, body);
      }
      throw const ExpenseApiException(
          'The server did not return a valid file. Nothing was saved.');
    }
    if (response.bodyBytes.isEmpty) {
      throw const ExpenseApiException('The downloaded file was empty.');
    }
    final String disposition = _header(response, 'content-disposition') ?? '';
    final RegExpMatch? match =
        RegExp(r'''filename\*?=(?:UTF-8'')?["']?([^"';]+)["']?''')
            .firstMatch(disposition);
    String filename = fallbackName;
    final String? raw = match?.group(1)?.trim();
    if (raw != null && raw.isNotEmpty) {
      try {
        filename = Uri.decodeComponent(raw);
      } catch (_) {
        filename = raw;
      }
    }
    filename = filename.replaceAll(RegExp(r'[\\/]'), '_');
    await _download(response.bodyBytes, filename, contentType);
    return filename;
  }

  // ---------------- Internals ----------------
  void _checkKind(String kind) {
    if (kind != 'categories' && kind != 'vendors') {
      throw const ExpenseApiException('Unknown catalog type.');
    }
  }

  void _checkKey(String key) {
    if (!ExpenseIdempotency.pattern.hasMatch(key)) {
      throw const ExpenseApiException('A valid operation key is required.');
    }
  }

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? query]) async {
    final String token = await _requiredToken();
    final http.Response response = await _guard(
      () => _client.get(uri(path, query), headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      }),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    String idempotencyKey,
    Map<String, dynamic> body,
  ) async {
    _checkKey(idempotencyKey);
    final String token = await _requiredToken();
    final http.Request request = http.Request(method, uri(path))
      ..headers.addAll(<String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Idempotency-Key': idempotencyKey,
      })
      ..body = jsonEncode(body);
    final http.Response response = await _guard(
      () async => http.Response.fromStream(await _client.send(request)),
      write: true,
    );
    return _decode(response);
  }

  Future<http.Response> _guard(
    Future<http.Response> Function() run, {
    bool write = false,
    Duration timeout = requestTimeout,
  }) async {
    try {
      return await run().timeout(timeout);
    } on TimeoutException {
      throw ExpenseApiException(
        write
            ? 'The server did not answer in time. The change may or may not have been saved. Retry uses the same operation key and cannot create a duplicate.'
            : 'The request timed out. Check your connection and reload.',
        outcomeUnknown: write,
      );
    } on ExpenseApiException {
      rethrow;
    } catch (_) {
      throw ExpenseApiException(
        write
            ? 'Connection lost before a confirmed result. Retry safely with the same operation key.'
            : 'Unable to reach the expense service. Check your connection and reload.',
        outcomeUnknown: write,
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final dynamic body = _json(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwResponse(response.statusCode, body);
    }
    if (body is! Map || body['success'] != true || body['data'] is! Map) {
      throw const ExpenseApiException(
          'The expense service returned an invalid response.');
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<String> _requiredToken() async {
    final String? raw = await _tokenLoader();
    final String token = raw?.trim() ?? '';
    if (token.isEmpty) {
      throw const ExpenseApiException(
          'Your admin session has expired. Please sign in again.',
          statusCode: 401);
    }
    return token.toLowerCase().startsWith('bearer ')
        ? token.substring(7)
        : token;
  }

  dynamic _json(String body) {
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
      400 => 'Some details were rejected. Review the highlighted fields.',
      401 => 'Your admin session has expired. Please sign in again.',
      403 => 'You do not have the expense permission required for this action.',
      404 => 'The expense service or record was not found.',
      409 =>
        'This record changed or the reference already exists. The latest version has been loaded.',
      413 => 'The document exceeds the permitted size.',
      429 => 'Too many requests. Wait a moment and try again.',
      503 => 'Expense management is not ready on the server.',
      _ => 'The expense service could not complete the request.',
    };
    final String? message =
        body is Map ? body['message']?.toString().trim() : null;
    final String? code = body is Map ? body['code']?.toString() : null;
    throw ExpenseApiException(
      message?.isNotEmpty == true ? message! : fallback,
      statusCode: status,
      code: code,
      outcomeUnknown: status >= 500 && status != 503,
    );
  }
}
