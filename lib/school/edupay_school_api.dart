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

  Future<Map<String, dynamic>> academicDashboard() =>
      request('GET', '/edupay/school/academic/dashboard');
  Future<Map<String, dynamic>> academicOverview() =>
      request('GET', '/edupay/school/academic');
  Future<Map<String, dynamic>> createSubject(Map<String, dynamic> body) =>
      request('POST', '/edupay/school/academic/subjects', body);
  Future<Map<String, dynamic>> academicStudents() =>
      request('GET', '/edupay/school/academic/students');
  Future<Map<String, dynamic>> createAcademicStudent(
          Map<String, dynamic> body) =>
      request('POST', '/edupay/school/academic/students', body);
  Future<Map<String, dynamic>> updateAcademicStudent(
          String id, Map<String, dynamic> body) =>
      request('PATCH', '/edupay/school/academic/students/$id', body);
  Future<Map<String, dynamic>> validateStudentImport(
          List<Map<String, dynamic>> rows) =>
      request('POST', '/edupay/school/academic/students/import/validate',
          {'rows': rows});
  Future<Map<String, dynamic>> commitStudentImport(
          List<Map<String, dynamic>> rows) =>
      request('POST', '/edupay/school/academic/students/import/commit',
          {'rows': rows});
  Future<Map<String, dynamic>> academicTeachers() =>
      request('GET', '/edupay/school/academic/teachers');
  Future<Map<String, dynamic>> createTeacher(Map<String, dynamic> body) =>
      request('POST', '/edupay/school/academic/teachers', body);
  Future<Map<String, dynamic>> updateTeacher(
    String id,
    Map<String, dynamic> body,
  ) =>
      request('PATCH', '/edupay/school/academic/teachers/$id', body);
  Future<Map<String, dynamic>> updateTeacherAssignments(
    String id,
    Map<String, dynamic> body,
  ) =>
      request('PATCH', '/edupay/school/academic/teachers/$id', body);
  Future<Map<String, dynamic>> updateTeacherStatus(String id, String status) =>
      request('PATCH', '/edupay/school/academic/teachers/$id/status', {
        'status': status,
      });
  Future<Map<String, dynamic>> resetTeacherPassword(
    String id,
    String temporaryPassword,
  ) =>
      request(
        'POST',
        '/edupay/school/academic/teachers/$id/reset-password',
        {'temporaryPassword': temporaryPassword},
      );
  Future<Map<String, dynamic>> assignTeacher(Map<String, dynamic> body) =>
      request('POST', '/edupay/school/academic/teachers/assignments', body);
  Future<Map<String, dynamic>> attendanceRoster(String classId) => request(
      'GET',
      '/edupay/school/academic/attendance/roster?classId=${Uri.encodeQueryComponent(classId)}');
  Future<Map<String, dynamic>> submitAcademicAttendance(
          Map<String, dynamic> body) =>
      request('POST', '/edupay/school/academic/attendance', body);
  Future<Map<String, dynamic>> assessments() =>
      request('GET', '/edupay/school/academic/assessments');
  Future<Map<String, dynamic>> createAssessment(Map<String, dynamic> body) =>
      request('POST', '/edupay/school/academic/assessments', body);
  Future<Map<String, dynamic>> saveScores(
          String id, Map<String, dynamic> body) =>
      request('PUT', '/edupay/school/academic/assessments/$id/scores', body);
  Future<Map<String, dynamic>> reviewAssessment(String id, String action,
          {String? note}) =>
      request('POST', '/edupay/school/academic/assessments/$id/review',
          {'action': action, if (note != null) 'note': note});
  Future<Map<String, dynamic>> timetable() =>
      request('GET', '/edupay/school/academic/timetable');
  Future<Map<String, dynamic>> createTimetable(Map<String, dynamic> body) =>
      request('POST', '/edupay/school/academic/timetable', body);
  Future<Map<String, dynamic>> activities() =>
      request('GET', '/edupay/school/academic/activities');
  Future<Map<String, dynamic>> createActivity(Map<String, dynamic> body) =>
      request('POST', '/edupay/school/academic/activities', body);
}
