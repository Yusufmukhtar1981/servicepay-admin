import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';
import 'admin_permissions.dart';

/// API boundary for the account recovery workflow.
class AccountSecurityRecoveryApi {
  AccountSecurityRecoveryApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        baseUrl = (baseUrl ?? AdminApiConfiguration.baseUrl)
            .replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final bool _ownsClient;
  final String baseUrl;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString('auth_token') ??
            prefs.getString('token') ??
            prefs.getString('admin_token') ??
            '')
        .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
        .trim();
    if (token.isEmpty) {
      throw StateError(
          'Your login session was not found. Please sign in again.');
    }
    return token;
  }

  Future<Map<String, dynamic>> _request(
    String customerId, {
    String? suffix,
    Map<String, dynamic>? body,
  }) async {
    final token = await _token();
    final uri = Uri.parse(
      '$baseUrl/admin/account-recovery/${Uri.encodeComponent(customerId)}'
      '${suffix == null ? '' : '/$suffix'}',
    );
    final response = body == null
        ? await _client.get(uri, headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          }).timeout(const Duration(seconds: 30))
        : await _client
            .post(
              uri,
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 30));
    Map<String, dynamic> responseBody;
    try {
      final decoded = jsonDecode(response.body);
      responseBody = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      responseBody = {};
    }
    // Recovery endpoints return the canonical flat contract. Accept an
    // envelope too for compatibility, but never require a fictional wrapper.
    final data = responseBody['data'] ?? responseBody;
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        responseBody['success'] != true ||
        data is! Map) {
      final status = response.statusCode;
      throw Exception(status == 401 || status == 403
          ? 'Your access could not be confirmed. Sign in again or contact an administrator.'
          : status == 404
              ? 'Account recovery is not available for this customer.'
              : 'Unable to complete the request. Refresh and try again.');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> load(String customerId) => _request(customerId);

  Future<Map<String, dynamic>> challenge(
    String customerId, {
    required String action,
    required String reason,
    required String currentPassword,
    String channel = 'EMAIL',
  }) =>
      _request(customerId, suffix: 'challenge', body: {
        'action': action,
        'reason': reason,
        'currentPassword': currentPassword,
        'channel': channel,
      });

  Future<Map<String, dynamic>> requestContactVerification(
    String customerId, {
    required String reason,
    required String currentPassword,
  }) =>
      _request(customerId, suffix: 'contact-verification', body: {
        'reason': reason,
        'currentPassword': currentPassword,
      });

  Future<Map<String, dynamic>> verify(
    String customerId, {
    required String challengeId,
    required String otp,
    required String currentPassword,
  }) =>
      _request(customerId, suffix: 'verify', body: {
        'challengeId': challengeId,
        'otp': otp,
        'currentPassword': currentPassword,
      });
}

class AccountSecurityRecovery extends StatefulWidget {
  const AccountSecurityRecovery({
    super.key,
    required this.customerId,
    this.api,
    this.access,
  });

  final String customerId;
  final AccountSecurityRecoveryApi? api;
  final AdminAccess? access;

  @override
  State<AccountSecurityRecovery> createState() =>
      _AccountSecurityRecoveryState();
}

class _AccountSecurityRecoveryState extends State<AccountSecurityRecovery> {
  static const _ink = Color(0xff173b40);
  static const _teal = Color(0xff087f78);
  static const _mint = Color(0xffe7f4ef);
  static const _line = Color(0xffdbe9e4);

  late final AccountSecurityRecoveryApi _api =
      widget.api ?? AccountSecurityRecoveryApi();
  AdminAccess? _access;
  Map<String, dynamic>? _snapshot;
  String? _error;
  String? _message;
  bool _loading = true;
  bool _submitting = false;
  Timer? _leaseTimer;
  String? _challengeId;
  String? _challengeExpiresAt;
  String? _phoneEntryUrl;
  bool _phoneChallengeStarted = false;
  String _action = 'PASSWORD_RESET';
  String _channel = 'EMAIL';

  final _reason = TextEditingController();
  final _currentPassword = TextEditingController();
  final _otp = TextEditingController();

  @override
  void initState() {
    super.initState();
    _access = widget.access;
    if (_access == null) _loadAccess();
    _refresh();
  }

  @override
  void dispose() {
    _reason.dispose();
    _currentPassword.dispose();
    _otp.dispose();
    _leaseTimer?.cancel();
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _loadAccess() async {
    try {
      final value = await AdminSessionStore.loadAccess();
      if (mounted) setState(() => _access = value);
    } catch (_) {
      if (mounted) setState(() => _access = null);
    }
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  List<String> _permissions(dynamic value) => value is List
      ? value.map((item) => item.toString().trim()).toList()
      : <String>[];
  List<Map<String, dynamic>> _history(dynamic value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];
  String _text(dynamic value, [String fallback = '—']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  bool _has(String permission) {
    final exactLocal = widget.access?.permissions ?? _access?.permissions ?? {};
    final exactServer = _permissions(_snapshot?['permissions']);
    // This workflow deliberately does not use AdminAccess.has/isFullAccess:
    // role aliases and wildcard grants cannot authorize recovery operations.
    return exactLocal.contains(permission) && exactServer.contains(permission);
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await _api.load(widget.customerId);
      if (mounted) {
        setState(() => _snapshot = result);
        _scheduleLeaseRefresh(result);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _snapshot = null;
          _error = 'Unable to load account security details. Please retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleLeaseRefresh(Map<String, dynamic> snapshot) {
    _leaseTimer?.cancel();
    final recovery = _map(snapshot['recovery']);
    final retryAfter = DateTime.tryParse(_text(recovery['retryAfter'], ''));
    if (retryAfter == null || !retryAfter.isAfter(DateTime.now())) return;
    final delay = retryAfter.difference(DateTime.now()) +
        const Duration(milliseconds: 50);
    _leaseTimer = Timer(delay, () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _startChallenge() async {
    if (!_canStart(_action, channel: _channel) || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await _api.challenge(
        widget.customerId,
        action: _action,
        reason: _reason.text.trim(),
        currentPassword: _currentPassword.text,
        channel: _channel,
      );
      if (!mounted) return;
      setState(() {
        if (_channel == 'PHONE') {
          _challengeId = null;
          _challengeExpiresAt = _text(result['expiresAt'], '');
          _phoneChallengeStarted = true;
          _phoneEntryUrl =
              _validatedCustomerEntryUrl(result['customerEntryUrl']);
          final delivery = _deliveryLabel(result['deliveryStatus']);
          _message = _phoneEntryUrl == null
              ? 'Phone OTP recovery was initiated, but a secure customer entry '
                  'URL was not returned. Do not ask the customer to share a '
                  'code; refresh and contact support. $delivery'
              : 'Phone recovery was initiated. Give the customer the secure '
                  'entry URL below so they can verify privately. The URL '
                  'contains no OTP and does not authorize a password reset. '
                  'No code or reset token is shown to Admin staff. '
                  'OTP expires ${_date(result['expiresAt'])}. $delivery';
        } else {
          _challengeId = _text(result['challengeId'], '');
          _challengeExpiresAt = _text(result['expiresAt'], '');
          _phoneChallengeStarted = false;
          _phoneEntryUrl = null;
          _message =
              'A verification code was sent to the customer’s verified email. '
              'The code is for the customer, not the Admin.';
        }
      });
      _currentPassword.clear();
      _otp.clear();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'The recovery request was not completed. Refresh the record before retrying.');
      }
      _currentPassword.clear();
      _otp.clear();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _requestContactReview() async {
    if (!_has('INITIATE_PASSWORD_RESET') ||
        _currentPassword.text.isEmpty ||
        _reason.text.trim().length < 10 ||
        _submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await _api.requestContactVerification(
        widget.customerId,
        reason: _reason.text.trim(),
        currentPassword: _currentPassword.text,
      );
      if (!mounted) return;
      final handoffMessage = _text(
          result['message'],
          'Identity verification is required before account recovery. '
          'The request has been handed off for independent review.');
      _currentPassword.clear();
      await _refresh();
      if (mounted) setState(() => _message = handoffMessage);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'The identity-review request was not completed. Refresh and retry.');
      }
      _currentPassword.clear();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _verifyChallenge() async {
    final challengeId = _challengeId;
    if (challengeId == null || challengeId.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
      _message = null;
    });
    try {
      await _api.verify(
        widget.customerId,
        challengeId: challengeId,
        otp: _otp.text.trim(),
        currentPassword: _currentPassword.text,
      );
      if (!mounted) return;
      setState(() {
        _message =
            'Customer verification completed. The customer will receive the next step by email.';
        _challengeId = null;
        _challengeExpiresAt = null;
      });
      _reason.clear();
      _otp.clear();
      _currentPassword.clear();
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Verification could not be completed. Check the code and retry, or refresh the record.');
      }
      _otp.clear();
      _currentPassword.clear();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Map<String, dynamic> _recoveryMethod(String channel) {
    final methods = _map(_snapshot?['recoveryMethods']);
    final configured = _map(methods[channel.toLowerCase()]);
    if (configured.isNotEmpty) return configured;
    // Legacy flat snapshots remain supported. The old channelAvailable flag
    // describes EMAIL only and must never imply that SMS can be sent.
    final customer = _map(_snapshot?['customer']);
    return {
      'verified': channel == 'EMAIL'
          ? customer['emailVerified'] == true
          : customer['phoneVerified'] == true,
      'available': channel == 'EMAIL' && _snapshot?['channelAvailable'] == true,
    };
  }

  String? _validatedCustomerEntryUrl(dynamic value) {
    final raw = _text(value, '');
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'api.servicepay.ng' ||
        uri.path != '/api/account-recovery/page' ||
        uri.fragment.isEmpty) {
      return null;
    }
    Map<String, String> fragment;
    try {
      fragment = Uri.splitQueryString(uri.fragment);
    } on FormatException {
      return null;
    }
    final challenge = fragment['challenge'] ?? '';
    if (fragment.length != 2 ||
        fragment['action'] != 'PHONE_OTP' ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(challenge)) {
      return null;
    }
    return uri.toString();
  }

  bool _phonePinRecoveryAvailable() =>
      _recoveryMethod('PHONE')['pinRecoveryAvailable'] == true;

  bool _providerLeaseActive() {
    final recovery = _map(_snapshot?['recovery']);
    final retryAfter = DateTime.tryParse(_text(recovery['retryAfter'], ''));
    return retryAfter != null && retryAfter.isAfter(DateTime.now());
  }

  bool _canStart(String action, {String channel = 'EMAIL'}) {
    if (action == 'UNLOCK' || !_has('VIEW_ACCOUNT_RECOVERY')) return false;
    if (_snapshot?['contactVerificationRequired'] == true) return false;
    if (_snapshot == null ||
        _map(_snapshot?['recovery'])['status'] == 'PENDING' ||
        _providerLeaseActive()) {
      return false;
    }
    if (channel == 'PHONE' &&
        action != 'PASSWORD_RESET' &&
        !(action == 'PIN_RECOVERY' && _phonePinRecoveryAvailable())) {
      return false;
    }
    final method = _recoveryMethod(channel);
    if (method['verified'] != true || method['available'] != true) {
      return false;
    }
    if (_currentPassword.text.isEmpty) return false;
    if (action == 'PASSWORD_RESET') {
      return _has('INITIATE_PASSWORD_RESET');
    }
    if (action == 'FORCE_PASSWORD_CHANGE') {
      return _has('INITIATE_PASSWORD_RESET');
    }
    if (action == 'PIN_RECOVERY') {
      return _has('INITIATE_PIN_RECOVERY');
    }
    return false;
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(_text(value, ''));
    if (date == null) return 'Not recorded';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _maskedPhone(Map<String, dynamic> customer) {
    final supplied = _text(customer['phoneMasked'], '');
    if (supplied.isNotEmpty) return supplied;
    final phone = _text(customer['phone'], '');
    if (phone.isEmpty) return 'Not recorded';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return '****';
    return '${List<String>.filled(digits.length - 4, '*').join()}'
        '${digits.substring(digits.length - 4)}';
  }

  String _deliveryLabel(dynamic value) {
    final status = _text(value, '').toUpperCase();
    if (status == 'DELIVERED') return 'SMS delivery is confirmed.';
    if (status == 'ACCEPTED' || status == 'QUEUED' || status == 'SENT') {
      return 'The SMS request was accepted; delivery is not confirmed.';
    }
    return 'Delivery status is not confirmed.';
  }

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('account-security-recovery'),
        margin: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(),
            if (_error != null) _notice(_error!, warning: true),
            if (_message != null) _notice(_message!),
            if (_loading && _snapshot == null) _skeleton(),
            if (_snapshot != null && !_has('VIEW_ACCOUNT_RECOVERY'))
              _notice(
                'Your assigned permissions do not include VIEW_ACCOUNT_RECOVERY.',
                warning: true,
              ),
            if (_snapshot != null && _has('VIEW_ACCOUNT_RECOVERY')) ...[
              _diagnostics(),
              _workflow(),
              if (_has('VIEW_RECOVERY_AUDIT_LOG')) _auditHistory(),
            ],
            if (_error != null && _snapshot == null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('recovery-retry'),
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry loading'),
                ),
              ),
          ],
        ),
      );

  Widget _heading() => _Panel(
        title: 'Account security & recovery',
        trailing: IconButton(
          key: const Key('recovery-refresh'),
          tooltip: 'Refresh security details',
          onPressed: _loading || _submitting ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        child: const Text(
          'Recovery is customer-led. Admin staff never receive a phone OTP, reset token, customer password or PIN.',
          style: TextStyle(color: Color(0xff526c67), height: 1.4),
        ),
      );

  Widget _diagnostics() {
    final customer = _map(_snapshot?['customer']);
    final diagnostics = _map(_snapshot?['diagnostics']);
    final emailVerified = _recoveryMethod('EMAIL')['verified'] == true;
    final phoneVerified = _recoveryMethod('PHONE')['verified'] == true;
    return _Panel(
      title: 'Verified customer & sign-in diagnostics',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_text(customer['fullName']),
            style: const TextStyle(
                color: _ink, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text('${_text(customer['email'])} · ${_maskedPhone(customer)}',
            style: const TextStyle(color: Color(0xff607773))),
        const SizedBox(height: 9),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _tag('Status: ${_text(customer['status'])}'),
          _tag(emailVerified ? 'Email verified' : 'Email not verified'),
          _tag(phoneVerified ? 'Phone verified' : 'Phone not verified'),
          _tag(_snapshot?['channelAvailable'] == true
              ? 'Email channel available'
              : 'Email channel unavailable'),
        ]),
        const Divider(height: 24),
        _detail(
            'Last successful login', _date(diagnostics['lastSuccessfulLogin'])),
        _detail('Failed login attempts',
            _text(diagnostics['failedLoginAttempts'], '0')),
        _detail(
            'Ordinary lock support',
            diagnostics['ordinaryLockSupported'] == false
                ? 'Unavailable'
                : _text(diagnostics['ordinaryLockSupported'])),
        _detail(
            'Existing restrictions',
            diagnostics['restrictionsPreserved'] == true
                ? 'Preserved'
                : _text(diagnostics['restrictionsPreserved'])),
      ]),
    );
  }

  Widget _workflow() {
    final recovery = _map(_snapshot?['recovery']);
    final unlockAllowedByServer = _permissions(_snapshot?['permissions'])
        .contains('UNLOCK_CUSTOMER_ACCOUNT');
    return _Panel(
      title: 'Customer recovery workflow',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _detail('Current recovery', _text(recovery['status'], 'NONE')),
        if (_providerLeaseActive())
          Container(
            key: const Key('recovery-provider-lease-notice'),
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xfffff4e5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xffead3a8)),
            ),
            child: Text(
              'A fresh recovery request can be made after '
              '${_date(recovery['retryAfter'])}. The customer’s five-minute '
              'code has expired; this provider lease does not extend its '
              'validity. Wait until the lease ends to avoid reusing a provider '
              'code across recovery actions.',
              style: const TextStyle(color: _ink, height: 1.45),
            ),
          ),
        if (_text(recovery['action'], '').isNotEmpty)
          _detail('Action', _text(recovery['action']).replaceAll('_', ' ')),
        if (_text(recovery['expiresAt'], '').isNotEmpty)
          _detail('Expires', _date(recovery['expiresAt'])),
        if (_text(recovery['deliveryStatus'], '').isNotEmpty)
          _detail('Delivery', _deliveryLabel(recovery['deliveryStatus'])),
        if (_challengeId == null && !_phoneChallengeStarted) ...[
          _recoveryReadiness(),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('recovery-action'),
            value: _action,
            decoration: const InputDecoration(
              labelText: 'Recovery action',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                  value: 'PASSWORD_RESET', child: Text('Password reset')),
              DropdownMenuItem(
                  value: 'FORCE_PASSWORD_CHANGE',
                  child: Text('Require password change')),
              DropdownMenuItem(
                  value: 'PIN_RECOVERY', child: Text('PIN recovery')),
              DropdownMenuItem(value: 'UNLOCK', child: Text('Unlock account')),
            ],
            onChanged: _submitting
                ? null
                : (value) {
                    setState(() {
                      _action = value ?? 'PASSWORD_RESET';
                      if (_action == 'PIN_RECOVERY' ||
                          _action == 'FORCE_PASSWORD_CHANGE') {
                        _channel = 'EMAIL';
                      }
                      _currentPassword.clear();
                    });
                  },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: const Key('recovery-channel'),
            value: _channel,
            decoration: const InputDecoration(
              labelText: 'Recovery method',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                  value: 'EMAIL', child: Text('Email recovery')),
              DropdownMenuItem(
                value: 'PHONE',
                enabled: _action == 'PASSWORD_RESET' ||
                    (_action == 'PIN_RECOVERY' && _phonePinRecoveryAvailable()),
                child: const Text('Phone OTP'),
              ),
            ],
            onChanged: _submitting
                ? null
                : (value) => setState(() {
                      _channel = value ?? 'EMAIL';
                      _currentPassword.clear();
                    }),
          ),
          if (_action == 'UNLOCK')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                unlockAllowedByServer
                    ? 'Unavailable: this service has no ordinary account-lock mechanism. Existing restrictions are preserved.'
                    : 'Unavailable: no ordinary account-lock mechanism exists; an unlock permission cannot create one.',
                key: const Key('recovery-unlock-unavailable'),
                style: const TextStyle(color: Color(0xff9b3d32), height: 1.4),
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('recovery-admin-current-password'),
            controller: _currentPassword,
            obscureText: true,
            autofillHints: const [],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Your current Admin password',
              helperText:
                  'Required for every recovery request. This is never the customer’s password.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('recovery-reason'),
            controller: _reason,
            onChanged: (_) => setState(() {}),
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Operational reason',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              key: const Key('recovery-send-challenge'),
              onPressed: _channel != 'EMAIL' ||
                      !_canStart(_action, channel: 'EMAIL') ||
                      _reason.text.trim().length < 10 ||
                      _submitting
                  ? null
                  : _startChallenge,
              style: FilledButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white),
              icon: const Icon(Icons.mark_email_read_outlined),
              label: Text(_submitting ? 'Sending…' : 'Send Email Recovery'),
            ),
            FilledButton.icon(
              key: const Key('recovery-send-phone-otp'),
              onPressed: _channel != 'PHONE' ||
                      !_canStart(_action, channel: 'PHONE') ||
                      _reason.text.trim().length < 10 ||
                      _submitting
                  ? null
                  : _startChallenge,
              style: FilledButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white),
              icon: const Icon(Icons.sms_outlined),
              label: Text(_submitting ? 'Sending…' : 'Send Phone OTP'),
            ),
          ]),
          if (!_has(_permissionFor(_action)) && _action != 'UNLOCK')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                  'This action is not enabled for your assigned permissions.',
                  key: Key('recovery-permission-denied'),
                  style: TextStyle(color: Color(0xff708783), fontSize: 12)),
            ),
          if (_recoveryMethod(_channel)['available'] != true ||
              _recoveryMethod(_channel)['verified'] != true)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'This recovery method requires a verified customer contact and an available delivery channel.',
                key: Key('recovery-email-unavailable'),
                style: TextStyle(color: Color(0xff9b3d32), fontSize: 12),
              ),
            ),
        ] else if (_phoneChallengeStarted) ...[
          const SizedBox(height: 10),
          const Text(
            'Customer phone verification',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Give this secure entry URL to the customer. It contains no OTP '
            'and does not authorize a password reset. Do not collect or enter '
            'the customer’s SMS code.',
            key: Key('recovery-phone-url-safety'),
            style: TextStyle(color: Color(0xff607773), height: 1.4),
          ),
          if (_phoneEntryUrl != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              _phoneEntryUrl!,
              key: const Key('recovery-customer-entry-url'),
              style: const TextStyle(color: _teal, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: const Key('recovery-copy-customer-entry-url'),
              onPressed: _submitting
                  ? null
                  : () async {
                      await Clipboard.setData(
                          ClipboardData(text: _phoneEntryUrl!));
                      if (mounted) {
                        setState(() => _message =
                            'Secure customer entry URL copied. It contains '
                                'no OTP and does not authorize a password reset.');
                      }
                    },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy customer entry URL'),
            ),
          ],
          if (_challengeExpiresAt != null && _challengeExpiresAt!.isNotEmpty)
            Text('Expires ${_date(_challengeExpiresAt)}',
                style: const TextStyle(color: Color(0xff708783), fontSize: 12)),
          TextButton(
            onPressed: _submitting
                ? null
                : () => setState(() {
                      _phoneChallengeStarted = false;
                      _phoneEntryUrl = null;
                      _challengeExpiresAt = null;
                      _currentPassword.clear();
                    }),
            child: const Text('Start another recovery request'),
          ),
        ] else ...[
          const SizedBox(height: 10),
          Text('Verification code for the customer’s email',
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
          if (_challengeExpiresAt != null && _challengeExpiresAt!.isNotEmpty)
            Text('Expires ${_date(_challengeExpiresAt)}',
                style: const TextStyle(color: Color(0xff708783), fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            key: const Key('recovery-customer-otp'),
            controller: _otp,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Customer verification code',
              helperText:
                  'Enter only the customer’s one-time verification code. Never enter a new customer password or PIN.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('recovery-admin-verify-password'),
            controller: _currentPassword,
            obscureText: true,
            autofillHints: const [],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Your current Admin password',
              helperText: 'Enter your current password again to verify.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              key: const Key('recovery-verify-challenge'),
              onPressed: _otp.text.trim().isEmpty ||
                      _currentPassword.text.isEmpty ||
                      _submitting
                  ? null
                  : _verifyChallenge,
              style: FilledButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white),
              child: Text(_submitting ? 'Verifying…' : 'Verify customer code'),
            ),
            TextButton(
              onPressed: _submitting
                  ? null
                  : () {
                      setState(() {
                        _challengeId = null;
                        _challengeExpiresAt = null;
                        _otp.clear();
                        _currentPassword.clear();
                      });
                    },
              child: const Text('Cancel'),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _recoveryReadiness() {
    final email = _recoveryMethod('EMAIL');
    final phone = _recoveryMethod('PHONE');
    final noVerifiedContacts =
        email['verified'] != true && phone['verified'] != true;
    final identityRequired =
        noVerifiedContacts || _snapshot?['contactVerificationRequired'] == true;
    return Container(
      key: const Key('recovery-method-readiness'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: identityRequired ? const Color(0xfffff0ed) : _mint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Recovery method readiness',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        _detail('Email',
            '${email['verified'] == true ? 'Verified' : 'Not verified'} · ${email['available'] == true ? 'Delivery available' : 'Delivery unavailable'}'),
        _detail('Phone',
            '${phone['verified'] == true ? 'Verified' : 'Not verified'} · ${phone['available'] == true ? 'SMS available' : 'SMS unavailable'}'),
        if (identityRequired) ...[
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Customer identity verification is required before account recovery.',
              key: Key('recovery-no-verified-contacts'),
              style: TextStyle(color: Color(0xff8e382f), height: 1.4),
            ),
          ),
          const SizedBox(height: 6),
          OutlinedButton(
            key: const Key('recovery-request-identity-review'),
            onPressed: _has('INITIATE_PASSWORD_RESET') &&
                    _currentPassword.text.isNotEmpty &&
                    _reason.text.trim().length >= 5 &&
                    !_submitting
                ? _requestContactReview
                : null,
            child: const Text('Request identity verification review'),
          ),
          const Text(
            'This audited handoff does not verify a contact or unlock recovery.',
            style: TextStyle(color: Color(0xff607773), fontSize: 12),
          ),
        ],
      ]),
    );
  }

  String _permissionFor(String action) => switch (action) {
        'PASSWORD_RESET' ||
        'FORCE_PASSWORD_CHANGE' =>
          'INITIATE_PASSWORD_RESET',
        'PIN_RECOVERY' => 'INITIATE_PIN_RECOVERY',
        'UNLOCK' => 'UNLOCK_CUSTOMER_ACCOUNT',
        _ => '',
      };

  Widget _auditHistory() {
    final history = _history(_snapshot?['history']);
    return _Panel(
      title: 'Recovery audit history',
      child: history.isEmpty
          ? const Text('No recovery audit entries were returned.',
              style: TextStyle(color: Color(0xff708783)))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: history
                  .map((item) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detail(
                            _text(item['event'] ?? item['action'],
                                    'Recovery event')
                                .replaceAll('_', ' '),
                            '${_text(item['status'] ?? item['outcome'])} · ${_date(item['createdAt'] ?? item['occurredAt'])}',
                          ),
                          _detail('Initiating actor', _text(item['actorId'])),
                          _detail('Documented reason', _text(item['reason'])),
                          const Divider(),
                        ],
                      ))
                  .toList()),
    );
  }

  Widget _skeleton() => _Panel(
        title: 'Loading security details',
        child: Column(children: [
          for (var i = 0; i < 3; i++)
            Container(
              height: 14,
              margin: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xffe8f0ed),
                borderRadius: BorderRadius.circular(7),
              ),
            ),
        ]),
      );

  Widget _notice(String text, {bool warning = false}) => Container(
        key: Key(warning ? 'recovery-error' : 'recovery-message'),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: warning ? const Color(0xfffff0ed) : _mint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: warning ? const Color(0xffe8b9b0) : _line),
        ),
        child: Text(text,
            style: TextStyle(
                color: warning ? const Color(0xff8e382f) : _ink, height: 1.4)),
      );

  Widget _tag(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: _mint, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: const TextStyle(
                color: _teal, fontSize: 11, fontWeight: FontWeight.w800)),
      );

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: const TextStyle(color: Color(0xff708783), fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffdbe9e4)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: Color(0xff173b40),
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );
}
