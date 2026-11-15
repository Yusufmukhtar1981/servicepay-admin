import 'package:flutter/material.dart';

import 'admin_control_center_download.dart';
import 'admin_permissions.dart';
import 'admin_referrals_api.dart';

const _referralInk = Color(0xFF17352B);
const _referralGreen = Color(0xFF08783E);

/// Privacy-safe Head Office referral qualification and reward report.
class AdminReferralsScreen extends StatefulWidget {
  const AdminReferralsScreen({super.key, this.api, this.initialAccess});

  final AdminReferralsApi? api;
  final AdminAccess? initialAccess;

  @override
  State<AdminReferralsScreen> createState() => _AdminReferralsScreenState();
}

typedef AdminReferralMonitoringScreen = AdminReferralsScreen;
typedef AdminReferralScreen = AdminReferralsScreen;

class _AdminReferralsScreenState extends State<AdminReferralsScreen> {
  late final AdminReferralsApi _api;
  late final bool _ownsApi;
  final _search = TextEditingController();
  AdminAccess? _access;
  bool _loading = true;
  String? _error;
  String _category = '';
  String _rewardStatus = '';
  String _commissionType = '';
  Map<String, dynamic> _programme = <String, dynamic>{};
  Map<String, dynamic> _readiness = <String, dynamic>{};
  bool _canManageProgramme = false;
  bool _programmeChecked = false;
  bool _programmeAvailable = false;
  String? _programmeError;
  bool _commissionsChecked = false;
  bool _commissionsAvailable = false;
  bool _commissionsLoading = false;
  String? _commissionsError;
  List<Map<String, dynamic>> _commissions = <Map<String, dynamic>>[];
  Map<String, dynamic> _commissionSummary = <String, dynamic>{};
  int _commissionTotal = 0;
  int _commissionPage = 1;
  int _commissionPages = 1;
  int _page = 1;
  static const _limit = 50;
  int _total = 0;
  Map<String, dynamic> _summary = <String, dynamic>{};
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? AdminReferralsApi();
    _ownsApi = widget.api == null;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    if (_ownsApi) _api.close();
    super.dispose();
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];

  static num _number(dynamic value) =>
      value is num ? value : num.tryParse('$value') ?? 0;

  static String _text(dynamic value, [String fallback = '—']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  static String _status(dynamic value, [String fallback = 'PENDING']) =>
      _text(value, fallback).replaceAll('_', ' ');

  String _earnedBreakdown(Map<String, dynamic> row) =>
      'Registration ₦${_number(row['registrationBonusEarned']).toStringAsFixed(0)}'
      ' · Transactions ₦${_number(row['transactionCommissionsEarned']).toStringAsFixed(0)}';

  Map<String, dynamic> _payload(
    Map<String, dynamic> result, [
    String key = '',
  ]) {
    final value = key.isEmpty ? result : result[key];
    if (value is Map) return _map(value);
    final data = result['data'];
    if (data is Map) {
      final nested = key.isEmpty ? data : data[key];
      return nested is Map ? _map(nested) : _map(data);
    }
    return result;
  }

  List<Map<String, dynamic>> _rowsFrom(Map<String, dynamic> result) {
    final direct = result['rows'] ??
        result['items'] ??
        result['referrals'] ??
        (result['data'] is List ? result['data'] : null);
    if (direct is List) return _maps(direct);
    final data = result['data'];
    return data is Map
        ? _maps(data['rows'] ?? data['items'] ?? data['referrals'])
        : <Map<String, dynamic>>[];
  }

  bool _canView(AdminAccess access) =>
      access.has(AdminPermissions.referralsView);

  bool get _isActiveV2 =>
      _number(_programme['version']).toInt() >= 2 &&
      (_programme['enabled'] == true ||
          _text(_programme['activatedAt'], '').isNotEmpty);

  Future<void> _applyFilters() async {
    _commissionPage = 1;
    await _load(page: 1);
  }

  Future<void> _load({int? page}) async {
    final access = widget.initialAccess ?? await AdminSessionStore.loadAccess();
    if (!_canView(access)) {
      if (!mounted) return;
      setState(() {
        _access = access;
        _loading = false;
        _error = 'You do not have permission to view referral monitoring.';
      });
      return;
    }
    if (mounted) {
      setState(() {
        _access = access;
        _loading = true;
        _error = null;
        if (page != null) _page = page;
        _programmeChecked = false;
        _commissionsChecked = false;
        _programmeError = null;
        _commissionsError = null;
      });
    }
    try {
      final responses = await Future.wait(<Future<Map<String, dynamic>>>[
        _api.summary(),
        _api.search(
          query: _search.text,
          category: _isActiveV2 ? '' : _category,
          rewardStatus: _isActiveV2 ? '' : _rewardStatus,
          page: _page,
          limit: _limit,
        ),
      ]);
      final listing = responses[1];
      if (!mounted) return;
      setState(() {
        _summary = _payload(responses[0], 'summary');
        _rows = _rowsFrom(listing);
        _total = (_number(listing['total'] ?? listing['count'])).toInt();
        if (_total == 0 && _rows.isNotEmpty) _total = _rows.length;
        _loading = false;
      });
      await _loadProgramme();
      await _loadCommissions();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  bool _isNotFound(Object error) =>
      error is AdminReferralsException && error.statusCode == 404;

  String _errorText(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Future<void> _loadProgramme() async {
    try {
      final response = await _api.programme();
      if (!mounted) return;
      setState(() {
        _programme = _payload(response, 'programme');
        _readiness = _map(response['readiness']);
        _canManageProgramme = response['canManage'] == true &&
            (_access?.has(AdminPermissions.settingsUpdate) ?? false);
        _programmeAvailable = true;
        _programmeChecked = true;
        _programmeError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _programmeAvailable = !_isNotFound(error);
        _programmeChecked = true;
        _canManageProgramme = false;
        _programmeError = _isNotFound(error) ? null : _errorText(error);
      });
    }
  }

  Future<void> _loadCommissions({int? page}) async {
    if (!mounted) return;
    setState(() {
      if (page != null) _commissionPage = page;
      _commissionsLoading = true;
      _commissionsChecked = false;
      _commissionsError = null;
    });
    try {
      final result = await _api.commissions(
        query: _search.text,
        rewardType: _commissionType,
        page: _commissionPage,
        limit: _limit,
      );
      if (!mounted) return;
      setState(() {
        _commissions = _rowsFrom(result);
        _commissionTotal = _number(result['total']).toInt();
        _commissionPages = (_number(
          result['pages'] ?? ((_commissionTotal + _limit - 1) ~/ _limit),
        ).toInt())
            .clamp(1, 100000);
        _commissionSummary = _map(result['summary']);
        _commissionsAvailable = true;
        _commissionsChecked = true;
        _commissionsLoading = false;
        _commissionsError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _commissionsAvailable = !_isNotFound(error);
        _commissionsChecked = true;
        _commissionsLoading = false;
        _commissionsError = _isNotFound(error) ? null : _errorText(error);
      });
    }
  }

  Future<void> _manageProgramme() async {
    if (!_canManageProgramme) return;
    final enabled = _programme['enabled'] == true;
    final registration = TextEditingController(
      text: '${_programme['registrationBonus'] ?? 100}',
    );
    final commission = TextEditingController(
      text: '${_programme['transactionCommission'] ?? 1}',
    );
    final reason = TextEditingController();
    final allServices = <String>[
      'AIRTIME',
      'DATA',
      'ELECTRICITY',
      'CABLE',
      'EXAM_PIN',
      'DELIVERY',
      'MARKETPLACE',
      'ID_VERIFICATION',
      'EDUPAY',
      'INTERSTATE_LOGISTICS',
    ];
    final selected = Set<String>.from(
      (_programme['eligibleServices'] is List
              ? _programme['eligibleServices'] as List
              : allServices)
          .map((value) => '$value'),
    );
    bool nextEnabled = !enabled;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Referral programme controls'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        nextEnabled ? 'Programme active' : 'Programme paused'),
                    value: nextEnabled,
                    onChanged: (value) =>
                        setDialogState(() => nextEnabled = value),
                  ),
                  if (nextEnabled)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Activation applies to future activity only. No past registrations or transactions will be backfilled.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  TextField(
                    controller: registration,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Registration bonus (NGN)'),
                  ),
                  TextField(
                    controller: commission,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Per-transaction commission (NGN)'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Eligible paid services',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  Wrap(
                    spacing: 4,
                    children: allServices
                        .map((service) => FilterChip(
                              label: Text(service.replaceAll('_', ' ')),
                              selected: selected.contains(service),
                              onSelected: (value) => setDialogState(() {
                                value
                                    ? selected.add(service)
                                    : selected.remove(service);
                              }),
                            ))
                        .toList(),
                  ),
                  TextField(
                    controller: reason,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'Reason (required)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                reason.text.trim().isNotEmpty &&
                    num.tryParse(registration.text) != null &&
                    num.tryParse(commission.text) != null,
              ),
              child: const Text('Save programme'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      registration.dispose();
      commission.dispose();
      reason.dispose();
      return;
    }
    try {
      final response = await _api.updateProgramme(
        enabled: nextEnabled,
        registrationBonus: num.parse(registration.text),
        transactionCommission: num.parse(commission.text),
        eligibleServices: selected.toList(),
        reason: reason.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _programme = _payload(response, 'programme');
        _readiness = _map(response['readiness']);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Referral programme updated.')),
      );
      await _load(page: _page);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update programme: $error')),
        );
      }
    } finally {
      registration.dispose();
      commission.dispose();
      reason.dispose();
    }
  }

  Future<void> _exportCommissions() async {
    try {
      final report = await _api.exportCommissions(
        query: _search.text,
        rewardType: _commissionType,
      );
      await downloadControlCenterCsv(
          report.csv, 'servicepay-referral-commissions.csv');
      if (mounted && report.limit != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export is bounded to ${report.limit} rows.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to export report: $error')),
        );
      }
    }
  }

  dynamic _summaryValue(List<String> keys) {
    dynamic find(Map<String, dynamic> value) {
      for (final key in keys) {
        if (value.containsKey(key)) return value[key];
      }
      return null;
    }

    final metrics = _map(_summary['metrics']);
    final counts = _map(_summary['counts']);
    return find(_summary) ?? find(metrics) ?? find(counts);
  }

  String _money(dynamic value) => '₦${_number(value).toStringAsFixed(0)}';

  String _customerName(Map<String, dynamic> row) {
    final customer = _map(row['customer']);
    return _text(
      customer['firstName'] ?? row['firstName'] ?? row['name'],
      'Referred customer',
    );
  }

  String _customerCode(Map<String, dynamic> row) {
    final customer = _map(row['customer']);
    return _text(
      customer['id'] ?? customer['_id'] ?? row['customerId'] ?? row['id'],
      '',
    );
  }

  Map<String, dynamic> _progress(Map<String, dynamic> row) =>
      _map(row['progress'] ?? row['qualificationProgress']);

  String _progressLabel(Map<String, dynamic> row) {
    final progress = _progress(row);
    if (progress.isEmpty) return 'No qualification activity';
    return progress.entries
        .map((entry) => '${entry.key} ${_number(entry.value).toInt()}/10')
        .join(' · ');
  }

  double _progressValue(Map<String, dynamic> row) {
    final values = _progress(row).values.map(_number);
    if (values.isEmpty) return 0;
    return (values.reduce((a, b) => a > b ? a : b) / 10).clamp(0, 1).toDouble();
  }

  String _rewardLabel(Map<String, dynamic> row) {
    final value = _text(row['rewardStatus'], 'PENDING').toUpperCase();
    if (value == 'AWARDED' || value == 'PAID') return 'Paid';
    if (value == 'NOT_ISSUED' || value == 'UNPAID') return 'Pending';
    return value.replaceAll('_', ' ');
  }

  int _totalReferrals() {
    final value = _summaryValue(<String>[
      'totalReferrals',
      'attributedReferrals',
      'total',
    ]);
    return value is List ? value.length : _number(value ?? _total).toInt();
  }

  int _statusCount(String name) {
    final value = _summaryValue(<String>[
      name.toLowerCase(),
      '${name.toLowerCase()}Referrals',
      '${name.toLowerCase()}Count',
    ]);
    if (value != null) return _number(value).toInt();
    return _rows
        .where(
          (row) => _text(row['qualificationStatus'], '').toUpperCase() == name,
        )
        .length;
  }

  String _rewardReference(Map<String, dynamic> row) =>
      _text(row['rewardReference'] ?? row['ledgerReference'], '');

  Future<void> _details(Map<String, dynamic> row) async {
    final id = _customerCode(row);
    if (id.isEmpty) return;
    try {
      final responses = await Future.wait(<Future<Map<String, dynamic>>>[
        _api.progress(id),
        _api.audit(id),
      ]);
      final progress = _payload(responses[0]);
      final audit = responses[1];
      final history = _maps(
        audit['auditHistory'] ??
            audit['history'] ??
            audit['events'] ??
            (audit['data'] is List ? audit['data'] : null),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${_customerName(row)} · Referral details'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _detail('Customer code', id),
                  if (_isActiveV2) ...[
                    _detail(
                      'Verified registration',
                      (progress['verified'] ?? row['verified']) == true
                          ? 'Verified'
                          : 'Not verified',
                    ),
                    _detail(
                      'Successful paid transactions',
                      '${_number(progress['successfulTransactions'] ?? row['successfulTransactions']).toInt()}',
                    ),
                    _detail(
                      'Registration bonus earned',
                      _money(progress['registrationBonusEarned'] ??
                          row['registrationBonusEarned']),
                    ),
                    _detail(
                      'Transaction commissions earned',
                      _money(progress['transactionCommissionsEarned'] ??
                          row['transactionCommissionsEarned']),
                    ),
                  ] else
                    _detail(
                      'Qualification',
                      _status(
                        progress['qualificationStatus'] ??
                            row['qualificationStatus'],
                      ),
                    ),
                  _detail(
                    'Reward status',
                    _rewardLabel(<String, dynamic>{
                      'rewardStatus':
                          progress['rewardStatus'] ?? row['rewardStatus'],
                    }),
                  ),
                  _detail(
                    'Reward reference',
                    _text(
                      progress['ledgerReference'] ??
                          progress['rewardReference'] ??
                          row['ledgerReference'] ??
                          _rewardReference(row),
                    ),
                  ),
                  if (!_isActiveV2) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Qualification progress',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(_progressLabel(progress.isEmpty ? row : progress)),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Audit history',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (history.isEmpty)
                    const Text('No audit events returned.')
                  else
                    ...history.map(
                      (event) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history_rounded),
                        title: Text(_text(
                          event['event'] ?? event['action'] ?? event['type'],
                          'Audit event',
                        )),
                        subtitle: Text([
                          _text(event['createdAt'] ??
                              event['occurredAt'] ??
                              event['timestamp']),
                          if (event['reference'] != null)
                            'Ref ${_text(event['reference'])}',
                          if (event['amount'] != null) _money(event['amount']),
                          if (event['status'] != null) _status(event['status']),
                        ].join(' · ')),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load referral history: $error')),
        );
      }
    }
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 145,
              child:
                  Text(label, style: const TextStyle(color: Color(0xFF667085))),
            ),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );

  Widget _metric(String title, String value, IconData icon) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: <Widget>[
              Icon(icon, color: _referralGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: const TextStyle(color: Color(0xFF667085))),
                    Text(
                      value,
                      style: const TextStyle(
                        color: _referralInk,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _filters() => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 250,
                child: TextField(
                  controller: _search,
                  onSubmitted: (_) => _applyFilters(),
                  decoration: InputDecoration(
                    labelText: 'Search referrals',
                    hintText: _isActiveV2
                        ? 'Name, phone or referral code'
                        : 'Name or customer code',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              if (!_isActiveV2)
                DropdownButton<String>(
                  value: _category,
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: '', child: Text('All categories')),
                    DropdownMenuItem(value: 'DATA', child: Text('Data')),
                    DropdownMenuItem(
                        value: 'DELIVERY', child: Text('Delivery')),
                    DropdownMenuItem(
                      value: 'MARKETPLACE',
                      child: Text('Marketplace'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _category = value ?? '');
                    _applyFilters();
                  },
                ),
              if (!_isActiveV2)
                DropdownButton<String>(
                  value: _rewardStatus,
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: '', child: Text('All rewards')),
                    DropdownMenuItem(value: 'AWARDED', child: Text('Paid')),
                  ],
                  onChanged: (value) {
                    setState(() => _rewardStatus = value ?? '');
                    _applyFilters();
                  },
                ),
              DropdownButton<String>(
                value: _commissionType,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                      value: '', child: Text('All commission types')),
                  DropdownMenuItem(
                      value: 'REGISTRATION', child: Text('Registration')),
                  DropdownMenuItem(
                      value: 'TRANSACTION', child: Text('Transaction')),
                ],
                onChanged: (value) {
                  setState(() => _commissionType = value ?? '');
                  _applyFilters();
                },
              ),
              FilledButton.icon(
                onPressed: _applyFilters,
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Apply filters'),
              ),
            ],
          ),
        ),
      );

  Widget _programmePanel() {
    if (_programmeError != null) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Referral programme unavailable',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(_programmeError!),
              TextButton.icon(
                onPressed: _loadProgramme,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry programme'),
              ),
            ],
          ),
        ),
      );
    }
    final enabled = _programme['enabled'] == true;
    final blockers = _readiness['blockers'] is List
        ? (_readiness['blockers'] as List).map((value) => '$value').toList()
        : <String>[];
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Referral programme',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Chip(
                  label: Text(enabled ? 'ACTIVE' : 'PAUSED'),
                  backgroundColor: enabled
                      ? const Color(0xFFE3F1E8)
                      : const Color(0xFFF0F1EF),
                ),
                if (_canManageProgramme)
                  FilledButton.icon(
                    onPressed: _manageProgramme,
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Manage programme'),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              '₦${_number(_programme['registrationBonus'] ?? 100).toStringAsFixed(0)} once per verified registration · '
              '₦${_number(_programme['transactionCommission'] ?? 1).toStringAsFixed(0)} per eligible paid transaction',
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            if (blockers.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text('Readiness blockers: ${blockers.join(' · ')}',
                  style: const TextStyle(color: Color(0xFF8A4D20))),
            ],
            const SizedBox(height: 5),
            const Text(
                'Changes affect future activity only; no backfill is performed.',
                style: TextStyle(color: Color(0xFF667085), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _commissionPanel() {
    if (_commissionsError != null) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Commission report unavailable',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(_commissionsError!),
              TextButton.icon(
                onPressed: () => _loadCommissions(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry commission report'),
              ),
            ],
          ),
        ),
      );
    }
    final summary = _commissionSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Commission ledger',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            OutlinedButton.icon(
              onPressed: _exportCommissions,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export CSV'),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _ledgerTotal(
              'Registration bonuses', summary['registrationBonusesEarned']),
          _ledgerTotal('Transaction commissions',
              summary['transactionCommissionsEarned']),
          _ledgerTotal(
              'Net referral earnings', summary['totalReferralEarnings']),
          _ledgerTotal('Legacy rewards', summary['legacyRewards']),
        ]),
        const SizedBox(height: 9),
        Text(
            'Showing ${_commissions.length} of $_commissionTotal commission entries',
            style: const TextStyle(color: Color(0xFF667085), fontSize: 12)),
        if (_commissions.isEmpty)
          const Card(
            elevation: 0,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No commission entries match these filters.'),
            ),
          )
        else
          ..._commissions.map(_commissionRow),
        if (_commissionsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_commissionTotal > _limit || _commissionPages > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous commission page',
                onPressed: _commissionsLoading || _commissionPage <= 1
                    ? null
                    : () => _loadCommissions(page: _commissionPage - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Commission page $_commissionPage of $_commissionPages'),
              IconButton(
                tooltip: 'Next commission page',
                onPressed: _commissionsLoading ||
                        _commissionPage * _limit >= _commissionTotal
                    ? null
                    : () => _loadCommissions(page: _commissionPage + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }

  Widget _ledgerTotal(String label, dynamic value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
            color: const Color(0xFFEAF1EB),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF667085))),
          Text(_money(value),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _commissionRow(Map<String, dynamic> row) {
    final referrer = _map(row['referrer']);
    final referred = _map(row['referredCustomer']);
    final debit = _text(row['direction'], 'CREDIT').toUpperCase() == 'DEBIT';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(_text(row['rewardType'], 'REWARD').replaceAll('_', ' '),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: _referralGreen)),
              Text(_text(row['date'])),
              Text('${debit ? '−' : '+'}${_money(row['amount'])}',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: debit ? const Color(0xFF9B4D3A) : _referralGreen)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
              '${_text(referrer['fullName'], 'Referrer')} · ${_text(referrer['referralCode'], 'No code')}'),
          Text('Referred: ${_text(referred['fullName'], 'Customer')}'),
          Text(
              'Reference: ${_text(row['reference'])} · Source: ${_text(row['sourceReference'])}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
        ]),
      ),
    );
  }

  Widget _row(Map<String, dynamic> row) => Card(
        elevation: 0,
        child: InkWell(
          onTap: () => _details(row),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _customerName(row),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      _status(_isActiveV2
                          ? row['rewardStatus']
                          : row['qualificationStatus']),
                      style: const TextStyle(
                        color: _referralGreen,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (_customerCode(row).isNotEmpty)
                  Text(
                    'Code: ${_customerCode(row)}',
                    style:
                        const TextStyle(color: Color(0xFF667085), fontSize: 12),
                  ),
                const SizedBox(height: 8),
                if (_isActiveV2) ...[
                  Wrap(
                    spacing: 14,
                    runSpacing: 5,
                    children: [
                      Text((row['verified'] == true)
                          ? 'Verified registration'
                          : 'Registration not verified'),
                      Text(
                          '${_number(row['successfulTransactions']).toInt()} successful paid transactions'),
                      Text(_earnedBreakdown(row)),
                      Text('Reward: ${_rewardLabel(row)}'),
                      if (_text(row['ledgerReference'], '').isNotEmpty)
                        Text('Ledger: ${_text(row['ledgerReference'])}'),
                    ],
                  ),
                ] else ...[
                  Wrap(
                    spacing: 14,
                    runSpacing: 5,
                    children: <Widget>[
                      Text(
                          'Category: ${_text(row['category'], 'Not selected')}'),
                      Text('Reward: ${_rewardLabel(row)}'),
                      if (_rewardReference(row).isNotEmpty)
                        Text('Ledger: ${_rewardReference(row)}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _progressValue(row),
                    minHeight: 7,
                    backgroundColor: const Color(0xFFE6EEE8),
                    color: _referralGreen,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _progressLabel(row),
                    style: const TextStyle(color: Color(0xFF667085)),
                  ),
                ],
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'View audit history',
                    style: TextStyle(
                      color: _referralGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final denied = _access != null && !_canView(_access!);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F3),
      appBar: AppBar(
        title: const Text(
          'Referral Monitoring',
          style: TextStyle(fontWeight: FontWeight.w800, color: _referralInk),
        ),
        backgroundColor: const Color(0xFFF4F8F3),
        foregroundColor: _referralInk,
        elevation: 0,
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(page: _page),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: denied
          ? Center(child: Text(_error ?? 'Access denied.'))
          : _loading && _rows.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _rows.isEmpty
                  ? Center(child: Text(_error!))
                  : RefreshIndicator(
                      onRefresh: () => _load(page: _page),
                      child: LayoutBuilder(
                        builder: (context, constraints) => ListView(
                          padding: EdgeInsets.all(
                              constraints.maxWidth < 600 ? 12 : 22),
                          children: <Widget>[
                            const Text(
                              'Privacy-safe qualification, reward and audit oversight',
                              style: TextStyle(color: Color(0xFF667085)),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: <Widget>[
                                _metric(
                                  'Total Referrals',
                                  '${_totalReferrals()}',
                                  Icons.people_alt_outlined,
                                ),
                                _metric(
                                  'Pending',
                                  '${_statusCount('PENDING')}',
                                  Icons.hourglass_empty,
                                ),
                                _metric(
                                  'Qualified',
                                  '${_statusCount('QUALIFIED')}',
                                  Icons.verified_outlined,
                                ),
                                _metric(
                                  'Paid Rewards',
                                  '${_number(_summaryValue(<String>[
                                        'paidRewards',
                                        'awardedClaims',
                                        'rewardsEarned'
                                      ])).toInt()}',
                                  Icons.payments_outlined,
                                ),
                                _metric(
                                  'Total Reward Value',
                                  _money(
                                    _summaryValue(<String>[
                                      'totalRewardValue',
                                      'awardedAmount',
                                      'rewardValue',
                                    ]),
                                  ),
                                  Icons.account_balance_wallet_outlined,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _filters(),
                            const SizedBox(height: 12),
                            if (_programmeChecked && _programmeAvailable) ...[
                              _programmePanel(),
                              const SizedBox(height: 12),
                            ],
                            if (_commissionsChecked &&
                                _commissionsAvailable) ...[
                              _commissionPanel(),
                              const SizedBox(height: 12),
                            ],
                            const SizedBox(height: 18),
                            const Text('Referral monitoring',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Text(
                              'Showing ${_rows.length} of $_total referrals',
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (_rows.isEmpty)
                              const Card(
                                elevation: 0,
                                child: Padding(
                                  padding: EdgeInsets.all(30),
                                  child: Center(
                                    child: Text('No referral records found.'),
                                  ),
                                ),
                              )
                            else
                              ..._rows.map(_row),
                            if (_total > _limit)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  IconButton(
                                    onPressed: _page > 1
                                        ? () => _load(page: _page - 1)
                                        : null,
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  Text('Page $_page'),
                                  IconButton(
                                    onPressed: _page * _limit < _total
                                        ? () => _load(page: _page + 1)
                                        : null,
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
    );
  }
}
