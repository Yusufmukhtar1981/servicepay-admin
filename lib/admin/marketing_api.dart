import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';

class MarketingApi {
  MarketingApi({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const String baseUrl =
      '${AdminApiConfiguration.baseUrl}/admin/marketing';
  final http.Client _client;
  final bool _ownsClient;

  Future<Map<String, dynamic>> schema() => _json('GET', 'schema');
  Future<Map<String, dynamic>> overview(Map<String, String> query) =>
      _json('GET', 'overview', query: query);
  Future<Map<String, dynamic>> records(
    String kind, {
    int page = 1,
    int limit = 20,
    String search = '',
    String status = '',
    Map<String, String> filters = const {},
  }) =>
      _json('GET', 'records/${Uri.encodeComponent(kind)}', query: {
        'page': '$page',
        'limit': '$limit',
        if (search.isNotEmpty) 'search': search,
        if (status.isNotEmpty) 'status': status,
        ...filters,
      });

  Future<Map<String, dynamic>> createRecord(
    String kind,
    Map<String, dynamic> payload, {
    required String idempotencyKey,
  }) =>
      _json('POST', 'records/${Uri.encodeComponent(kind)}',
          payload: payload, idempotencyKey: idempotencyKey);

  Future<Map<String, dynamic>> updateRecord(
    String kind,
    String id,
    Map<String, dynamic> payload,
  ) =>
      _json('PATCH',
          'records/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(id)}',
          payload: payload);

  Future<Map<String, dynamic>> transition(
    String kind,
    String id,
    Map<String, dynamic> payload,
  ) =>
      _json('POST',
          'records/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(id)}/transition',
          payload: payload);

  Future<Map<String, dynamic>> activity({int page = 1, int limit = 25}) =>
      _json('GET', 'records/activity',
          query: {'page': '$page', 'limit': '$limit'});
  Future<Map<String, dynamic>> team() => _json('GET', 'team');
  Future<Map<String, dynamic>> createStaff(Map<String, dynamic> payload) =>
      _json('POST', 'team', payload: payload);
  Future<Map<String, dynamic>> updateStaff(
          String id, Map<String, dynamic> payload) =>
      _json('PATCH', 'team/${Uri.encodeComponent(id)}', payload: payload);
  Future<Map<String, dynamic>> staffStatus(String id, String status) =>
      _json('POST', 'team/${Uri.encodeComponent(id)}/status',
          payload: {'status': status});

  Future<Map<String, dynamic>> performanceContext() =>
      _json('GET', 'performance/context');
  Future<Map<String, dynamic>> performanceMe() =>
      _json('GET', 'performance/me');
  Future<Map<String, dynamic>> performanceStaff(String id) =>
      _json('GET', 'performance/staff/${Uri.encodeComponent(id)}');
  Future<Map<String, dynamic>> performanceDepartment(
          {String period = 'MONTHLY',
          String? from,
          String? to,
          int page = 1,
          int limit = 20,
          String search = ''}) =>
      _json('GET', 'performance/department', query: {
        'period': period,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        'page': '$page',
        'limit': '$limit',
        if (search.isNotEmpty) 'search': search,
      });
  Future<Map<String, dynamic>> performanceArchive(
          {String? kind,
          String? period,
          String? status,
          String search = '',
          String? from,
          String? to,
          int page = 1,
          int limit = 20,
          bool archived = true}) =>
      _json('GET', 'performance/archive', query: {
        if (kind != null && kind.isNotEmpty) 'kind': kind,
        if (period != null && period.isNotEmpty) 'period': period,
        if (status != null && status.isNotEmpty) 'status': status,
        if (search.isNotEmpty) 'search': search,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        'page': '$page',
        'limit': '$limit',
        'archived': '$archived',
      });
  Future<Map<String, dynamic>> archivePerformanceRecord(
          String kind, String id, Map<String, dynamic> payload) =>
      _json('POST',
          'performance/archive/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(id)}',
          payload: payload);
  Future<Map<String, dynamic>> performanceHistory(String kind, String id) =>
      _json('GET',
          'performance/history/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(id)}');
  Future<Map<String, dynamic>> capturePerformanceSnapshot(
          Map<String, dynamic> payload) =>
      _json('POST', 'performance/snapshot', payload: payload);
  Future<Map<String, dynamic>> performanceNotifications() =>
      _json('GET', 'performance/notifications');
  Future<Map<String, dynamic>> markPerformanceNotificationRead(String id) =>
      _json('POST',
          'performance/notifications/${Uri.encodeComponent(id)}/read',
          payload: {});
  Future<Map<String, dynamic>> rankingPolicy() =>
      _json('GET', 'performance/ranking-policy');
  Future<Map<String, dynamic>> updateRankingPolicy(
          Map<String, dynamic> payload) =>
      _json('PATCH', 'performance/ranking-policy', payload: payload);
  Future<http.Response> exportPerformance(
          {required String format,
          String period = 'MONTHLY',
          String? from,
          String? to,
          String? officerId,
          bool department = false}) async {
    final response = await _client
        .get(
          Uri.parse('$baseUrl/performance/export').replace(queryParameters: {
            'format': format,
            'period': period,
            if (from != null) 'from': from,
            if (to != null) 'to': to,
            if (officerId != null) 'officerId': officerId,
            if (department) 'department': 'true',
          }),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Performance export failed (${response.statusCode}).');
    }
    return response;
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? payload,
    String? idempotencyKey,
  }) async {
    final uri = Uri.parse('$baseUrl/$path').replace(queryParameters: query);
    final headers = await _headers();
    if (payload != null) headers['Content-Type'] = 'application/json';
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    final encoded = payload == null ? null : jsonEncode(payload);
    final response = switch (method) {
      'POST' => await _client
          .post(uri, headers: headers, body: encoded)
          .timeout(const Duration(seconds: 30)),
      'PATCH' => await _client
          .patch(uri, headers: headers, body: encoded)
          .timeout(const Duration(seconds: 30)),
      _ => await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30)),
    };
    return _decode(response);
  }

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    var token = (prefs.getString('admin_token') ??
            prefs.getString('auth_token') ??
            prefs.getString('token') ??
            '')
        .trim();
    token = token.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
    if (token.isEmpty) {
      throw Exception(
          'Your Admin session was not found. Please sign in again.');
    }
    return {'Accept': 'application/json', 'Authorization': 'Bearer $token'};
  }

  Map<String, dynamic> _decode(http.Response response) {
    dynamic parsed;
    try {
      parsed = jsonDecode(response.body);
    } catch (_) {}
    final body =
        parsed is Map ? Map<String, dynamic>.from(parsed) : <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] != true) {
      throw Exception(
        '${response.statusCode}: ${(body['message'] ?? 'Marketing request failed.').toString()}',
      );
    }
    final data = body['data'];
    return data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{'value': data};
  }

  Future<Map<String, dynamic>> uploadAsset(
    String filename,
    String mime,
    Uint8List bytes, {
    required String idempotencyKey,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/assets'));
    request.headers.addAll(await _headers());
    request.headers['Idempotency-Key'] = idempotencyKey;
    request.files
        .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed =
        await _client.send(request).timeout(const Duration(seconds: 60));
    return _decode(await http.Response.fromStream(streamed));
  }

  Future<http.Response> export(String kind, String format,
      {Map<String, String> query = const {}}) async {
    final response = await _client
        .get(
          Uri.parse('$baseUrl/export/${Uri.encodeComponent(kind)}')
              .replace(queryParameters: {'format': format, ...query}),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Export request failed (${response.statusCode}).');
    }
    return response;
  }

  Future<http.Response> downloadAsset(String id) async {
    final response = await _client
        .get(
          Uri.parse('$baseUrl/assets/${Uri.encodeComponent(id)}'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Private asset download failed (${response.statusCode}).');
    }
    return response;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
