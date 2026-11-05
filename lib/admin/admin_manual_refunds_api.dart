import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminManualRefundsApi {
  AdminManualRefundsApi({
    http.Client? client,
    String? baseUrl,
    Future<String?> Function()? tokenProvider,
    Future<bool> Function(String key, String value)? intentWriter,
  })  : baseUrl = (baseUrl ??
                const String.fromEnvironment(
                  'SERVICEPAY_API_BASE_URL',
                  defaultValue: 'https://api.servicepay.ng/api',
                ))
            .replaceFirst(RegExp(r'/$'), ''),
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _tokenProvider = tokenProvider ?? _storedToken,
        _intentWriter = intentWriter;

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final Future<String?> Function() _tokenProvider;
  final Future<bool> Function(String key, String value)? _intentWriter;

  void close() {
    if (_ownsClient) _client.close();
  }

  static Future<String?> _storedToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ??
        prefs.getString('token') ??
        prefs.getString('admin_token');
  }

  Future<Map<String, dynamic>> transaction(String id) =>
      _request('GET', '/transactions/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> history({int page = 1}) =>
      _request('GET', '/history', query: <String, String>{'page': '$page'});

  Future<Map<String, dynamic>> refund(
    String id, {
    required String reason,
    required String idempotencyKey,
    required bool providerRiskAcknowledged,
  }) async {
    if (!providerRiskAcknowledged) {
      throw const ManualRefundApiException(
        'Acknowledge the provider outcome risk before submitting a refund.',
      );
    }
    final ManualRefundIntent? savedIntent = await loadIntent(id);
    if (savedIntent != null &&
        (savedIntent.reason != reason ||
            savedIntent.idempotencyKey != idempotencyKey)) {
      throw const ManualRefundApiException(
        'A saved refund retry request must be reused without changing its reason or key.',
      );
    }
    await saveIntent(
      id,
      ManualRefundIntent(
        reason: savedIntent?.reason ?? reason,
        idempotencyKey: savedIntent?.idempotencyKey ?? idempotencyKey,
        providerRiskAcknowledged: true,
      ),
    );
    return _request(
      'POST',
      '/transactions/${Uri.encodeComponent(id)}/refund',
      payload: <String, dynamic>{
        'reason': reason,
        'confirmation': true,
        'providerRiskAcknowledged': true,
        'idempotencyKey': idempotencyKey,
      },
      idempotencyKey: idempotencyKey,
    );
  }

  /// Persists the exact reason and key before the first POST. Subsequent calls
  /// for this actor/session and transaction always replay that immutable intent.
  Future<Map<String, dynamic>> submitRefund(
    String id, {
    required String reason,
    required bool providerRiskAcknowledged,
  }) async {
    ManualRefundIntent? intent = await loadIntent(id);
    if (intent == null) {
      if (!providerRiskAcknowledged) {
        throw const ManualRefundApiException(
          'Acknowledge the provider outcome risk before submitting a refund.',
        );
      }
      intent = ManualRefundIntent(
        reason: reason,
        idempotencyKey: _newIdempotencyKey(),
        providerRiskAcknowledged: true,
      );
    } else if (!intent.providerRiskAcknowledged) {
      if (!providerRiskAcknowledged) {
        throw const ManualRefundApiException(
          'This saved request predates risk acknowledgement. Explicitly acknowledge the provider outcome risk before retrying.',
        );
      }
      // Preserve the original immutable reason/key while upgrading the legacy
      // intent only after a fresh, explicit acknowledgement.
      intent = ManualRefundIntent(
        reason: intent.reason,
        idempotencyKey: intent.idempotencyKey,
        providerRiskAcknowledged: true,
      );
    }
    // SharedPreferences can retain a failed write in memory. Every submission,
    // including a retry, must successfully persist the SAME request first.
    await saveIntent(id, intent);
    late Map<String, dynamic> response;
    try {
      response = await refund(
        id,
        reason: intent.reason,
        idempotencyKey: intent.idempotencyKey,
        providerRiskAcknowledged: intent.providerRiskAcknowledged,
      );
    } on ManualRefundApiException catch (error) {
      if (const <int>{400, 401, 403, 404, 422}.contains(error.statusCode)) {
        try {
          await clearIntent(id);
        } catch (_) {
          // Retaining a safe-failure intent is conservative if cleanup fails.
        }
      }
      rethrow;
    }
    // A successful or replayed server response is definitive. If local cleanup
    // fails, keeping the intent is safe: a later retry uses the same key/body.
    try {
      await clearIntent(id);
    } catch (_) {
      // Do not turn confirmed server success into an uncertain UI result.
    }
    return response;
  }

  Future<ManualRefundIntent?> loadIntent(String transactionId) async {
    final String token = await _requiredToken();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString(_intentPreferenceKey(
      prefs,
      token,
      transactionId,
    ));
    if (encoded == null) return null;
    try {
      final dynamic value = jsonDecode(encoded);
      if (value is Map &&
          value['reason'] is String &&
          value['idempotencyKey'] is String) {
        return ManualRefundIntent(
          reason: value['reason'] as String,
          idempotencyKey: value['idempotencyKey'] as String,
          providerRiskAcknowledged: value['providerRiskAcknowledged'] == true,
        );
      }
    } catch (_) {
      // A corrupt local record must never be used to create a different POST.
    }
    throw const ManualRefundApiException(
      'A saved refund retry request could not be read. Contact an administrator before retrying.',
    );
  }

  Future<void> saveIntent(
    String transactionId,
    ManualRefundIntent intent,
  ) async {
    final String token = await _requiredToken();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = _intentPreferenceKey(prefs, token, transactionId);
    final String value = jsonEncode(<String, dynamic>{
      'reason': intent.reason,
      'idempotencyKey': intent.idempotencyKey,
      'providerRiskAcknowledged': intent.providerRiskAcknowledged,
    });
    final bool saved = _intentWriter == null
        ? await prefs.setString(key, value)
        : await _intentWriter!(key, value);
    if (!saved) {
      throw const ManualRefundApiException(
        'The safe retry request could not be saved. No refund was submitted.',
      );
    }
  }

  Future<void> clearIntent(String transactionId) async {
    final String token = await _requiredToken();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_intentPreferenceKey(prefs, token, transactionId));
  }

  String _intentPreferenceKey(
    SharedPreferences prefs,
    String token,
    String transactionId,
  ) {
    final String actor =
        (prefs.getString('user_id') ?? prefs.getString('admin_id') ?? '')
            .trim();
    final String scope = actor.isNotEmpty
        ? 'actor-${_fingerprint(actor)}'
        : 'session-${_fingerprint(token)}';
    return 'manual_refund_intent_v1_${scope}_${Uri.encodeComponent(transactionId)}';
  }

  Future<String> _requiredToken() async {
    final String? token = await _tokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const ManualRefundApiException(
        'Your admin session is unavailable. Sign in again before continuing.',
      );
    }
    return token.trim();
  }

  String _newIdempotencyKey() {
    final Random random = Random.secure();
    final String randomPart = List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'manual-refund-${DateTime.now().microsecondsSinceEpoch}-$randomPart';
  }

  String _fingerprint(String value) {
    final BigInt mask = (BigInt.one << 64) - BigInt.one;
    final BigInt prime = BigInt.parse('1099511628211');
    BigInt hash = BigInt.parse('14695981039346656037');
    for (final int unit in value.codeUnits) {
      hash = ((hash ^ BigInt.from(unit)) * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? payload,
    String? idempotencyKey,
  }) async {
    final String token = await _requiredToken();
    final Uri uri = Uri.parse('$baseUrl/admin/manual-refunds$path')
        .replace(queryParameters: query);
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (payload != null) 'Content-Type': 'application/json',
      if (idempotencyKey != null) 'X-Idempotency-Key': idempotencyKey,
    };
    late http.Response response;
    try {
      if (method == 'POST') {
        response = await _client
            .post(uri, headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 30));
      } else {
        response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 30));
      }
    } on Exception {
      throw const ManualRefundApiException(
        'The request could not be confirmed. Retry using the same request; do not start another refund.',
      );
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map && decoded['success'] == true) {
        if (method != 'POST' || decoded['refund'] is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
      throw const ManualRefundApiException(
        'The server response could not be confirmed. Keep this request open and retry safely.',
      );
    }
    if (response.statusCode == 401) {
      throw const ManualRefundApiException(
        'Your admin session has expired. Sign in again before continuing.',
        statusCode: 401,
      );
    }
    if (response.statusCode == 403) {
      throw const ManualRefundApiException(
        'Your account lacks the explicit transactions.refund permission required for refunds. Ask a Head Office access administrator to assign it.',
        statusCode: 403,
      );
    }
    final String message = decoded is Map &&
            decoded['message'] is String &&
            (decoded['message'] as String).trim().isNotEmpty
        ? (decoded['message'] as String).trim()
        : 'The request was not completed (server ${response.statusCode}).';
    throw ManualRefundApiException(message, statusCode: response.statusCode);
  }
}

class ManualRefundIntent {
  const ManualRefundIntent({
    required this.reason,
    required this.idempotencyKey,
    required this.providerRiskAcknowledged,
  });

  final String reason;
  final String idempotencyKey;
  final bool providerRiskAcknowledged;
}

class ManualRefundApiException implements Exception {
  const ManualRefundApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
