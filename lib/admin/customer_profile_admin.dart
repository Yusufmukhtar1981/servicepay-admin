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
    Map<String, dynamic> contactVerifications = const {},
    String? currentPassword,
    String? expectedPhone,
    String? expectedEmail,
  }) async {
    final token = await _token();
    final response = await _client
        .put(
          Uri.parse('$baseUrl/admin/users/$customerId/profile'),
          headers: _headers(token, jsonBody: true),
          body: jsonEncode({
            ...profile,
            'reason': reason,
            if (currentPassword != null) 'currentPassword': currentPassword,
            if (expectedPhone != null) 'expectedPhone': expectedPhone,
            if (expectedEmail != null) 'expectedEmail': expectedEmail,
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

  Future<Map<String, dynamic>> contactCorrectionAccess({
    required String customerId,
  }) async {
    final token = await _token();
    final response = await _client
        .get(
          Uri.parse(
              '$baseUrl/admin/users/$customerId/profile/contact-correction'),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 30));
    final body = _decode(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] != true ||
        body['data'] is! Map) {
      _throw(body, 'Unable to check contact-correction permission.');
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>?> contactProposal({
    required String customerId,
  }) async {
    final token = await _token();
    final response = await _client
        .get(
          Uri.parse(
              '$baseUrl/admin/users/$customerId/profile/contact-proposal'),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 30));
    final body = _decode(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] != true) {
      _throw(body, 'Unable to load the pending contact correction.');
    }
    final data = body['data'];
    final proposal = data is Map ? data['proposal'] : null;
    return proposal is Map ? Map<String, dynamic>.from(proposal) : null;
  }

  Future<Map<String, dynamic>?> proposeContactCorrection({
    required String customerId,
    String? phone,
    String? email,
    required String currentPassword,
    required String reason,
    required String? expectedProposalId,
  }) async {
    final token = await _token();
    late final http.Response response;
    try {
      response = await _client
          .put(
            Uri.parse(
                '$baseUrl/admin/users/$customerId/profile/contact-proposal'),
            headers: _headers(token, jsonBody: true),
            body: jsonEncode({
              if (phone != null) 'phone': phone,
              if (email != null) 'email': email,
              'currentPassword': currentPassword,
              'reason': reason,
              'expectedProposalId': expectedProposalId,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      // A timeout or disconnected response can leave the write outcome unknown.
      await _refreshProposal(customerId);
      rethrow;
    }
    final body = _decode(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] != true) {
      if (response.statusCode == 401 || response.statusCode == 409) {
        await _refreshProposal(customerId);
      }
      _throw(body, 'Unable to submit the pending contact correction.');
    }
    return _proposalFrom(body);
  }

  Future<void> withdrawContactCorrection({
    required String customerId,
    required String currentPassword,
    required String reason,
    required String expectedProposalId,
  }) async {
    final token = await _token();
    late final http.Response response;
    try {
      response = await _client
          .delete(
            Uri.parse(
                '$baseUrl/admin/users/$customerId/profile/contact-proposal'),
            headers: _headers(token, jsonBody: true),
            body: jsonEncode({
              'currentPassword': currentPassword,
              'reason': reason,
              'expectedProposalId': expectedProposalId,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      await _refreshProposal(customerId);
      rethrow;
    }
    final body = _decode(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] != true) {
      if (response.statusCode == 401 || response.statusCode == 409) {
        await _refreshProposal(customerId);
      }
      _throw(body, 'Unable to withdraw the pending contact correction.');
    }
  }

  Map<String, dynamic>? _proposalFrom(Map<String, dynamic> body) {
    final data = body['data'];
    final proposal = data is Map ? data['proposal'] : null;
    return proposal is Map ? Map<String, dynamic>.from(proposal) : null;
  }

  Future<void> _refreshProposal(String customerId) async {
    try {
      await contactProposal(customerId: customerId);
    } catch (_) {
      // Keep the original write error; the editor can retry the GET.
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
  });

  final Map<String, dynamic> customer;
  final AdminCustomerProfileApi api;

  @override
  State<AdminCustomerProfileEditor> createState() =>
      _AdminCustomerProfileEditorState();
}

class _AdminCustomerProfileEditorState
    extends State<AdminCustomerProfileEditor> {
  late final Map<String, TextEditingController> _fields;
  final _auditReason = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false;
  String? _error;
  late Future<Map<String, dynamic>> _accessFuture;
  static const _green = Color(0xFF08783E);
  bool get _busy => _saving;
  String get _customerId =>
      "${widget.customer['_id'] ?? widget.customer['id']}";

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
    _accessFuture = widget.api.contactCorrectionAccess(customerId: _customerId);
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _auditReason.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_fields['fullName']!.text.trim().length < 2 ||
        _auditReason.text.trim().length < 5) {
      setState(() => _error =
          'Name is required and the audit reason must be at least 5 characters.');
      return;
    }
    final phone = _fields['phone']!.text.trim();
    final email = _fields['email']!.text.trim();
    final originalPhone = '${widget.customer['phone'] ?? ''}'.trim();
    final originalEmail = '${widget.customer['email'] ?? ''}'.trim();
    final contactsChanged = phone != originalPhone || email != originalEmail;

    var canCorrectContacts = false;
    if (contactsChanged) {
      try {
        final access = await _accessFuture;
        canCorrectContacts = access['canCorrect'] == true;
      } catch (_) {
        canCorrectContacts = false;
      }
      if (!canCorrectContacts) {
        setState(() => _error =
            'Contact-correction permission is required to change phone or email.');
        return;
      }
      if (_password.text.trim().isEmpty) {
        setState(() => _error =
            'Enter your current admin password to save contact changes.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.updateProfile(
        customerId: _customerId,
        profile: {
          'fullName': _fields['fullName']!.text.trim(),
          'phone': phone,
          'email': email,
          'address': _fields['address']!.text.trim(),
          'state': _fields['state']!.text.trim(),
          'lga': _fields['lga']!.text.trim(),
          'zone': _fields['zone']!.text.trim(),
        },
        reason: _auditReason.text.trim(),
        contactVerifications: const {},
        currentPassword: contactsChanged ? _password.text : null,
        expectedPhone: contactsChanged ? originalPhone : null,
        expectedEmail: contactsChanged ? originalEmail : null,
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

  Widget _contactFields() => FutureBuilder<Map<String, dynamic>>(
        future: _accessFuture,
        builder: (context, snapshot) {
          final canCorrect = snapshot.connectionState == ConnectionState.done &&
              !snapshot.hasError &&
              snapshot.data?['canCorrect'] == true;
          if (!canCorrect) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field('phone', 'Phone Number',
                      keyboard: TextInputType.phone, readOnly: true),
                  _field('email', 'Email Address',
                      keyboard: TextInputType.emailAddress, readOnly: true),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF5E8),
                      border: Border.all(color: const Color(0xFFE8D1AA)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Contact-correction permission is required to edit phone or email. Other profile fields remain available.',
                      key: Key('admin-profile-contact-permission-notice'),
                    ),
                  ),
                ]);
          }
          return Column(children: [
            _field('phone', 'Phone Number', keyboard: TextInputType.phone),
            _field('email', 'Email Address',
                keyboard: TextInputType.emailAddress),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5E8),
                border: Border.all(color: const Color(0xFFE8D1AA)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Changed contact details are saved immediately as unverified. They cannot be used for account recovery until verified.',
                key: Key('admin-profile-unverified-contact-warning'),
              ),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current admin password (only for contact changes)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
          ]);
        },
      );

  @override
  Widget build(BuildContext context) => PopScope<void>(
        canPop: !_busy,
        child: AlertDialog(
          title: const Text('Edit Customer Profile'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _field('fullName', 'Full Name'),
                _contactFields(),
                _field('address', 'Residential Address'),
                _field('state', 'State'),
                _field('lga', 'LGA'),
                _field('zone', 'Zone'),
                TextField(
                  controller: _auditReason,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Audit reason (required, at least 5 characters)',
                    border: OutlineInputBorder(),
                  ),
                ),
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
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _green),
              onPressed: _busy ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Changes'),
            ),
          ],
        ),
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
                      final action = '${item['action'] ?? ''}';
                      final metadata = item['metadata'] is Map
                          ? Map<String, dynamic>.from(item['metadata'])
                          : <String, dynamic>{};
                      final directCorrection =
                          metadata['directCorrection'] is Map
                              ? Map<String, dynamic>.from(
                                  metadata['directCorrection'])
                              : <String, dynamic>{};
                      final unverifiedFields =
                          directCorrection['unverifiedContactFields'] is List
                              ? (directCorrection['unverifiedContactFields']
                                      as List)
                                  .map((field) => field.toString())
                                  .toSet()
                              : <String>{};
                      if (directCorrection['verificationMethod'] ==
                          'ADMIN_DIRECT_UNVERIFIED') {
                        for (final field in ['phone', 'email']) {
                          if (unverifiedFields.contains(field) &&
                              '${previous[field] ?? ''}' !=
                                  '${next[field] ?? ''}') {
                            changes.add(
                                '$field status: UNVERIFIED · unavailable for recovery');
                          }
                        }
                      }
                      final pending = metadata['pendingContact'] is Map
                          ? Map<String, dynamic>.from(
                              metadata['pendingContact'])
                          : <String, dynamic>{};
                      if (action == 'PROFILE_CONTACT_PROPOSED') {
                        changes.add(
                            'Contact proposal (not applied) · ${pending['status'] ?? 'PENDING_VERIFICATION'}');
                        if (pending['proposedPhone'] != null) {
                          changes.add(
                              'Proposed phone: ${pending['proposedPhone']}');
                        }
                        if (pending['proposedEmail'] != null) {
                          changes.add(
                              'Proposed email: ${pending['proposedEmail']}');
                        }
                      } else if (action == 'PROFILE_CONTACT_WITHDRAWN') {
                        changes
                            .add('Contact correction withdrawn · not applied');
                        if (pending['proposedPhone'] != null) {
                          changes.add(
                              'Withdrawn proposed phone: ${pending['proposedPhone']}');
                        }
                        if (pending['proposedEmail'] != null) {
                          changes.add(
                              'Withdrawn proposed email: ${pending['proposedEmail']}');
                        }
                      }
                      final isLegacyProposal =
                          action == 'PROFILE_CONTACT_PROPOSED' ||
                              action == 'PROFILE_CONTACT_WITHDRAWN';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            "${item['actorName'] ?? 'Unknown actor'} · ${item['actorRole'] ?? '—'}",
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            "${item['createdAt'] ?? ''}\n${action.isEmpty ? '' : 'Action: ${action.replaceAll('_', ' ')}${isLegacyProposal ? ' · not applied' : ''}\n'}${directCorrection['ownershipVerified'] == false ? 'Ownership: not verified\n' : ''}Reason: ${item['reason'] ?? '—'}\n${changes.join('\n')}"),
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
