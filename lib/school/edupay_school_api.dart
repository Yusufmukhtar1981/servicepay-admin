import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EduPaySchoolApi {
  EduPaySchoolApi({
    http.Client? client,
    this.baseUrl = 'https://api.servicepay.ng/api',
  }) : client = client ?? http.Client();
  final http.Client client;
  final String baseUrl;
  Future<String> _token() async =>
      (await SharedPreferences.getInstance()).getString('school_auth_token') ??
      '';
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer ${await _token()}',
      if (body != null) 'Content-Type': 'application/json',
    };
    final uri = Uri.parse('$baseUrl$path');
    final response = switch (method) {
      'POST' => await client.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        ),
      'PUT' => await client.put(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        ),
      'PATCH' => await client.patch(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        ),
      _ => await client.get(uri, headers: headers),
    };
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw Exception('The school service returned an invalid response.');
    }
    final result = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    final success = result['success'];
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (success != null && success != true)) {
      throw Exception(result['message'] ?? 'Unable to load school data.');
    }
    return result;
  }

  Future<Map<String, dynamic>> applySchool({
    required Map<String, String> fields,
    PlatformFile? logo,
    List<PlatformFile> supportingDocuments = const [],
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/edupay/schools/apply'),
    )..headers['Accept'] = 'application/json';
    final token = await _token();
    if (token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
    request.fields.addAll(fields);
    if (logo?.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'logo',
          logo!.bytes!,
          filename: logo.name,
          contentType: _mime(logo.extension),
        ),
      );
    }
    for (final file in supportingDocuments) {
      if (file.bytes != null)
        request.files.add(
          http.MultipartFile.fromBytes(
            'supportingDocuments',
            file.bytes!,
            filename: file.name,
            contentType: _mime(file.extension),
          ),
        );
    }
    final response = await client.send(request);
    final body = await response.stream.bytesToString();
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw Exception('The school service returned an invalid response.');
    }
    final result = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (result['success'] != null && result['success'] != true)) {
      throw Exception(
        result['message'] ?? 'Unable to submit school application.',
      );
    }
    return result;
  }

  MediaType _mime(String? extension) => switch (extension?.toLowerCase()) {
        'png' => MediaType('image', 'png'),
        'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
        'pdf' => MediaType('application', 'pdf'),
        _ => MediaType('application', 'octet-stream'),
      };

  Future<Map<String, dynamic>> createAcademicSession(
    Map<String, dynamic> body,
  ) =>
      request('POST', '/edupay/school/sessions', body);
  Future<Map<String, dynamic>> createTerm(Map<String, dynamic> body) =>
      request('POST', '/edupay/school/terms', body);
  Future<Map<String, dynamic>> createClass(Map<String, dynamic> body) =>
      request('POST', '/edupay/school/classes', body);
  Future<Map<String, dynamic>> sessions() =>
      request('GET', '/edupay/school/sessions');
  Future<Map<String, dynamic>> terms() =>
      request('GET', '/edupay/school/terms');
  Future<Map<String, dynamic>> classes() =>
      request('GET', '/edupay/school/classes');
  Future<Map<String, dynamic>> fees() => request('GET', '/edupay/school/fees');

  /// Student Activity Center endpoints are all resolved by the backend from
  /// the authenticated school session.  No schoolId supplied by the client is
  /// trusted, which keeps this API safe for multi-school staff accounts.
  Future<Map<String, dynamic>> activityCenter(String type) => request('GET',
      '/edupay/activity-center/school/records?type=${Uri.encodeQueryComponent(type)}');

  Future<Map<String, dynamic>> activityAction(
          String type, Map<String, dynamic> body) =>
      request('POST', '/edupay/activity-center/school/$type', body);

  Future<Map<String, dynamic>> updateActivity(
          String recordId, Map<String, dynamic> body) =>
      request(
          'PATCH', '/edupay/activity-center/school/records/$recordId', body);

  Future<Map<String, dynamic>> publishResult(String id) =>
      request('POST', '/edupay/activity-center/school/records/$id/publish');

  Future<Map<String, dynamic>> bulkAttendance(Map<String, dynamic> body) =>
      request('POST', '/edupay/activity-center/school/attendance/bulk', body);

  Future<Map<String, dynamic>> verifyGuardian(Map<String, dynamic> body) =>
      request('POST', '/edupay/activity-center/school/guardians/verify', body);

  Future<Map<String, dynamic>> createGuardianInvite(String childId) => request(
      'POST',
      '/edupay/activity-center/school/guardians/invites',
      {'childId': childId});
}
