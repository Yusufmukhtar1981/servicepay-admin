import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'edupay_api.dart';

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
  Set<String> permissions = <String>{};
  String section = 'Overview';
  bool loading = true;
  String? error;
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
      permissions = (prefs.getStringList('staff_permissions') ?? <String>[])
          .map((value) => value.toLowerCase())
          .toSet();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
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

  List<Map<String, dynamic>> _rows() {
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
  @override
  Widget build(BuildContext context) {
    final summary = (data?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    return Scaffold(
      backgroundColor: const Color(0xfff4f7f5),
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
          NavigationRail(
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
  Widget _summary(Map<String, dynamic> s) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 4,
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
    final ready = readiness?['ready'] == true;
    return Card(
      color: ready ? const Color(0xffe9f6ee) : const Color(0xfffff4df),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(ready ? Icons.verified_outlined : Icons.info_outline,
                color:
                    ready ? const Color(0xff08783e) : Colors.orange.shade800),
            const SizedBox(width: 12),
            Expanded(
              child: Text(ready
                  ? 'EduPay is ready for separated settlement operations.'
                  : 'Readiness is blocked. A Super Admin must assign distinct account, verification and settlement duties. Coverage: ${coverage['manage'] ?? 0} / ${coverage['verify'] ?? 0} / ${coverage['process'] ?? 0}.'),
            ),
          ],
        ),
      ),
    );
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

  Widget _table(List<Map<String, dynamic>> rows) => rows.isEmpty
      ? const _Empty()
      : Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: (rows.first.keys.take(
                6,
              )).map((k) => DataColumn(label: Text(k))).toList(),
              rows: rows
                  .map(
                    (r) => DataRow(
                      cells: r.values
                          .take(6)
                          .map((v) => DataCell(Text(_display(v))))
                          .toList(),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
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
