import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';
import 'admin_change_password_screen.dart';
import 'admin_permissions.dart';
import 'login_screen.dart';

class AdminSessionGate extends StatefulWidget {
  const AdminSessionGate({
    super.key,
    this.fallback,
    this.client,
    this.preferencesLoader = SharedPreferences.getInstance,
  });

  final Widget? fallback;
  final http.Client? client;
  final Future<SharedPreferences> Function() preferencesLoader;

  @override
  State<AdminSessionGate> createState() => _AdminSessionGateState();
}

class _AdminSessionGateState extends State<AdminSessionGate> {
  late final http.Client _client;
  late final bool _ownsClient;
  late final Future<bool> _forcedChange;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _forcedChange = _checkTemporarySession();
  }

  Future<bool> _checkTemporarySession() async {
    final SharedPreferences preferences = await widget.preferencesLoader();
    final bool mustChange = preferences.getBool('must_change_password') == true;
    String token = (preferences.getString('auth_token') ??
            preferences.getString('token') ??
            preferences.getString('access_token') ??
            '')
        .trim();
    token = token.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
    if (token.isEmpty) {
      if (mustChange) await preferences.remove('must_change_password');
      return false;
    }
    if (mustChange) return true;

    // Deep links can outlive an older app version that did not persist the
    // temporary-password flag. Verify those routes before mounting their
    // protected screens so PASSWORD_CHANGE_REQUIRED always opens this gate.
    if (widget.fallback == null) return false;
    try {
      final http.Response response = await _client.get(
        Uri.parse('${AdminApiConfiguration.baseUrl}/auth/profile'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 12));
      final Map<String, dynamic> result = _decodeMap(response.body);
      if (response.statusCode == 403 &&
          result['code']?.toString().trim().toUpperCase() ==
              'PASSWORD_CHANGE_REQUIRED') {
        await preferences.setBool('must_change_password', true);
        return true;
      }
      final Map<String, dynamic> profile = _profileFrom(result);
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          profile['mustChangePassword'] == true) {
        final String role =
            (profile['role'] ?? profile['effectiveRole'] ?? '').toString();
        if (role.trim().isNotEmpty) {
          await preferences.setString('user_role', role.toUpperCase());
          await AdminSessionStore.saveAccess(AdminAccess.fromUser(profile));
        }
        await preferences.setBool('must_change_password', true);
        return true;
      }
    } catch (_) {
      // Existing route authorization checks handle transient profile errors.
    }
    return false;
  }

  Map<String, dynamic> _decodeMap(String body) {
    try {
      final dynamic decoded = jsonDecode(body);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Map<String, dynamic> _profileFrom(Map<String, dynamic> response) {
    if (response['user'] is Map) {
      return Map<String, dynamic>.from(response['user'] as Map);
    }
    if (response['data'] is Map) {
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(response['data'] as Map);
      if (data['user'] is Map) {
        return Map<String, dynamic>.from(data['user'] as Map);
      }
      return data;
    }
    return <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _forcedChange,
        builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          }
          if (snapshot.data != true) {
            return widget.fallback ?? const AdminLoginScreen();
          }
          return AdminChangePasswordScreen(
            onRelogin: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminLoginScreen(),
                ),
                (Route<dynamic> route) => false,
              );
            },
          );
        },
      );

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
