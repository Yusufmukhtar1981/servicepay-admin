import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';
import 'admin_permissions.dart';

/// Operations Manager scope for Staff Management. Only the support role the
/// backend approves can be created; no role definitions, peer/Head Office
/// role assignment, password resets or financial actions are exposed.
bool canUseScopedStaffControlCentre(AdminAccess access) =>
    AdminAccess.normalizeRole(access.role) == 'HEAD_OFFICE' ||
    access.permissions
        .map((p) => p.trim().toLowerCase())
        .contains(AdminPermissions.operationsStaffManage);

class StaffControlCentreException implements Exception {
  const StaffControlCentreException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class StaffControlCentreOptions {
  const StaffControlCentreOptions({
    this.supportRole,
    this.canCreateSupport = false,
    this.zonalManagers = const [],
    this.managerTypes = const [],
    this.zonalPermissionProfiles = const [],
  });
  final Map<String, dynamic>? supportRole;
  final bool canCreateSupport;
  final List<Map<String, dynamic>> zonalManagers;
  final List<String> managerTypes;

  /// Server-defined Zonal Manager profiles (STANDARD / READ_ONLY). The client
  /// only selects one by id; it never composes permission keys itself.
  final List<ZonalPermissionProfile> zonalPermissionProfiles;

  bool get canCreateZonal => managerTypes.contains('ZONAL_MANAGER');
  bool get canCreateState =>
      managerTypes.contains('STATE_MANAGER') && zonalManagers.isNotEmpty;
  String get supportRoleLabel {
    final r = supportRole;
    if (r == null) return 'Customer Support';
    final d = '${r['displayName'] ?? r['name'] ?? ''}'.trim();
    return d.isEmpty ? 'Customer Support' : d;
  }

  factory StaffControlCentreOptions.fromJson(Map<String, dynamic> j) =>
      StaffControlCentreOptions(
        supportRole: j['supportRole'] is Map
            ? Map<String, dynamic>.from(j['supportRole'])
            : null,
        canCreateSupport: j['canCreateSupport'] == true && j['supportRole'] is Map,
        zonalManagers: j['zonalManagers'] is List
            ? (j['zonalManagers'] as List)
                .whereType<Map>()
                .map(Map<String, dynamic>.from)
                .where((m) => '${m['id'] ?? ''}'.isNotEmpty)
                .toList()
            : const [],
        managerTypes: j['managerTypes'] is List
            ? (j['managerTypes'] as List).map((e) => '$e').toList()
            : const [],
        zonalPermissionProfiles: j['zonalPermissionProfiles'] is List
            ? (j['zonalPermissionProfiles'] as List)
                .whereType<Map>()
                .map((m) => ZonalPermissionProfile.fromJson(
                    Map<String, dynamic>.from(m)))
                .where((p) => ZonalPermissionProfile.allowedIds.contains(p.id))
                .toList()
            : const [],
      );
}

class ZonalPermissionProfile {
  const ZonalPermissionProfile(this.id, this.label, this.permissions);
  static const allowedIds = {'STANDARD', 'READ_ONLY'};
  final String id;
  final String label;
  final List<String> permissions;
  bool get isReadOnly => id == 'READ_ONLY';

  factory ZonalPermissionProfile.fromJson(Map<String, dynamic> j) {
    final id = '${j['id'] ?? ''}'.trim().toUpperCase();
    final label = '${j['label'] ?? ''}'.trim();
    return ZonalPermissionProfile(
      id,
      label.isEmpty ? id : label,
      j['permissions'] is List
          ? (j['permissions'] as List)
              .map((e) => '$e'.trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : const [],
    );
  }
}

/// Maps the existing executive dashboard range keys onto the scoped
/// Head Office dashboard endpoint (day|week|month|year). Custom date ranges
/// are not supported by that endpoint and are rejected rather than faked.
String scopedDashboardRange(String range) => switch (range) {
      'today' || 'day' => 'day',
      '7d' || 'week' => 'week',
      '30d' || 'month' => 'month',
      'year' || '365d' => 'year',
      _ => throw const StaffControlCentreException(
          'Custom date ranges are not available on this dashboard. Choose Today, 7 Days or 30 Days.'),
    };

class StaffManagerPage {
  const StaffManagerPage(this.items, this.page, this.pages, this.total);
  final List<Map<String, dynamic>> items;
  final int page, pages, total;
}

class AdminStaffControlCentreApi {
  AdminStaffControlCentreApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        baseUrl =
            '${(baseUrl ?? AdminApiConfiguration.baseUrl).replaceFirst(RegExp(r'/$'), '')}/admin/staff-workspace/control-centre';

  final http.Client _client;
  final bool _ownsClient;
  final String baseUrl;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, String>? query, Map<String, dynamic>? body}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString('auth_token') ??
            prefs.getString('token') ??
            prefs.getString('admin_token') ??
            '')
        .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
        .trim();
    if (token.isEmpty) {
      throw const StaffControlCentreException(
          'Your login session was not found. Please sign in again.');
    }
    final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters:
            query == null ? null : (Map.of(query)..removeWhere((_, v) => v.isEmpty)));
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };
    final http.Response response;
    switch (method) {
      case 'POST':
        response = await _client
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 30));
      case 'PUT':
        response = await _client
            .put(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 30));
      default:
        response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 30));
    }
    Map<String, dynamic> decoded = {};
    try {
      final v = jsonDecode(response.body);
      if (v is Map) decoded = Map<String, dynamic>.from(v);
    } catch (_) {}
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] == false) {
      final m = '${decoded['message'] ?? ''}'.trim();
      throw StaffControlCentreException(
        m.isNotEmpty && m.length <= 240 && !m.contains('<')
            ? m
            : response.statusCode == 403
                ? 'Your account is not permitted to manage operations staff.'
                : 'Unable to complete this staff request.',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Future<StaffControlCentreOptions> options() async {
    final r = await _request('GET', '/staff/options');
    return StaffControlCentreOptions.fromJson(
        r['data'] is Map ? Map<String, dynamic>.from(r['data']) : {});
  }

  Future<List<Map<String, dynamic>>> loadStaff(
      {String search = '', String status = ''}) async {
    final r = await _request('GET', '/staff',
        query: {'search': search.trim(), 'status': status});
    final raw = r['staff'];
    return raw is List
        ? raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : [];
  }

  Future<Map<String, dynamic>> staffDetail(String id) =>
      _request('GET', '/staff/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> createSupportStaff({
    required String fullName,
    required String phone,
    required String email,
    required String password,
    required String reason,
  }) =>
      _request('POST', '/staff', body: {
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'password': password,
        'confirmed': true,
        'reason': reason.trim(),
      });

  Future<Map<String, dynamic>> updateStaff(
          String id, Map<String, dynamic> values, String reason) =>
      _request('PUT', '/staff/${Uri.encodeComponent(id)}', body: {
        for (final k in const ['fullName', 'phone', 'email'])
          if (values[k] != null) k: '${values[k]}'.trim(),
        'confirmed': true,
        'reason': reason.trim(),
      });

  Future<Map<String, dynamic>> updateStatus(
      String id, String status, String reason) {
    if (status != 'ACTIVE' && status != 'SUSPENDED') {
      throw const StaffControlCentreException('Unsupported status.');
    }
    return _request('PUT', '/staff/${Uri.encodeComponent(id)}/status',
        body: {'status': status, 'confirmed': true, 'reason': reason.trim()});
  }

  Future<Map<String, dynamic>> createZonalManager({
    required String fullName,
    required String phone,
    required String email,
    required String password,
    required String zone,
    required String reason,
    String? permissionProfile,
    String? status,
  }) {
    if (permissionProfile != null &&
        !ZonalPermissionProfile.allowedIds.contains(permissionProfile)) {
      throw const StaffControlCentreException('Unsupported permission profile.');
    }
    if (status != null && status != 'ACTIVE' && status != 'SUSPENDED') {
      throw const StaffControlCentreException('Unsupported status.');
    }
    return _request('POST', '/managers/zonal', body: {
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'password': password,
        'zone': zone.trim(),
        if (permissionProfile != null) 'permissionProfile': permissionProfile,
        if (status != null) 'status': status,
        'confirmed': true,
        'reason': reason.trim(),
      });
  }

  /// Same payload as /admin/dashboard/executive, served for explicit
  /// operations.executive.view holders. Returns the `data` map.
  Future<Map<String, dynamic>> headOfficeDashboard(String range) async {
    final parts =
        range.startsWith('custom:') ? range.split(':') : const <String>[];
    final valid = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (range.startsWith('custom:') &&
        (parts.length != 3 || !valid.hasMatch(parts[1]) || !valid.hasMatch(parts[2]))) {
      throw const StaffControlCentreException('Invalid custom date range.');
    }
    final r = await _request('GET', '/head-office-dashboard',
        query: parts.length == 3
            ? {
                'startDate': '${parts[1]}T00:00:00+01:00',
                'endDate': '${parts[2]}T23:59:59.999+01:00',
              }
            : {'range': scopedDashboardRange(range)});
    return r['data'] is Map ? Map<String, dynamic>.from(r['data']) : {};
  }

  /// Zonal Managers only: atomic, audited, revokes sessions server-side.
  Future<Map<String, dynamic>> updateManagerAccess(String id,
      {required String permissionProfile,
      required String status,
      required String reason}) {
    if (!ZonalPermissionProfile.allowedIds.contains(permissionProfile)) {
      throw const StaffControlCentreException('Unsupported permission profile.');
    }
    if (status != 'ACTIVE' && status != 'SUSPENDED') {
      throw const StaffControlCentreException('Unsupported status.');
    }
    return _request('PUT', '/managers/${Uri.encodeComponent(id)}/access',
        body: {
          'permissionProfile': permissionProfile,
          'status': status,
          'confirmed': true,
          'reason': reason.trim(),
        });
  }

  Future<Map<String, dynamic>> createStateManager({
    required String fullName,
    required String phone,
    required String email,
    required String password,
    required String state,
    required String zonalManagerId,
    required String reason,
  }) =>
      _request('POST', '/managers/state', body: {
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'password': password,
        'state': state.trim(),
        'zonalManagerId': zonalManagerId,
        'confirmed': true,
        'reason': reason.trim(),
      });

  Future<StaffManagerPage> managers(
      {required String role, int page = 1, int limit = 20, String q = ''}) async {
    final r = await _request('GET', '/managers', query: {
      'role': role,
      'page': '$page',
      'limit': '$limit',
      'q': q.trim(),
    });
    final data = r['data'] is Map ? Map<String, dynamic>.from(r['data']) : {};
    final p = data['pagination'] is Map
        ? Map<String, dynamic>.from(data['pagination'])
        : <String, dynamic>{};
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final raw = data['items'];
    return StaffManagerPage(
      raw is List
          ? raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : [],
      n(p['page']) < 1 ? 1 : n(p['page']),
      n(p['pages']),
      n(p['total']),
    );
  }
}

String? _reasonError(String v) {
  final t = v.trim();
  if (t.length < 10) return 'Enter a reason of at least 10 characters.';
  if (t.length > 500) return 'Keep the reason under 500 characters.';
  return null;
}

/// Reason + explicit confirmation for scoped edits/status changes.
Future<String?> showStaffReasonDialog(BuildContext context,
    {required String title, required String summary, required String action}) {
  var reason = '';
  var confirmed = false;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(summary, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('scoped-staff-reason'),
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              onChanged: (v) => setD(() => reason = v),
              decoration: InputDecoration(
                labelText: 'Reason (10–500 characters)',
                errorText: reason.isEmpty ? null : _reasonError(reason),
                border: const OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              key: const Key('scoped-staff-confirm-check'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: confirmed,
              onChanged: (v) => setD(() => confirmed = v == true),
              title: const Text('I confirm this change is authorised.',
                  style: TextStyle(fontSize: 13)),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            key: const Key('scoped-staff-confirm'),
            onPressed: confirmed && _reasonError(reason) == null
                ? () => Navigator.pop(ctx, reason.trim())
                : null,
            child: Text(action),
          ),
        ],
      ),
    ),
  );
}

enum ScopedAccountKind { support, zonal, state }

/// Shared create form for support staff and managers. Submits once and
/// returns true only after the backend confirms creation.
Future<bool> showScopedAccountForm(
  BuildContext context, {
  required AdminStaffControlCentreApi api,
  required StaffControlCentreOptions options,
  required ScopedAccountKind kind,
}) async {
  final created = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _ScopedAccountDialog(api: api, options: options, kind: kind),
  );
  return created == true;
}

class _ScopedAccountDialog extends StatefulWidget {
  const _ScopedAccountDialog(
      {required this.api, required this.options, required this.kind});
  final AdminStaffControlCentreApi api;
  final StaffControlCentreOptions options;
  final ScopedAccountKind kind;
  @override
  State<_ScopedAccountDialog> createState() => _ScopedAccountDialogState();
}

class _ScopedAccountDialogState extends State<_ScopedAccountDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _territory = TextEditingController();
  final _reason = TextEditingController();
  String? _zonalId;
  String? _profileId;
  String _status = 'ACTIVE';
  bool _confirmed = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _name, _phone, _email, _password, _confirmPassword, _territory, _reason
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _title => switch (widget.kind) {
        ScopedAccountKind.support =>
          'Create ${widget.options.supportRoleLabel}',
        ScopedAccountKind.zonal => 'Create Zonal Manager',
        ScopedAccountKind.state => 'Create State Manager',
      };

  Map<String, dynamic>? get _zonal => widget.options.zonalManagers
      .where((m) => '${m['id']}' == _zonalId)
      .firstOrNull;

  String? _required(String? v) =>
      v == null || v.trim().isEmpty ? 'This field is required.' : null;

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate() || !_confirmed) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      switch (widget.kind) {
        case ScopedAccountKind.support:
          await widget.api.createSupportStaff(
              fullName: _name.text,
              phone: _phone.text,
              email: _email.text,
              password: _password.text,
              reason: _reason.text);
        case ScopedAccountKind.zonal:
          await widget.api.createZonalManager(
              fullName: _name.text,
              phone: _phone.text,
              email: _email.text,
              password: _password.text,
              zone: _territory.text,
              reason: _reason.text,
              permissionProfile: _profileId,
              status: _status);
        case ScopedAccountKind.state:
          await widget.api.createStateManager(
              fullName: _name.text,
              phone: _phone.text,
              email: _email.text,
              password: _password.text,
              state: _territory.text,
              zonalManagerId: _zonalId!,
              reason: _reason.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  List<Widget> _zonalControls() {
    final profiles = widget.options.zonalPermissionProfiles;
    final selected =
        profiles.where((p) => p.id == _profileId).firstOrNull;
    return [
      const SizedBox(height: 8),
      if (profiles.isNotEmpty)
        DropdownButtonFormField<String>(
          key: const Key('scoped-zonal-profile'),
          value: _profileId,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Permission profile',
              helperText: 'Defaults to Standard if not selected.'),
          items: profiles
              .map((p) => DropdownMenuItem(
                  value: p.id,
                  child: Text(p.label, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged:
              _submitting ? null : (v) => setState(() => _profileId = v),
        ),
      if (selected != null) ...[
        if (selected.isReadOnly)
          Container(
            key: const Key('scoped-readonly-notice'),
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDBA74))),
            child: const Text(
                'Read-only applies to the whole account: every authenticated change is blocked. The manager can still complete password setup and log out. It cannot be combined with extra permissions or financial authority.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: Color(0xFF9A3412))),
          ),
        Container(
          key: const Key('scoped-profile-permissions'),
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFFF1F5F4),
              borderRadius: BorderRadius.circular(10)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Permissions in this profile',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                if (selected.permissions.isEmpty)
                  const Text('No permissions listed by the server.',
                      style: TextStyle(fontSize: 12))
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: selected.permissions
                        .map((k) => Chip(
                              label: Text(k,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace')),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ))
                        .toList(),
                  ),
              ]),
        ),
      ],
      const SizedBox(height: 10),
      const Align(
          alignment: Alignment.centerLeft,
          child: Text('Account status',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        key: const Key('scoped-zonal-status'),
        segments: const [
          ButtonSegment(value: 'ACTIVE', label: Text('Active')),
          ButtonSegment(value: 'SUSPENDED', label: Text('Suspended')),
        ],
        selected: {_status},
        onSelectionChanged:
            _submitting ? null : (s) => setState(() => _status = s.first),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        title: Text(_title),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_error != null)
                  Container(
                    key: const Key('scoped-form-error'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 10),
                    color: const Color(0xFFFEE2E2),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Color(0xFF991B1B),
                            fontWeight: FontWeight.w700)),
                  ),
                if (widget.kind == ScopedAccountKind.support)
                  const Text(
                      'The account is created with the approved Customer Support role only and must change its password at first login.',
                      style: TextStyle(color: Color(0xFF4B5563), height: 1.4)),
                TextFormField(
                    key: const Key('scoped-name'),
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Full name *'),
                    validator: _required),
                TextFormField(
                    key: const Key('scoped-phone'),
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone *'),
                    validator: _required),
                TextFormField(
                    key: const Key('scoped-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email *'),
                    validator: (v) => _required(v) ??
                        (v!.contains('@') ? null : 'Enter a valid email address.')),
                TextFormField(
                    key: const Key('scoped-password'),
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Temporary password (min 12) *'),
                    validator: (v) => (v ?? '').length < 12
                        ? 'Use at least 12 characters.'
                        : null),
                TextFormField(
                    key: const Key('scoped-password-confirm'),
                    controller: _confirmPassword,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Confirm password *'),
                    validator: (v) =>
                        v != _password.text ? 'Passwords do not match.' : null),
                if (widget.kind == ScopedAccountKind.zonal)
                  TextFormField(
                      key: const Key('scoped-zone'),
                      controller: _territory,
                      decoration: const InputDecoration(labelText: 'Zone *'),
                      validator: _required),
                if (widget.kind == ScopedAccountKind.zonal) ..._zonalControls(),
                if (widget.kind == ScopedAccountKind.state) ...[
                  DropdownButtonFormField<String>(
                    key: const Key('scoped-zonal-manager'),
                    value: _zonalId,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Zonal Manager *'),
                    items: widget.options.zonalManagers
                        .map((m) => DropdownMenuItem(
                            value: '${m['id']}',
                            child: Text(
                                '${m['fullName'] ?? 'Zonal Manager'} · ${m['zone'] ?? 'Zone not set'}',
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: _submitting
                        ? null
                        : (v) => setState(() => _zonalId = v),
                    validator: (v) =>
                        v == null ? 'Select an active Zonal Manager.' : null,
                  ),
                  if (_zonal != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Zone: ${_zonal!['zone'] ?? 'Not set'}',
                            key: const Key('scoped-zone-readonly'),
                            style: const TextStyle(
                                color: Color(0xFF0F766E),
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  TextFormField(
                      key: const Key('scoped-state'),
                      controller: _territory,
                      decoration: const InputDecoration(labelText: 'State *'),
                      validator: _required),
                ],
                const SizedBox(height: 10),
                TextFormField(
                    key: const Key('scoped-reason'),
                    controller: _reason,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Reason (10–500 characters) *'),
                    validator: (v) => _reasonError(v ?? '')),
                CheckboxListTile(
                  key: const Key('scoped-confirm-check'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _confirmed,
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _confirmed = v == true),
                  title: const Text('I confirm this account is authorised.',
                      style: TextStyle(fontSize: 13)),
                ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _submitting ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            key: const Key('scoped-submit'),
            onPressed: _confirmed && !_submitting ? _submit : null,
            child: Text(_submitting ? 'Creating…' : 'Create account'),
          ),
        ],
      ),
    );
  }
}

/// Paged Zonal/State Manager directory for the scoped Operations view.
class ScopedManagerDirectory extends StatefulWidget {
  const ScopedManagerDirectory(
      {super.key, required this.api, this.profiles = const [], this.onChanged});
  final AdminStaffControlCentreApi api;
  final List<ZonalPermissionProfile> profiles;

  /// Called after a successful access change so the parent refreshes options.
  final VoidCallback? onChanged;
  @override
  State<ScopedManagerDirectory> createState() => _ScopedManagerDirectoryState();
}

class _ScopedManagerDirectoryState extends State<ScopedManagerDirectory> {
  final _search = TextEditingController();
  String _role = 'ZONAL_MANAGER';
  StaffManagerPage? _page;
  bool _loading = true;
  String? _error;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(int page) async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.api
          .managers(role: _role, page: page, q: _search.text);
      if (mounted && gen == _gen) setState(() => _page = r);
    } catch (e) {
      if (mounted && gen == _gen) setState(() => _error = '$e');
    } finally {
      if (mounted && gen == _gen) setState(() => _loading = false);
    }
  }

  Future<void> _editAccess(Map<String, dynamic> m) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ManagerAccessDialog(
          api: widget.api, manager: m, profiles: widget.profiles),
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('Access updated. Active sessions were signed out.')));
    widget.onChanged?.call();
    await _load(_page?.page ?? 1);
  }

  @override
  Widget build(BuildContext context) {
    final p = _page;
    return Container(
      key: const Key('scoped-manager-directory'),
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Manager directory',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          key: const Key('scoped-manager-role'),
          segments: const [
            ButtonSegment(value: 'ZONAL_MANAGER', label: Text('Zonal')),
            ButtonSegment(value: 'STATE_MANAGER', label: Text('State')),
          ],
          selected: {_role},
          onSelectionChanged: (s) {
            setState(() => _role = s.first);
            _load(1);
          },
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('scoped-manager-search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(1),
          decoration: InputDecoration(
              isDense: true,
              hintText: 'Search managers',
              prefixIcon: const Icon(Icons.search_rounded),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
        ),
        const SizedBox(height: 10),
        if (_loading)
          ...List.generate(
              2,
              (_) => Container(
                  height: 54,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F4),
                      borderRadius: BorderRadius.circular(12))))
        else if (_error != null)
          Row(children: [
            Expanded(
                child: Text(_error!,
                    key: const Key('scoped-manager-error'),
                    style: const TextStyle(color: Color(0xFF991B1B)))),
            TextButton(
                onPressed: () => _load(p?.page ?? 1),
                child: const Text('Retry')),
          ])
        else if (p == null || p.items.isEmpty)
          const Padding(
            key: Key('scoped-manager-empty'),
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No managers found.',
                style: TextStyle(color: Color(0xFF6B7280))),
          )
        else ...[
          ...p.items.map((m) => ListTile(
                key: Key('scoped-manager-${m['id']}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hub_outlined, color: Color(0xFF0F766E)),
                title: Text('${m['fullName'] ?? 'Manager'}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text([
                  m['zone'],
                  m['state'],
                  m['phone'],
                  m['email'],
                ].where((v) => v != null && '$v'.isNotEmpty).join(' · ')),
                trailing: _role == 'ZONAL_MANAGER' &&
                        '${m['role'] ?? 'ZONAL_MANAGER'}' == 'ZONAL_MANAGER'
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                              '${m['status'] ?? ''} · ${m['permissionProfile'] ?? 'STANDARD'}',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w900)),
                          InkWell(
                            key: Key('scoped-manager-access-${m['id']}'),
                            onTap: () => _editAccess(m),
                            child: const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text('Access & status',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF0F766E),
                                      fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ])
                    : Text('${m['status'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w900)),
              )),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(p.pages > 0 ? 'Page ${p.page} of ${p.pages}' : 'Page ${p.page}',
                style: const TextStyle(fontSize: 12)),
            IconButton(
                tooltip: 'Previous page',
                onPressed: p.page > 1 ? () => _load(p.page - 1) : null,
                icon: const Icon(Icons.chevron_left)),
            IconButton(
                key: const Key('scoped-manager-next'),
                tooltip: 'Next page',
                onPressed: p.page < p.pages ? () => _load(p.page + 1) : null,
                icon: const Icon(Icons.chevron_right)),
          ]),
        ],
      ]),
    );
  }
}

class _ManagerAccessDialog extends StatefulWidget {
  const _ManagerAccessDialog(
      {required this.api, required this.manager, required this.profiles});
  final AdminStaffControlCentreApi api;
  final Map<String, dynamic> manager;
  final List<ZonalPermissionProfile> profiles;
  @override
  State<_ManagerAccessDialog> createState() => _ManagerAccessDialogState();
}

class _ManagerAccessDialogState extends State<_ManagerAccessDialog> {
  late String _profile;
  late String _status;
  final _reason = TextEditingController();
  bool _confirmed = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = '${widget.manager['permissionProfile'] ?? 'STANDARD'}'.toUpperCase();
    _profile = ZonalPermissionProfile.allowedIds.contains(p) ? p : 'STANDARD';
    final st = '${widget.manager['status'] ?? 'ACTIVE'}'.toUpperCase();
    _status = st == 'SUSPENDED' ? 'SUSPENDED' : 'ACTIVE';
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.updateManagerAccess('${widget.manager['id']}',
          permissionProfile: _profile, status: _status, reason: _reason.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = {for (final p in widget.profiles) p.id: p};
    final selected = labels[_profile];
    final canSave =
        _confirmed && !_saving && _reasonError(_reason.text) == null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text('Access & status · ${widget.manager['fullName'] ?? 'Zonal Manager'}'),
        content: SizedBox(
          width: 460,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null)
                  Container(
                    key: const Key('scoped-access-error'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 10),
                    color: const Color(0xFFFEE2E2),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Color(0xFF991B1B),
                            fontWeight: FontWeight.w700)),
                  ),
                const Text('Permission profile',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  key: const Key('scoped-access-profile'),
                  segments: [
                    for (final id in const ['STANDARD', 'READ_ONLY'])
                      ButtonSegment(
                          value: id,
                          label: Text(labels[id]?.label ??
                              (id == 'STANDARD' ? 'Standard' : 'Read only'))),
                  ],
                  selected: {_profile},
                  onSelectionChanged: _saving
                      ? null
                      : (v) => setState(() => _profile = v.first),
                ),
                if (_profile == 'READ_ONLY')
                  const Padding(
                    key: Key('scoped-access-readonly-notice'),
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                        'Read-only blocks every authenticated change on this account. Password setup and log out remain available. Switch back to Standard here to restore normal access.',
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: Color(0xFF9A3412))),
                  ),
                if (selected != null && selected.permissions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(selected.permissions.join(', '),
                        key: const Key('scoped-access-permissions'),
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace')),
                  ),
                const SizedBox(height: 12),
                const Text('Account status',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  key: const Key('scoped-access-status'),
                  segments: const [
                    ButtonSegment(value: 'ACTIVE', label: Text('Active')),
                    ButtonSegment(value: 'SUSPENDED', label: Text('Suspended')),
                  ],
                  selected: {_status},
                  onSelectionChanged: _saving
                      ? null
                      : (v) => setState(() => _status = v.first),
                ),
                const SizedBox(height: 8),
                const Text(
                    'Saving signs the manager out of all sessions. Balances and hierarchy are not changed.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF4B5563))),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('scoped-access-reason'),
                  controller: _reason,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  enabled: !_saving,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Reason (10–500 characters)',
                    errorText: _reason.text.isEmpty
                        ? null
                        : _reasonError(_reason.text),
                    border: const OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  key: const Key('scoped-access-confirm-check'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _confirmed,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _confirmed = v == true),
                  title: const Text('I confirm this access change is authorised.',
                      style: TextStyle(fontSize: 13)),
                ),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            key: const Key('scoped-access-save'),
            onPressed: canSave ? _save : null,
            child: Text(_saving ? 'Saving…' : 'Save access'),
          ),
        ],
      ),
    );
  }
}
