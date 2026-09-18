import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class EduPayApi {
  EduPayApi({
    http.Client? client,
    this.baseUrl = 'https://api.servicepay.ng/api',
  }) : client = client ?? http.Client();
  final http.Client client;
  final String baseUrl;

  Future<String> _token() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString('auth_token') ?? '').replaceFirst('Bearer ', '').trim();
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    final token = await _token();
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
    };
    final uri = Uri.parse('$baseUrl$path');
    final response = switch (method) {
      'POST' => await client.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        ),
      'PATCH' => await client.patch(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        ),
      'PUT' =>
        await client.put(uri, headers: headers, body: jsonEncode(body ?? {})),
      'DELETE' => await client.delete(uri, headers: headers),
      _ => await client.get(uri, headers: headers),
    };
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw Exception('EduPay service returned an invalid response.');
    }
    final result = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (result['success'] != null && result['success'] != true)) {
      throw Exception(
        result['message']?.toString() ??
            'EduPay request failed (${response.statusCode}).',
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> readiness() =>
      request('GET', '/admin/edupay/readiness');
  Future<Map<String, dynamic>> saveSettings(
    Map<String, dynamic> settings,
  ) =>
      request('PATCH', '/admin/edupay/settings', body: settings);
  Future<Map<String, dynamic>> processSettlement(String id) =>
      request('POST', '/admin/edupay/settlements/$id/process');
  Future<Map<String, dynamic>> requerySettlement(String id) =>
      request('POST', '/admin/edupay/settlements/$id/requery');
  Future<Map<String, dynamic>> saveSettlementAccount(
    String schoolId,
    Map<String, dynamic> body,
  ) =>
      request('PUT', '/admin/edupay/schools/$schoolId/settlement-account',
          body: body);
  Future<Map<String, dynamic>> verifySettlementAccount(String schoolId,
          {String? accountId, int? version}) =>
      request(
          'POST', '/admin/edupay/schools/$schoolId/settlement-account/verify',
          body: {'accountId': accountId, 'version': version});
  Future<Map<String, dynamic>> assignDuty(
    String userId,
    List<String> permissions,
  ) =>
      request('PUT', '/admin/edupay/duties/$userId',
          body: {'permissions': permissions});
  Future<Map<String, dynamic>> configureDuties(
    Map<String, String> assignments,
  ) =>
      request('PUT', '/admin/edupay/duties',
          body: {'assignments': assignments});
  Future<Map<String, dynamic>> revokeDuty(String userId) =>
      request('DELETE', '/admin/edupay/duties/$userId');
  Future<Map<String, dynamic>> schoolAction(String schoolId, String action,
          {String? note}) =>
      request('PATCH', '/admin/edupay/schools/$schoolId',
          body: {'action': action, if (note != null) 'note': note});
  Future<Map<String, dynamic>> schoolDetail(String schoolId) =>
      request('GET', '/admin/edupay/schools/$schoolId');
  Future<Map<String, dynamic>> schoolRequests() =>
      request('GET', '/admin/edupay/school-requests');
  Future<Map<String, dynamic>> schoolRequestDetail(String requestId) =>
      request('GET', '/admin/edupay/school-requests/$requestId');
  Future<Map<String, dynamic>> schoolRequestAction(
    String requestId,
    String action, {
    String? rejectionReason,
    bool? representativeAuthorityConfirmed,
  }) =>
      request(
        'PATCH',
        '/admin/edupay/school-requests/$requestId',
        body: {
          'action': action,
          if (rejectionReason != null) 'rejectionReason': rejectionReason,
          if (representativeAuthorityConfirmed != null)
            'representativeAuthorityConfirmed':
                representativeAuthorityConfirmed,
        },
      );
  Future<Map<String, dynamic>> privateSchoolDocuments(String schoolId) =>
      request('GET', '/admin/edupay/schools/$schoolId/private-assets');
  Future<http.Response> privateAssetBytes(String schoolId, String fileId) async {
    final token = await _token();
    final response = await client.get(
      Uri.parse('$baseUrl/admin/edupay/schools/$schoolId/private-assets/$fileId'),
      headers: {'Accept': '*/*', 'Authorization': 'Bearer $token'});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Unable to download private asset (${response.statusCode}).');
    }
    return response;
  }
  Future<Map<String, dynamic>> eligibleDutyUsers() =>
      request('GET', '/admin/edupay/duties/eligible-users');
  Future<Map<String, dynamic>> enableFeature(String feature, String reason) =>
      request('PATCH', '/feature-control/admin/$feature',
          body: {
            'enabled': true,
            'reason': reason,
            'confirmationText': feature,
          });
}
