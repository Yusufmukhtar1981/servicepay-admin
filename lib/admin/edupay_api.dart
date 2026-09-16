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
      _ => await client.get(uri, headers: headers),
    };
    final decoded = jsonDecode(response.body);
    final result = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        result['success'] != true) {
      throw Exception(
        result['message']?.toString() ??
            'EduPay request failed (${response.statusCode}).',
      );
    }
    return result;
  }
}
