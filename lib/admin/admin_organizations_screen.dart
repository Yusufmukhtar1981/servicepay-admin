import 'package:flutter/material.dart';

import 'admin_organizations_api.dart';
import 'admin_permissions.dart';

String organizationStatusPermission(
  String nextStatus, {
  String? currentStatus,
}) {
  final String next = nextStatus.toUpperCase();
  final String current = currentStatus?.toUpperCase() ?? '';
  if (current == 'SUSPENDED' && next == 'VERIFIED') {
    return AdminPermissions.organizationsStatusManage;
  }
  return next == 'VERIFIED' || next == 'REJECTED'
      ? AdminPermissions.organizationsReview
      : AdminPermissions.organizationsStatusManage;
}

dynamic organizationPendingCount(Map<String, dynamic> summary) {
  return summary['pending'] ??
      summary['PENDING_VERIFICATION'] ??
      summary['pendingVerification'];
}

class AdminOrganizationsScreen extends StatefulWidget {
  const AdminOrganizationsScreen({super.key, this.api, this.access});

  final AdminOrganizationsApiClient? api;
  final AdminAccess? access;

  @override
  State<AdminOrganizationsScreen> createState() =>
      _AdminOrganizationsScreenState();
}

class _AdminOrganizationsScreenState extends State<AdminOrganizationsScreen> {
  late final AdminOrganizationsApiClient _api =
      widget.api ?? AdminOrganizationsApi();
  AdminAccess? _access;
  bool _loading = true;
  String? _error;
  String _status = '';
  String _search = '';
  Map<String, dynamic> _summary = <String, dynamic>{};
  List<Map<String, dynamic>> _organizations = <Map<String, dynamic>>[];

  bool _can(String permission) => _access?.has(permission) ?? false;
  String _id(Map<String, dynamic> value) =>
      (value['id'] ?? value['_id'] ?? '').toString();
  String _text(dynamic value, [String fallback = '—']) =>
      value?.toString().trim().isNotEmpty == true ? value.toString() : fallback;

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  Future<void> _loadAccess() async {
    _access = widget.access ?? await AdminSessionStore.loadAccess();
    await _load();
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> body) {
    final dynamic raw = body['organizations'] ?? body['items'] ?? body['data'];
    return raw is List
        ? raw
              .whereType<Map>()
              .map((Map e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait(<Future<Map<String, dynamic>>>[
        _api.summary(),
        _api.list(status: _status.isEmpty ? null : _status, search: _search),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = values[0]['summary'] is Map
            ? Map<String, dynamic>.from(values[0]['summary'] as Map)
            : values[0];
        _organizations = _items(values[1]);
        _loading = false;
      });
    } on AdminOrganizationsApiException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Unable to load organizations. Please try again.';
        });
      }
    }
  }

  Future<void> _statusAction(Map<String, dynamic> item, String status) async {
    if (!_can(
      organizationStatusPermission(
        status,
        currentStatus: item['status']?.toString(),
      ),
    )) {
      return;
    }
    try {
      await _api.updateStatus(_id(item), status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Organization ${status.toLowerCase().replaceAll('_', ' ')}.',
            ),
          ),
        );
      }
      await _load();
    } on AdminOrganizationsApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _openDetails(Map<String, dynamic> item) async {
    if (!_can(AdminPermissions.organizationsView)) return;
    try {
      final response = await _api.details(_id(item));
      final details = response['organization'] is Map
          ? Map<String, dynamic>.from(response['organization'] as Map)
          : item;
      final walletResponse = await _api.wallet(_id(item));
      if (walletResponse['wallet'] is Map) {
        details['wallet'] = Map<String, dynamic>.from(
          walletResponse['wallet'] as Map,
        );
      }
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _DetailsSheet(
          details: details,
          api: _api,
          access: _access!,
          onStatus: (String status) => _statusAction(details, status),
        ),
      );
      await _load();
    } on AdminOrganizationsApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Organizations',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          Text(
            'Review and manage ServicePay organizations',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_can(AdminPermissions.organizationsWithdrawalsView) ||
              _can(AdminPermissions.organizationsSettlementAccountsView) ||
              _can(AdminPermissions.organizationsTreasuryManage)) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _openTreasury(),
                icon: const Icon(Icons.account_balance_outlined),
                label: const Text('Treasury review'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metric(
                'Total',
                _summary['total'] ?? _summary['totalOrganizations'],
              ),
              _metric(
                'Pending verification',
                organizationPendingCount(_summary),
              ),
              _metric('Verified', _summary['VERIFIED'] ?? _summary['verified']),
              _metric('Suspended', _summary['suspended']),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search organizations',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    _search = value.trim();
                    _load();
                  },
                ),
              ),
              DropdownButton<String>(
                value: _status,
                hint: const Text('Status'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('All statuses')),
                  DropdownMenuItem(value: 'DRAFT', child: Text('Draft')),
                  DropdownMenuItem(
                    value: 'PENDING_VERIFICATION',
                    child: Text('Pending verification'),
                  ),
                  DropdownMenuItem(value: 'VERIFIED', child: Text('Verified')),
                  DropdownMenuItem(
                    value: 'SUSPENDED',
                    child: Text('Suspended'),
                  ),
                  DropdownMenuItem(value: 'REJECTED', child: Text('Rejected')),
                ],
                onChanged: (value) {
                  _status = value ?? '';
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_organizations.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: Text('No organizations found.')),
              ),
            )
          else
            ..._organizations.map((item) => _organizationCard(item)),
        ],
      ),
    );
  }

  Widget _metric(String label, dynamic value) => Card(
    child: SizedBox(
      width: 150,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _text(value, '0'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _organizationCard(Map<String, dynamic> item) {
    final status = _text(item['status'], 'DRAFT').toUpperCase();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => _openDetails(item),
        leading: CircleAvatar(
          child: Text(_text(item['name'], 'O').substring(0, 1).toUpperCase()),
        ),
        title: Text(
          _text(item['name'], 'Unnamed organization'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_text(item['contact'] is Map ? (item['contact'] as Map)['email'] : item['email'])} • ${_text(item['memberCount'], '0')} members',
        ),
        trailing: Wrap(
          spacing: 8,
          children: [
            _badge(status),
            if (status == 'PENDING_VERIFICATION' &&
                _can(AdminPermissions.organizationsReview))
              IconButton(
                tooltip: 'Review',
                onPressed: () => _openDetails(item),
                icon: const Icon(Icons.fact_check_outlined),
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String status) => Chip(
    label: Text(
      status,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
    ),
    backgroundColor: status == 'VERIFIED'
        ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1D5544)
              : const Color(0xFFE0F2E9))
        : status == 'SUSPENDED'
        ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF5A3C27)
              : const Color(0xFFFFE9D6))
        : status == 'PENDING_VERIFICATION'
        ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF5A4A20)
              : const Color(0xFFFFF0BF))
        : Theme.of(context).colorScheme.surfaceContainerHighest,
  );

  Future<void> _openTreasury() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TreasuryReviewSheet(api: _api, access: _access!),
    );
  }
}

class _TreasuryReviewSheet extends StatefulWidget {
  const _TreasuryReviewSheet({required this.api, required this.access});
  final AdminOrganizationsApiClient api;
  final AdminAccess access;

  @override
  State<_TreasuryReviewSheet> createState() => _TreasuryReviewSheetState();
}

class _TreasuryReviewSheetState extends State<_TreasuryReviewSheet> {
  bool _loading = true;
  String? _error;
  int _tab = 0;
  String _status = '';
  String _search = '';
  Map<String, dynamic> _summary = <String, dynamic>{};
  List<Map<String, dynamic>> _withdrawals = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _accounts = <Map<String, dynamic>>[];
  Map<String, dynamic> _config = <String, dynamic>{};

  bool get canConfigure =>
      widget.access.has(AdminPermissions.organizationsTreasuryManage);
  bool get canWithdrawalsView =>
      widget.access.has(AdminPermissions.organizationsWithdrawalsView);
  bool get canWithdrawalsReview =>
      widget.access.has(AdminPermissions.organizationsWithdrawalsReview);
  bool get canAccountsView =>
      widget.access.has(AdminPermissions.organizationsSettlementAccountsView);
  bool get canAccountsReview =>
      widget.access.has(AdminPermissions.organizationsSettlementAccountsReview);
  String _configOrganizationId = '';
  bool _configLoading = false;

  @override
  void initState() {
    super.initState();
    _tab = canWithdrawalsView
        ? 0
        : canAccountsView
        ? 1
        : 2;
    _load();
  }

  dynamic _wrappedValue(Map<String, dynamic> response, String key) {
    final direct = response[key];
    if (direct != null) return direct;
    final data = response['data'];
    if (data is Map) {
      return data[key] ?? data['items'] ?? data['results'] ?? data;
    }
    return data;
  }

  Map<String, dynamic> _mapValue(Map<String, dynamic> response, String key) {
    final raw = _wrappedValue(response, key);
    return raw is Map ? Map<String, dynamic>.from(raw) : response;
  }

  List<Map<String, dynamic>> _list(
    Map<String, dynamic> response, [
    String key = 'items',
  ]) {
    final raw = _wrappedValue(response, key);
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait(<Future<Map<String, dynamic>>>[
        if (canWithdrawalsView) widget.api.withdrawalsSummary(),
        if (canWithdrawalsView)
          widget.api.withdrawals(
            status: _status.isEmpty ? null : _status,
            search: _search,
          ),
        if (canAccountsView) widget.api.settlementAccounts(status: 'PENDING'),
      ]);
      if (!mounted) return;
      var index = 0;
      setState(() {
        if (canWithdrawalsView) {
          _summary = _mapValue(responses[index++], 'summary');
          _withdrawals = _list(responses[index++], 'withdrawals');
        }
        if (canAccountsView) {
          _accounts = _list(responses[index++], 'accounts');
        }
        _loading = false;
      });
    } on AdminOrganizationsApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Unable to load treasury review data.';
        });
      }
    }
  }

  String _id(Map<String, dynamic> item) =>
      (item['id'] ?? item['_id'] ?? '').toString();
  String _value(dynamic value) =>
      value?.toString().trim().isNotEmpty == true ? value.toString() : '—';

  Future<String?> _reason({required bool required}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(required ? 'Rejection reason' : 'Review note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter a reason for the audit trail',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (required && controller.text.trim().isEmpty) return;
              Navigator.pop(context, controller.text.trim());
            },
            child: Text(required ? 'Reject' : 'Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _withdrawalAction(
    Map<String, dynamic> item,
    bool approve,
  ) async {
    if (!canWithdrawalsReview) return;
    final reason = await _reason(required: !approve);
    if (reason == null) return;
    try {
      if (approve) {
        await widget.api.approveWithdrawal(_id(item), reason: reason);
      } else {
        await widget.api.rejectWithdrawal(_id(item), reason: reason);
      }
      await _load();
    } on AdminOrganizationsApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _accountAction(Map<String, dynamic> item, bool approve) async {
    if (!canAccountsReview) return;
    final reason = await _reason(required: !approve);
    if (reason == null) return;
    try {
      if (approve) {
        await widget.api.approveSettlementAccount(_id(item), reason: reason);
      } else {
        await widget.api.rejectSettlementAccount(_id(item), reason: reason);
      }
      await _load();
    } on AdminOrganizationsApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Organization treasury',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        _metric(
                          'Pending',
                          _summary['pending'] ?? _summary['pendingApproval'],
                        ),
                        _metric('Processing', _summary['processing']),
                        _metric('Successful', _summary['successful']),
                        _metric('Total value', _summary['totalValue']),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<int>(
                      segments: <ButtonSegment<int>>[
                        if (canWithdrawalsView)
                          const ButtonSegment(
                            value: 0,
                            label: Text('Withdrawals'),
                          ),
                        if (canAccountsView)
                          const ButtonSegment(
                            value: 1,
                            label: Text('Settlement accounts'),
                          ),
                        if (canConfigure)
                          const ButtonSegment(
                            value: 2,
                            label: Text('Limits/config'),
                          ),
                      ],
                      selected: <int>{_tab},
                      onSelectionChanged: (value) =>
                          setState(() => _tab = value.first),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _tab == 0
                          ? _withdrawalList()
                          : _tab == 1
                          ? _accountList()
                          : _configView(),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _metric(String label, dynamic value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            _value(value),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );

  Widget _withdrawalList() => Column(
    children: [
      TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          labelText: 'Search reference, organization or account',
        ),
        onSubmitted: (value) {
          _search = value.trim();
          _load();
        },
      ),
      const SizedBox(height: 8),
      DropdownButton<String>(
        value: _status,
        isExpanded: true,
        items: const [
          DropdownMenuItem(value: '', child: Text('All withdrawal statuses')),
          DropdownMenuItem(
            value: 'PENDING_APPROVAL',
            child: Text('Pending approval'),
          ),
          DropdownMenuItem(value: 'PROCESSING', child: Text('Processing')),
          DropdownMenuItem(value: 'SUCCESS', child: Text('Successful')),
          DropdownMenuItem(value: 'FAILED', child: Text('Failed')),
          DropdownMenuItem(value: 'REJECTED', child: Text('Rejected')),
        ],
        onChanged: (value) {
          setState(() => _status = value ?? '');
          _load();
        },
      ),
      Expanded(
        child: _withdrawals.isEmpty
            ? const Center(child: Text('No organization withdrawals found.'))
            : ListView(
                children: _withdrawals
                    .map(
                      (item) => Card(
                        child: ListTile(
                          title: Text(_value(item['reference'] ?? item['id'])),
                          subtitle: Text(
                            '${_value(item['organizationName'] ?? item['organization'])} • ${_value(item['amount'])} • ${_value(item['status'])}',
                          ),
                          trailing:
                              item['status']?.toString().toUpperCase() ==
                                      'PENDING_APPROVAL' &&
                                  canWithdrawalsReview
                              ? Wrap(
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.check,
                                        color: Colors.green,
                                      ),
                                      onPressed: () =>
                                          _withdrawalAction(item, true),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.red,
                                      ),
                                      onPressed: () =>
                                          _withdrawalAction(item, false),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    ],
  );

  Widget _accountList() => _accounts.isEmpty
      ? const Center(child: Text('No pending settlement accounts.'))
      : ListView(
          children: _accounts
              .map(
                (item) => Card(
                  child: ListTile(
                    title: Text(
                      _value(
                        item['accountName'] ?? item['resolvedAccountName'],
                      ),
                    ),
                    subtitle: Text(
                      '${_value(item['organizationName'] ?? item['organization'])} • ${_value(item['bankName'] ?? item['bank'])} • ${_maskedAccount(item)}',
                    ),
                    trailing: canAccountsReview
                        ? Wrap(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.check,
                                  color: Colors.green,
                                ),
                                onPressed: () => _accountAction(item, true),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.red,
                                ),
                                onPressed: () => _accountAction(item, false),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
              )
              .toList(),
        );

  String _maskedAccount(Map<String, dynamic> item) {
    final value =
        item['accountNumberMasked'] ??
        item['maskedAccountNumber'] ??
        item['accountNumberLast4'] ??
        item['last4'];
    return value == null || value.toString().trim().isEmpty
        ? 'Account number redacted'
        : value.toString();
  }

  Widget _configView() => ListView(
    children: [
      TextField(
        decoration: const InputDecoration(
          labelText: 'Organization ID',
          helperText: 'Select an organization before loading treasury limits.',
        ),
        onChanged: (value) => _configOrganizationId = value.trim(),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _configLoading || _configOrganizationId.isEmpty
            ? null
            : _loadConfig,
        icon: _configLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download_outlined),
        label: const Text('Load organization limits'),
      ),
      ..._config.entries.map(
        (entry) => ListTile(
          title: Text(entry.key),
          subtitle: Text(_value(entry.value)),
        ),
      ),
      if (canConfigure && _config.isNotEmpty)
        OutlinedButton.icon(
          onPressed: _editConfig,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit treasury limits'),
        ),
    ],
  );

  Future<void> _loadConfig() async {
    setState(() => _configLoading = true);
    try {
      final response = await widget.api.treasuryConfig(_configOrganizationId);
      if (!mounted) return;
      setState(() {
        _config = _mapValue(response, 'config');
        _configLoading = false;
      });
    } on AdminOrganizationsApiException catch (e) {
      if (mounted) {
        setState(() => _configLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _editConfig() async {
    final minimum = TextEditingController(
      text: _value(_config['minimumWithdrawal']),
    );
    final maximum = TextEditingController(
      text: _value(_config['maximumWithdrawal']),
    );
    final daily = TextEditingController(text: _value(_config['dailyLimit']));
    final monthly = TextEditingController(
      text: _value(_config['monthlyLimit']),
    );
    final form = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Treasury limits'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              for (final field in <MapEntry<String, TextEditingController>>[
                MapEntry('minimumWithdrawal', minimum),
                MapEntry('maximumWithdrawal', maximum),
                MapEntry('dailyLimit', daily),
                MapEntry('monthlyLimit', monthly),
              ])
                TextField(
                  controller: field.value,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: field.key),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, <String, dynamic>{
              'minimumWithdrawal': minimum.text.trim(),
              'maximumWithdrawal': maximum.text.trim(),
              'dailyLimit': daily.text.trim(),
              'monthlyLimit': monthly.text.trim(),
            }),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    minimum.dispose();
    maximum.dispose();
    daily.dispose();
    monthly.dispose();
    if (form == null) return;
    try {
      await widget.api.updateTreasuryConfig(_configOrganizationId, form);
      await _loadConfig();
    } on AdminOrganizationsApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({
    required this.details,
    required this.api,
    required this.access,
    required this.onStatus,
  });
  final Map<String, dynamic> details;
  final AdminOrganizationsApiClient api;
  final AdminAccess access;
  final ValueChanged<String> onStatus;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  bool _frozen = false;
  bool _busy = false;
  List<Map<String, dynamic>> _tabItems = <Map<String, dynamic>>[];
  String _error = '';

  String get id =>
      (widget.details['id'] ?? widget.details['_id'] ?? '').toString();
  bool can(String p) => widget.access.has(p);

  @override
  void initState() {
    super.initState();
    final dynamic wallet = widget.details['wallet'];
    final String walletStatus = wallet is Map
        ? (wallet['status'] ?? '').toString().toUpperCase()
        : (widget.details['walletStatus'] ?? '').toString().toUpperCase();
    _frozen = walletStatus == 'FROZEN';
  }

  Future<void> _loadTab(int tab) async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final response = tab == 0
          ? await widget.api.members(id)
          : tab == 1
          ? await widget.api.payments(id)
          : await widget.api.audit(id);
      final raw =
          response['members'] ??
          response['payments'] ??
          response['activity'] ??
          response['audit'] ??
          response['items'] ??
          <dynamic>[];
      if (mounted) {
        setState(() {
          _tabItems = raw is List
              ? raw
                    .whereType<Map>()
                    .map((Map e) => Map<String, dynamic>.from(e))
                    .toList()
              : <Map<String, dynamic>>[];
          _busy = false;
        });
      }
    } on AdminOrganizationsApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _freeze() async {
    if (!can(AdminPermissions.organizationsWalletManage)) return;
    setState(() => _busy = true);
    try {
      await widget.api.updateWalletFreeze(id, !_frozen);
      if (mounted) {
        setState(() {
          _frozen = !_frozen;
          _busy = false;
        });
      }
    } on AdminOrganizationsApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.details['name']?.toString() ?? 'Organization',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _badge(
                  (widget.details['status'] ?? 'DRAFT')
                      .toString()
                      .toUpperCase(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _line(
              'Type',
              widget.details['type'] ?? widget.details['organizationType'],
            ),
            _line('Registration', widget.details['registrationNumber']),
            _line('Contact', (widget.details['contact'] as Map?)?['name']),
            _line('Email', (widget.details['contact'] as Map?)?['email']),
            _line('Phone', (widget.details['contact'] as Map?)?['phone']),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.details['status'] == 'PENDING_VERIFICATION' &&
                    can(AdminPermissions.organizationsReview))
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onStatus('VERIFIED');
                    },
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Approve / verify'),
                  ),
                if (widget.details['status'] == 'PENDING_VERIFICATION' &&
                    can(AdminPermissions.organizationsReview))
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onStatus('REJECTED');
                    },
                    child: const Text('Reject'),
                  ),
                if (widget.details['status'] == 'VERIFIED' &&
                    can(AdminPermissions.organizationsStatusManage))
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onStatus('SUSPENDED');
                    },
                    child: const Text('Suspend'),
                  ),
                if (widget.details['status'] == 'SUSPENDED' &&
                    can(AdminPermissions.organizationsStatusManage))
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onStatus('VERIFIED');
                    },
                    child: const Text('Reactivate'),
                  ),
                if (can(AdminPermissions.organizationsWalletManage))
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _freeze,
                    icon: Icon(_frozen ? Icons.lock_open : Icons.lock_outline),
                    label: Text(_frozen ? 'Unfreeze wallet' : 'Freeze wallet'),
                  ),
              ],
            ),
            const Divider(height: 28),
            if (can(AdminPermissions.organizationsMembersView) ||
                can(AdminPermissions.organizationsPaymentsView) ||
                can(AdminPermissions.organizationsAuditView))
              DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    TabBar(
                      onTap: (i) {
                        if ((i == 0 &&
                                !can(
                                  AdminPermissions.organizationsMembersView,
                                )) ||
                            (i == 1 &&
                                !can(
                                  AdminPermissions.organizationsPaymentsView,
                                )) ||
                            (i == 2 &&
                                !can(
                                  AdminPermissions.organizationsAuditView,
                                ))) {
                          return;
                        }
                        _loadTab(i);
                      },
                      tabs: const [
                        Tab(text: 'Members'),
                        Tab(text: 'Payments'),
                        Tab(text: 'Audit'),
                      ],
                    ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    if (_error.isNotEmpty) Text(_error),
                    ..._tabItems.map(
                      (item) => ListTile(
                        dense: true,
                        title: Text(
                          (item['name'] ??
                                  item['fullName'] ??
                                  item['action'] ??
                                  item['reference'] ??
                                  'Record')
                              .toString(),
                        ),
                        subtitle: Text(
                          (item['email'] ??
                                  item['status'] ??
                                  item['createdAt'] ??
                                  '')
                              .toString(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _line(String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value?.toString() ?? '—',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _badge(String status) => Chip(
    label: Text(
      status,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
    ),
    backgroundColor: status == 'VERIFIED'
        ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1D5544)
              : const Color(0xFFE0F2E9))
        : status == 'SUSPENDED'
        ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF5A3C27)
              : const Color(0xFFFFE9D6))
        : status == 'PENDING_VERIFICATION'
        ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF5A4A20)
              : const Color(0xFFFFF0BF))
        : Theme.of(context).colorScheme.surfaceContainerHighest,
  );
}
