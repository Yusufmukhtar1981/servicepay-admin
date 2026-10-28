import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';

class AdminCustomerProfileApi {
  AdminCustomerProfileApi({http.Client? client, String? baseUrl})
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
    final token = prefs.getString('auth_token') ??
        prefs.getString('token') ??
        prefs.getString('admin_token');
    if (token == null || token.trim().isEmpty) {
      throw StateError('Admin login token was not found. Please login again.');
    }
    return token;
  }

  Map<String, String> _headers(String token, {bool jsonBody = false}) => {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        if (jsonBody) 'Content-Type': 'application/json',
      };

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      return value is Map ? Map<String, dynamic>.from(value) : {};
    } catch (_) {
      return {'message': response.body};
    }
  }

  Never _throw(Map<String, dynamic> body, String fallback) {
    throw Exception((body['message'] ?? body['error'] ?? fallback).toString());
  }

  Future<String> requestContactCode({
    required String customerId,
    required String field,
    required String value,
    required String currentPassword,
    required String reason,
  }) async {
    final token = await _token();
    final response = await _client
        .post(
          Uri.parse('$baseUrl/admin/users/$customerId/profile/contact/request'),
          headers: _headers(token, jsonBody: true),
          body: jsonEncode({
            'field': field,
            'value': value,
            'currentPassword': currentPassword,
            'reason': reason,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final body = _decode(response);
    final data = body['data'];
    final id = data is Map ? data['challengeId']?.toString() : null;
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] != true ||
        id == null ||
        id.isEmpty) {
      _throw(body, 'Unable to request contact verification codes.');
    }
    return id;
  }

  Future<void> updateProfile({
    required String customerId,
    required Map<String, dynamic> profile,
    required String reason,
    required Map<String, dynamic> contactVerifications,
  }) async {
    final token = await _token();
    final response = await _client
        .put(
          Uri.parse('$baseUrl/admin/users/$customerId/profile'),
          headers: _headers(token, jsonBody: true),
          body: jsonEncode({
            ...profile,
            'reason': reason,
            if (contactVerifications.isNotEmpty)
              'contactVerifications': contactVerifications,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final body = _decode(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] == false) {
      _throw(body, 'Unable to update customer profile.');
    }
  }

  Future<Map<String, dynamic>> history({
    required String customerId,
    int page = 1,
  }) async {
    final token = await _token();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/admin/users/$customerId/profile/history')
              .replace(queryParameters: {'page': '$page'}),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 30));
    final body = _decode(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] != true) {
      _throw(body, 'Unable to load profile history.');
    }
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : {};
  }
}

class AdminCustomerProfileEditor extends StatefulWidget {
  const AdminCustomerProfileEditor({
    super.key,
    required this.customer,
    required this.api,
    this.contactChangesEnabled,
  });

  static const bool _releaseContactChangesEnabled = bool.fromEnvironment(
    'SERVICEPAY_PROFILE_CONTACT_CHANGES_ENABLED',
    defaultValue: false,
  );

  final Map<String, dynamic> customer;
  final AdminCustomerProfileApi api;

  /// Optional test seam; release behavior is controlled by the compile-time flag.
  final bool? contactChangesEnabled;

  bool get contactsEnabled =>
      contactChangesEnabled ?? _releaseContactChangesEnabled;

  @override
  State<AdminCustomerProfileEditor> createState() =>
      _AdminCustomerProfileEditorState();
}

class _AdminCustomerProfileEditorState
    extends State<AdminCustomerProfileEditor> {
  late final Map<String, TextEditingController> _fields;
  final _reason = TextEditingController();
  final _password = TextEditingController();
  final Map<String, TextEditingController> _newCode = {};
  final Map<String, TextEditingController> _approvalCode = {};
  final Map<String, String> _challenges = {};
  final Map<String, String> _requestedValue = {};
  final Map<String, DateTime> _expiry = {};
  final Map<String, int> _seconds = {};
  final Map<String, bool> _requesting = {};
  bool _saving = false;
  String? _error;
  static const _green = Color(0xFF08783E);

  @override
  void initState() {
    super.initState();
    _fields = {
      for (final key in [
        'fullName',
        'phone',
        'email',
        'address',
        'state',
        'lga',
        'zone'
      ])
        key: TextEditingController(text: '${widget.customer[key] ?? ''}'),
    };
    for (final key in ['phone', 'email']) {
      _newCode[key] = TextEditingController();
      _approvalCode[key] = TextEditingController();
      _fields[key]!.addListener(() {
        if (_challenges.containsKey(key) &&
            _fields[key]!.text.trim().toLowerCase() !=
                (_requestedValue[key] ?? '').toLowerCase()) {
          setState(() {
            _challenges.remove(key);
            _requestedValue.remove(key);
            _expiry.remove(key);
            _seconds.remove(key);
            _newCode[key]!.clear();
            _approvalCode[key]!.clear();
          });
        }
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _reason.dispose();
    _password.dispose();
    for (final controller in _newCode.values) {
      controller.dispose();
    }
    for (final controller in _approvalCode.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _changed(String field) =>
      _fields[field]!.text.trim().toLowerCase() !=
      '${widget.customer[field] ?? ''}'.trim().toLowerCase();

  Future<void> _request(String field) async {
    if (!widget.contactsEnabled) {
      setState(() => _error =
          'Phone and email changes are temporarily unavailable while secure verification is configured.');
      return;
    }
    final other = field == 'email' ? 'phone' : 'email';
    if (_changed(other)) {
      setState(() => _error =
          'Change and save one contact method at a time. Update $other afterward.');
      return;
    }
    if (_password.text.isEmpty || _reason.text.trim().length < 5) {
      setState(() => _error =
          'Enter your admin password and a reason (at least 5 characters).');
      return;
    }
    setState(() {
      _requesting[field] = true;
      _error = null;
    });
    try {
      final id = await widget.api.requestContactCode(
        customerId: "${widget.customer['_id'] ?? widget.customer['id']}",
        field: field,
        value: _fields[field]!.text.trim(),
        currentPassword: _password.text,
        reason: _reason.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _challenges[field] = id;
        _requestedValue[field] = _fields[field]!.text.trim();
        _expiry[field] = DateTime.now().add(const Duration(minutes: 10));
        _seconds[field] = 600;
        _newCode[field]!.clear();
        _approvalCode[field]!.clear();
      });
      Future<void>.delayed(const Duration(seconds: 1), () {
        if (!mounted || !_challenges.containsKey(field)) return;
        final remaining = _expiry[field]!.difference(DateTime.now()).inSeconds;
        setState(() => _seconds[field] = remaining.clamp(0, 600).toInt());
        if (remaining > 0) _tick(field);
      });
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _requesting[field] = false);
    }
  }

  void _tick(String field) {
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!mounted || !_challenges.containsKey(field)) return;
      final remaining = _expiry[field]!.difference(DateTime.now()).inSeconds;
      setState(() => _seconds[field] = remaining.clamp(0, 600).toInt());
      if (remaining > 0) _tick(field);
    });
  }

  Future<void> _save() async {
    if (!widget.contactsEnabled && (_changed('email') || _changed('phone'))) {
      setState(() => _error =
          'Phone and email changes are temporarily unavailable while secure verification is configured.');
      return;
    }
    if (_changed('email') && _changed('phone')) {
      setState(() => _error =
          'Change and save one contact method at a time. Save phone or email first, then edit the other.');
      return;
    }
    if (_fields['fullName']!.text.trim().length < 2 ||
        _reason.text.trim().length < 5) {
      setState(() => _error =
          'Name is required and the audit reason must be at least 5 characters.');
      return;
    }
    final verifications = <String, dynamic>{};
    for (final field in ['phone', 'email']) {
      if (!_changed(field)) continue;
      if (!_challenges.containsKey(field) ||
          (_seconds[field] ?? 0) <= 0 ||
          _newCode[field]!.text.trim().isEmpty ||
          _approvalCode[field]!.text.trim().isEmpty) {
        setState(() => _error =
            'Both verification codes for the changed $field are required and must be unexpired.');
        return;
      }
      verifications[field] = {
        'challengeId': _challenges[field],
        'code': _newCode[field]!.text.trim(),
        'approvalCode': _approvalCode[field]!.text.trim(),
      };
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.updateProfile(
        customerId: "${widget.customer['_id'] ?? widget.customer['id']}",
        profile: {
          'fullName': _fields['fullName']!.text.trim(),
          'address': _fields['address']!.text.trim(),
          if (widget.contactsEnabled && _changed('phone'))
            'phone': _fields['phone']!.text.trim(),
          if (widget.contactsEnabled && _changed('email'))
            'email': _fields['email']!.text.trim(),
        },
        reason: _reason.text.trim(),
        contactVerifications: verifications,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label,
          {TextInputType keyboard = TextInputType.text,
          bool readOnly = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _fields[key],
          keyboardType: keyboard,
          readOnly: readOnly,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );

  Widget _verification(String field) {
    if (!widget.contactsEnabled || !_changed(field)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFFF1F7F3),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              "Contact verification · ${(_seconds[field] ?? 0) > 0 ? '${_seconds[field]}s remaining' : 'pending / expired'}"),
          TextField(
              controller: _newCode[field],
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Code sent to new contact')),
          TextField(
              controller: _approvalCode[field],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Approval code sent to existing contact')),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed:
                  _requesting[field] == true ? null : () => _request(field),
              child: Text(_requesting[field] == true
                  ? 'Sending…'
                  : _challenges.containsKey(field)
                      ? 'Resend both codes'
                      : 'Request both codes'),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit Customer Profile'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field('fullName', 'Full Name'),
              if (!widget.contactsEnabled)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Phone and email changes are temporarily unavailable while secure verification is configured.',
                    key: Key('admin-profile-contact-changes-disabled'),
                    style: TextStyle(
                      color: Color(0xFF8A5A00),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (widget.contactsEnabled &&
                  _changed('email') &&
                  _changed('phone'))
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Change and save one contact method at a time. The customer can then be edited again for the second contact.',
                    style: TextStyle(color: Color(0xFF8A5A00)),
                  ),
                ),
              _field('phone', 'Phone Number',
                  keyboard: TextInputType.phone,
                  readOnly: !widget.contactsEnabled),
              _verification('phone'),
              _field('email', 'Email Address',
                  keyboard: TextInputType.emailAddress,
                  readOnly: !widget.contactsEnabled),
              _verification('email'),
              _field('address', 'Residential Address'),
              _field('state', 'State', readOnly: true),
              _field('lga', 'LGA', readOnly: true),
              _field('zone', 'Zone', readOnly: true),
              if (widget.contactsEnabled &&
                  (_changed('email') || _changed('phone')))
                TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText:
                            'Admin password (required for OTP requests)')),
              TextField(
                  controller: _reason,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Audit reason (required)')),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFB42318)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _green),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save Changes'),
          ),
        ],
      );
}

class AdminCustomerProfileHistory extends StatefulWidget {
  const AdminCustomerProfileHistory(
      {super.key, required this.customer, required this.api});
  final Map<String, dynamic> customer;
  final AdminCustomerProfileApi api;

  @override
  State<AdminCustomerProfileHistory> createState() =>
      _AdminCustomerProfileHistoryState();
}

class _AdminCustomerProfileHistoryState
    extends State<AdminCustomerProfileHistory> {
  int _page = 1;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() => widget.api.history(
        customerId: "${widget.customer['_id'] ?? widget.customer['id']}",
        page: _page,
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Profile modification history'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Unable to load audit history.'),
                  TextButton(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('Retry')),
                ]));
              }
              final data = snapshot.data ?? {};
              final raw = data['history'];
              final entries =
                  raw is List ? raw.whereType<Map>().toList() : <Map>[];
              final pages = int.tryParse('${data['pages'] ?? 1}') ?? 1;
              if (entries.isEmpty) {
                return const Center(
                    child: Text('No profile changes recorded.'));
              }
              return Column(children: [
                Expanded(
                  child: ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = entries[index];
                      final previous = item['previousData'] is Map
                          ? Map<String, dynamic>.from(item['previousData'])
                          : <String, dynamic>{};
                      final next = item['newData'] is Map
                          ? Map<String, dynamic>.from(item['newData'])
                          : <String, dynamic>{};
                      final changes = <String>[
                        for (final key in [
                          'fullName',
                          'phone',
                          'email',
                          'address',
                          'state',
                          'lga',
                          'zone'
                        ])
                          if ('${previous[key] ?? ''}' != '${next[key] ?? ''}')
                            "$key: ${previous[key] ?? '—'} → ${next[key] ?? '—'}",
                      ];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            "${item['actorName'] ?? 'Unknown actor'} · ${item['actorRole'] ?? '—'}",
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            "${item['createdAt'] ?? ''}\nReason: ${item['reason'] ?? '—'}\n${changes.join('\n')}"),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(
                      onPressed: _page > 1
                          ? () => setState(() {
                                _page--;
                                _future = _load();
                              })
                          : null,
                      icon: const Icon(Icons.chevron_left)),
                  Text('Page $_page of $pages'),
                  IconButton(
                      onPressed: _page < pages
                          ? () => setState(() {
                                _page++;
                                _future = _load();
                              })
                          : null,
                      icon: const Icon(Icons.chevron_right)),
                ]),
              ]);
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      );
}
