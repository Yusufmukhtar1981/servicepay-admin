import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';
import 'admin_control_center_download_common.dart';

/// RFC 4122 v4 identifier used as the idempotency key for job writes.
String newVirtualAccountJobRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
String _str(dynamic v) => v?.toString().trim() ?? '';
Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class VirtualAccountPermissions {
  const VirtualAccountPermissions(
      {this.view = false, this.generate = false, this.bulk = false});
  final bool view, generate, bulk;
  factory VirtualAccountPermissions.fromJson(Map<String, dynamic> j) =>
      VirtualAccountPermissions(
        view: j['view'] == true,
        generate: j['generate'] == true,
        bulk: j['bulk'] == true,
      );
}

class VirtualAccountSummary {
  const VirtualAccountSummary({
    required this.totalCustomers,
    required this.withoutAccounts,
    required this.withAccounts,
    required this.permissions,
    required this.storageReady,
  });
  final int totalCustomers, withoutAccounts, withAccounts;
  final VirtualAccountPermissions permissions;
  final bool storageReady;
  factory VirtualAccountSummary.fromJson(Map<String, dynamic> j) =>
      VirtualAccountSummary(
        totalCustomers: _int(j['totalCustomers']),
        withoutAccounts: _int(j['withoutAccounts']),
        withAccounts: _int(j['withAccounts']),
        permissions: VirtualAccountPermissions.fromJson(_map(j['permissions'])),
        storageReady: j['storageReady'] == true,
      );
}

class VirtualAccountPagination {
  const VirtualAccountPagination(
      {this.page = 1, this.limit = 20, this.total = 0, this.pages = 0});
  final int page, limit, total, pages;
  bool get hasPrevious => page > 1;
  bool get hasNext => page < pages;
  factory VirtualAccountPagination.fromJson(Map<String, dynamic> j) =>
      VirtualAccountPagination(
        page: max(1, _int(j['page'])),
        limit: _int(j['limit']),
        total: _int(j['total']),
        pages: _int(j['pages'] ?? j['totalPages']),
      );
}

class VirtualAccountJob {
  const VirtualAccountJob({
    required this.id,
    required this.status,
    required this.total,
    required this.processed,
    required this.successful,
    required this.failed,
    required this.pending,
    required this.skipped,
    required this.createdAt,
    required this.updatedAt,
    this.pauseReason,
  });
  final String id, status;
  final int total, processed, successful, failed, pending, skipped;
  final DateTime? createdAt, updatedAt;
  final String? pauseReason;

  static const activeStatuses = {'QUEUED', 'RUNNING'};
  bool get isActive => activeStatuses.contains(status);
  bool get canRetryFailed => !isActive && failed > 0;
  double get progress => total <= 0 ? 0 : (processed / total).clamp(0, 1);

  factory VirtualAccountJob.fromJson(Map<String, dynamic> j) {
    final pause = _str(j['pauseReason']);
    return VirtualAccountJob(
      id: _str(j['id']),
      status: _str(j['status']).toUpperCase(),
      total: _int(j['total']),
      processed: _int(j['processed']),
      successful: _int(j['successful']),
      failed: _int(j['failed']),
      pending: _int(j['pending']),
      skipped: _int(j['skipped']),
      createdAt: DateTime.tryParse(_str(j['createdAt'])),
      updatedAt: DateTime.tryParse(_str(j['updatedAt'])),
      pauseReason: pause.isEmpty ? null : pause,
    );
  }
}

class VirtualAccountJobItem {
  const VirtualAccountJobItem({
    required this.customerId,
    required this.fullName,
    required this.phone,
    required this.status,
    required this.reason,
    required this.updatedAt,
  });
  final String customerId, fullName, phone, status, reason;
  final DateTime? updatedAt;
  factory VirtualAccountJobItem.fromJson(Map<String, dynamic> j) =>
      VirtualAccountJobItem(
        customerId: _str(j['customerId']),
        fullName: _str(j['fullName']),
        phone: _str(j['phone']),
        status: _str(j['status']).toUpperCase(),
        reason: _str(j['reason']),
        updatedAt: DateTime.tryParse(_str(j['updatedAt'])),
      );
}

class VirtualAccountJobPage {
  const VirtualAccountJobPage(this.items, this.pagination);
  final List<VirtualAccountJob> items;
  final VirtualAccountPagination pagination;
}

class VirtualAccountJobDetail {
  const VirtualAccountJobDetail(this.job, this.items, this.pagination);
  final VirtualAccountJob job;
  final List<VirtualAccountJobItem> items;
  final VirtualAccountPagination pagination;
}

class VirtualAccountReport {
  const VirtualAccountReport(this.bytes, this.filename);
  final List<int> bytes;
  final String filename;
}

/// Raised by the client. [ambiguous] means the write may have been accepted
/// (timeout, transport loss, 5xx); callers must refresh rather than replay.
class VirtualAccountManagementException implements Exception {
  const VirtualAccountManagementException(this.message,
      {this.statusCode, this.ambiguous = false});
  final String message;
  final int? statusCode;
  final bool ambiguous;
  @override
  String toString() => message;
}

typedef AdminTokenLoader = Future<String?> Function();

class AdminVirtualAccountManagementApi {
  AdminVirtualAccountManagementApi({
    http.Client? client,
    String? baseUrl,
    AdminTokenLoader? tokenLoader,
    this.timeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _tokenLoader = tokenLoader,
        baseUrl = '${(baseUrl ?? AdminApiConfiguration.baseUrl).replaceFirst(RegExp(r'/$'), '')}/admin/virtual-account-management';

  final http.Client _client;
  final bool _ownsClient;
  final AdminTokenLoader? _tokenLoader;
  final String baseUrl;
  final Duration timeout;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<String> _token() async {
    String? raw;
    final loader = _tokenLoader;
    if (loader != null) {
      raw = await loader();
    } else {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString('auth_token') ??
          prefs.getString('token') ??
          prefs.getString('admin_token');
    }
    final token = (raw ?? '')
        .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
        .trim();
    if (token.isEmpty) {
      throw const VirtualAccountManagementException(
          'Your login session was not found. Please sign in again.');
    }
    return token;
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<http.Response> _send(String method, String path,
      {Map<String, String>? query, Object? body, bool json = true}) async {
    final token = await _token();
    final headers = {
      'Accept': json ? 'application/json' : 'text/csv',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };
    final write = method == 'POST';
    try {
      final future = write
          ? _client.post(_uri(path, query),
              headers: headers, body: jsonEncode(body))
          : _client.get(_uri(path, query), headers: headers);
      return await future.timeout(timeout);
    } on TimeoutException {
      throw VirtualAccountManagementException(
        write
            ? 'No response before the timeout. The request may have been recorded; refresh jobs before doing anything else.'
            : 'The server took too long to respond. Try again.',
        ambiguous: write,
      );
    } on http.ClientException {
      throw VirtualAccountManagementException(
        write
            ? 'The connection dropped. The request may have been recorded; refresh jobs before doing anything else.'
            : 'Unable to reach ServicePay. Check the connection and try again.',
        ambiguous: write,
      );
    }
  }

  static String safeMessage(Map<String, dynamic> body, int status) {
    final message = _str(body['message']);
    final sensitive = RegExp(
        r'(secret|token|api.?key|password|credential|authorization|stack|https?://|<)',
        caseSensitive: false);
    if (message.isNotEmpty &&
        message.length <= 240 &&
        !sensitive.hasMatch(message)) {
      return message;
    }
    if (status == 401 || status == 403) {
      return 'Your access to virtual-account management could not be confirmed.';
    }
    if (status == 404) return 'The requested job was not found.';
    if (status == 409) {
      return 'The job state changed. Refresh before continuing.';
    }
    if (status == 503) {
      return 'Virtual-account service is temporarily unavailable.';
    }
    return 'Unable to complete the virtual-account request.';
  }

  Map<String, dynamic> _data(http.Response response, {bool write = false}) {
    Map<String, dynamic> body;
    try {
      body = _map(jsonDecode(response.body));
    } catch (_) {
      body = {};
    }
    final ok = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        body['success'] != false &&
        body['data'] is Map;
    if (!ok) {
      final status = response.statusCode;
      // A 2xx without a parsable body, or any 5xx (including 503, which can
      // follow a DB commit) on a write, gives no proof either way.
      final ambiguous = write &&
          ((status >= 200 && status < 300) || status >= 500);
      throw VirtualAccountManagementException(
        ambiguous
            ? 'The server response was unclear. The request may have been recorded; refresh jobs before doing anything else.'
            : safeMessage(body, status),
        statusCode: status,
        ambiguous: ambiguous,
      );
    }
    return _map(body['data']);
  }

  Future<VirtualAccountSummary> summary() async =>
      VirtualAccountSummary.fromJson(_data(await _send('GET', '/summary')));

  Future<VirtualAccountJobPage> jobs({int page = 1, int limit = 20}) async {
    final data = _data(await _send('GET', '/jobs',
        query: {'page': '$page', 'limit': '$limit'}));
    final raw = data['items'];
    if (raw is! List) {
      throw const VirtualAccountManagementException(
          'The job list returned an invalid response.');
    }
    return VirtualAccountJobPage(
      raw.whereType<Map>().map((e) => VirtualAccountJob.fromJson(_map(e))).toList(),
      VirtualAccountPagination.fromJson(_map(data['pagination'])),
    );
  }

  Future<VirtualAccountJob> createJob({
    required String requestId,
    required String reason,
    required String mode,
    List<String> customerIds = const [],
  }) async {
    final trimmed = reason.trim();
    if (trimmed.length < 5 || trimmed.length > 500) {
      throw const VirtualAccountManagementException(
          'Enter a reason between 5 and 500 characters.');
    }
    if (mode != 'ALL' && mode != 'SELECTED') {
      throw const VirtualAccountManagementException('Unsupported mode.');
    }
    if (mode == 'SELECTED' && customerIds.isEmpty) {
      throw const VirtualAccountManagementException(
          'Select at least one customer.');
    }
    final data = _data(
      await _send('POST', '/jobs', body: {
        'requestId': requestId,
        'reason': trimmed,
        'confirmed': true,
        'mode': mode,
        'customerIds': mode == 'ALL' ? <String>[] : customerIds,
      }),
      write: true,
    );
    return VirtualAccountJob.fromJson(_map(data['job']));
  }

  Future<VirtualAccountJobDetail> job(String id,
      {int page = 1, int limit = 20}) async {
    final data = _data(await _send('GET', '/jobs/${Uri.encodeComponent(id)}',
        query: {'page': '$page', 'limit': '$limit'}));
    final raw = data['items'];
    return VirtualAccountJobDetail(
      VirtualAccountJob.fromJson(_map(data['job'])),
      raw is List
          ? raw
              .whereType<Map>()
              .map((e) => VirtualAccountJobItem.fromJson(_map(e)))
              .toList()
          : const [],
      VirtualAccountPagination.fromJson(_map(data['pagination'])),
    );
  }

  Future<VirtualAccountJob> retryJob({
    required String jobId,
    required String requestId,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.length < 5 || trimmed.length > 500) {
      throw const VirtualAccountManagementException(
          'Enter a reason between 5 and 500 characters.');
    }
    final data = _data(
      await _send('POST', '/jobs/${Uri.encodeComponent(jobId)}/retry', body: {
        'requestId': requestId,
        'reason': trimmed,
        'confirmed': true,
      }),
      write: true,
    );
    return VirtualAccountJob.fromJson(_map(data['job']));
  }

  /// Fetches the CSV report as raw bytes. HTML or JSON bodies are rejected so
  /// an error page is never saved or displayed as a report.
  Future<VirtualAccountReport> report(String jobId) async {
    final response = await _send(
        'GET', '/jobs/${Uri.encodeComponent(jobId)}/report',
        json: false);
    final type = (response.headers['content-type'] ?? '').toLowerCase();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      Map<String, dynamic> body = {};
      try {
        body = _map(jsonDecode(response.body));
      } catch (_) {}
      throw VirtualAccountManagementException(
          safeMessage(body, response.statusCode),
          statusCode: response.statusCode);
    }
    final bytes = response.bodyBytes;
    final head = utf8
        .decode(bytes.take(64).toList(), allowMalformed: true)
        .trimLeft()
        .toLowerCase();
    if (type.contains('html') ||
        type.contains('json') ||
        head.startsWith('<') ||
        head.startsWith('{')) {
      throw const VirtualAccountManagementException(
          'The report service did not return a CSV file.');
    }
    return VirtualAccountReport(
      bytes,
      reportFilename(response.headers['content-disposition'], jobId),
    );
  }

  static String reportFilename(String? disposition, String jobId) {
    final match = RegExp(r'''filename\*?=(?:UTF-8'')?"?([^";]+)"?''',
            caseSensitive: false)
        .firstMatch(disposition ?? '');
    var name = match == null ? '' : Uri.decodeComponent(match.group(1)!);
    name = name.split(RegExp(r'[\\/]')).last;
    name = controlCenterSafeDownloadFilename(name);
    if (name == 'export.csv' || name.replaceAll(RegExp(r'[._]'), '').isEmpty) {
      name = controlCenterSafeDownloadFilename(
          'virtual-account-job-$jobId.csv');
    }
    if (!name.toLowerCase().endsWith('.csv')) name = '$name.csv';
    return name;
  }
}
