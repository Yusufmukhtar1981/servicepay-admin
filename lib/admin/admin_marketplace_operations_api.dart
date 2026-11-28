import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';

class MarketplaceApiException implements Exception {
  MarketplaceApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class MarketplacePage {
  const MarketplacePage(this.items, this.page, this.pages, this.total);
  final List<Map<String, dynamic>> items;
  final int page;
  final int pages;
  final int total;
}

/// Head Office marketplace operations client. Uses the shared
/// AdminApiConfiguration resolver (preview builds override via
/// SERVICEPAY_API_BASE_URL) and the same stored-token convention as the
/// existing moderation screen.
class AdminMarketplaceOperationsApi {
  AdminMarketplaceOperationsApi({
    http.Client? client,
    String? baseUrl,
    Future<String?> Function()? tokenReader,
  })  : _client = client ?? http.Client(),
        _base = '${baseUrl ?? AdminApiConfiguration.baseUrl}/admin/marketplace',
        _tokenReader = tokenReader ?? _defaultToken;

  final http.Client _client;
  final String _base;
  final Future<String?> Function() _tokenReader;

  static const policyConfirmation = 'CONFIRM_MARKETPLACE_POLICY';

  static Future<String?> _defaultToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ??
        prefs.getString('token') ??
        prefs.getString('admin_token');
  }

  Future<Map<String, String>> _headers() async {
    final token = await _tokenReader();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path, [Map<String, String?> query = const {}]) {
    final q = <String, String>{
      for (final e in query.entries)
        if (e.value != null && e.value!.trim().isNotEmpty) e.key: e.value!.trim(),
    };
    return Uri.parse('$_base$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Map<String, dynamic> _decode(http.Response res) {
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {}
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    if (!ok || body is! Map || body['success'] == false) {
      final msg = body is Map
          ? (body['message'] ?? body['error'] ?? body['detail'])
          : null;
      throw MarketplaceApiException(
        msg?.toString() ?? 'Request failed (HTTP ${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }
    return Map<String, dynamic>.from(body);
  }

  static List<Map<String, dynamic>> listOf(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  static Map<String, dynamic> mapOf(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static MarketplacePage pageOf(Map<String, dynamic> body, String key) {
    final p = mapOf(body['pagination']);
    int n(String k, int d) => int.tryParse('${p[k] ?? d}') ?? d;
    final items = listOf(body[key]);
    return MarketplacePage(items, n('page', 1), n('pages', 1), n('total', items.length));
  }

  Future<MarketplacePage> merchants({
    String? q, String? status, String? state, String? lga,
    String? from, String? to, int page = 1, int limit = 20,
  }) async {
    final res = await _client.get(
      _uri('/merchants', {
        'q': q, 'status': status, 'state': state, 'lga': lga,
        'from': from, 'to': to, 'page': '$page', 'limit': '$limit',
      }),
      headers: await _headers(),
    );
    return pageOf(_decode(res), 'merchants');
  }

  Future<Map<String, dynamic>> merchant(String id) async =>
      _decode(await _client.get(_uri('/merchants/$id'), headers: await _headers()));

  Future<Map<String, dynamic>> setMerchantStatus(
      String id, {required String status, required String expectedStatus, required String reason}) async {
    final res = await _client.patch(_uri('/merchants/$id/status'),
        headers: await _headers(),
        body: jsonEncode({'status': status, 'expectedStatus': expectedStatus, 'reason': reason}));
    return mapOf(_decode(res)['merchant']);
  }

  /// Fetches protected KYC document bytes with the Authorization header.
  /// Only server-supplied /admin/kyc/... paths are accepted; no tokens or
  /// asset URLs are ever placed in the URL.
  Future<({List<int> bytes, String contentType})> kycDocument(String path) async {
    if (!RegExp(r'^/admin/kyc/[A-Za-z0-9_-]+/document/[A-Za-z0-9_-]+$').hasMatch(path)) {
      throw MarketplaceApiException('Document path is not a protected KYC path.');
    }
    final root = _base.substring(0, _base.length - '/admin/marketplace'.length);
    final headers = await _headers()..remove('Content-Type');
    headers['Accept'] = 'image/*,application/pdf,application/json';
    final res = await _client.get(Uri.parse('$root$path'), headers: headers);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String? msg;
      try {
        final b = jsonDecode(res.body);
        if (b is Map) msg = '${b['message'] ?? ''}';
      } catch (_) {}
      throw MarketplaceApiException(
          msg == null || msg.isEmpty ? 'Document unavailable (HTTP ${res.statusCode}).' : msg,
          statusCode: res.statusCode);
    }
    return (bytes: res.bodyBytes.toList(), contentType: res.headers['content-type'] ?? '');
  }

  Future<MarketplacePage> orders({
    String? q, String? status, String? paymentStatus, String? from,
    String? to, String? merchantId, String? fundsStatus, int page = 1, int limit = 20,
  }) async {
    final res = await _client.get(
      _uri('/orders', {
        'q': q, 'status': status, 'paymentStatus': paymentStatus,
        'from': from, 'to': to, 'merchantId': merchantId,
        'fundsStatus': fundsStatus,
        'page': '$page', 'limit': '$limit',
      }),
      headers: await _headers(),
    );
    return pageOf(_decode(res), 'orders');
  }

  Future<Map<String, dynamic>> order(String id) async => mapOf(
      _decode(await _client.get(_uri('/orders/$id'), headers: await _headers()))['order']);

  Future<Map<String, dynamic>> setOrderStatus(
      String id, {required String status, required String expectedStatus, required String reason}) async {
    if (!fulfillmentStatuses.contains(status)) {
      throw MarketplaceApiException('$status cannot be set by Head Office.');
    }
    final res = await _client.patch(_uri('/orders/$id/status'),
        headers: await _headers(),
        body: jsonEncode({'status': status, 'expectedStatus': expectedStatus, 'reason': reason}));
    return mapOf(_decode(res)['order']);
  }

  Future<Map<String, dynamic>> analytics({String? from, String? to}) async => mapOf(
      _decode(await _client.get(_uri('/analytics', {'from': from, 'to': to}),
          headers: await _headers()))['analytics']);

  Future<MarketplaceSettingsEnvelope> settings() async =>
      MarketplaceSettingsEnvelope.fromBody(
          _decode(await _client.get(_uri('/settings'), headers: await _headers())));

  Future<MarketplaceSettingsEnvelope> saveSettings(
      MarketplaceSettings next, {required int expectedVersion, required String reason}) async {
    final res = await _client.put(_uri('/settings'),
        headers: await _headers(),
        body: jsonEncode({
          'expectedVersion': expectedVersion,
          'reason': reason,
          ...next.toJson(),
          'confirmation': policyConfirmation,
        }));
    return MarketplaceSettingsEnvelope.fromBody(_decode(res));
  }

  static const fulfillmentStatuses = <String>[
    'ACCEPTED', 'PROCESSING', 'READY', 'SHIPPED', 'OUT_FOR_DELIVERY',
  ];
  static const merchantStatuses = <String>['ACTIVE', 'SUSPENDED', 'REJECTED'];
}

/// Percent text to basis points. Returns null for blank/invalid/out of range.
int? percentToBps(String text) {
  final t = text.trim().replaceAll('%', '');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v < 0 || v > 100) return null;
  return (v * 100).round();
}

String bpsToPercent(int? bps) {
  if (bps == null) return '';
  final p = bps / 100;
  return p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);
}

class MarketplaceSettings {
  const MarketplaceSettings({
    required this.enabled,
    required this.defaultRateBps,
    required this.merchantOverrides,
    required this.categoryOverrides,
    required this.deliveryEnabled,
    required this.deliveryFee,
    this.deliveryFeeRecipient,
    required this.version,
  });

  final bool enabled;
  final int? defaultRateBps;
  final List<({String merchantId, int rateBps})> merchantOverrides;
  final List<({String category, int rateBps})> categoryOverrides;
  final bool deliveryEnabled;
  final double? deliveryFee;

  /// Null means unselected. Only 'MERCHANT' is supported by the server.
  final String? deliveryFeeRecipient;

  static const supportedDeliveryFeeRecipients = <String>['MERCHANT'];

  /// A positive paid delivery fee requires an explicit supported recipient.
  static String? validateDeliveryRecipient({
    required bool deliveryEnabled,
    required double? deliveryFee,
    required String? recipient,
  }) {
    if (recipient != null && !supportedDeliveryFeeRecipients.contains(recipient)) {
      return 'Unsupported delivery fee recipient.';
    }
    if (deliveryEnabled && (deliveryFee ?? 0) > 0 && recipient == null) {
      return 'Choose who receives the delivery fee before enabling paid delivery.';
    }
    return null;
  }
  final int version;

  static int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

  factory MarketplaceSettings.fromJson(Map<String, dynamic> j) {
    final fee = j['deliveryFee'];
    return MarketplaceSettings(
      enabled: j['enabled'] == true,
      defaultRateBps: _int(j['defaultRateBps']),
      merchantOverrides: AdminMarketplaceOperationsApi.listOf(j['merchantOverrides'])
          .where((e) => _int(e['rateBps']) != null)
          .map((e) => (merchantId: '${e['merchantId'] ?? ''}', rateBps: _int(e['rateBps'])!))
          .toList(),
      categoryOverrides: AdminMarketplaceOperationsApi.listOf(j['categoryOverrides'])
          .where((e) => _int(e['rateBps']) != null)
          .map((e) => (category: '${e['category'] ?? ''}', rateBps: _int(e['rateBps'])!))
          .toList(),
      deliveryEnabled: j['deliveryEnabled'] == true,
      deliveryFee: fee is num ? fee.toDouble() : double.tryParse('${fee ?? ''}'),
      deliveryFeeRecipient: j['deliveryFeeRecipient'] is String &&
              (j['deliveryFeeRecipient'] as String).trim().isNotEmpty
          ? (j['deliveryFeeRecipient'] as String).trim().toUpperCase()
          : null,
      version: _int(j['version']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'defaultRateBps': defaultRateBps,
        'merchantOverrides': [
          for (final o in merchantOverrides) {'merchantId': o.merchantId, 'rateBps': o.rateBps}
        ],
        'categoryOverrides': [
          for (final o in categoryOverrides) {'category': o.category, 'rateBps': o.rateBps}
        ],
        'deliveryEnabled': deliveryEnabled,
        'deliveryFee': deliveryFee,
        'deliveryFeeRecipient': deliveryFeeRecipient,
      };
}

class MarketplaceSettingsEnvelope {
  const MarketplaceSettingsEnvelope(this.settings, this.canManage);
  final MarketplaceSettings settings;
  final bool canManage;

  factory MarketplaceSettingsEnvelope.fromBody(Map<String, dynamic> body) =>
      MarketplaceSettingsEnvelope(
        MarketplaceSettings.fromJson(AdminMarketplaceOperationsApi.mapOf(body['settings'])),
        body['canManage'] == true,
      );
}
