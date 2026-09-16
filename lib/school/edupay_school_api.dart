import 'dart:convert';
import 'package:http/http.dart' as http;
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
    final response = method == 'POST'
        ? await client.post(Uri.parse('$baseUrl$path'),
            headers: headers, body: jsonEncode(body ?? {}))
        : await client.get(Uri.parse('$baseUrl$path'), headers: headers);
    final decoded = jsonDecode(response.body);
    final result = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        result['success'] != true) {
      throw Exception(result['message'] ?? 'Unable to load school data.');
    }
    return result;
  }
}
