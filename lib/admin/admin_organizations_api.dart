import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

abstract class AdminOrganizationsApiClient {
  Future<Map<String, dynamic>> summary();
  Future<Map<String, dynamic>> list(
      {String? status, String? search, String? organizationType});
  Future<Map<String, dynamic>> details(String id);
  Future<Map<String, dynamic>> wallet(String id);
  Future<Map<String, dynamic>> members(String id);
  Future<Map<String, dynamic>> payments(String id);
  Future<Map<String, dynamic>> audit(String id);
  Future<Map<String, dynamic>> startReview(String id);
  Future<Map<String, dynamic>> approve(String id);
  Future<Map<String, dynamic>> reject(String id, {required String reason});
  Future<Map<String, dynamic>> requestInformation(String id,
      {required String reason, List<String> fields, List<String> documents});
  Future<Map<String, dynamic>> suspend(String id, {required String reason});
  Future<Map<String, dynamic>> document(String id, String documentId,
      {String action = 'view'});
  Future<void> updateStatus(String id, String status);
  Future<void> updateWalletFreeze(String id, bool frozen);
  Future<Map<String, dynamic>> withdrawalsSummary();
  Future<Map<String, dynamic>> withdrawals({
    String? status,
    String? organizationId,
    String? search,
    String? from,
    String? to,
  });
  Future<Map<String, dynamic>> withdrawalDetails(String id);
  Future<void> approveWithdrawal(String id, {String? reason});
  Future<void> rejectWithdrawal(String id, {required String reason});
  Future<Map<String, dynamic>> settlementAccounts({
    String? status,
    String? organizationId,
  });
  Future<void> approveSettlementAccount(String id, {String? reason});
  Future<void> rejectSettlementAccount(String id, {required String reason});
  Future<Map<String, dynamic>> treasuryConfig(String organizationId);
  Future<Map<String, dynamic>> updateTreasuryConfig(
    String organizationId,
    Map<String, dynamic> configuration,
  );
}

class AdminOrganizationsApi implements AdminOrganizationsApiClient {
  AdminOrganizationsApi({http.Client? client, String? baseUrl, this.authToken})
    : baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'SERVICEPAY_API_BASE_URL',
            defaultValue: 'https://api.servicepay.ng/api',
          ),
      _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final String? authToken;

  Future<Map<String, String>> _headers() async {
    final SharedPreferences? prefs = authToken == null
        ? await SharedPreferences.getInstance()
        : null;
    final String token = authToken ?? prefs?.getString('auth_token') ?? '';
    return <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token.isNotEmpty)
        'Authorization': token.startsWith('Bearer ') ? token : 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final Uri uri = Uri.parse(
      '$baseUrl/admin/organizations$path',
    ).replace(queryParameters: query?.isEmpty ?? true ? null : query);
    final Map<String, String> headers = await _headers();
    late http.Response response;
    if (method == 'PATCH') {
      response = await _client.patch(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
    } else if (method == 'POST') {
      response = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
    } else {
      response = await _client.get(uri, headers: headers);
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    final Map<String, dynamic> result = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AdminOrganizationsApiException(
        result['message']?.toString() ?? 'Organization request failed.',
        response.statusCode,
      );
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> summary() => _request('GET', '/summary');

  @override
  Future<Map<String, dynamic>> list(
          {String? status, String? search, String? organizationType}) =>
      _request('GET', '', query: <String, String>{
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (organizationType != null && organizationType.isNotEmpty)
          'organizationType': organizationType,
      });

  @override
  Future<Map<String, dynamic>> details(String id) => _request('GET', '/$id');

  @override
  Future<Map<String, dynamic>> wallet(String id) =>
      _request('GET', '/$id/wallet');

  @override
  Future<Map<String, dynamic>> members(String id) =>
      _request('GET', '/$id/members');

  @override
  Future<Map<String, dynamic>> payments(String id) =>
      _request('GET', '/$id/payments');

  @override
  Future<Map<String, dynamic>> audit(String id) =>
      _request('GET', '/$id/audit');

  @override
  Future<Map<String, dynamic>> startReview(String id) =>
      _request('POST', '/$id/start-review');

  @override
  Future<Map<String, dynamic>> approve(String id) =>
      _request('POST', '/$id/approve');

  @override
  Future<Map<String, dynamic>> reject(String id, {required String reason}) {
    if (reason.trim().isEmpty) {
      throw const AdminOrganizationsApiException(
          'A rejection reason is required.', 400);
    }
    return _request('POST', '/$id/reject',
        body: <String, dynamic>{'reason': reason.trim()});
  }

  @override
  Future<Map<String, dynamic>> requestInformation(String id,
      {required String reason,
      List<String> fields = const <String>[],
      List<String> documents = const <String>[]}) {
    if (reason.trim().isEmpty) {
      throw const AdminOrganizationsApiException(
          'A reason is required to request information.', 400);
    }
    return _request('POST', '/$id/request-information', body: <String, dynamic>{
      'reason': reason.trim(),
      'fields': fields,
      'documents': documents,
    });
  }

  @override
  Future<Map<String, dynamic>> suspend(String id, {required String reason}) {
    if (reason.trim().isEmpty) {
      throw const AdminOrganizationsApiException(
          'A suspension reason is required.', 400);
    }
    return _request('POST', '/$id/suspend',
        body: <String, dynamic>{'reason': reason.trim()});
  }

  @override
  Future<Map<String, dynamic>> document(String id, String documentId,
      {String action = 'view'}) {
    final safeAction =
        <String>{'preview', 'download'}.contains(action) ? '/$action' : '';
    return _request('GET', '/$id/documents/$documentId$safeAction');
  }

  @override
  Future<void> updateStatus(String id, String status) async {
    await _request(
      'PATCH',
      '/$id/status',
      body: <String, dynamic>{'status': status},
    );
  }

  @override
  Future<void> updateWalletFreeze(String id, bool frozen) async {
    await _request(
      'PATCH',
      '/$id/wallet',
      body: <String, dynamic>{
        'status': frozen ? 'FROZEN' : 'ACTIVE',
        'frozen': frozen,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> withdrawalsSummary() =>
      _request('GET', '/withdrawals/summary');

  @override
  Future<Map<String, dynamic>> withdrawals({
    String? status,
    String? organizationId,
    String? search,
    String? from,
    String? to,
  }) => _request(
    'GET',
    '/withdrawals',
    query: <String, String>{
      if (status != null && status.isNotEmpty) 'status': status,
      if (organizationId != null && organizationId.isNotEmpty)
        'organizationId': organizationId,
      if (search != null && search.isNotEmpty) 'search': search,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    },
  );

  @override
  Future<Map<String, dynamic>> withdrawalDetails(String id) =>
      _request('GET', '/withdrawals/$id');

  @override
  Future<void> approveWithdrawal(String id, {String? reason}) async {
    await _request(
      'POST',
      '/withdrawals/$id/approve',
      body: <String, dynamic>{
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  @override
  Future<void> rejectWithdrawal(String id, {required String reason}) async {
    if (reason.trim().isEmpty) {
      throw const AdminOrganizationsApiException(
        'A rejection reason is required.',
        400,
      );
    }
    await _request(
      'POST',
      '/withdrawals/$id/reject',
      body: <String, dynamic>{'reason': reason.trim()},
    );
  }

  @override
  Future<Map<String, dynamic>> settlementAccounts({
    String? status,
    String? organizationId,
  }) => _request(
    'GET',
    '/settlement-accounts',
    query: <String, String>{
      if (status != null && status.isNotEmpty) 'status': status,
      if (organizationId != null && organizationId.isNotEmpty)
        'organizationId': organizationId,
    },
  );

  @override
  Future<void> approveSettlementAccount(String id, {String? reason}) async {
    await _request(
      'POST',
      '/settlement-accounts/$id/approve',
      body: <String, dynamic>{
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  @override
  Future<void> rejectSettlementAccount(
    String id, {
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw const AdminOrganizationsApiException(
        'A rejection reason is required.',
        400,
      );
    }
    await _request(
      'POST',
      '/settlement-accounts/$id/reject',
      body: <String, dynamic>{'reason': reason.trim()},
    );
  }

  @override
  Future<Map<String, dynamic>> treasuryConfig(String organizationId) =>
      _request(
        'GET',
        '/treasury-config',
        query: <String, String>{'organizationId': organizationId},
      );

  @override
  Future<Map<String, dynamic>> updateTreasuryConfig(
    String organizationId,
    Map<String, dynamic> configuration,
  ) {
    return _request(
      'PATCH',
      '/treasury-config',
      body: <String, dynamic>{
        'organizationId': organizationId,
        ...configuration,
      },
    );
  }
}

class AdminOrganizationsApiException implements Exception {
  const AdminOrganizationsApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}
