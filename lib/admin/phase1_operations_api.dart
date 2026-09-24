import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 1 Head Office/manager operations client.
///
/// All privileged decisions remain server-side. This client deliberately does
/// not accept an actor/user id from callers.
class Phase1OperationsApi {
  Phase1OperationsApi({
    http.Client? client,
    this.baseUrl = 'https://api.servicepay.ng/api',
    Future<SharedPreferences> Function()? preferencesLoader,
  })  : _client = client ?? http.Client(),
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final http.Client _client;
  final String baseUrl;
  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<Map<String, dynamic>> createZonalManager({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    String zone = '',
    String state = '',
  }) =>
      _request(
        'POST',
        '/admin/role-users',
        body: <String, dynamic>{
          'fullName': fullName.trim(),
          'email': email.trim(),
          'phone': phone.trim(),
          'password': password,
          'role': 'ZONAL_MANAGER',
          if (zone.trim().isNotEmpty) 'zone': zone.trim(),
          if (state.trim().isNotEmpty) 'state': state.trim(),
        },
      );

  Future<Map<String, dynamic>> promoteUser({
    required String userId,
    required String targetRole,
  }) =>
      _request(
        'POST',
        '/admin/role-users/${Uri.encodeComponent(userId)}/promote',
        body: <String, dynamic>{'targetRole': targetRole},
      );

  Future<Map<String, dynamic>> hierarchySummary() =>
      _request('GET', '/admin/hierarchy/summary');

  Future<Map<String, dynamic>> searchCustomers(String search) => _request(
        'GET',
        '/admin/wallet-adjustment/customers',
        query: <String, String>{
          if (search.trim().isNotEmpty) 'search': search.trim(),
        },
      );

  Future<Map<String, dynamic>> adjustWallet({
    required String customerId,
    required String action,
    required String amount,
    required String reason,
    required String reference,
    required String idempotencyKey,
  }) =>
      _request(
        'POST',
        '/admin/wallet-adjustment',
        body: <String, dynamic>{
          'customerId': customerId,
          'action': action,
          'amount': amount,
          'reason': reason.trim(),
          'reference': reference.trim(),
          'idempotencyKey': idempotencyKey,
        },
      );

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final token = await _token();
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final response = switch (method) {
      'POST' => await _client
          .post(uri, headers: headers, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 30)),
      _ => await _client.get(uri, headers: headers).timeout(
            const Duration(seconds: 30),
          ),
    };
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['message']?.toString() : null;
      throw Phase1OperationsException(
        response.statusCode,
        message?.trim().isNotEmpty == true
            ? message!.trim()
            : 'Unable to complete this operation.',
      );
    }
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  Future<String> _token() async {
    final prefs = await _preferencesLoader();
    for (final key in const [
      'auth_token',
      'token',
      'access_token',
      'accessToken',
      'jwt_token',
      'jwt',
    ]) {
      final value = prefs.getString(key)?.trim() ?? '';
      if (value.isNotEmpty) {
        return value.toLowerCase().startsWith('bearer ')
            ? value.substring(7)
            : value;
      }
    }
    throw const Phase1OperationsException(
      401,
      'Your session has expired. Please sign in again.',
    );
  }
}

class Phase1OperationsException implements Exception {
  const Phase1OperationsException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}

@visibleForTesting
String phase1IdempotencyKey() =>
    'admin-wallet-${DateTime.now().microsecondsSinceEpoch}';
