import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminFeatureControlsApi {
  AdminFeatureControlsApi({
    http.Client? client,
    this.baseUrl = const String.fromEnvironment(
      'SERVICEPAY_API_BASE_URL',
      defaultValue: 'https://api.servicepay.ng/api',
    ),
    Future<SharedPreferences> Function()? preferencesLoader,
  })  : _client = client ?? http.Client(),
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final http.Client _client;
  final String baseUrl;
  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<Map<String, bool>> load() async {
    final response = await _request('GET');
    final decoded = _decode(response);
    final data = decoded['data'];
    final raw = data is Map ? data['featureToggles'] : null;
    if (raw is! Map) {
      throw const AdminFeatureControlsException(
        502,
        'The service returned an invalid feature-control response.',
      );
    }
    return <String, bool>{
      for (final entry in raw.entries)
        if (entry.value is bool) entry.key.toString(): entry.value as bool,
    };
  }

  Future<FeatureControlRegistry> loadRegistry() async {
    late http.Response response;
    try {
      response = await _request(
        'GET',
        path: '/settings/admin/feature-control/registry',
      );
    } on AdminFeatureControlsException catch (error) {
      if (error.statusCode != 404 && error.statusCode != 405) rethrow;
      // Keep older deployments usable while the registry route rolls out.
      response = await _request('GET');
    }
    final decoded = _decode(response);
    final data = decoded['data'];
    if (data is Map && data['features'] is List) {
      final features = (data['features'] as List)
          .whereType<Map>()
          .map(
            (value) =>
                FeatureControl.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList();
      final rawMetrics = data['metrics'];
      return FeatureControlRegistry(
        features: features,
        metrics: rawMetrics is Map
            ? Map<String, int>.fromEntries(
                rawMetrics.entries.where((entry) => entry.value is num).map(
                      (entry) => MapEntry(
                        entry.key.toString(),
                        (entry.value as num).toInt(),
                      ),
                    ),
              )
            : const <String, int>{},
        sync: data['sync'] is Map
            ? Map<String, dynamic>.from(data['sync'] as Map)
            : const <String, dynamic>{},
      );
    }
    // A rolling upgrade can return the existing fintech-control payload.
    final raw = data is Map ? data['featureToggles'] : null;
    if (raw is Map) {
      const labels = <String, String>{
        'airtime': 'Airtime',
        'data': 'Mobile Data',
        'electricity': 'Electricity',
        'cableTv': 'Cable TV',
        'examPin': 'Exam PIN',
        'ninVerification': 'NIN Verification',
        'bvnVerification': 'BVN Verification',
        'delivery': 'Delivery',
        'walletFunding': 'Wallet Funding',
        'servicepayTransfer': 'ServicePay Transfer',
        'bankTransfer': 'Bank Transfer',
        'flightBooking': 'Flight Booking',
        'notifications': 'Notifications',
        'kekeNapep': 'Keke NAPEP',
        'amana': 'Amana',
      };
      return FeatureControlRegistry(
        features: raw.entries
            .where((entry) => entry.value is bool)
            .map(
              (entry) => FeatureControl(
                key: entry.key.toString(),
                displayName:
                    labels[entry.key.toString()] ?? entry.key.toString(),
                category: 'Platform',
                description: '',
                enabled: entry.value as bool,
              ),
            )
            .toList(),
        metrics: const <String, int>{},
        sync: const <String, dynamic>{'realtime': false},
      );
    }
    throw const AdminFeatureControlsException(
      502,
      'The service returned an invalid feature registry response.',
    );
  }

  /// Named collection alias used by the Admin API contract.
  Future<FeatureControlRegistry> list() => loadRegistry();

  Future<FeatureControl> patchFeature(
    String key,
    Map<String, dynamic> changes,
    String reason, {
    bool protectedConfirmation = false,
    String? confirmationText,
  }) async {
    _validateReason(reason);
    final body = <String, dynamic>{
      'reason': reason.trim(),
      'feature': _jsonSafe(changes),
      if (protectedConfirmation) 'protectedConfirmation': true,
      if (confirmationText != null) 'confirmationText': confirmationText,
    };
    final response = await _request(
      'PATCH',
      path: '/settings/admin/feature-control/${Uri.encodeComponent(key)}',
      body: jsonEncode(body),
    );
    final decoded = _decode(response);
    final data = decoded['data'];
    if (data is! Map) {
      throw const AdminFeatureControlsException(
        502,
        'The service returned an invalid feature response.',
      );
    }
    return FeatureControl.fromJson(Map<String, dynamic>.from(data));
  }

  Future<FeatureControl> patch(
    String key,
    Map<String, dynamic> changes,
    String reason, {
    bool protectedConfirmation = false,
    String? confirmationText,
  }) =>
      patchFeature(
        key,
        changes,
        reason,
        protectedConfirmation: protectedConfirmation,
        confirmationText: confirmationText,
      );

  Future<FeatureControlRegistry> bulk(
    List<String> keys,
    String action,
    String reason, {
    bool protectedConfirmation = false,
    String? confirmationText,
  }) async {
    _validateReason(reason);
    final response = await _request(
      'POST',
      path: '/settings/admin/feature-control/bulk',
      body: jsonEncode(<String, dynamic>{
        'keys': keys,
        'action': action,
        'reason': reason.trim(),
        if (protectedConfirmation) 'protectedConfirmation': true,
        if (confirmationText != null) 'confirmationText': confirmationText,
      }),
    );
    final decoded = _decode(response);
    final data = decoded['data'];
    if (data is! Map || data['features'] is! List) {
      throw const AdminFeatureControlsException(
        502,
        'The service returned an invalid bulk feature response.',
      );
    }
    return FeatureControlRegistry(
      features: (data['features'] as List)
          .whereType<Map>()
          .map(
            (value) =>
                FeatureControl.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
      metrics: data['metrics'] is Map
          ? Map<String, int>.fromEntries(
              (data['metrics'] as Map)
                  .entries
                  .where((entry) => entry.value is num)
                  .map(
                    (entry) => MapEntry(
                      entry.key.toString(),
                      (entry.value as num).toInt(),
                    ),
                  ),
            )
          : const <String, int>{},
      sync: const <String, dynamic>{},
    );
  }

  Future<List<Map<String, dynamic>>> audit({String? featureKey}) async {
    final response = await _request(
      'GET',
      path: '/settings/admin/feature-control/audit',
      query: featureKey == null
          ? null
          : <String, String>{'featureKey': featureKey},
    );
    final decoded = _decode(response);
    final data = decoded['data'];
    final rows = data is Map ? (data['entries'] ?? data['audit']) : null;
    if (rows is! List) {
      throw const AdminFeatureControlsException(
        502,
        'The service returned an invalid audit response.',
      );
    }
    return rows
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
  }

  Future<void> save(Map<String, bool> toggles, String reason) async {
    final cleanReason = reason.trim();
    if (cleanReason.length < 10) {
      throw const AdminFeatureControlsException(
        0,
        'Provide a reason of at least 10 characters.',
      );
    }
    final response = await _request(
      'PUT',
      body: jsonEncode(<String, dynamic>{
        'reason': cleanReason,
        'fintechControl': <String, dynamic>{
          'featureToggles': toggles,
        },
      }),
    );
    _decode(response);
  }

  void _validateReason(String reason) {
    if (reason.trim().length < 10) {
      throw const AdminFeatureControlsException(
        0,
        'Provide a reason of at least 10 characters.',
      );
    }
  }

  dynamic _jsonSafe(dynamic value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafe(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_jsonSafe).toList();
    }
    return value;
  }

  Future<http.Response> _request(
    String method, {
    String? body,
    String? path,
    Map<String, String>? query,
  }) async {
    final prefs = await _preferencesLoader();
    final token = (prefs.getString('auth_token') ?? '').trim();
    if (token.isEmpty) {
      throw const AdminFeatureControlsException(
        401,
        'Your session has expired. Please sign in again.',
      );
    }
    final basePath = path ?? '/settings/admin/fintech-control';
    final uri = Uri.parse('$baseUrl$basePath').replace(queryParameters: query);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };
    final response = switch (method) {
      'PUT' => await _client.put(uri, headers: headers, body: body),
      'PATCH' => await _client.patch(uri, headers: headers, body: body),
      'POST' => await _client.post(uri, headers: headers, body: body),
      _ => await _client.get(uri, headers: headers),
    };
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Unable to load Feature Controls.';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['message'] != null) {
          message = decoded['message'].toString();
        }
      } catch (_) {}
      throw AdminFeatureControlsException(response.statusCode, message);
    }
    return response;
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    throw const AdminFeatureControlsException(
      502,
      'The service returned an invalid response.',
    );
  }
}

class FeatureControlRegistry {
  const FeatureControlRegistry({
    required this.features,
    required this.metrics,
    required this.sync,
  });

  final List<FeatureControl> features;
  final Map<String, int> metrics;
  final Map<String, dynamic> sync;
}

class FeatureControl {
  const FeatureControl({
    required this.key,
    required this.displayName,
    required this.category,
    required this.description,
    required this.enabled,
    this.effectiveEnabled,
    this.visible = true,
    this.maintenanceMode = false,
    this.maintenanceTitle = '',
    this.maintenanceMessage = '',
    this.scope = 'GLOBAL',
    this.scheduledEnabledAt,
    this.scheduledDisabledAt,
    this.expectedReturnAt,
    this.minimumAppVersion,
    this.updatedAt,
    this.updatedBy,
    this.isProtected = false,
  });

  final String key;
  final String displayName;
  final String category;
  final String description;
  final bool enabled;
  final bool? effectiveEnabled;
  final bool visible;
  final bool maintenanceMode;
  final String maintenanceTitle;
  final String maintenanceMessage;
  final String scope;
  final DateTime? scheduledEnabledAt;
  final DateTime? scheduledDisabledAt;
  final DateTime? expectedReturnAt;
  final String? minimumAppVersion;
  final DateTime? updatedAt;
  final String? updatedBy;
  final bool isProtected;

  bool get available => effectiveEnabled ?? enabled;

  static DateTime? _date(dynamic value) {
    if (value == null || value.toString().isEmpty) return null;
    return DateTime.tryParse(value.toString());
  }

  factory FeatureControl.fromJson(Map<String, dynamic> json) {
    return FeatureControl(
      key: (json['key'] ?? '').toString(),
      displayName:
          (json['displayName'] ?? json['name'] ?? json['key'] ?? '').toString(),
      category: (json['category'] ?? 'Platform').toString(),
      description: (json['description'] ?? '').toString(),
      enabled: json['enabled'] == true,
      effectiveEnabled: json['effectiveEnabled'] is bool
          ? json['effectiveEnabled'] as bool
          : null,
      visible: json['visible'] != false,
      maintenanceMode: json['maintenanceMode'] == true,
      maintenanceTitle: (json['maintenanceTitle'] ?? '').toString(),
      maintenanceMessage: (json['maintenanceMessage'] ?? '').toString(),
      scope: (json['scope'] ?? 'GLOBAL').toString(),
      scheduledEnabledAt: _date(json['scheduledEnabledAt']),
      scheduledDisabledAt: _date(json['scheduledDisabledAt']),
      expectedReturnAt: _date(json['expectedReturnAt']),
      minimumAppVersion: json['minimumAppVersion']?.toString(),
      updatedAt: _date(json['updatedAt']),
      updatedBy: json['updatedBy']?.toString(),
      isProtected: json['protected'] == true,
    );
  }
}

class AdminFeatureControlsException implements Exception {
  const AdminFeatureControlsException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}
