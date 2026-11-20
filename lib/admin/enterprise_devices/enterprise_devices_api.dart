import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../admin_api_configuration.dart';
import '../admin_permissions.dart';

const String enterpriseDevicesViewPermission = 'enterprise.devices.view';
const String enterpriseDevicesManagePermission = 'enterprise.devices.manage';

Set<String> _norm(Set<String> p) =>
    p.map((String e) => e.trim().toLowerCase()).toSet();

const String enterpriseDevicesEnrollPermission = 'enterprise.devices.enroll';

bool _isHeadOffice(String role, Set<String> permissions) =>
    AdminAccess(role: role, permissions: permissions).isHeadOffice;

/// Entry requires Head Office or the explicit `enterprise.devices.view`
/// grant. `manage`/`enroll` alone do not pass the backend view check, and
/// wildcards are not honoured for scoped staff.
bool canAccessEnterpriseDevicesNavigation({
  required String role,
  required Set<String> permissions,
}) =>
    _isHeadOffice(role, permissions) ||
    _norm(permissions).contains(enterpriseDevicesViewPermission);

/// Register / assign / status / settings.
bool canManageEnterpriseDevices({
  required String role,
  required Set<String> permissions,
}) =>
    _isHeadOffice(role, permissions) ||
    (canAccessEnterpriseDevicesNavigation(
          role: role,
          permissions: permissions,
        ) &&
        _norm(permissions).contains(enterpriseDevicesManagePermission));

/// Enrollment token issue and companion revoke. Separate from manage.
bool canEnrollEnterpriseDevices({
  required String role,
  required Set<String> permissions,
}) =>
    _isHeadOffice(role, permissions) ||
    (canAccessEnterpriseDevicesNavigation(
          role: role,
          permissions: permissions,
        ) &&
        _norm(permissions).contains(enterpriseDevicesEnrollPermission));

class EnterpriseDevicesException implements Exception {
  EnterpriseDevicesException(
    this.message, {
    this.code,
    this.statusCode,
    this.provisioningRequired = false,
  });
  final String message;
  final String? code;
  final int? statusCode;
  final bool provisioningRequired;
  @override
  String toString() => message;
}

const List<String> enterpriseManufacturers = <String>[
  'TECNO',
  'Infinix',
  'Redmi',
  'Samsung',
  'Other',
];

const List<String> enterpriseDeviceStatuses = <String>[
  'AVAILABLE',
  'ASSIGNED',
  'INACTIVE',
  'LOST_STOLEN',
  'RETIRED',
];

String newEnterpriseRequestId([Random? random]) {
  final Random r = random ?? Random.secure();
  final List<int> b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final String h = b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// Admin client for /admin/enterprise-devices. Auth handling mirrors
/// AdminStaffWorkspaceApi exactly (stored session bearer token, no bypass).
class EnterpriseDevicesApi {
  EnterpriseDevicesApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrl = baseUrl ?? defaultBaseUrl;

  static const String defaultBaseUrl =
      '${AdminApiConfiguration.baseUrl}/admin/enterprise-devices';
  static const String provisioningMessage =
      'Enterprise Devices service is not provisioned yet. Backend provisioning '
      'and owner approval are required before this module can be used.';

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<Map<String, dynamic>> overview() => _request('GET', 'overview');

  Future<Map<String, dynamic>> search({
    String q = '',
    String manufacturer = '',
    String model = '',
    String staff = '',
    String department = '',
    String status = '',
    int page = 1,
    int limit = 25,
  }) =>
      _request(
        'POST',
        'search',
        payload: <String, dynamic>{
          'q': q.trim(),
          'manufacturer': manufacturer,
          'model': model.trim(),
          'staff': staff.trim(),
          'department': department.trim(),
          'status': status,
          'page': page,
          'limit': limit,
        },
      );

  Future<Map<String, dynamic>> staff(String q) =>
      _request('GET', 'staff', query: <String, String>{'q': q.trim()});

  Future<Map<String, dynamic>> register(Map<String, dynamic> body) =>
      _request('POST', '', payload: body);

  Future<Map<String, dynamic>> device(String id) =>
      _request('GET', Uri.encodeComponent(id));

  Future<Map<String, dynamic>> history(String id, {int page = 1}) => _request(
        'GET',
        '${Uri.encodeComponent(id)}/history',
        query: <String, String>{'page': '$page'},
      );

  Future<Map<String, dynamic>> assign(
    String id, {
    required String staffId,
    required int expectedVersion,
    required String reason,
  }) =>
      _request(
        'POST',
        '${Uri.encodeComponent(id)}/assign',
        payload: <String, dynamic>{
          'staffId': staffId,
          'expectedVersion': expectedVersion,
          'reason': reason,
        },
      );

  Future<Map<String, dynamic>> setStatus(
    String id, {
    required String status,
    required int expectedVersion,
    required String reason,
  }) {
    if (status == 'ASSIGNED') {
      throw EnterpriseDevicesException(
        'ASSIGNED can only be set through the assign action.',
      );
    }
    return _request(
      'PATCH',
      '${Uri.encodeComponent(id)}/status',
      payload: <String, dynamic>{
        'status': status,
        'expectedVersion': expectedVersion,
        'reason': reason,
      },
    );
  }

  /// Returns the one-time enrollment token. Callers must never persist or
  /// log it; it is only sent in the response body, never in a URL.
  Future<Map<String, dynamic>> enrollment(
    String id, {
    required int expectedVersion,
  }) =>
      _request(
        'POST',
        '${Uri.encodeComponent(id)}/enrollment',
        payload: <String, dynamic>{'expectedVersion': expectedVersion},
      );

  Future<Map<String, dynamic>> revoke(
    String id, {
    required int expectedVersion,
    required String reason,
  }) =>
      _request(
        'POST',
        '${Uri.encodeComponent(id)}/revoke',
        payload: <String, dynamic>{
          'expectedVersion': expectedVersion,
          'reason': reason,
        },
      );

  Future<Map<String, dynamic>> reports() => _request('GET', 'reports');

  Future<Map<String, dynamic>> settings() => _request('GET', 'settings');

  Future<Map<String, dynamic>> updateSettings({
    required bool allowWallpaper,
    required bool allowLauncher,
    required List<String> approvedPackages,
    required int revision,
    required String reason,
  }) =>
      _request(
        'PUT',
        'settings',
        payload: <String, dynamic>{
          'allowWallpaper': allowWallpaper,
          'allowLauncher': allowLauncher,
          'approvedPackages': approvedPackages,
          'revision': revision,
          'reason': reason,
        },
      );

  /// Returns the `data` map of a success envelope.
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? payload,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String token =
        (prefs.getString('auth_token') ?? prefs.getString('token') ?? '')
            .trim()
            .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
    if (token.isEmpty) {
      throw EnterpriseDevicesException(
        'Your login session was not found. Please sign in again.',
        statusCode: 401,
      );
    }
    final Uri uri = Uri.parse(path.isEmpty ? _baseUrl : '$_baseUrl/$path')
        .replace(queryParameters: query);
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (payload != null) 'Content-Type': 'application/json',
    };
    const Duration t = Duration(seconds: 30);
    final String? body = payload == null ? null : jsonEncode(payload);
    final http.Response response = switch (method) {
      'POST' =>
        await _client.post(uri, headers: headers, body: body).timeout(t),
      'PATCH' =>
        await _client.patch(uri, headers: headers, body: body).timeout(t),
      'PUT' => await _client.put(uri, headers: headers, body: body).timeout(t),
      _ => await _client.get(uri, headers: headers).timeout(t),
    };
    if (response.statusCode == 503) {
      throw EnterpriseDevicesException(
        provisioningMessage,
        statusCode: 503,
        provisioningRequired: true,
      );
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    final Map<String, dynamic> result = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        result['success'] != true) {
      throw EnterpriseDevicesException(
        '${result['message'] ?? 'Enterprise Devices request failed (${response.statusCode}).'}',
        code: result['code']?.toString(),
        statusCode: response.statusCode,
      );
    }
    if (result['data'] is! Map) {
      throw EnterpriseDevicesException(
        'Enterprise Devices returned an invalid response.',
      );
    }
    return Map<String, dynamic>.from(result['data'] as Map);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
