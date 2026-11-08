import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';

enum PendingResolutionAction { markSuccessful, refund, retry }

@immutable
class PendingResolutionIntent {
  const PendingResolutionIntent({
    required this.transactionId,
    required this.action,
    required this.reason,
    required this.idempotencyKey,
    this.evidenceReference = '',
    this.deliveryConfirmed = false,
    this.providerRiskAcknowledged = false,
  });

  final String transactionId;
  final PendingResolutionAction action;
  final String reason;
  final String idempotencyKey;
  final String evidenceReference;
  final bool deliveryConfirmed;
  final bool providerRiskAcknowledged;

  Map<String, dynamic> get body {
    if (action == PendingResolutionAction.retry) {
      return <String, dynamic>{
        'reason': reason,
        'idempotencyKey': idempotencyKey,
      };
    }
    final bool refundAction = action == PendingResolutionAction.refund;
    return <String, dynamic>{
      'action': refundAction ? 'REFUND' : 'MARK_SUCCESSFUL',
      'reason': reason,
      if (!refundAction) 'evidenceReference': evidenceReference,
      'confirmation': true,
      if (refundAction)
        'providerRiskAcknowledged': providerRiskAcknowledged
      else
        'deliveryConfirmed': deliveryConfirmed,
      'idempotencyKey': idempotencyKey,
    };
  }

  factory PendingResolutionIntent.fromJson(Map<String, dynamic> value) {
    final String actionValue = '${value['action'] ?? ''}';
    return PendingResolutionIntent(
      transactionId: '${value['transactionId'] ?? ''}',
      action: PendingResolutionAction.values.firstWhere(
        (PendingResolutionAction action) => action.name == actionValue,
        orElse: () => throw const PendingResolutionApiException(
          'A saved request cannot be read safely. Do not start another action.',
        ),
      ),
      reason: '${value['reason'] ?? ''}',
      idempotencyKey: '${value['idempotencyKey'] ?? ''}',
      evidenceReference: '${value['evidenceReference'] ?? ''}',
      deliveryConfirmed: value['deliveryConfirmed'] == true,
      providerRiskAcknowledged: value['providerRiskAcknowledged'] == true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'transactionId': transactionId,
        'action': action.name,
        'reason': reason,
        'idempotencyKey': idempotencyKey,
        'evidenceReference': evidenceReference,
        'deliveryConfirmed': deliveryConfirmed,
        'providerRiskAcknowledged': providerRiskAcknowledged,
      };

  bool sameRequest(PendingResolutionIntent other) =>
      transactionId == other.transactionId &&
      action == other.action &&
      reason == other.reason &&
      evidenceReference == other.evidenceReference &&
      deliveryConfirmed == other.deliveryConfirmed &&
      providerRiskAcknowledged == other.providerRiskAcknowledged;
}

class PendingResolutionApiException implements Exception {
  const PendingResolutionApiException(
    this.message, {
    this.statusCode,
    this.code,
  });
  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

/// Authenticated client for the Admin-only pending transaction workspace.
/// Mutation intents are persisted per actor/session before the first POST.
class PendingResolutionApi {
  PendingResolutionApi({
    http.Client? client,
    String? baseUrl,
    Future<String?> Function()? tokenProvider,
    Future<bool> Function(String key, String value)? intentWriter,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrl = (baseUrl ?? AdminApiConfiguration.baseUrl)
            .replaceFirst(RegExp(r'/$'), ''),
        _tokenProvider = tokenProvider ?? _storedToken,
        _intentWriter = intentWriter;

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
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

  Future<Map<String, dynamic>> summary() => _get('summary');

  Future<Map<String, dynamic>> transactions({
    int page = 1,
    int limit = 20,
    String search = '',
    String type = '',
    String from = '',
    String to = '',
    String minAmount = '',
    String maxAmount = '',
    String duration = 'ALL',
    String status = 'PENDING',
  }) {
    final Map<String, String> query = <String, String>{
      'page': '${page < 1 ? 1 : page}',
      'limit': '${limit.clamp(1, 50)}',
      'duration': duration,
      'status': status,
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (type.isNotEmpty) 'type': type,
      if (from.isNotEmpty) 'from': from,
      if (to.isNotEmpty) 'to': to,
      if (minAmount.isNotEmpty) 'minAmount': minAmount,
      if (maxAmount.isNotEmpty) 'maxAmount': maxAmount,
    };
    return _get('transactions', query: query);
  }

  Future<Map<String, dynamic>> transaction(String id) =>
      _get('transactions/${Uri.encodeComponent(id)}');

  Future<PendingResolutionIntent?> loadIntent(String transactionId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString(await _intentKey(transactionId));
    if (encoded == null) return null;
    try {
      final dynamic decoded = jsonDecode(encoded);
      if (decoded is Map) {
        final PendingResolutionIntent intent = PendingResolutionIntent.fromJson(
            Map<String, dynamic>.from(decoded));
        if (intent.transactionId == transactionId &&
            intent.idempotencyKey.isNotEmpty) {
          return intent;
        }
      }
    } catch (_) {
      // Never replace a corrupt saved key with a new request.
    }
    throw const PendingResolutionApiException(
      'A saved request could not be read. Contact an administrator before retrying.',
    );
  }

  Future<Map<String, dynamic>> submitAction(
    String transactionId, {
    required PendingResolutionAction action,
    required String reason,
    String evidenceReference = '',
    bool deliveryConfirmed = false,
    bool providerRiskAcknowledged = false,
  }) async {
    final PendingResolutionIntent? existing = await loadIntent(transactionId);
    final PendingResolutionIntent proposed = PendingResolutionIntent(
      transactionId: transactionId,
      action: action,
      reason: reason.trim(),
      evidenceReference: evidenceReference.trim(),
      deliveryConfirmed: deliveryConfirmed,
      providerRiskAcknowledged: providerRiskAcknowledged,
      idempotencyKey: existing?.idempotencyKey ?? _newKey(),
    );
    if (existing != null && !existing.sameRequest(proposed)) {
      throw const PendingResolutionApiException(
        'An unresolved request is saved for this transaction. Retry that exact action, reason and evidence before starting another action.',
      );
    }
    if (action == PendingResolutionAction.retry) {
      throw const PendingResolutionApiException(
        'Use submitRetry for a provider status recheck.',
      );
    }
    if (reason.trim().length < 10 || reason.trim().length > 500) {
      throw const PendingResolutionApiException(
        'Reason must be between 10 and 500 characters.',
      );
    }
    if (action == PendingResolutionAction.markSuccessful &&
        (evidenceReference.trim().length < 6 ||
            evidenceReference.trim().length > 200 ||
            !deliveryConfirmed)) {
      throw const PendingResolutionApiException(
        'A delivery confirmation and evidence reference of 6–200 characters are required.',
      );
    }
    if (action == PendingResolutionAction.refund && !providerRiskAcknowledged) {
      throw const PendingResolutionApiException(
        'Acknowledge the possible financial loss before submitting a refund.',
      );
    }
    await _saveIntent(proposed);
    try {
      final Map<String, dynamic> result = await _post(
        'transactions/${Uri.encodeComponent(transactionId)}/resolve',
        body: proposed.body,
        idempotencyKey: proposed.idempotencyKey,
      );
      final dynamic data = result['data'];
      final String state =
          data is Map ? '${data['state'] ?? ''}'.toUpperCase() : '';
      // A processing acknowledgement is not a terminal result; keep the same
      // request available for replay until an authoritative outcome arrives.
      if (state != 'PROCESSING') await _clearIntent(transactionId);
      return result;
    } on PendingResolutionApiException catch (error) {
      if (_isDefinitiveNoAction(error.statusCode)) {
        await _clearIntent(transactionId);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> submitRetry(
    String transactionId, {
    required String reason,
  }) async {
    final PendingResolutionIntent? existing = await loadIntent(transactionId);
    final PendingResolutionIntent proposed = PendingResolutionIntent(
      transactionId: transactionId,
      action: PendingResolutionAction.retry,
      reason: reason.trim(),
      idempotencyKey: existing?.idempotencyKey ?? _newKey(),
    );
    if (existing != null && !existing.sameRequest(proposed)) {
      throw const PendingResolutionApiException(
        'A saved request is unresolved. Replay it with the original reason and key.',
      );
    }
    if (reason.trim().length < 10 || reason.trim().length > 500) {
      throw const PendingResolutionApiException(
        'Reason must be between 10 and 500 characters.',
      );
    }
    await _saveIntent(proposed);
    try {
      final Map<String, dynamic> result = await _post(
        'transactions/${Uri.encodeComponent(transactionId)}/retry',
        body: proposed.body,
        idempotencyKey: proposed.idempotencyKey,
      );
      final dynamic data = result['data'];
      final String state =
          data is Map ? '${data['state'] ?? ''}'.toUpperCase() : '';
      if (state != 'PROCESSING') await _clearIntent(transactionId);
      return result;
    } on PendingResolutionApiException catch (error) {
      if (_isDefinitiveNoAction(error.statusCode)) {
        await _clearIntent(transactionId);
      }
      rethrow;
    }
  }

  bool _isDefinitiveNoAction(int? status) =>
      status != null && status >= 400 && status < 500 &&
      !<int>{408, 425, 429}.contains(status);

  Future<void> _saveIntent(PendingResolutionIntent intent) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _intentKey(intent.transactionId);
    final String encoded = jsonEncode(intent.toJson());
    final bool saved = _intentWriter == null
        ? await prefs.setString(key, encoded)
        : await _intentWriter!(key, encoded);
    if (!saved) {
      throw const PendingResolutionApiException(
        'The safe retry request could not be saved. No action was submitted.',
      );
    }
  }

  Future<void> _clearIntent(String transactionId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _intentKey(transactionId));
  }

  Future<String> _intentKey(String transactionId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String token = (await _requiredToken()).trim();
    final String actor =
        (prefs.getString('user_id') ?? prefs.getString('admin_id') ?? '')
            .trim();
    final String scope = actor.isNotEmpty
        ? 'actor-${_fingerprint(actor)}'
        : 'session-${_fingerprint(token)}';
    return 'pending_resolution_intent_v1_${scope}_${Uri.encodeComponent(transactionId)}';
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

  String _newKey() {
    final Random random = Random.secure();
    final String part = List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'pending-resolution-${DateTime.now().microsecondsSinceEpoch}-$part';
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) =>
      _request('GET', path, query: query);

  Future<Map<String, dynamic>> _post(
    String path, {
    required Map<String, dynamic> body,
    required String idempotencyKey,
  }) =>
      _request(
        'POST',
        path,
        payload: body,
        idempotencyKey: idempotencyKey,
      );

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? payload,
    String? idempotencyKey,
  }) async {
    final String token = (await _requiredToken()).trim();
    final Uri uri = Uri.parse('$_baseUrl/admin/pending-resolution/$path')
        .replace(queryParameters: query);
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (payload != null) 'Content-Type': 'application/json',
      if (idempotencyKey != null) 'X-Idempotency-Key': idempotencyKey,
    };
    late http.Response response;
    try {
      response = method == 'POST'
          ? await _client
              .post(uri, headers: headers, body: jsonEncode(payload))
              .timeout(const Duration(seconds: 30))
          : await _client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 30));
    } on Exception {
      throw const PendingResolutionApiException(
        'The request outcome is uncertain. Keep this request open and replay the same saved request; do not create another action.',
      );
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    final Map<String, dynamic> envelope = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (envelope['success'] == true && envelope['data'] is Map) {
        return envelope;
      }
      throw const PendingResolutionApiException(
        'The server response could not be confirmed. Keep the saved request and replay it safely.',
      );
    }
    final String message = envelope['message'] is String &&
            (envelope['message'] as String).trim().isNotEmpty
        ? (envelope['message'] as String).trim()
        : response.statusCode == 401
            ? 'Your admin session has expired. Sign in again before continuing.'
            : 'Request was not completed (server ${response.statusCode}).';
    throw PendingResolutionApiException(
      message,
      statusCode: response.statusCode,
      code: envelope['code']?.toString(),
    );
  }

  Future<String> _requiredToken() async {
    final String? token = await _tokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const PendingResolutionApiException(
        'Your admin session is unavailable. Sign in again before continuing.',
      );
    }
    return token.trim();
  }
}
