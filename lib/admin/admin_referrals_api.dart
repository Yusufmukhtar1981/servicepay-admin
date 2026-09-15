import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Read-only client for the privacy-safe Head Office referral report.
class AdminReferralsApi {
  AdminReferralsApi({http.Client? client, String? baseUrl})
    : baseUrl =
          (baseUrl ??
                  const String.fromEnvironment(
                    'SERVICEPAY_API_BASE_URL',
                    defaultValue: 'https://api.servicepay.ng/api',
                  ))
              .replaceFirst(RegExp(r'/$'), ''),
      _client = client ?? http.Client(),
      _ownsClient = client == null;

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  Future<Map<String, dynamic>> summary() => _get('/summary');
  Future<Map<String, dynamic>> getSummary() => summary();

  Future<Map<String, dynamic>> search({
    String query = '',
    String search = '',
    String category = '',
    String rewardStatus = '',
    int page = 1,
    int limit = 50,
  }) {
    final value = query.trim().isNotEmpty ? query.trim() : search.trim();
    return _get('', <String, String>{
      if (value.isNotEmpty) 'q': value,
      if (category.trim().isNotEmpty) 'category': category.trim().toUpperCase(),
      if (rewardStatus.trim().isNotEmpty)
        'rewardStatus': rewardStatus.trim().toUpperCase(),
      'page': '$page',
      'limit': '${limit.clamp(1, 200)}',
    });
  }

  Future<Map<String, dynamic>> list({
    String search = '',
    String category = '',
    String rewardStatus = '',
    int page = 1,
    int limit = 50,
  }) => this.search(
    search: search,
    category: category,
    rewardStatus: rewardStatus,
    page: page,
    limit: limit,
  );

  Future<Map<String, dynamic>> progress(String customerId) =>
      _get('/${Uri.encodeComponent(customerId)}/progress');
  Future<Map<String, dynamic>> getProgress(String customerId) =>
      progress(customerId);

  Future<Map<String, dynamic>> audit(String customerId) =>
      _get('/${Uri.encodeComponent(customerId)}/audit');
  Future<Map<String, dynamic>> getAudit(String customerId) => audit(customerId);

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final prefs = await SharedPreferences.getInstance();
    final token =
        <String>[
              'auth_token',
              'token',
              'access_token',
              'accessToken',
              'jwt_token',
              'jwt',
            ]
            .map((key) => prefs.getString(key)?.trim() ?? '')
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final uri = Uri.parse(
      '$baseUrl/admin/referrals$path',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
    final response = await _client.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {}
    final result = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (result.containsKey('success') && result['success'] != true)) {
      throw AdminReferralsException(
        result['message']?.toString() ??
            'Unable to load referral monitoring data.',
        statusCode: response.statusCode,
      );
    }
    return result;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

typedef AdminReferralMonitoringApi = AdminReferralsApi;
typedef AdminReferralApi = AdminReferralsApi;

class AdminReferralsException implements Exception {
  AdminReferralsException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
