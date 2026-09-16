import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'edupay_api.dart';
import 'private_asset_download.dart';

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
  List<Map<String, dynamic>> eligibleUsers = [];
  bool isSuperAdmin = false;
  Set<String> permissions = <String>{};
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
    'Settings',
    'Audit logs',
  ];
  @override
  void initState() {
    super.initState();
    _load();
    _loadReadiness();
  }

  Future<void> _loadReadiness() async {
    try {
      readiness = await _api.readiness();
      final prefs = await SharedPreferences.getInstance();
      isSuperAdmin = (prefs.getString('user_role') ?? '').toUpperCase() == 'SUPER_ADMIN';
      permissions = (prefs.getStringList('staff_permissions') ?? <String>[])
          .map((value) => value.toLowerCase()).toSet();
      if (!isSuperAdmin) {
        if (mounted) setState(() {});
        return;
      }
      final eligible = await _api.eligibleDutyUsers();
      final users = eligible['users'] ?? eligible['data'];
      if (users is List) {
        eligibleUsers = users.whereType<Map>()
            .map((u) => Map<String, dynamic>.from(u)).where((u) =>
              (u['role']?.toString().toUpperCase() == 'HEAD_OFFICE') &&
              (u['active'] != false)).toList();
      }
      if (mounted) setState(() {});
    } catch (_) {}
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
    return value is List
        ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
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
                            if (readiness != null) _readinessCard(),
                            if (section == 'Overview')
                              _summary(summary)
                            else if (section == 'Reports')
                              _reportsView()
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
        trailing: permissions.contains('edupay.manage')
            ? const Icon(Icons.edit_outlined) : null)).toList()));
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

  Widget _readinessCard() {
    final coverage =
        (readiness?['dutyCoverage'] as Map?)?.cast<String, dynamic>() ?? {};
    final payout = (readiness?['payoutConfig'] as Map?)?.cast<String, dynamic>() ?? {};
    final ready = readiness?['ready'] == true;
    final holders = (readiness?['currentHolders'] as Map?)?.cast<String, dynamic>() ?? {};
    return Card(
      color: ready ? const Color(0xffe9f6ee) : const Color(0xfffff4df),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12, runSpacing: 8,
              children: [
                Icon(ready ? Icons.verified_outlined : Icons.info_outline,
                    color: ready ? const Color(0xff08783e) : Colors.orange.shade800),
                SizedBox(width: 280, child: Text(ready
                    ? 'EduPay is ready for separated settlement operations.'
                    : 'Readiness is blocked. Assign distinct duties. Coverage: ${coverage['manage'] ?? 0} / ${coverage['verify'] ?? 0} / ${coverage['process'] ?? 0}.')),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 18, runSpacing: 6, children: [
              Text('Payout provider: ${_display(payout['provider'])}'),
              Text('Account encryption: ${_display(payout['accountEncryption'])}'),
              Text('Settlement method: ${_display(payout['settlementMethod'])}'),
              Text('Rates: ${_display(payout['rates'])}'),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 18, runSpacing: 6, children: [
              Text('account.manage: ${_display(holders['account.manage'])}'),
              Text('account.verify: ${_display(holders['account.verify'])}'),
              Text('settlement.process: ${_display(holders['settlement.process'])}'),
            ]),
            if (permissions.contains('edupay.manage')) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                if (isSuperAdmin) OutlinedButton.icon(onPressed: _assignDuty, icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Assign distinct duty')),
                FilledButton.tonalIcon(onPressed: ready && permissions.contains('feature_control.manage') ? _enableEduPay : null,
                    icon: const Icon(Icons.power_settings_new), label: const Text('Enable EduPay')),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _assignDuty() async {
    if (eligibleUsers.length < 3) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Three distinct active HEAD_OFFICE duty holders are required.')));
      return;
    }
    final selected = <String?>[null, null, null];
    final labels = ['account.manage', 'account.verify', 'settlement.process'];
    final ok = await showDialog<bool>(context: context, builder: (d) => StatefulBuilder(
      builder: (d, setDialogState) => AlertDialog(
        title: const Text('Payout readiness: assign three distinct duties'),
        content: Column(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) =>
          DropdownButton<String>(isExpanded: true, hint: Text(labels[i]),
            value: selected[i], items: eligibleUsers.map((u) {
              final id = (u['id'] ?? u['_id']).toString();
              return DropdownMenuItem(value: id, child: Text(u['name']?.toString() ?? id));
            }).toList(), onChanged: (v) => setDialogState(() => selected[i] = v))),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: selected.every((v) => v != null) && selected.toSet().length == 3
            ? () => Navigator.pop(d, true) : null, child: const Text('Assign duties'))],
      ),
    ));
    if (ok != true) return;
    try {
      for (var i = 0; i < selected.length; i++) {
        await _api.assignDuty(selected[i]!, [labels[i]]);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Duty assigned and audit recorded.')));
      _loadReadiness();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _enableEduPay() async {
    try {
      await _api.enableFeature('edupay', 'EduPay launch readiness checklist completed');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('EduPay enabled and audit recorded.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
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
                           if (section == 'Schools & onboarding') ...[
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
