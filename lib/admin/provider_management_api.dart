import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class ProviderService {
  const ProviderService({
    required this.service,
    required this.configurationReported,
    required this.primaryProvider,
    required this.fallbackProvider,
    required this.currentProvider,
    required this.providers,
    required this.fallbackSupported,
    required this.updatedAt,
    required this.updatedBy,
  });

  final String service;
  final bool configurationReported;
  final String? primaryProvider;
  final String? fallbackProvider;
  final String? currentProvider;
  final List<Map<String, dynamic>> providers;
  final bool fallbackSupported;
  final String? updatedAt;
  final String? updatedBy;

  ProviderCapabilities capabilitiesFor(Map<String, dynamic> provider) =>
      ProviderCapabilities.fromJson(provider['capabilities']);

  factory ProviderService.fromJson(Map<String, dynamic> json) {
    final dynamic rawProviders = json['providers'];
    return ProviderService(
      service: (json['service'] ?? '').toString(),
      configurationReported: true,
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

  factory ProviderService.notReported(String service) {
    const String reason = 'The backend did not return this service configuration.';
    return ProviderService(
      service: service,
      configurationReported: false,
      primaryProvider: null,
      fallbackProvider: null,
      currentProvider: null,
      providers: <Map<String, dynamic>>[
        <String, dynamic>{'provider': 'NELLOBYTES', 'reason': reason},
        <String, dynamic>{
          'provider': 'TELECOM_ABODE',
          'reason': reason,
        },
      ],
      fallbackSupported: false,
      updatedAt: null,
      updatedBy: null,
    );
  }

  static String? _nullableString(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    return value.toString();
  }
}

@immutable
class ProviderCapabilities {
  const ProviderCapabilities({
    required this.adapterImplemented,
    required this.credentialsConfigured,
    required this.catalogAvailable,
    required this.purchaseSupported,
    required this.querySupported,
    required this.webhookSupported,
    required this.webhookVerified,
    required this.financialSafetyVerified,
    required this.productionReady,
    required this.readinessReasons,
  });

  final bool? adapterImplemented;
  final bool? credentialsConfigured;
  final bool? catalogAvailable;
  final bool? purchaseSupported;
  final bool? querySupported;
  final bool? webhookSupported;
  final bool? webhookVerified;
  final bool? financialSafetyVerified;
  final bool? productionReady;
  final List<String> readinessReasons;

  factory ProviderCapabilities.fromJson(dynamic json) {
    final Map<dynamic, dynamic>? values = json is Map ? json : null;
    final dynamic rawReasons = values?['readinessReasons'];
    return ProviderCapabilities(
      adapterImplemented: _reportedBoolean(values?['adapterImplemented']),
      credentialsConfigured:
          _reportedBoolean(values?['credentialsConfigured']),
      catalogAvailable: _reportedBoolean(values?['catalogAvailable']),
      purchaseSupported: _reportedBoolean(values?['purchaseSupported']),
      querySupported: _reportedBoolean(values?['querySupported']),
      webhookSupported: _reportedBoolean(values?['webhookSupported']),
      webhookVerified: _reportedBoolean(values?['webhookVerified']),
      financialSafetyVerified:
          _reportedBoolean(values?['financialSafetyVerified']),
      productionReady: _reportedBoolean(values?['productionReady']),
      readinessReasons: rawReasons is List
          ? rawReasons
              .whereType<String>()
              .where((String reason) => reason.trim().isNotEmpty)
              .toList(growable: false)
          : const <String>[],
    );
  }

  static bool? _reportedBoolean(dynamic value) =>
      value is bool ? value : null;
}

class ProviderManagementApi {
  ProviderManagementApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? _defaultBaseUrl;

  static const String _defaultBaseUrl = String.fromEnvironment(
    'SERVICEPAY_API_BASE_URL',
    defaultValue: 'https://api.servicepay.ng/api',
  );
  static const String _resource =
      '/admin/fintech-operations/provider-management';

  final http.Client _client;
  final String baseUrl;

  Uri get _resourceUri {
    final String normalizedBase = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final Uri configuredUri = Uri.parse('$normalizedBase$_resource');
    return configuredUri.hasScheme
        ? configuredUri
        : Uri.base.resolveUri(configuredUri);
  }

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
      _resourceUri,
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
    final List<ProviderService> returned = rawItems
        .whereType<Map>()
        .map((Map item) => ProviderService.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    const List<String> serviceOrder = <String>[
      'AIRTIME',
      'DATA',
      'ELECTRICITY',
      'CABLE',
    ];
    String serviceKey(String service) =>
        service.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    final Map<String, ProviderService> byService = <String, ProviderService>{};
    for (final ProviderService service in returned) {
      byService.putIfAbsent(serviceKey(service.service), () => service);
    }

    final List<ProviderService> ordered = serviceOrder
        .map((String key) => byService.remove(key) ?? ProviderService.notReported(key))
        .toList(growable: true);
    final List<ProviderService> additional = byService.values.toList()
      ..sort((ProviderService a, ProviderService b) =>
          a.service.compareTo(b.service));
    return <ProviderService>[...ordered, ...additional];
  }

  Future<void> updateProvider({
    required String service,
    required String action,
    required String provider,
  }) async {
    final Uri uri = _resourceUri;
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