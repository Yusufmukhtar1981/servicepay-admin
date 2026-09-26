import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class ProviderService {
  const ProviderService({
    required this.service,
    required this.primaryProvider,
    required this.fallbackProvider,
    required this.currentProvider,
    required this.providers,
    required this.fallbackSupported,
    required this.updatedAt,
    required this.updatedBy,
  });

  final String service;
  final String? primaryProvider;
  final String? fallbackProvider;
  final String? currentProvider;
  final List<Map<String, dynamic>> providers;
  final bool fallbackSupported;
  final String? updatedAt;
  final String? updatedBy;

  factory ProviderService.fromJson(Map<String, dynamic> json) {
    final dynamic rawProviders = json['providers'];
    return ProviderService(
      service: (json['service'] ?? '').toString(),
      primaryProvider: _nullableString(json['primaryProvider']),
      fallbackProvider: _nullableString(json['fallbackProvider']),
      currentProvider: _nullableString(json['currentProvider']),
      providers: rawProviders is List
          ? rawProviders
              .whereType<Map>()
              .map((Map value) => Map<String, dynamic>.from(value))
              .toList(growable: false)
          : const <Map<String, dynamic>>[],
      fallbackSupported: json['fallbackSupported'] == true,
      updatedAt: _nullableString(json['updatedAt']),
      updatedBy: _nullableString(json['updatedBy']),
    );
  }

  static String? _nullableString(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    return value.toString();
  }
}

class ProviderManagementApi {
  ProviderManagementApi({http.Client? client})
      : _client = client ?? http.Client();

  static const String _baseUrl = 'https://api.servicepay.ng/api';
  static const String _resource =
      '/admin/fintech-operations/provider-management';

  final http.Client _client;

  Future<Map<String, String>> _headers() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String token = '';
    for (final String key in const <String>[
      'auth_token',
      'token',
      'access_token',
      'accessToken',
      'jwt_token',
      'jwt',
    ]) {
      token = (prefs.getString(key) ?? '').trim();
      if (token.isNotEmpty) break;
    }
    if (token.startsWith('Bearer ')) token = token.substring(7);
    if (token.isEmpty) throw Exception('Admin session not found. Sign in again.');
    return <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<ProviderService>> loadServices() async {
    final http.Response response = await _client.get(
      Uri.parse('$_baseUrl$_resource'),
      headers: await _headers(),
    );
    final dynamic decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(decoded, 'Unable to load provider settings.'));
    }
    if (decoded is! Map || decoded['success'] != true || decoded['data'] is! Map) {
      throw Exception(_message(decoded, 'Provider settings response was invalid.'));
    }
    final dynamic rawItems = (decoded['data'] as Map)['items'];
    if (rawItems is! List) {
      throw Exception('Provider settings response did not include items.');
    }
    return rawItems
        .whereType<Map>()
        .map((Map item) => ProviderService.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<void> updateProvider({
    required String service,
    required String action,
    required String provider,
  }) async {
    final Uri uri = Uri.parse('$_baseUrl$_resource');
    final http.Response response = await _client.patch(
      uri,
      headers: await _headers(),
      body: jsonEncode(<String, String>{
        'service': service,
        'action': action,
        'provider': provider,
      }),
    );
    final dynamic decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(decoded, 'Unable to update provider settings.'));
    }
    if (decoded is! Map || decoded['success'] != true) {
      throw Exception(_message(decoded, 'Provider update was not confirmed.'));
    }
  }

  dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return const <String, dynamic>{};
    }
  }

  String _message(dynamic decoded, String fallback) {
    if (decoded is Map) {
      final dynamic message = decoded['message'] ?? decoded['error'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
    return fallback;
  }

  @visibleForTesting
  void close() => _client.close();
}