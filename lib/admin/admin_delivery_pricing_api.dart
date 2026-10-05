import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';

class AdminDeliveryPricingApiException implements Exception {
  const AdminDeliveryPricingApiException(
    this.message, {
    this.statusCode,
  });

  final String message;
  final int? statusCode;

  bool get isConflict => statusCode == 409 || statusCode == 412;

  @override
  String toString() => message;
}

abstract interface class AdminDeliveryPricingApiClient {
  Future<Map<String, dynamic>> getPricing();

  Future<Map<String, dynamic>> updateIntraStatePrice({
    required num price,
    required int expectedVersion,
  });

  Future<Map<String, dynamic>> createRoute(Map<String, dynamic> body);

  Future<Map<String, dynamic>> updateRoutePrice({
    required String routeId,
    required num baseFare,
    required String expectedUpdatedAt,
  });

  Future<Map<String, dynamic>> setRouteActive({
    required String routeId,
    required bool active,
  });

  Future<Map<String, dynamic>> deleteRoute({
    required String routeId,
    required String expectedUpdatedAt,
  });
}

@immutable
class AdminDeliveryPricingApi implements AdminDeliveryPricingApiClient {
  AdminDeliveryPricingApi({
    http.Client? client,
    String? baseUrl,
    this.tokenLoader,
    this.requestTimeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? AdminApiConfiguration.baseUrl;

  static const String _path = '/admin/logistics/interstate';

  final http.Client _client;
  final String baseUrl;
  final Future<String> Function()? tokenLoader;
  final Duration requestTimeout;

  static Map<String, dynamic> mapFrom(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<String> _loadToken() async {
    if (tokenLoader != null) {
      return (await tokenLoader!())
          .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
          .trim();
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for (final String key in const <String>[
      'auth_token',
      'token',
      'access_token',
      'accessToken',
      'jwt_token',
      'jwt',
    ]) {
      final String token = (prefs.getString(key) ?? '')
          .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
          .trim();
      if (token.isNotEmpty) return token;
    }
    return '';
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final String token = await _loadToken();
    if (token.isEmpty) {
      throw const AdminDeliveryPricingApiException(
        'Your admin session was not found. Please sign in again.',
        statusCode: 401,
      );
    }
    final String normalizedBase = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final Uri uri = Uri.parse('$normalizedBase$_path$path');
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    try {
      final http.Response response;
      switch (method) {
        case 'POST':
          response = await _client
              .post(uri, headers: headers, body: jsonEncode(body))
              .timeout(requestTimeout);
          break;
        case 'PATCH':
          response = await _client
              .patch(uri, headers: headers, body: jsonEncode(body))
              .timeout(requestTimeout);
          break;
        case 'DELETE':
          response = await _client
              .delete(uri, headers: headers, body: jsonEncode(body))
              .timeout(requestTimeout);
          break;
        default:
          response = await _client.get(uri, headers: headers).timeout(
                requestTimeout,
              );
          break;
      }
      Map<String, dynamic> root = <String, dynamic>{};
      if (response.body.trim().isNotEmpty) {
        try {
          root = mapFrom(jsonDecode(response.body));
        } on FormatException {
          throw AdminDeliveryPricingApiException(
            'The ServicePay server returned an invalid response.',
            statusCode: response.statusCode,
          );
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AdminDeliveryPricingApiException(
          root['message']?.toString().trim().isNotEmpty == true
              ? root['message'].toString()
              : response.statusCode == 409 || response.statusCode == 412
                  ? 'Pricing changed since this page was loaded. Refresh and review the latest values.'
                  : 'The delivery pricing request failed.',
          statusCode: response.statusCode,
        );
      }
      if (root['success'] == false) {
        throw AdminDeliveryPricingApiException(
          root['message']?.toString().trim().isNotEmpty == true
              ? root['message'].toString()
              : 'The delivery pricing request was not accepted.',
        );
      }
      return root;
    } on TimeoutException {
      throw const AdminDeliveryPricingApiException(
        'The ServicePay server took too long to respond. Please retry.',
      );
    } on http.ClientException {
      throw const AdminDeliveryPricingApiException(
        'Unable to reach the ServicePay server. Check your connection and retry.',
      );
    }
  }

  Map<String, dynamic> _payload(Map<String, dynamic> root) =>
      mapFrom(root['data']).isEmpty ? root : mapFrom(root['data']);

  @override
  Future<Map<String, dynamic>> getPricing() async =>
      _payload(await _request('GET', '/pricing'));

  @override
  Future<Map<String, dynamic>> updateIntraStatePrice({
    required num price,
    required int expectedVersion,
  }) async =>
      _request('PATCH', '/pricing/intra-state', body: <String, dynamic>{
        'price': price,
        'expectedVersion': expectedVersion,
        'confirmed': true,
      });

  @override
  Future<Map<String, dynamic>> createRoute(Map<String, dynamic> body) =>
      _request('POST', '/routes', body: body);

  @override
  Future<Map<String, dynamic>> updateRoutePrice({
    required String routeId,
    required num baseFare,
    required String expectedUpdatedAt,
  }) =>
      _request(
        'PATCH',
        '/routes/${Uri.encodeComponent(routeId)}/price',
        body: <String, dynamic>{
          'baseFare': baseFare,
          'pricingMode': 'FIXED',
          'expectedUpdatedAt': expectedUpdatedAt,
          'confirmed': true,
        },
      );

  @override
  Future<Map<String, dynamic>> setRouteActive({
    required String routeId,
    required bool active,
  }) =>
      _request(
        'PATCH',
        '/routes/${Uri.encodeComponent(routeId)}/${active ? 'activate' : 'deactivate'}',
        body: <String, dynamic>{'confirmed': true},
      );

  @override
  Future<Map<String, dynamic>> deleteRoute({
    required String routeId,
    required String expectedUpdatedAt,
  }) =>
      _request(
        'DELETE',
        '/routes/${Uri.encodeComponent(routeId)}',
        body: <String, dynamic>{
          'confirmed': true,
          'expectedUpdatedAt': expectedUpdatedAt,
        },
      );
}
