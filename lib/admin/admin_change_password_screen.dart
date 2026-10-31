import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';
import 'admin_permissions.dart';
import 'main_navigation.dart';

class AdminChangePasswordScreen extends StatefulWidget {
  const AdminChangePasswordScreen({
    super.key,
    this.client,
    this.onRelogin,
    this.authenticatedHomeBuilder,
  });

  static const String baseUrl = AdminApiConfiguration.baseUrl;

  final http.Client? client;
  final VoidCallback? onRelogin;
  final WidgetBuilder? authenticatedHomeBuilder;

  @override
  State<AdminChangePasswordScreen> createState() =>
      _AdminChangePasswordScreenState();
}

class _AdminChangePasswordScreenState extends State<AdminChangePasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _currentPassword = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _saving = false;
  bool _needsRelogin = false;
  String? _error;

  http.Client get _client => widget.client ?? http.Client();

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String? _passwordError(String value) {
    if (value.length < 8) return 'Use at least 8 characters.';
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Add at least one uppercase letter.';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Add at least one lowercase letter.';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Add at least one number.';
    }
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
      return 'Add at least one special character.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _needsRelogin = false;
    });
    bool serverChangedPassword = false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String token = (prefs.getString('auth_token') ??
              prefs.getString('token') ??
              prefs.getString('access_token') ??
              '')
          .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
          .trim();
      if (token.isEmpty) {
        throw const _ReloginRequiredException(
            'Your temporary session is no longer available. Sign in again.');
      }
      final http.Response response = await _client
          .put(
            Uri.parse(
                '${AdminChangePasswordScreen.baseUrl}/auth/change-password'),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, String>{
              'currentPassword': _currentPassword.text,
              'newPassword': _newPassword.text,
              'confirmPassword': _confirmPassword.text,
            }),
          )
          .timeout(const Duration(seconds: 30));
      dynamic decoded;
      try {
        decoded =
            response.body.trim().isEmpty ? null : jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
      final Map<String, dynamic> result = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          result['success'] != true) {
        throw Exception(
          result['message']?.toString().trim().isNotEmpty == true
              ? result['message'].toString()
              : 'Password change failed. Check your current password and try again.',
        );
      }
      serverChangedPassword = true;
      final Map<String, dynamic> data = result['data'] is Map
          ? Map<String, dynamic>.from(result['data'] as Map)
          : <String, dynamic>{};
      final String replacementToken =
          (result['token'] ?? result['accessToken'] ?? data['token'] ?? '')
              .toString()
              .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
              .trim();
      if (replacementToken.isEmpty) {
        throw const _ReloginRequiredException(
            'Password changed, but the refreshed session was not returned. Sign in again with your new password.');
      }
      const List<String> tokenKeys = <String>[
        'auth_token',
        'token',
        'access_token',
      ];
      for (final String key in tokenKeys) {
        final bool saved = await prefs.setString(key, replacementToken);
        if (!saved || prefs.getString(key) != replacementToken) {
          throw const _ReloginRequiredException(
            'Password changed, but the refreshed session could not be saved. Sign in again with your new password.',
          );
        }
      }
      final bool clearedFlag =
          await prefs.setBool('must_change_password', false);
      if (!clearedFlag || prefs.getBool('must_change_password') == true) {
        throw const _ReloginRequiredException(
            'Password changed, but this device could not refresh the session. Sign in again with your new password.');
      }
      await prefs.remove('forced_password_user_context');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              widget.authenticatedHomeBuilder?.call(context) ??
              const AdminMainNavigation(),
        ),
        (Route<dynamic> route) => false,
      );
    } on _ReloginRequiredException catch (error) {
      if (serverChangedPassword) {
        await _clearChangedSession();
      }
      if (mounted) {
        setState(() {
          _error = error.message;
          _needsRelogin = true;
        });
      }
    } on FormatException {
      if (mounted) {
        setState(() => _error = 'The server returned an invalid response.');
      }
    } on http.ClientException {
      if (mounted) {
        setState(() =>
            _error = 'Unable to connect. Check your network and try again.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearChangedSession() async {
    try {
      await AdminSessionStore.clearSession();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('must_change_password');
      await prefs.remove('forced_password_user_context');
    } catch (_) {
      // Keep the screen blocked; the user can use the explicit sign-in action.
    }
  }

  InputDecoration _decoration({
    required String label,
    required String hint,
    required bool visible,
    required VoidCallback onToggle,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: visible ? 'Hide $label' : 'Show $label',
          onPressed: _saving ? null : onToggle,
          icon: Icon(
            visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) =>
              SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth < 600 ? 16 : 28,
              20,
              constraints.maxWidth < 600 ? 16 : 28,
              32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Card(
                  child: Padding(
                    padding:
                        EdgeInsets.all(constraints.maxWidth < 360 ? 16 : 24),
                    child: AutofillGroup(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Icon(Icons.lock_reset_outlined,
                                size: 40, color: colors.primary),
                            const SizedBox(height: 12),
                            Text(
                              'Set your own password',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Your temporary password must be replaced before accessing staff workspaces.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              key: const Key('admin-current-password'),
                              controller: _currentPassword,
                              obscureText: !_showCurrent,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.next,
                              decoration: _decoration(
                                label: 'Current temporary password',
                                hint: 'Enter the password issued to you',
                                visible: _showCurrent,
                                onToggle: () => setState(
                                    () => _showCurrent = !_showCurrent),
                              ),
                              validator: (String? value) =>
                                  (value ?? '').isEmpty
                                      ? 'Enter your current password.'
                                      : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              key: const Key('admin-new-password'),
                              controller: _newPassword,
                              obscureText: !_showNew,
                              autofillHints: const [AutofillHints.newPassword],
                              textInputAction: TextInputAction.next,
                              decoration: _decoration(
                                label: 'New password',
                                hint:
                                    'At least 8 characters with mixed character types',
                                visible: _showNew,
                                onToggle: () =>
                                    setState(() => _showNew = !_showNew),
                              ),
                              validator: (String? value) =>
                                  _passwordError(value ?? ''),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              key: const Key('admin-confirm-password'),
                              controller: _confirmPassword,
                              obscureText: !_showConfirm,
                              autofillHints: const [AutofillHints.newPassword],
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: _decoration(
                                label: 'Confirm new password',
                                hint: 'Re-enter your new password',
                                visible: _showConfirm,
                                onToggle: () => setState(
                                    () => _showConfirm = !_showConfirm),
                              ),
                              validator: (String? value) =>
                                  value != _newPassword.text
                                      ? 'Passwords do not match.'
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Use 8+ characters, including uppercase, lowercase, a number, and a special character.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (_error != null) ...<Widget>[
                              const SizedBox(height: 12),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _error!,
                                  key: const Key('admin-password-error'),
                                  style: TextStyle(color: colors.error),
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 50,
                              child: FilledButton(
                                key: const Key('admin-change-password-submit'),
                                onPressed: _saving ? null : _submit,
                                child: _saving
                                    ? const SizedBox(
                                        height: 21,
                                        width: 21,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Text('Change password'),
                              ),
                            ),
                            if (_needsRelogin) ...<Widget>[
                              const SizedBox(height: 10),
                              OutlinedButton(
                                key: const Key('admin-password-relogin'),
                                onPressed: widget.onRelogin,
                                child: const Text('Sign in again'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReloginRequiredException implements Exception {
  const _ReloginRequiredException(this.message);

  final String message;
}
