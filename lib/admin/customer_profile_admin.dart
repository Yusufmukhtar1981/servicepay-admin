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
  final _proposalReason = TextEditingController();
  final _password = TextEditingController();
  final _proposedPhone = TextEditingController();
  final _proposedEmail = TextEditingController();
  bool _saving = false;
  bool _savingProposal = false;
  bool _withdrawingProposal = false;
  String? _error;
  String? _proposalError;
  Map<String, dynamic>? _proposal;
  late Future<Map<String, dynamic>?> _proposalFuture;
  static const _green = Color(0xFF08783E);
  bool get _busy => _saving || _savingProposal || _withdrawingProposal;
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
    _proposalFuture = widget.api.contactProposal(customerId: _customerId);
    _proposalFuture.then(
      (proposal) {
        if (mounted) setState(() => _proposal = proposal);
      },
      onError: (Object error) {
        if (mounted) {
          setState(() => _proposalError =
              error.toString().replaceFirst('Exception: ', ''));
        }
      },
    );
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _auditReason.dispose();
    _proposalReason.dispose();
    _password.dispose();
    _proposedPhone.dispose();
    _proposedEmail.dispose();
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.updateProfile(
        customerId: _customerId,
        profile: {
          'fullName': _fields['fullName']!.text.trim(),
          'address': _fields['address']!.text.trim(),
          'state': _fields['state']!.text.trim(),
          'lga': _fields['lga']!.text.trim(),
          'zone': _fields['zone']!.text.trim(),
        },
        reason: _auditReason.text.trim(),
        contactVerifications: const {},
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

  Future<void> _refreshProposal({bool clearError = true}) async {
    setState(() {
      if (clearError) _proposalError = null;
      _proposalFuture = widget.api.contactProposal(customerId: _customerId);
    });
    try {
      final result = await _proposalFuture;
      if (mounted) setState(() => _proposal = result);
    } catch (error) {
      if (mounted) {
        setState(() =>
            _proposalError = error.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _submitProposal() async {
    if (_busy) return;
    final phone = _proposedPhone.text.trim();
    final email = _proposedEmail.text.trim();
    if ((phone.isEmpty && email.isEmpty) ||
        _password.text.isEmpty ||
        _proposalReason.text.trim().length < 5) {
      setState(() => _proposalError =
          'Enter a proposed phone or email, your admin password, and a reason of at least 5 characters.');
      return;
    }
    setState(() {
      _savingProposal = true;
      _proposalError = null;
    });
    try {
      // Preserve the operator's displayed CAS version; never adopt a newer
      // version from the preflight read without asking them to review it.
      final latest = await widget.api.contactProposal(customerId: _customerId);
      final displayedId = _proposal?['id']?.toString();
      final latestId = latest?['id']?.toString();
      if (latestId != displayedId) {
        if (mounted) {
          setState(() {
            _proposal = latest;
            _proposalFuture = Future.value(latest);
            _proposalError =
                'The pending correction changed since it was displayed. Review the refreshed details before submitting again.';
          });
        }
        return;
      }
      final result = await widget.api.proposeContactCorrection(
        customerId: _customerId,
        phone: phone.isEmpty ? null : phone,
        email: email.isEmpty ? null : email,
        currentPassword: _password.text,
        reason: _proposalReason.text.trim(),
        expectedProposalId: displayedId,
      );
      if (mounted) {
        setState(() {
          _proposal = result;
          _proposedPhone.clear();
          _proposedEmail.clear();
        });
      }
      await _refreshProposal();
    } catch (error) {
      if (mounted) {
        setState(() =>
            _proposalError = error.toString().replaceFirst('Exception: ', ''));
        final message = _proposalError!;
        await _refreshProposal(clearError: false);
        if (mounted) setState(() => _proposalError = message);
      }
    } finally {
      if (mounted) setState(() => _savingProposal = false);
    }
  }

  Future<void> _withdrawProposal() async {
    if (_busy) return;
    if (_proposal == null) return;
    if (_password.text.isEmpty || _proposalReason.text.trim().length < 5) {
      setState(() => _proposalError =
          'Enter your admin password and a reason of at least 5 characters to withdraw.');
      return;
    }
    setState(() {
      _withdrawingProposal = true;
      _proposalError = null;
    });
    try {
      final latest = await widget.api.contactProposal(customerId: _customerId);
      final displayedId = _proposal?['id']?.toString();
      final latestId = latest?['id']?.toString();
      if (latestId != displayedId) {
        if (mounted) {
          setState(() {
            _proposal = latest;
            _proposalFuture = Future.value(latest);
            _proposalError =
                'The pending correction changed since it was displayed. Review the refreshed details before withdrawing.';
          });
        }
        return;
      }
      await widget.api.withdrawContactCorrection(
        customerId: _customerId,
        currentPassword: _password.text,
        reason: _proposalReason.text.trim(),
        expectedProposalId: displayedId!,
      );
      if (mounted) setState(() => _proposal = null);
      await _refreshProposal();
    } catch (error) {
      if (mounted) {
        setState(() =>
            _proposalError = error.toString().replaceFirst('Exception: ', ''));
        final message = _proposalError!;
        await _refreshProposal(clearError: false);
        if (mounted) setState(() => _proposalError = message);
      }
    } finally {
      if (mounted) setState(() => _withdrawingProposal = false);
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

  Widget _contactProposalPanel() => Container(
        key: const Key('admin-profile-contact-proposal'),
        margin: const EdgeInsets.only(top: 8, bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F7F3),
          border: Border.all(color: const Color(0xFFD5E8DE)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Pending contact correction',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 5),
          const Text(
            'Current contacts remain active for login and recovery. Proposed contacts are unverified and will not replace them.',
            style: TextStyle(height: 1.35),
          ),
          const SizedBox(height: 10),
          Text('Current phone  ${widget.customer['phone'] ?? '—'}'),
          Text('Current email  ${widget.customer['email'] ?? '—'}'),
          const SizedBox(height: 10),
          FutureBuilder<Map<String, dynamic>?>(
            future: _proposalFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return Row(children: [
                  const Expanded(
                      child: Text('Pending correction status unavailable.')),
                  TextButton(
                      onPressed: _refreshProposal, child: const Text('Retry')),
                ]);
              }
              final proposal = snapshot.data;
              if (proposal == null) {
                return const Text('No pending correction.',
                    key: Key('admin-profile-proposal-empty'));
              }
              final status = '${proposal['status'] ?? ''}';
              return Container(
                key: const Key('admin-profile-proposal-status'),
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status == 'STALE'
                            ? 'STALE · not applied'
                            : 'PENDING VERIFICATION · not applied',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF8A5A00)),
                      ),
                      const SizedBox(height: 6),
                      if (proposal['proposedPhone'] != null)
                        Text('Proposed phone  ${proposal['proposedPhone']}'),
                      if (proposal['proposedEmail'] != null)
                        Text('Proposed email  ${proposal['proposedEmail']}'),
                      Text(
                          'Requested by  ${proposal['requestedByName'] ?? '—'}'),
                      Text('Requested  ${proposal['requestedAt'] ?? '—'}'),
                      Text('Reason  ${proposal['reason'] ?? '—'}'),
                    ]),
              );
            },
          ),
          if (_proposalError != null) ...[
            const SizedBox(height: 8),
            Text(_proposalError!,
                style: const TextStyle(color: Color(0xFFB42318))),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _proposedPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Proposed phone (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _proposedEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Proposed email (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Admin password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _proposalReason,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Proposal reason (required, at least 5 characters)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              key: const Key('admin-profile-propose-contact'),
              onPressed: _busy ? null : _submitProposal,
              child: Text(
                _savingProposal ? 'Submitting…' : 'Submit proposal',
              ),
            ),
            if (_proposal != null)
              OutlinedButton(
                key: const Key('admin-profile-withdraw-contact'),
                onPressed: _busy ? null : _withdrawProposal,
                child: Text(_withdrawingProposal
                    ? 'Withdrawing…'
                    : 'Withdraw pending correction'),
              ),
          ]),
        ]),
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
                _field('phone', 'Phone Number', readOnly: true),
                _field('email', 'Email Address', readOnly: true),
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
                _contactProposalPanel(),
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
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            "${item['actorName'] ?? 'Unknown actor'} · ${item['actorRole'] ?? '—'}",
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            "${item['createdAt'] ?? ''}\n${action.isEmpty ? '' : 'Action: ${action.replaceAll('_', ' ')} · not applied\n'}Reason: ${item['reason'] ?? '—'}\n${changes.join('\n')}"),
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
