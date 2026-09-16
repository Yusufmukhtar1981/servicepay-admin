import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'edupay_api.dart';
import 'private_asset_download.dart';

String eduPayDutyDisplayLabel(String permission) => switch (permission) {
      'account.manage' => 'Account Management Officer',
      'account.verify' => 'Account Verification Officer',
      'settlement.process' => 'Settlement Processing Officer',
      _ => permission,
    };

class EduPayControlCenterScreen extends StatefulWidget {
  const EduPayControlCenterScreen({super.key});
  @override
  State<EduPayControlCenterScreen> createState() =>
      _EduPayControlCenterScreenState();
}

class _EduPayControlCenterScreenState extends State<EduPayControlCenterScreen> {
  final _api = EduPayApi();
  Map<String, dynamic>? data;
  Map<String, dynamic>? readiness;
  bool canConfigureDuties = false;
  Set<String> permissions = <String>{};
  String adminRole = '';
  String section = 'Overview';
  bool loading = true;
  String? error;
  final schoolSearch = TextEditingController();
  String schoolStatus = 'All';
  final sections = const <String>[
    'Overview',
    'Schools & onboarding',
    'Fee approvals',
    'Parents & plans',
    'Savings & transactions',
    'Settlements',
    'Repayments',
    'Sponsors',
    'Reconciliation',
    'Reports',
    'Launch Readiness',
    'Settings',
    'Audit logs',
  ];
  bool get isHeadOffice => const <String>{
        'HEAD_OFFICE',
        'HEAD_OFFICE_ADMIN',
        'ADMIN',
        'SUPER_ADMIN',
        'SERVICEPAY_SUPER_ADMIN',
      }.contains(adminRole);
  bool get canManageEduPay =>
      isHeadOffice || permissions.contains('edupay.manage');
  bool get canEnableEduPay =>
      adminRole == 'SERVICEPAY_SUPER_ADMIN' ||
      permissions.contains('feature_control.protected_manage');
  @override
  void initState() {
    super.initState();
    _load();
    _loadReadiness();
  }

  Future<void> _loadReadiness() async {
    try {
      readiness = await _api.readiness();
      canConfigureDuties =
          (readiness?['capabilities'] as Map?)?['configureDuties'] == true;
      final prefs = await SharedPreferences.getInstance();
      adminRole = (prefs.getString('user_role') ??
              prefs.getString('admin_role') ??
              prefs.getString('role') ??
              '')
          .trim()
          .toUpperCase()
          .replaceAll(RegExp(r'[\s-]+'), '_');
      permissions = (prefs.getStringList('staff_permissions') ??
              prefs.getStringList('admin_effective_permissions') ??
              <String>[])
          .map((value) => value.toLowerCase()).toSet();
      if (mounted) setState(() {});
    } catch (_) {
      canConfigureDuties = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (section == 'Reports') {
        final responses = await Future.wait([
          _api.request('GET', '/admin/edupay/transactions'),
          _api.request('GET', '/admin/edupay/sponsors'),
          _api.request('GET', '/admin/edupay/audit'),
        ]);
        data = <String, dynamic>{
          'transactionContributions': responses[0]['contributions'],
          'transactionLedger': responses[0]['ledger'],
          'repaymentTransactions': responses[0]['repaymentTransactions'],
          'sponsorInvites': responses[1]['invites'],
          'sponsorContributions': responses[1]['contributions'],
          'audit': responses[2]['audit'],
        };
        if (mounted) setState(() => loading = false);
        return;
      }
      if (section == 'Launch Readiness') {
        await _loadReadiness();
        data = await _api.request('GET', '/admin/edupay/settings');
        if (mounted) setState(() => loading = false);
        return;
      }
      final path = switch (section) {
        'Overview' => '/admin/edupay/overview',
        'Schools & onboarding' => '/admin/edupay/schools',
        'Fee approvals' => '/admin/edupay/fees',
        'Parents & plans' => '/admin/edupay/plans',
        'Savings & transactions' => '/admin/edupay/transactions',
        'Settlements' => '/admin/edupay/settlements',
        'Repayments' => '/admin/edupay/repayments',
        'Sponsors' => '/admin/edupay/sponsors',
        'Reconciliation' => '/admin/edupay/reconciliation',
        'Audit logs' => '/admin/edupay/audit',
        'Settings' => '/admin/edupay/settings',
        _ => '/admin/edupay/overview',
      };
      data = await _api.request('GET', path);
      if (section == 'Schools & onboarding' &&
          data?['onboardingRequests'] == null) {
        try {
          final requests = await _api.schoolRequests();
          data = <String, dynamic>{
            ...data!,
            'onboardingRequests':
                requests['requests'] ?? requests['onboardingRequests'] ?? [],
          };
        } catch (_) {
          // Keep school review usable on older backends without this endpoint.
        }
      }
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    schoolSearch.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows() {
    if (section == 'Savings & transactions' || section == 'Reconciliation') {
      final rows = <Map<String, dynamic>>[];
      for (final key in ['contributions', 'ledger', 'repaymentTransactions']) {
        final value = data?[key];
        if (value is List) {
          rows.addAll(value.whereType<Map>().map((row) =>
              {...Map<String, dynamic>.from(row), '_source': key}));
        }
      }
      return rows;
    }
    if (section == 'Sponsors') {
      final rows = <Map<String, dynamic>>[];
      for (final key in ['invites', 'contributions']) {
        final value = data?[key];
        if (value is List) {
          rows.addAll(value.whereType<Map>().map((row) =>
              {...Map<String, dynamic>.from(row), '_source': key}));
        }
      }
      return rows;
    }
    if (section == 'Audit logs') {
      final value = data?['audit'];
      return value is List
          ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : <Map<String, dynamic>>[];
    }
    final value = data?[{
      'Schools & onboarding': 'schools',
      'Fee approvals': 'fees',
      'Parents & plans': 'plans',
      'Savings & transactions': 'transactions',
      'Settlements': 'settlements',
      'Repayments': 'repayments',
      'Sponsors': 'sponsors',
      'Reconciliation': 'transactions',
      'Audit logs': 'logs',
    }[section]];
    final rows = value is List
        ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    if (section == 'Schools & onboarding' &&
        data?['onboardingRequests'] is List) {
      rows.insertAll(
        0,
        (data!['onboardingRequests'] as List).whereType<Map>().map((request) => {
              'type': 'SCHOOL_REQUEST',
              'schoolName': request['schoolName'] ?? request['name'],
              'location': request['location'],
              'contactPhone': request['contactPhone'],
              'status': request['status'] ?? 'PENDING',
              'createdAt': request['createdAt'],
              '_requestId': request['_id'] ?? request['id'],
            }),
      );
    }
    return rows;
  }

  String _display(dynamic v) => v == null ? '—' : v.toString();
  Widget _reportsView() {
    final contributionRows = (data?['transactionContributions'] is List)
        ? (data!['transactionContributions'] as List).length : 0;
    final ledgerRows = (data?['transactionLedger'] is List)
        ? (data!['transactionLedger'] as List).length : 0;
    final repaymentRows = (data?['repaymentTransactions'] is List)
        ? (data!['repaymentTransactions'] as List).length : 0;
    final values = <String, dynamic>{
      'Contributions': contributionRows,
      'Ledger': ledgerRows,
      'Repayment transactions': repaymentRows,
      'Sponsor invites': data?['sponsorInvites'] is List
          ? (data!['sponsorInvites'] as List).length : 0,
      'Sponsor contributions': data?['sponsorContributions'] is List
          ? (data!['sponsorContributions'] as List).length : 0,
      'Audit events': data?['audit'] is List
          ? (data!['audit'] as List).length : 0,
    };
    return GridView.count(shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: MediaQuery.sizeOf(context).width < 700 ? 1 : 3,
      children: values.entries.map((e) => Card(child: ListTile(
        leading: const Icon(Icons.analytics_outlined), title: Text(e.key),
        subtitle: Text(_display(e.value))))).toList());
  }
  @override
  Widget build(BuildContext context) {
    final summary = (data?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    return Scaffold(
      backgroundColor: const Color(0xfff4f7f5),
      drawer: MediaQuery.sizeOf(context).width < 700
          ? Drawer(child: ListView(children: sections.map((s) => ListTile(
              title: Text(s), selected: section == s, onTap: () {
                Navigator.pop(context);
                setState(() => section = s);
                _load();
              })).toList()))
          : null,
      appBar: AppBar(
        title: const Text('EduPay Control Center'),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Row(
        children: [
          Visibility(visible: MediaQuery.sizeOf(context).width >= 700,
            child: SingleChildScrollView(
              child: NavigationRail(
            selectedIndex: sections.indexOf(section),
            onDestinationSelected: (i) {
              setState(() => section = sections[i]);
              _load();
            },
            labelType: NavigationRailLabelType.all,
            destinations: sections
                .map(
                  (s) => NavigationRailDestination(
                    icon: Icon(_icon(s)),
                    selectedIcon: Icon(_icon(s)),
                    label: Text(s),
                  ),
                )
                .toList(),
              ),
            )),
          const VerticalDivider(width: 1),
          Expanded(
            child: loading
                ? const _Loading()
                : error != null
                    ? _Error(message: error!, retry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            Text(
                              section,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _subtitle(section),
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 22),
                             if (readiness != null && section != 'Launch Readiness') _readinessCard(),
                            if (section == 'Overview')
                              _summary(summary)
                            else if (section == 'Reports')
                              _reportsView()
                             else if (section == 'Launch Readiness')
                               _readinessView()
                            else if (section == 'Settings')
                              _settingsView()
                            else
                              _table(_rows()),
                            if (section == 'Settlements') _settlementTools(),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  IconData _icon(String s) => switch (s) {
        'Overview' => Icons.dashboard_outlined,
        'Schools & onboarding' => Icons.school_outlined,
        'Fee approvals' => Icons.fact_check_outlined,
        'Parents & plans' => Icons.family_restroom_outlined,
        'Savings & transactions' => Icons.account_balance_wallet_outlined,
        'Settlements' => Icons.payments_outlined,
        'Repayments' => Icons.replay_outlined,
        'Sponsors' => Icons.handshake_outlined,
        'Reconciliation' => Icons.compare_arrows_outlined,
        'Reports' => Icons.assessment_outlined,
        'Launch Readiness' => Icons.verified_outlined,
        'Settings' => Icons.tune_outlined,
        _ => Icons.history_outlined,
      };
  String _subtitle(String s) => s == 'Overview'
      ? 'A precise view of EduPay money movement and partner health.'
      : 'Traceable records from the EduPay API.';
  Widget _settingsView() {
    final settings = (data?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    return Card(child: Column(children: settings.entries.map((entry) =>
      ListTile(title: Text(entry.key), subtitle: Text('${entry.value}'),
        trailing: canManageEduPay && entry.key != 'enabled'
            ? IconButton(
                tooltip: 'Edit operating settings',
                icon: const Icon(Icons.edit_outlined),
                onPressed: _editSettings,
              )
            : null)).toList()));
  }

  Widget _readinessView() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _readinessCard(),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: Icon(
                ((data?['settings'] as Map?)?['enabled'] == true)
                    ? Icons.check_circle
                    : Icons.pause_circle_outline,
              ),
              title: const Text('Feature status'),
              subtitle: Text(
                ((data?['settings'] as Map?)?['enabled'] == true)
                    ? 'ENABLED'
                    : 'DISABLED',
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Provider credentials and account encryption are deployment-controlled. '
                'They cannot be entered or exposed in this dashboard.',
              ),
            ),
          ),
        ],
      );

  Future<void> _editSettings() async {
    if (!canManageEduPay) return;
    final source = (data?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final fields = <String>[
      'schoolCommissionRate',
      'parentShortfallChargeRate',
      'minimumSavingsRequirement',
      'maximumEduPayCover',
      'maximumCoverPercentage',
      'defaultRepaymentPeriodDays',
      'settlementLeadDays',
      'gracePeriodDays',
    ];
    final controllers = <String, TextEditingController>{
      for (final key in fields)
        key: TextEditingController(text: '${source[key] ?? ''}'),
    };
    var settlementMethod =
        '${source['settlementMethod'] ?? 'DEDUCT_COMMISSION'}';
    var autosave = source['autosaveEnabled'] == true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('EduPay operating settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final key in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: controllers[key],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: key,
                        helperText: key.contains('Rate') ||
                                key == 'maximumCoverPercentage'
                            ? 'Enter a percentage from 0 to 100'
                            : null,
                      ),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  value: settlementMethod,
                  decoration:
                      const InputDecoration(labelText: 'settlementMethod'),
                  items: const [
                    DropdownMenuItem(
                      value: 'DEDUCT_COMMISSION',
                      child: Text('Deduct commission'),
                    ),
                    DropdownMenuItem(
                      value: 'GROSS_AND_RECEIVABLE',
                      child: Text('Gross and receivable'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => settlementMethod = value ?? settlementMethod,
                  ),
                ),
                SwitchListTile(
                  value: autosave,
                  title: const Text('autosaveEnabled'),
                  onChanged: (value) =>
                      setDialogState(() => autosave = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Validate and save'),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    final payload = <String, dynamic>{};
    for (final key in fields) {
      final value = double.tryParse(controllers[key]!.text.trim());
      final isPercentage =
          key.contains('Rate') || key == 'maximumCoverPercentage';
      if (value == null || value < 0 || (isPercentage && value > 100)) {
        _showError('Enter valid non-negative settings; percentages must be 0–100.');
        return;
      }
      payload[key] = value;
    }
    payload['settlementMethod'] = settlementMethod;
    payload['autosaveEnabled'] = autosave;
    try {
      await _api.saveSettings(payload);
      await _load();
      await _loadReadiness();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('EduPay settings saved and audited.')),
        );
      }
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
  Widget _summary(Map<String, dynamic> s) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: MediaQuery.sizeOf(context).width < 700 ? 1 : 4,
        childAspectRatio: 1.8,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        children: s.entries
            .map(
              (e) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.key
                            .replaceAllMapped(
                                RegExp(r'([A-Z])'), (m) => ' ${m[1]}')
                            .trim(),
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const Spacer(),
                      Text(
                        _display(e.value),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Color(0xff08783e),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      );

  String _holderName(Map<String, dynamic> holders, String permission) {
    final value = holders[permission];
    if (value is List && value.isNotEmpty && value.first is Map) {
      final holder = Map<String, dynamic>.from(value.first as Map);
      return (holder['fullName'] ?? holder['name'] ?? 'Configured').toString();
    }
    if (value is Map) {
      return (value['fullName'] ?? value['name'] ?? 'Configured').toString();
    }
    return 'Not configured';
  }

  Widget _readinessRow({
    required String title,
    required bool ready,
    String? detail,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ready ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: ready ? const Color(0xff08783e) : Colors.orange.shade800,
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(detail,
                        style: TextStyle(
                            color: Colors.grey.shade700, fontSize: 12)),
                  ],
                ],
              ),
            ),
            Text(
              ready ? 'READY' : 'CONFIGURE',
              style: TextStyle(
                color: ready ? const Color(0xff08783e) : Colors.orange.shade900,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );

  Widget _readinessCard() {
    final coverage =
        (readiness?['dutyCoverage'] as Map?)?.cast<String, dynamic>() ?? {};
    final payout = (readiness?['payoutConfig'] as Map?)?.cast<String, dynamic>() ?? {};
    final ready = readiness?['ready'] == true;
    final holders = (readiness?['currentHolders'] as Map?)?.cast<String, dynamic>() ?? {};
    final missing = (payout['missingEnvironment'] as List?)
            ?.map((value) => value.toString())
            .toList() ??
        <String>[];
    return Card(
      color: ready ? const Color(0xffe9f6ee) : const Color(0xfffff4df),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EDUPAY LAUNCH READINESS',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xff10231a),
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              ready
                  ? 'All launch controls are verified.'
                  : 'Complete every required control before enabling customer initiation.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),
            const Text('Duty Separation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            _readinessRow(
              title: eduPayDutyDisplayLabel('account.manage'),
              ready: (coverage['manage'] ?? 0) > 0,
              detail: _holderName(holders, 'account.manage'),
            ),
            _readinessRow(
              title: eduPayDutyDisplayLabel('account.verify'),
              ready: (coverage['verify'] ?? 0) > 0,
              detail: _holderName(holders, 'account.verify'),
            ),
            _readinessRow(
              title: eduPayDutyDisplayLabel('settlement.process'),
              ready: (coverage['process'] ?? 0) > 0,
              detail: _holderName(holders, 'settlement.process'),
            ),
            const Divider(height: 28),
            const Text('Financial Infrastructure',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            _readinessRow(
              title: 'Payout Provider',
              ready: payout['provider'] == true,
              detail:
                  '${payout['providerName'] ?? 'SQUAD'} · ${payout['configurationStatus'] ?? 'NOT READY'} · ${payout['connectionStatus'] ?? 'NOT READY'}',
            ),
            _readinessRow(
              title: 'Account Encryption',
              ready: payout['accountEncryption'] == true,
              detail: payout['accountEncryption'] == true
                  ? 'Deployment encryption key is configured.'
                  : 'Deployment encryption key is required.',
            ),
            _readinessRow(
              title: 'Settlement Method',
              ready: payout['settlementMethod'] == true,
            ),
            _readinessRow(
              title: 'Rates',
              ready: payout['rates'] == true,
            ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Missing production environment configuration',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: missing
                    .map((key) => Chip(
                          avatar: const Icon(Icons.key_outlined, size: 16),
                          label: Text(key),
                        ))
                    .toList(),
              ),
            ],
            const Divider(height: 32),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ready
                    ? const Color(0xffd8f0e2)
                    : Colors.orange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Overall Readiness: ${ready ? 'READY' : 'NOT READY'}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: ready
                      ? const Color(0xff08783e)
                      : Colors.orange.shade900,
                ),
              ),
            ),
            if (canManageEduPay) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  if (canConfigureDuties)
                    OutlinedButton.icon(
                      key: const Key('configure-edupay-officers'),
                      onPressed: _assignDuty,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Configure officers'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _loadReadiness,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Verify configuration'),
                  ),
                  FilledButton.icon(
                    onPressed: ready && canEnableEduPay ? _enableEduPay : null,
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('Enable EduPay'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _assignDuty() async {
    final holders =
        (readiness?['currentHolders'] as Map?)?.cast<String, dynamic>() ?? {};
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => EduPayOfficerAssignmentsDialog(
        api: _api,
        currentHolders: holders,
      ),
    );
    if (ok != true) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Duty officers saved and audit recorded.')));
    }
    await _loadReadiness();
  }

  Future<void> _enableEduPay() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable EduPay?'),
        content: const Text(
          'This enables customer EduPay initiation. All readiness controls will be checked again by the Backend before the change is accepted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enable EduPay'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.enableFeature('edupay', 'EduPay launch readiness checklist completed');
      await _loadReadiness();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('EduPay enabled and audit recorded.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Widget _settlementTools() {
    final canManage = permissions.contains('edupay.manage');
    final canProcess = permissions.contains('edupay.settlement.process') &&
        readiness?['ready'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Settlement lifecycle',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
              'Approve under Manage, then use explicit Squad process and requery routes. Legacy PATCH PROCESS and CONFIRM are never used.'),
          const SizedBox(height: 12),
          Wrap(spacing: 10, children: [
            FilledButton.tonal(
                onPressed:
                    canManage ? () => _settlementAction('APPROVE') : null,
                child: const Text('Approve settlement')),
            FilledButton(
                onPressed:
                    canProcess ? () => _settlementAction('PROCESS') : null,
                child: const Text('Process payout')),
            OutlinedButton(
                onPressed:
                    canProcess ? () => _settlementAction('REQUERY') : null,
                child: const Text('Requery payout')),
          ]),
          if (!canProcess)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                  'Process and requery stay disabled until permission and viable duty separation are confirmed.'),
            ),
        ]),
      ),
    );
  }

  Future<void> _settlementAction(String action) async {
    final id = await _promptForId('settlement ID');
    if (id == null || id.isEmpty) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$action settlement?'),
        content: const Text(
            'This sensitive financial action will be recorded in the audit log.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (action == 'APPROVE') {
        await _api.request('PATCH', '/admin/edupay/settlements/$id',
            body: {'action': 'APPROVE'});
      } else if (action == 'PROCESS') {
        await _api.processSettlement(id);
      } else {
        await _api.requerySettlement(id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Server action completed and audited.')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<String?> _promptForId(String label) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Enter $label'),
        content: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Continue')),
        ],
      ),
    );
  }

  Widget _table(List<Map<String, dynamic>> rows) {
    if (section == 'Schools & onboarding') {
      rows = rows.where((r) {
        final q = schoolSearch.text.trim().toLowerCase();
        final status = r['status']?.toString() ?? '';
        return (q.isEmpty || r.values.any((v) => '$v'.toLowerCase().contains(q))) &&
            (schoolStatus == 'All' || status.toLowerCase() == schoolStatus.toLowerCase());
      }).toList();
    }
    final table = rows.isEmpty
      ? const _Empty()
      : Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: (rows.first.keys.take(
                6,
              )).map((k) => DataColumn(label: Text(k))).toList()
                ..add(const DataColumn(label: Text('Actions'))),
              rows: rows
                  .map(
                    (r) => DataRow(
                      cells: r.values
                          .take(6)
                           .map((v) => DataCell(Text(_display(v)))).toList()
                         ..add(DataCell(Wrap(spacing: 4, children: [
                           if (section == 'Schools & onboarding')
                             IconButton(tooltip: 'View details', icon: const Icon(Icons.visibility_outlined),
                               onPressed: () => _schoolDetails(r)),
                            if (section == 'Schools & onboarding' &&
                                r['type'] != 'SCHOOL_REQUEST') ...[
                             ..._schoolActionButtons(r),
                           ],
                         ]))),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
    if (section != 'Schools & onboarding') return table;
    return Column(children: [
      Row(children: [
        Expanded(child: TextField(controller: schoolSearch, onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search schools'))),
        const SizedBox(width: 12),
        DropdownButton<String>(value: schoolStatus, items: const ['All', 'PENDING_REVIEW', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'SUSPENDED']
          .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (v) => setState(() => schoolStatus = v ?? 'All')),
      ]),
      const SizedBox(height: 14), table,
    ]);
  }

  Future<void> _schoolDetails(Map<String, dynamic> row) async {
    if (!mounted) return;
    final id = row['id']?.toString() ?? row['_id']?.toString();
    Map<String, dynamic> details = row;
    if (id != null && id.isNotEmpty) {
      try {
        final response = await _api.schoolDetail(id);
        final value = response['school'] ?? response['data'];
        if (value is Map) details = Map<String, dynamic>.from(value);
        if (permissions.contains('edupay.school.private_assets.view')) {
          final privateData = await _api.privateSchoolDocuments(id);
          final assets = privateData['assets'];
          details = {...details, 'privateAssets': assets is Map
              ? [if (assets['logo'] is Map) assets['logo'],
                 ...((assets['supportingDocuments'] as List?) ?? const [])]
              : (assets ?? privateData['documents'] ?? privateData['data'])};
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
    showDialog<void>(context: context, builder: (_) => AlertDialog(
      title: Text(details['name']?.toString() ?? 'School details'),
      content: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(details.entries.where((e) => e.key != 'privateAssets')
              .map((e) => '${e.key}: ${e.value}').join('\n')),
          if (permissions.contains('edupay.school.private_assets.view') &&
              details['privateAssets'] is List) ...[
            const Divider(), const Text('Private assets',
              style: TextStyle(fontWeight: FontWeight.bold)),
            ...(details['privateAssets'] as List).whereType<Map>().map((asset) {
              final id = (asset['fileId'] ?? asset['id'] ?? asset['_id']).toString();
              return ListTile(title: Text(asset['originalName']?.toString() ?? 'Document'),
                subtitle: Text(asset['mimeType']?.toString() ?? 'Private file'),
                trailing: Wrap(children: [
                  IconButton(tooltip: 'Preview', icon: const Icon(Icons.visibility_outlined),
                    onPressed: () => _downloadAsset(
                      (details['id'] ?? details['_id']).toString(), id,
                      mimeType: asset['mimeType']?.toString(),
                      assetName: asset['originalName']?.toString(), preview: true)),
                  IconButton(tooltip: 'Download', icon: const Icon(Icons.download_outlined),
                    onPressed: () => _downloadAsset(
                      (details['id'] ?? details['_id']).toString(), id,
                      mimeType: asset['mimeType']?.toString(),
                      assetName: asset['originalName']?.toString())),
                ]));
            }),
          ],
        ],
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  Future<void> _downloadAsset(String schoolId, String fileId,
      {String? mimeType, String? assetName, bool preview = false}) async {
    // The authenticated response is intentionally kept in memory; no private
    // URL or document reference is rendered into the public UI.
    if (schoolId.isEmpty) return;
    try {
      final response = await _api.privateAssetBytes(schoolId, fileId);
      if (!mounted) return;
      if (preview) {
        await showDialog<void>(context: context, builder: (_) => AlertDialog(
          title: const Text('Private asset preview'),
          content: mimeType?.startsWith('image/') == true
              ? Image.memory(response.bodyBytes, fit: BoxFit.contain)
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.picture_as_pdf, size: 48),
                  Text('Authenticated PDF loaded (${response.bodyBytes.length} bytes).'),
                ]),
          actions: [TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Close'))],
        ));
      } else {
        await savePrivateAsset(response.bodyBytes, assetName ?? 'private-asset',
            mimeType ?? 'application/octet-stream');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Authenticated private asset downloaded.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _schoolAction(Map<String, dynamic> row, String action) async {
    final id = row['id']?.toString() ?? row['_id']?.toString();
    if (id == null || id.isEmpty) return;
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: Text('$action school'),
      content: TextField(controller: note, maxLines: 3,
        decoration: const InputDecoration(labelText: 'Review note (required)')),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, note.text.trim().isNotEmpty),
          child: const Text('Confirm'))],
    ));
    if (confirmed != true) return;
    try {
      await _api.schoolAction(id, action, note: note.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('School $action completed and audited.')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  List<Widget> _schoolActionButtons(Map<String, dynamic> row) {
    if (row['type'] == 'SCHOOL_REQUEST') return const <Widget>[];
    final state = row['status']?.toString().toUpperCase() ?? '';
    final actions = switch (state) {
      'PENDING_REVIEW' => ['APPROVE', 'REJECT', 'REQUEST_UPDATE'],
      'UNDER_REVIEW' => ['APPROVE', 'REJECT', 'REQUEST_UPDATE'],
      'APPROVED' => ['SUSPEND'],
      'SUSPENDED' => ['REACTIVATE'],
      _ => <String>[],
    };
    final icons = <String, IconData>{
      'APPROVE': Icons.check_circle_outline, 'REJECT': Icons.cancel_outlined,
      'REQUEST_UPDATE': Icons.edit_note, 'SUSPEND': Icons.pause_circle_outline,
      'REACTIVATE': Icons.play_circle_outline,
    };
    return actions.map((action) => IconButton(tooltip: action,
      icon: Icon(icons[action]), onPressed: () => _schoolAction(row, action))).toList();
  }
}

class EduPayOfficerAssignmentsDialog extends StatefulWidget {
  const EduPayOfficerAssignmentsDialog({
    super.key,
    required this.api,
    required this.currentHolders,
  });

  final EduPayApi api;
  final Map<String, dynamic> currentHolders;

  @override
  State<EduPayOfficerAssignmentsDialog> createState() =>
      _EduPayOfficerAssignmentsDialogState();
}

class _EduPayOfficerAssignmentsDialogState
    extends State<EduPayOfficerAssignmentsDialog> {
  static const duties = <String>[
    'account.manage',
    'account.verify',
    'settlement.process',
  ];

  List<Map<String, dynamic>> users = <Map<String, dynamic>>[];
  late final List<String?> selected;
  bool loading = true;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    selected = duties
        .map((duty) => _currentHolderId(widget.currentHolders[duty]))
        .toList();
    _loadOfficers();
  }

  String? _currentHolderId(dynamic value) {
    if (value is! List || value.isEmpty || value.first is! Map) return null;
    final holder = Map<String, dynamic>.from(value.first as Map);
    final id = (holder['id'] ?? holder['_id'])?.toString().trim();
    return id == null || id.isEmpty ? null : id;
  }

  Future<void> _loadOfficers() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await widget.api.eligibleDutyUsers();
      final rows = response['users'] ?? response['data'];
      final loaded = rows is List
          ? rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .where((row) =>
                  row['role']?.toString().toUpperCase() == 'HEAD_OFFICE' &&
                  row['status']?.toString().toUpperCase() == 'ACTIVE')
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        users = loaded;
        for (var index = 0; index < selected.length; index++) {
          if (!users.any((user) =>
              (user['id'] ?? user['_id']).toString() == selected[index])) {
            selected[index] = null;
          }
        }
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = exception.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  bool get hasCompleteDistinctSelection =>
      selected.every((value) => value != null) &&
      selected.toSet().length == duties.length;

  Future<void> _save() async {
    if (!hasCompleteDistinctSelection || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api.configureDuties(<String, String>{
        for (var index = 0; index < duties.length; index++)
          duties[index]: selected[index]!,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = exception.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final duplicateSelection = selected.whereType<String>().length > 1 &&
        selected.whereType<String>().toSet().length !=
            selected.whereType<String>().length;
    return AlertDialog(
      title: const Text('Configure officers'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 14),
                        Text('Loading active Head Office officers…'),
                      ],
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Assign three distinct active Head Office officers. These assignments are saved together and audited.',
                    ),
                    const SizedBox(height: 18),
                    if (error != null) ...[
                      Text(
                        error!,
                        key: const Key('edupay-officer-error'),
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (users.isEmpty) ...[
                      const Text(
                        'No eligible active Head Office officers are available.',
                        key: Key('edupay-officer-empty'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _loadOfficers,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ] else
                      ...List.generate(
                        duties.length,
                        (index) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: DropdownButtonFormField<String>(
                            key: Key('edupay-officer-${duties[index]}'),
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: eduPayDutyDisplayLabel(duties[index]),
                            ),
                            value: selected[index],
                            items: users.map((user) {
                              final id =
                                  (user['id'] ?? user['_id']).toString();
                              return DropdownMenuItem<String>(
                                value: id,
                                child: Text(user['name']?.toString() ?? id),
                              );
                            }).toList(),
                            onChanged: saving
                                ? null
                                : (value) =>
                                    setState(() => selected[index] = value),
                          ),
                        ),
                      ),
                    if (duplicateSelection)
                      Text(
                        'Each duty must be assigned to a different officer.',
                        key: const Key('edupay-officer-duplicate'),
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-edupay-officer-assignments'),
          onPressed: !loading &&
                  users.length >= duties.length &&
                  hasCompleteDistinctSelection &&
                  !saving
              ? _save
              : null,
          child: saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save Assignments'),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext c) =>
      const Center(child: CircularProgressIndicator());
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext c) => const Card(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: Text('No records returned by the server.')),
        ),
      );
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext c) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: retry, child: const Text('Try again')),
          ],
        ),
      );
}
