import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Authenticated Head Office client for the Business Partner control centre.
///
/// This client deliberately never reads or retains credentials returned by an
/// API response. Business partner records are operational records, not API
/// client accounts.
class AdminBusinessPartnersApi {
  AdminBusinessPartnersApi({
    http.Client? client,
    this.baseUrl =
        'https://api.servicepay.ng/api/business-partner/admin/partners',
    this.authToken,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final String baseUrl;
  final String? authToken;

  Future<Map<String, dynamic>> list({String search = '', String status = ''}) =>
      get(
        '',
        query: {
          if (search.trim().isNotEmpty)
            baseUrl.endsWith('/partners') ? 'q' : 'search': search.trim(),
          if (status.trim().isNotEmpty) 'status': status.trim().toUpperCase(),
        },
      );

  Future<Map<String, dynamic>> counts() => get('/count');
  Future<Map<String, dynamic>> detail(String id) =>
      get('/${Uri.encodeComponent(id)}');
  Future<Map<String, dynamic>> summary() => counts();
  Future<Map<String, dynamic>> details(String id) => detail(id);

  Future<Map<String, dynamic>> customers(
    String partnerId, {
    Map<String, String>? filters,
  }) =>
      get('/${Uri.encodeComponent(partnerId)}/customers', query: filters);

  Future<Map<String, dynamic>> officers(
    String partnerId, {
    Map<String, String>? filters,
  }) =>
      get('/${Uri.encodeComponent(partnerId)}/officers', query: filters);

  Future<Map<String, dynamic>> transactions(
    String partnerId, {
    Map<String, String>? filters,
  }) =>
      get('/${Uri.encodeComponent(partnerId)}/transactions', query: filters);

  Future<Map<String, dynamic>> transactionVolume(
    String partnerId, {
    Map<String, String>? filters,
  }) =>
      get(
        '/${Uri.encodeComponent(partnerId)}/transaction-volume',
        query: filters,
      );

  Future<Map<String, dynamic>> commissions(
    String partnerId, {
    Map<String, String>? filters,
  }) =>
      get('/${Uri.encodeComponent(partnerId)}/commissions', query: filters);

  Future<Map<String, dynamic>> targets(String partnerId) =>
      get('/${Uri.encodeComponent(partnerId)}/targets');

  Future<Map<String, dynamic>> bonuses(
    String partnerId, {
    Map<String, String>? filters,
  }) =>
      get('/${Uri.encodeComponent(partnerId)}/bonuses', query: filters);

  Future<Map<String, dynamic>> liabilities(String partnerId) =>
      get('/${Uri.encodeComponent(partnerId)}/liabilities');

  Future<Map<String, dynamic>> audit(
    String partnerId, {
    Map<String, String>? filters,
  }) =>
      get('/${Uri.encodeComponent(partnerId)}/audit', query: filters);

  String get _adminBaseUrl {
    const partnersSuffix = '/partners';
    if (baseUrl.endsWith(partnersSuffix)) {
      return baseUrl.substring(0, baseUrl.length - partnersSuffix.length);
    }
    if (baseUrl.endsWith('/business-partner/admin')) {
      return baseUrl;
    }
    return '$baseUrl/business-partner/admin';
  }

  Future<Map<String, dynamic>> commissionRules({String? service}) => _request(
        'GET',
        '/commission-rules',
        query: <String, String>{
          if (service != null && service.trim().isNotEmpty)
            'service': service.trim(),
        },
        absoluteBaseUrl: _adminBaseUrl,
      );

  Future<Map<String, dynamic>> createCommissionRule(
    Map<String, dynamic> rule,
  ) =>
      _request(
        'POST',
        '/commission-rules',
        payload: rule,
        absoluteBaseUrl: _adminBaseUrl,
      );

  Future<Map<String, dynamic>> updateCommissionRule(
    String ruleId,
    Map<String, dynamic> rule,
  ) =>
      _request(
        'PATCH',
        '/commission-rules/${Uri.encodeComponent(ruleId)}',
        payload: rule,
        absoluteBaseUrl: _adminBaseUrl,
      );

  Future<Map<String, dynamic>> updateCommissionRuleStatus(
    String ruleId,
    bool enabled,
  ) =>
      _request(
        'PATCH',
        '/commission-rules/${Uri.encodeComponent(ruleId)}/status',
        payload: <String, dynamic>{'status': enabled ? 'ACTIVE' : 'DISABLED'},
        absoluteBaseUrl: _adminBaseUrl,
      );

  Future<Map<String, dynamic>> updatePartnerStatus(
    String partnerId,
    String status,
  ) =>
      setStatus(partnerId, status);

  Future<Map<String, dynamic>> bonusRules({String? partnerId}) => _request(
        'GET',
        '/bonus-rules',
        query: <String, String>{
          if (partnerId != null && partnerId.trim().isNotEmpty)
            'partnerId': partnerId.trim(),
        },
        absoluteBaseUrl: _adminBaseUrl,
      );

  Future<Map<String, dynamic>> bonusHistory(String partnerId) =>
      get('/${Uri.encodeComponent(partnerId)}/bonuses');

  Future<Map<String, dynamic>> createBonusRule(Map<String, dynamic> rule) =>
      _request(
        'POST',
        '/bonus-rules',
        payload: rule,
        absoluteBaseUrl: _adminBaseUrl,
      );

  Future<Map<String, dynamic>> updateBonusRule(
    String ruleId,
    Map<String, dynamic> rule,
  ) =>
      _request(
        'PATCH',
        '/bonus-rules/${Uri.encodeComponent(ruleId)}',
        payload: rule,
        absoluteBaseUrl: _adminBaseUrl,
      );

  Future<Map<String, dynamic>> updateBonusRuleStatus(
    String ruleId,
    bool enabled,
  ) =>
      _request(
        'PATCH',
        '/bonus-rules/${Uri.encodeComponent(ruleId)}/status',
        payload: <String, dynamic>{'status': enabled ? 'ACTIVE' : 'SUSPENDED'},
        absoluteBaseUrl: _adminBaseUrl,
      );
  Future<Map<String, dynamic>> create(Map<String, dynamic> body) =>
      post('', body);
  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> body) =>
      patch('/$id', body);
  Future<Map<String, dynamic>> setStatus(
    String id,
    String status, {
    String note = '',
  }) =>
      patch('/$id/status', {
        'status': status.toUpperCase(),
        if (note.trim().isNotEmpty) 'note': note.trim(),
      });

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _request('GET', path, query: query);
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _request('POST', path, payload: body);
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) =>
      _request('PATCH', path, payload: body);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? payload,
    String? absoluteBaseUrl,
  }) async {
    final String requestBase = absoluteBaseUrl ??
        (baseUrl.endsWith('/partners')
            ? baseUrl
            : '$baseUrl/business-partner/admin/partners');
    final uri = Uri.parse('$requestBase$path').replace(queryParameters: query);
    final token = await _token();
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        if (payload != null) 'Content-Type': 'application/json',
      });
    if (payload != null) {
      request.body = jsonEncode(payload);
    }
    final response = await _client.send(request).then(http.Response.fromStream);
    dynamic decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    final body = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (body.containsKey('success') && body['success'] != true)) {
      throw AdminBusinessPartnersException(
        body['message']?.toString() ??
            body['error']?.toString() ??
            'Business partner request failed.',
      );
    }
    return body;
  }

  Future<String> _token() async {
    if (authToken != null) {
      var token = authToken!.trim();
      if (token.toLowerCase().startsWith('bearer ')) {
        token = token.substring(7).trim();
      }
      return token;
    }
    final prefs = await SharedPreferences.getInstance();
    for (final key in const [
      'auth_token',
      'token',
      'access_token',
      'accessToken',
      'jwt_token',
      'jwt',
    ]) {
      var token = prefs.getString(key)?.trim() ?? '';
      if (token.toLowerCase().startsWith('bearer ')) {
        token = token.substring(7).trim();
      }
      if (token.isNotEmpty) {
        return token;
      }
    }
    throw const AdminBusinessPartnersException(
      'Your login session was not found. Please sign in again.',
    );
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class AdminBusinessPartnersException implements Exception {
  const AdminBusinessPartnersException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Canonical Premium 2.0 names retained as source-compatible aliases while
/// the production repository keeps its established plural filenames.
typedef AdminBusinessPartnerApi = AdminBusinessPartnersApi;
typedef AdminBusinessPartnerApiException = AdminBusinessPartnersException;
