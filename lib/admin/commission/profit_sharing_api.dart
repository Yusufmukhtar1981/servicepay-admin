import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../admin_api_configuration.dart';

@immutable
class ProfitSharingApiException implements Exception {
  const ProfitSharingApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isConflict => statusCode == 409;
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => message;
}

class ProfitSharingApi {
  ProfitSharingApi({
    http.Client? client,
    String? baseUrl,
    Future<String?> Function()? tokenProvider,
    this.timeout = const Duration(seconds: 35),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrl = baseUrl ?? AdminApiConfiguration.baseUrl,
        _tokenProvider = tokenProvider;

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final Future<String?> Function()? _tokenProvider;
  final Duration timeout;

  static const String endpoint = '/admin/product-commissions/profit-sharing';

  Future<String> _token() async {
    String? token;
    if (_tokenProvider != null) {
      token = await _tokenProvider!();
    } else {
      final SharedPreferences preferences = await SharedPreferences.getInstance();
      for (final String key in const <String>[
        'auth_token',
        'admin_token',
        'token',
        'access_token',
        'accessToken',
        'jwt_token',
        'jwt',
      ]) {
        final String candidate = preferences.getString(key) ?? '';
        if (candidate.trim().isNotEmpty) {
          token = candidate;
          break;
        }
      }
    }
    final String clean =
        (token ?? '').replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '').trim();
    if (clean.isEmpty) {
      throw const ProfitSharingApiException(
        'Your admin session was not found. Please sign in again.',
        statusCode: 401,
      );
    }
    return clean;
  }

  Future<Map<String, dynamic>> getSettings() => _send('GET');

  Future<Map<String, dynamic>> getEngine() => _send('GET', suffix: '/engine');

  Future<Map<String, dynamic>> getSettlements({
    int page = 1,
    int limit = 25,
    String? from,
    String? to,
  }) {
    if (page < 1 || limit < 1 || limit > 100) {
      throw const ProfitSharingApiException('Choose a valid settlement history page.');
    }
    final DateTime? fromDate =
        from == null ? null : DateTime.tryParse(from);
    final DateTime? toDate = to == null ? null : DateTime.tryParse(to);
    if ((from != null && fromDate == null) ||
        (to != null && toDate == null) ||
        (fromDate != null &&
            toDate != null &&
            fromDate.isAfter(toDate))) {
      throw const ProfitSharingApiException(
        'Choose a valid settlement report period.',
      );
    }
    return _send(
      'GET',
      suffix: '/settlements',
      query: <String, String>{
        'page': '$page',
        'limit': '$limit',
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      },
    );
  }

  Future<Map<String, dynamic>> dryRun(String transactionId) {
    final String id = transactionId.trim();
    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(id)) {
      throw const ProfitSharingApiException(
        'Enter a valid 24-character transaction ID.',
      );
    }
    return _send(
      'POST',
      suffix: '/dry-run',
      body: <String, dynamic>{'transactionId': id},
    );
  }

  Future<Map<String, dynamic>> activate(Map<String, dynamic> payload) {
    final String mode = payload['mode']?.toString() ?? '';
    final String? serviceAction = payload['serviceAction']?.toString();
    final dynamic revision = payload['revision'];
    if (mode != 'LIVE' && mode != 'PAUSED') {
      throw const ProfitSharingApiException('Choose a valid distribution mode.');
    }
    if (serviceAction != null &&
        serviceAction != 'ENABLE' &&
        serviceAction != 'DISABLE') {
      throw const ProfitSharingApiException('Choose a valid service action.');
    }
    if ((serviceAction == 'ENABLE' && mode != 'LIVE') ||
        (serviceAction == 'DISABLE' && mode != 'PAUSED')) {
      throw const ProfitSharingApiException(
        'The selected service action does not match the requested mode.',
      );
    }
    if (revision is! num ||
        !revision.isFinite ||
        revision < 0 ||
        revision != revision.roundToDouble()) {
      throw const ProfitSharingApiException(
        'A current non-negative integer engine revision is required.',
      );
    }
    if (payload['confirmation'] != true ||
        (mode == 'LIVE' &&
            payload['confirmationText'] !=
                'ACTIVATE FUTURE PROFIT SHARING') ||
        payload['reason'] is! String ||
        (payload['reason'] as String).trim().length < 10 ||
        payload['currentPassword'] is! String ||
        (payload['currentPassword'] as String).isEmpty ||
        payload['services'] is! List ||
        (payload['services'] as List).length != 1) {
      throw const ProfitSharingApiException(
        'The activation confirmation is incomplete.',
      );
    }
    if (mode == 'LIVE' &&
        (serviceAction != 'ENABLE' ||
            payload['dryRunIds'] is! Map ||
            (payload['dryRunIds'] as Map).length != 1 ||
            (payload['dryRunIds'] as Map).keys.first !=
                (payload['services'] as List).single)) {
      throw const ProfitSharingApiException(
        'A fresh eligible dry-run receipt is required for activation.',
      );
    }
    return _send('POST', suffix: '/activation', body: payload);
  }

  Future<Map<String, dynamic>> saveRule(Map<String, dynamic> payload) async {
    const List<String> roles = <String>[
      'HEAD_OFFICE',
      'ZONAL_MANAGER',
      'STATE_MANAGER',
      'AGGREGATOR',
    ];
    final dynamic rawPercentages = payload['percentages'];
    if (rawPercentages is! Map ||
        rawPercentages.length != roles.length ||
        !roles.every(rawPercentages.containsKey) ||
        rawPercentages.values.any((dynamic value) =>
            value is! num ||
            !value.isFinite ||
            value < 0 ||
            value > 100 ||
            ((value * 100).roundToDouble() - value * 100).abs() > 1e-8) ||
        (rawPercentages.values.cast<num>().fold<num>(
                      0,
                      (num total, num value) => total + value,
                    ) -
                100)
            .abs() >
            0.000001) {
      throw const ProfitSharingApiException(
        'All four beneficiary percentages must total 100%, with each value from 0 to 100 and at most two decimal places.',
      );
    }
    final Map<String, dynamic> requestBody = Map<String, dynamic>.from(payload)
      ..remove('policyVersion')
      ..remove('poolPercentage');
    final Map<String, dynamic> root =
        await _send('POST', body: requestBody);
    final dynamic raw = root['data'];
    final Map<String, dynamic> data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final dynamic rawVersions = data['versions'];
    bool validFourRoleRates(dynamic rawRates) {
      if (rawRates is! Map ||
          rawRates.length != roles.length ||
          !roles.every(rawRates.containsKey)) {
        return false;
      }
      final Iterable<dynamic> values = rawRates.values;
      if (values.any((dynamic value) =>
          value is! num ||
          !value.isFinite ||
          value < 0 ||
          value > 100 ||
          ((value * 100).roundToDouble() - value * 100).abs() > 1e-8)) {
        return false;
      }
      return (values.cast<num>().fold<num>(
                    0,
                    (num total, num value) => total + value,
                  ) -
                  100)
              .abs() <=
          0.000001;
    }

    final bool validVersions = rawVersions is List &&
        rawVersions.isNotEmpty &&
        rawVersions.every((dynamic value) {
          if (value is! Map) return false;
          final Map<String, dynamic> version = Map<String, dynamic>.from(value);
          return version['id'] != null &&
              version['serviceType'] is String &&
              version['enabled'] is bool &&
              version['effectiveAt'] is String &&
              version['percentages'] is Map &&
              version['createdAt'] is String &&
              version['createdBy'] != null &&
              version['reason'] is String;
        });
    if (data['serviceType'] != payload['serviceType'] ||
        data['revision'] is! num ||
        !validVersions ||
        !(data['versions'] as List).any((dynamic value) =>
            value is Map &&
            value['policyVersion'] == 3 &&
            validFourRoleRates(value['percentages']) &&
            value.containsKey('previousPercentages') &&
            (value['previousPercentages'] == null ||
                validFourRoleRates(value['previousPercentages']))) ||
        data['replayed'] is! bool) {
      throw const ProfitSharingApiException(
        'The server response could not confirm whether this rule was saved.',
        statusCode: 200,
      );
    }
    return root;
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<Map<String, dynamic>> _send(
    String method, {
    String suffix = '',
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final String token = await _token();
    final Uri uri = Uri.parse(
      '${_baseUrl.replaceFirst(RegExp(r'/+$'), '')}$endpoint$suffix',
    ).replace(queryParameters: query);
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };
    try {
      final http.Response response = method == 'POST'
          ? await _client
              .post(uri, headers: headers, body: jsonEncode(body))
              .timeout(timeout)
          : await _client.get(uri, headers: headers).timeout(timeout);
      Map<String, dynamic> root = <String, dynamic>{};
      if (response.body.trim().isNotEmpty) {
        final dynamic decoded;
        try {
          decoded = jsonDecode(response.body);
        } on FormatException {
          throw ProfitSharingApiException(
            'The ServicePay server returned invalid data.',
            statusCode: response.statusCode,
          );
        }
        if (decoded is Map) root = Map<String, dynamic>.from(decoded);
      }
      if (response.statusCode < 200 || response.statusCode >= 300 ||
          root['success'] != true) {
        final String message = (root['message'] ?? root['error'] ?? '')
            .toString()
            .trim();
        throw ProfitSharingApiException(
          message.isEmpty
              ? response.statusCode == 409
                  ? 'This rule changed while you were editing. Refresh and review the latest version.'
                  : response.statusCode == 403
                      ? 'You do not have permission to manage profit-sharing rules.'
                      : 'The profit-sharing request could not be completed.'
              : message,
          statusCode: response.statusCode,
        );
      }
      if (root['data'] is! Map) {
        throw ProfitSharingApiException(
          'The ServicePay server returned an incomplete response.',
          statusCode: response.statusCode,
        );
      }
      return root;
    } on TimeoutException {
      rethrow;
    } on http.ClientException {
      rethrow;
    }
  }
}
