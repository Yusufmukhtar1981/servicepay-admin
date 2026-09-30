import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Authenticated API for the manually operated customer withdrawal queue.
///
/// Marking a request paid records a staff attestation after the staff member
/// has transferred the funds from the company bank account. This API does not
/// initiate a transfer or independently verify one with a bank.
class AdminCustomerWithdrawalsApi {
  AdminCustomerWithdrawalsApi({
    http.Client? client,
    String? baseUrl,
  })  : baseUrl = (baseUrl ??
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
  static const Duration _timeout = Duration(seconds: 30);

  Future<List<Map<String, dynamic>>> list({String status = ''}) async {
    final Map<String, dynamic> response = await _request(
      'GET',
      '/withdrawals/admin',
      query: status.trim().isEmpty || status.trim().toUpperCase() == 'ALL'
          ? null
          : <String, String>{'status': status.trim().toUpperCase()},
    );
    final dynamic withdrawals = response['withdrawals'];
    if (withdrawals is! List) {
      throw const FormatException(
        'The server returned an invalid customer withdrawal queue.',
      );
    }
    return withdrawals
        .whereType<Map>()
        .map((Map item) => Map<String, dynamic>.from(item))
        .toList();
  }

  /// Records a manual-payment attestation. It never sends or initiates money.
  Future<Map<String, dynamic>> markPaid(
    String id, {
    required String payoutReference,
    required String adminNote,
    required bool manualPaymentConfirmed,
    required num expectedAmount,
    required String expectedAccountNumber,
  }) {
    final String reference = payoutReference.trim();
    if (id.trim().isEmpty) {
      throw ArgumentError('A valid withdrawal request ID is required.');
    }
    if (reference.isEmpty || reference.length > 120) {
      throw ArgumentError(
          'A payout reference is required (maximum 120 characters).');
    }
    if (!manualPaymentConfirmed) {
      throw ArgumentError(
        'Confirm that the company-bank transfer was actually completed.',
      );
    }
    if (expectedAmount <= 0 || expectedAccountNumber.trim().isEmpty) {
      throw ArgumentError(
          'The request amount and beneficiary account are required.');
    }
    return _request(
      'POST',
      '/withdrawals/admin/${Uri.encodeComponent(id)}/approve',
      payload: <String, dynamic>{
        'payoutReference': reference,
        'adminNote': adminNote.trim(),
        'manualPaymentConfirmed': true,
        'expectedAmount': expectedAmount,
        'expectedAccountNumber': expectedAccountNumber,
      },
    );
  }

  /// Uses the established rejection/refund route for a withdrawal request.
  Future<Map<String, dynamic>> reject(
    String id, {
    required String reason,
  }) {
    final String note = reason.trim();
    if (id.trim().isEmpty) {
      throw ArgumentError('A valid withdrawal request ID is required.');
    }
    if (note.isEmpty) {
      throw ArgumentError('A rejection reason is required.');
    }
    return _request(
      'POST',
      '/withdrawals/admin/${Uri.encodeComponent(id)}/reject',
      payload: <String, dynamic>{'adminNote': note},
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? payload,
  }) async {
    final String token = await _token();
    final Uri uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (payload != null) 'Content-Type': 'application/json',
    };
    final http.Response response;
    if (method == 'POST') {
      response = await _client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_timeout);
    } else {
      response = await _client.get(uri, headers: headers).timeout(_timeout);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const FormatException('The server returned an invalid response.');
    }
    final Map<String, dynamic> body = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] != true) {
      throw Exception(
        body['message']?.toString() ??
            'Unable to complete the customer withdrawal action.',
      );
    }
    return body;
  }

  Future<String> _token() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    for (final String key in <String>[
      'auth_token',
      'token',
      'access_token',
      'accessToken',
      'jwt_token',
      'jwt',
    ]) {
      String value = preferences.getString(key)?.trim() ?? '';
      if (value.toLowerCase().startsWith('bearer ')) {
        value = value.substring(7).trim();
      }
      if (value.isNotEmpty) return value;
    }
    throw Exception('Your login session was not found. Please sign in again.');
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
