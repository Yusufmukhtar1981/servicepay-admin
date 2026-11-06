import 'package:flutter/material.dart';

import 'admin_control_center_download.dart';
import 'admin_customer_support_operations_center.dart';
import 'admin_customer_support_screen.dart';
import 'admin_permissions.dart';
import 'admin_manual_refunds_api.dart';
import 'admin_staff_workspace_api.dart';
import 'admin_transaction_reliability_panel.dart';
import 'admin_transactions_screen.dart';
import 'financial_control_charts.dart';
import 'staff_management_screen.dart';

/// Enterprise view over server-calculated operational intelligence.
/// The UI never derives financial facts or makes client-side authorization
/// decisions for a mutation; server-provided permission flags only control
/// whether controls are presented.
class OperationsEnterpriseDashboard extends StatefulWidget {
  const OperationsEnterpriseDashboard({super.key, this.api});
  final AdminStaffWorkspaceApi? api;

  @override
  State<OperationsEnterpriseDashboard> createState() =>
      _OperationsEnterpriseDashboardState();
}

class _OperationsEnterpriseDashboardState
    extends State<OperationsEnterpriseDashboard> {
  late final AdminStaffWorkspaceApi _api =
      widget.api ?? AdminStaffWorkspaceApi();
  String _period = 'day';
  String _section = 'Executive';
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String _error = '';
  bool _staffHistoryAllowed = false;
  String _operationError = '';
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadStaffViewPermission();
  }

  Future<void> _loadStaffViewPermission() async {
    try {
      final access = await AdminSessionStore.loadAccess();
      if (mounted) {
        setState(
          () => _staffHistoryAllowed = access.has('operations.staff.view'),
        );
      }
    } catch (_) {
      // No local permission means the protected history action stays hidden.
    }
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map(_map).toList(growable: false)
      : <Map<String, dynamic>>[];

  Map<String, dynamic> get _permissions => _map(_data['permissions']);
  bool _allowed(String key) => _permissions[key] == true;

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final result = await _api.enterprise(period: _period);
      final value = _map(result['data']);
      if (mounted && request == _request) setState(() => _data = value);
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async => _load();

  String _money(dynamic value) {
    final amount = value is num ? value : num.tryParse('$value');
    if (amount == null) return 'Unavailable';
    final fixed = amount.toStringAsFixed(2).split('.');
    final whole = fixed.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '₦$whole.${fixed.last}';
  }

  String _number(dynamic value) {
    if (value is! num) return '—';
    return value.toInt().toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
        );
  }

  String _titleCase(dynamic value) => (value ?? 'Unavailable')
      .toString()
      .replaceAll('_', ' ')
      .toLowerCase()
      .split(' ')
      .map((word) =>
          word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');

  void _open(Widget screen) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => screen),
      );

  Widget _sectionHeader(String title, String caption) => Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xff173e35),
                  )),
          const SizedBox(height: 3),
          Text(caption, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  Widget _metric(String label, dynamic value, String note, IconData icon,
      {bool money = false}) {
    return Container(
      width: 190,
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xfff8fbf8),
        border: Border.all(color: const Color(0xffdce8e1)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 17, color: const Color(0xff167461)),
          const SizedBox(width: 7),
          Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xff60756b),
                      fontSize: 11,
                      fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 12),
        _loading && _data.isEmpty
            ? Container(
                height: 22,
                width: 105,
                decoration: BoxDecoration(
                    color: const Color(0xffe5eee8),
                    borderRadius: BorderRadius.circular(5)))
            : Text(money ? _money(value) : _number(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xff173e35),
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text(note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Color(0xff74877e))),
      ]),
    );
  }

  Widget _card(String title, Widget child, {String? caption}) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xff21483c))),
            if (caption != null) ...[
              const SizedBox(height: 4),
              Text(caption,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xff708279))),
            ],
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );

  Widget _executive() {
    final summary = _map(_data['summary']);
    final customerCounts = _map(_data['customers']);
    final support = _map(_data['support']);
    final financial = _map(_data['financial']);
    final trends = _rows(_data['trends'])
        .map((row) => <String, dynamic>{
              'date': '${row['date'] ?? ''}',
              'revenue': row['recordedEarnings'],
            })
        .toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(
          child: Text('Executive overview',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xff173e35),
                  )),
        ),
        DropdownButton<String>(
          value: _period,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: 'day', child: Text('Day')),
            DropdownMenuItem(value: 'week', child: Text('Week')),
            DropdownMenuItem(value: 'month', child: Text('Month')),
          ],
          onChanged: _loading
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _period = value);
                  _load();
                },
        ),
      ]),
      Text(
        '${_data['from'] ?? 'Coverage unavailable'} → ${_data['to'] ?? ''} · '
        'Generated ${_data['generatedAt'] ?? 'time unavailable'}',
        style: const TextStyle(fontSize: 11, color: Color(0xff6c7f75)),
      ),
      if ('${_data['coverageNotice'] ?? ''}'.isNotEmpty)
        _notice('${_data['coverageNotice']}'),
      if (_loading && _data.isEmpty) ...[
        const SizedBox(height: 16),
        ...List.generate(4, (_) => const _SkeletonCard()),
      ] else if (_error.isNotEmpty && _data.isEmpty)
        _failure(_error, _load)
      else ...[
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _metric('Transactions', summary['total'], 'Across selected period',
              Icons.receipt_long_outlined),
          _metric('Successful', summary['successful'], 'Recorded outcomes',
              Icons.check_circle_outline),
          _metric('Failed', summary['failed'], 'Recorded outcomes',
              Icons.error_outline),
          _metric('Pending', summary['pending'], 'Awaiting outcome',
              Icons.hourglass_empty),
          _metric(
              'Transaction volume',
              summary['volume'],
              'Gross transaction amount · not earnings',
              Icons.account_balance_wallet_outlined,
              money: true),
          _metric('Recorded earnings', summary['recordedEarnings'],
              'Stored ServicePay earnings · not net income', Icons.trending_up,
              money: true),
          _metric('Refund amount', summary['refundAmount'], 'Recorded refunds',
              Icons.undo_outlined,
              money: true),
          _metric('Charges', summary['charges'], 'Recorded transaction charges',
              Icons.receipt_outlined,
              money: true),
          _metric('Commission', summary['commission'],
              'Recorded non-reversed commission', Icons.percent_outlined,
              money: true),
          _metric(
              'Customers',
              customerCounts['total'],
              '${_number(customerCounts['active'])} active · ${_number(customerCounts['inactive'])} inactive',
              Icons.people_outline),
          _metric(
              'Open support',
              support['open'],
              '${_number(support['escalated'])} escalated · ${_number(support['overdue'])} overdue',
              Icons.support_agent),
        ]),
        const SizedBox(height: 16),
        _card(
          'Recorded earnings trend',
          FinancialTrendChart(points: trends, currency: 'NGN'),
          caption:
              'Daily stored earnings within the selected $_period window. No extrapolation.',
        ),
        _card(
          'Period earnings context',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Daily: ${_money(financial['dailyEarnings'])}'),
            Text('Weekly: ${_money(financial['weeklyEarnings'])}'),
            Text('Monthly: ${_money(financial['monthlyEarnings'])}'),
            if ('${financial['notice'] ?? ''}'.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${financial['notice']}')),
          ]),
          caption: 'Stored ServicePay earnings, not gross turnover.',
        ),
        _card(
          'Recent transactions',
          _rows(_data['recentTransactions']).isEmpty
              ? const _EmptyState(
                  'No recent transactions are included in this response.')
              : Column(
                  children: _rows(_data['recentTransactions'])
                      .take(8)
                      .map((row) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.receipt_long_outlined),
                            title: Text(
                                '${row['reference'] ?? row['id'] ?? 'Transaction'}'),
                            subtitle: Text(
                                '${row['service'] ?? 'Service'} · ${row['status'] ?? 'Status'} · ${row['createdAt'] ?? 'Time unavailable'}'),
                            trailing: Text(_money(row['amount'])),
                          ))
                      .toList()),
          caption: 'Sampled operational records from the selected response.',
        ),
        _activityPanel(),
      ],
    ]);
  }

  Widget _activityPanel() {
    final rows = _rows(_data['activity']);
    return _card(
      'Recent workspace activity',
      rows.isEmpty
          ? const _EmptyState('No recorded staff activity in this coverage.')
          : Column(
              children: rows
                  .take(12)
                  .map((row) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history, size: 19),
                        title: Text('${row['action'] ?? 'Activity'}'),
                        subtitle: Text(
                            '${row['actorName'] ?? 'Operator unavailable'} · ${row['createdAt'] ?? 'Time unavailable'}'),
                      ))
                  .toList()),
    );
  }

  Widget _notice(String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: const Color(0xfffff6e7),
          border: Border.all(color: const Color(0xffead7ac)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xff725725),
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );

  Widget _failure(String message, VoidCallback retry) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 34),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          TextButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry')),
        ]),
      );

  Widget _transactions() => _EnterpriseTransactions(
        api: _api,
        permissions: _permissions,
        money: _money,
        titleCase: _titleCase,
      );

  Widget _customers() => ListView(padding: const EdgeInsets.all(14), children: [
        _sectionHeader('Customer operations',
            'Existing customer investigation and full support history, with a separate permission-gated status workflow.'),
        if (_allowed('customerManage'))
          _card(
            'Account status controls',
            _CustomerStatusForm(api: _api, enabled: true),
            caption:
                'Only standard ACTIVE / SUSPENDED status changes are requested. Reactivation is limited to unchanged operational holds; the server enforces eligibility.',
          )
        else
          _notice(
              'Customer status controls are unavailable without operations.customers.manage.'),
        SizedBox(
          height: 690,
          child: CustomerSupportOperationsCenter(api: _api),
        ),
      ]);

  Widget _services() {
    final controls = _rows(_data['serviceControls']);
    final services = _rows(_data['services']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      _sectionHeader('Service health',
          'Only recorded activity and explicitly captured errors are shown. Absence of errors is not a health guarantee.'),
      if (_operationError.isNotEmpty)
        MaterialBanner(
          content: Text(_operationError),
          actions: [
            TextButton(
              onPressed: () => setState(() => _operationError = ''),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      if (_loading && services.isEmpty)
        ...List.generate(3, (_) => const _SkeletonCard())
      else if (services.isEmpty)
        const _EmptyState('No service activity is available for this period.')
      else
        ...services.map((service) {
          final key = '${service['service'] ?? 'Unknown'}';
          final matches = controls.where((e) => '${e['key']}' == key).toList();
          final control = matches.isEmpty ? null : matches.first;
          final availability = '${service['availability'] ?? 'NO_ACTIVITY'}';
          final rate = service['errorRate'] is num
              ? '${(service['errorRate'] as num).toStringAsFixed(1)}%'
              : 'Unavailable';
          return _card(
            _titleCase(key),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                _tag('Status · ${_titleCase(availability)}'),
                _tag('Transactions · ${_number(service['total'])}'),
                _tag(
                    'Recorded errors · ${_number(service['recordedHttpErrors'])}'),
                _tag('Error rate · $rate'),
              ]),
              const SizedBox(height: 8),
              Text(
                  'Volume ${_money(service['volume'])} · Earnings ${_money(service['recordedEarnings'])} · Refunds ${_money(service['refundAmount'])}'),
              if (_numberValue(service['recordedHttpSamples']) > 0)
                Text(
                    'Recorded HTTP samples: ${_number(service['recordedHttpSamples'])}'),
              if (control != null && _allowed('serviceControl'))
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _changeService(key, control['enabled'] == true),
                    icon: Icon(control['enabled'] == true
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline),
                    label: Text(control['enabled'] == true
                        ? 'Request pause'
                        : 'Request enable'),
                  ),
                )
              else if (control == null)
                const Text(
                    'No safe feature-control adapter is exposed for this service.'),
            ]),
          );
        }),
      if (!_allowed('serviceControl'))
        _notice(
            'Service control is unavailable without an explicit operations.services.control grant.'),
    ]);
  }

  num _numberValue(dynamic value) => value is num ? value : 0;

  Future<void> _changeService(String key, bool currentlyEnabled) async {
    final reason = await _reasonDialog('Service availability change');
    if (!mounted || reason == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            currentlyEnabled ? 'Pause $key service?' : 'Enable $key service?'),
        content: Text(
            'This submits an audited request to the existing safe feature-control adapter. Reason: $reason'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm change')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _operationError = '');
    try {
      await _api.updateServiceStatus(
        key,
        enabled: !currentlyEnabled,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service control request recorded.')));
      await _load();
    } catch (error) {
      if (mounted) {
        setState(
            () => _operationError = '$error'.replaceFirst('Exception: ', ''));
        _showError(error);
      }
    }
  }

  Widget _reports() => ListView(padding: const EdgeInsets.all(16), children: [
        _sectionHeader('Operational reports',
            'Exports are generated by the reporting service and downloaded byte-for-byte from the protected endpoint.'),
        _card(
          'Export selected period',
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final format in const ['csv', 'xlsx', 'pdf'])
              FilledButton.tonalIcon(
                onPressed:
                    _allowed('reportExport') ? () => _export(format) : null,
                icon: const Icon(Icons.download_outlined),
                label: Text(format.toUpperCase()),
              ),
          ]),
          caption:
              'Period: ${_titleCase(_period)} · ${_data['from'] ?? 'coverage unavailable'} to ${_data['to'] ?? ''}',
        ),
        if (!_allowed('reportExport'))
          _notice(
              'Exports are unavailable without an explicit report-export permission.'),
      ]);

  Future<void> _export(String format) async {
    try {
      final file = await _api.export(period: _period, format: format);
      await downloadControlCenterBytes(
          file.bytes, file.contentType, file.filename);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${file.filename} downloaded.')));
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Widget _staff() {
    final staff = _rows(_data['staff']);
    final coverage = _map(_data['staffCoverage']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      _sectionHeader('Staff performance',
          'Workload and resolution metrics for the selected period. Staff account and role administration stays protected.'),
      if (coverage['truncated'] == true)
        _notice(
            'Staff listing is capped at ${coverage['limit'] ?? 100}; the response is truncated.'),
      if (staff.isEmpty)
        const _EmptyState('No staff performance records are available.')
      else
        ...staff.map((person) => _card(
              '${person['name'] ?? 'Staff member'}',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    '${_titleCase(person['role'])} · ${_titleCase(person['status'])}'),
                const SizedBox(height: 6),
                Text(
                    '${_number(person['assigned'])} assigned · ${_number(person['resolved'])} resolved · ${person['resolutionRate'] ?? '—'}% resolution'),
                Text(
                    'Avg response ${_duration(person['averageResponseMs'])} · avg resolution ${_duration(person['averageResolutionMs'])}'),
                if (_staffHistoryAllowed)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _showStaffHistory(person),
                      icon: const Icon(Icons.history),
                      label: const Text('View activity history'),
                    ),
                  ),
                if (_allowed('staffManage'))
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _open(const StaffManagementScreen()),
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: const Text('Staff administration'),
                    ),
                  ),
              ]),
            )),
      if (!_allowed('staffManage'))
        _notice(
            'Staff account and role administration is unavailable here. Performance data remains read-only.'),
    ]);
  }

  Future<void> _showStaffHistory(Map<String, dynamic> person) async {
    final id = '${person['id'] ?? ''}';
    if (id.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 42,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );
    try {
      final result = await _api.staffHistory(id);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final data = _map(result['data']);
      final rows = _rows(data['items'] ?? data['history'] ?? data['activity']);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${person['name'] ?? 'Staff'} · activity'),
          content: SizedBox(
            width: 520,
            child: rows.isEmpty
                ? const _EmptyState('No staff activity history is available.')
                : ListView(
                    shrinkWrap: true,
                    children: rows
                        .map((row) => ListTile(
                              dense: true,
                              title: Text(
                                  '${row['action'] ?? row['type'] ?? 'Activity'}'),
                              subtitle: Text(
                                  '${row['createdAt'] ?? 'Time unavailable'}'),
                            ))
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close')),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _showError(error);
      }
    }
  }

  String _duration(dynamic millis) {
    if (millis is! num) return 'Unavailable';
    final seconds = millis / 1000;
    return seconds < 60
        ? '${seconds.toStringAsFixed(1)} sec'
        : '${(seconds / 60).toStringAsFixed(1)} min';
  }

  Widget _support() => ListView(padding: const EdgeInsets.all(16), children: [
        _sectionHeader('Support operations',
            'Assignment, conversation, escalation and resolution remain in the established support desk workflow.'),
        _card(
          'Support desk',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Open ${_number(_map(_data['support'])['open'])} · '
                'Escalated ${_number(_map(_data['support'])['escalated'])} · '
                'Overdue ${_number(_map(_data['support'])['overdue'])}'),
            const SizedBox(height: 8),
            Text(
                'Average response ${_duration(_map(_data['support'])['averageResponseMs'])} · '
                'average resolution ${_duration(_map(_data['support'])['averageResolutionMs'])}'),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _open(const AdminCustomerSupportScreen()),
              icon: const Icon(Icons.support_agent),
              label: const Text('Open support desk'),
            ),
          ]),
          caption: '${_map(_data['support'])['coverageNotice'] ?? ''}',
        ),
        if (!_allowed('supportManage'))
          _notice(
              'The server will enforce existing support.assign / support.resolve grants. This dashboard does not grant support access.'),
      ]);

  Widget _alerts() {
    final alerts = _rows(_data['alerts']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      _sectionHeader('Operational alerts',
          'Alerts are based on captured operational signals, not inferred provider status.'),
      if (alerts.isEmpty)
        const _EmptyState('No alerts were returned for this period.')
      else
        ...alerts.map((alert) => _card(
              '${_titleCase(alert['severity'])} · ${alert['code'] ?? 'Signal'}',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${alert['message'] ?? 'No alert description supplied.'}'),
                const SizedBox(height: 6),
                Text(
                    'Count ${_number(alert['count'])} · observed ${alert['observedAt'] ?? 'time unavailable'}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xff6d8077))),
              ]),
            )),
    ]);
  }

  Future<String?> _reasonDialog(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: 'Reason', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => controller.text.trim().length < 4
                ? null
                : Navigator.pop(context, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$error'.replaceFirst('Exception: ', '')),
        backgroundColor: const Color(0xff8b3d31)));
  }

  Widget _tabBody() => switch (_section) {
        'Executive' => _executive(),
        'Transactions' => _transactions(),
        'Customers' => _customers(),
        'Services' => _services(),
        'Support' => _support(),
        'Reports' => _reports(),
        'Staff' => _staff(),
        'Alerts' => _alerts(),
        _ => _executive(),
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xfff2f6f3),
        appBar: AppBar(
          titleSpacing: 18,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ServicePay operations',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              Text('CONTROL CENTER',
                  style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(children: [
          Container(
            width: double.infinity,
            color: const Color(0xffe3eee7),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final section in const [
                  'Executive',
                  'Transactions',
                  'Customers',
                  'Services',
                  'Support',
                  'Reports',
                  'Staff',
                  'Alerts',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(section),
                      selected: _section == section,
                      onSelected: (_) => setState(() => _section = section),
                      selectedColor: const Color(0xff1b725f),
                      labelStyle: TextStyle(
                          color: _section == section
                              ? Colors.white
                              : const Color(0xff31594b),
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                      side: BorderSide(
                          color: _section == section
                              ? const Color(0xff1b725f)
                              : const Color(0xffc8d9cf)),
                      showCheckmark: false,
                    ),
                  ),
              ]),
            ),
          ),
          if (_loading && _data.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (_error.isNotEmpty && _data.isNotEmpty)
            MaterialBanner(
              content: Text(_error),
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry'))
              ],
            ),
          Expanded(
              child: RefreshIndicator(onRefresh: _refresh, child: _tabBody())),
        ]),
      );
}

class _EnterpriseTransactions extends StatefulWidget {
  const _EnterpriseTransactions({
    required this.api,
    required this.permissions,
    required this.money,
    required this.titleCase,
  });
  final AdminStaffWorkspaceApi api;
  final Map<String, dynamic> permissions;
  final String Function(dynamic) money;
  final String Function(dynamic) titleCase;

  @override
  State<_EnterpriseTransactions> createState() =>
      _EnterpriseTransactionsState();
}

class _EnterpriseTransactionsState extends State<_EnterpriseTransactions> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _min = TextEditingController();
  final TextEditingController _max = TextEditingController();
  String _status = '';
  String _service = '';
  String _from = '';
  String _to = '';
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = '';
      _page = page;
    });
    try {
      final response = await widget.api.transactions(
        query: _search.text.trim(),
        status: _status,
        type: _service,
        from: _from,
        to: _to,
        minAmount: _min.text.trim(),
        maxAmount: _max.text.trim(),
        page: page,
        limit: 20,
      );
      final data = _map(response['data']);
      if (!mounted) return;
      setState(() {
        _items = data['items'] is List
            ? (data['items'] as List).whereType<Map>().map(_map).toList()
            : <Map<String, dynamic>>[];
        _total = (data['total'] as num?)?.toInt() ?? 0;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseDate(bool start) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: DateTime.now(),
    );
    if (picked == null) return;
    final value =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      if (start) {
        _from = value;
      } else {
        _to = value;
      }
    });
    _load();
  }

  Future<void> _details(Map<String, dynamic> row) async {
    final id = '${row['id'] ?? row['_id'] ?? ''}';
    if (id.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (context) => const AlertDialog(
        content: SizedBox(
            height: 40, child: Center(child: CircularProgressIndicator())),
      ),
    );
    try {
      final detail = await widget.api.transactionDetail(id);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final value = _map(detail['data']);
      await showDialog<void>(
        context: context,
        builder: (context) => _TransactionDetailDialog(
          detail: value,
          row: row,
          permissions: widget.permissions,
          api: widget.api,
          money: widget.money,
          titleCase: widget.titleCase,
          onRefundDone: () => _load(page: _page),
        ),
      );
    } catch (error) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          AdminTransactionReliabilityPanel(api: widget.api),
          const SizedBox(height: 8),
          Text('Transaction investigation',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xff173e35),
                  )),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              labelText: 'Search reference or customer',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _loading ? null : () => _load(),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                value: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  ['', 'All statuses'],
                  ['SUCCESSFUL', 'Successful'],
                  ['FAILED', 'Failed'],
                  ['PENDING', 'Pending'],
                  ['REFUNDED', 'Refunded'],
                ]
                    .map(
                        (e) => DropdownMenuItem(value: e[0], child: Text(e[1])))
                    .toList(),
                onChanged: (v) {
                  _status = v ?? '';
                  _load();
                },
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                value: _service,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Service'),
                items: const [
                  ['', 'All services'],
                  ['AIRTIME', 'Airtime'],
                  ['DATA', 'Data'],
                  ['ELECTRICITY', 'Electricity'],
                  ['CABLE', 'Cable'],
                  ['TRANSFER', 'Transfer'],
                ]
                    .map(
                        (e) => DropdownMenuItem(value: e[0], child: Text(e[1])))
                    .toList(),
                onChanged: (v) {
                  _service = v ?? '';
                  _load();
                },
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _chooseDate(true),
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_from.isEmpty ? 'From date' : _from),
            ),
            OutlinedButton.icon(
              onPressed: () => _chooseDate(false),
              icon: const Icon(Icons.event_outlined),
              label: Text(_to.isEmpty ? 'To date' : _to),
            ),
            SizedBox(
              width: 125,
              child: TextField(
                controller: _min,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Min ₦'),
                onSubmitted: (_) => _load(),
              ),
            ),
            SizedBox(
              width: 125,
              child: TextField(
                controller: _max,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max ₦'),
                onSubmitted: (_) => _load(),
              ),
            ),
            FilledButton.tonal(
                onPressed: () => _load(), child: const Text('Apply amount')),
          ]),
          const SizedBox(height: 8),
          if (_error.isNotEmpty)
            MaterialBanner(content: Text(_error), actions: [
              TextButton(
                  onPressed: () => _load(page: _page),
                  child: const Text('Retry'))
            ])
          else if (_loading && _items.isEmpty)
            ...List.generate(4, (_) => const _SkeletonCard())
          else if (_items.isEmpty)
            const _EmptyState('No transactions match these filters.')
          else
            ..._items.map((row) => Card(
                  child: ListTile(
                    onTap: () => _details(row),
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(
                        '${row['reference'] ?? row['id'] ?? 'Transaction'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${widget.titleCase(row['service'] ?? row['type'])} · ${widget.titleCase(row['status'])}\n${row['createdAt'] ?? 'Time unavailable'}',
                      maxLines: 2,
                    ),
                    trailing: Text(widget.money(row['amount'])),
                    isThreeLine: true,
                  ),
                )),
          if (_loading && _items.isNotEmpty) const LinearProgressIndicator(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Page $_page · ${_total.toString()} records'),
            Row(children: [
              IconButton(
                onPressed: _page > 1 && !_loading
                    ? () => _load(page: _page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: _page * 20 < _total && !_loading
                    ? () => _load(page: _page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
          ]),
        ],
      );
}

class _TransactionDetailDialog extends StatefulWidget {
  const _TransactionDetailDialog({
    required this.detail,
    required this.row,
    required this.permissions,
    required this.api,
    required this.money,
    required this.titleCase,
    required this.onRefundDone,
  });
  final Map<String, dynamic> detail;
  final Map<String, dynamic> row;
  final Map<String, dynamic> permissions;
  final AdminStaffWorkspaceApi api;
  final String Function(dynamic) money;
  final String Function(dynamic) titleCase;
  final Future<void> Function() onRefundDone;

  @override
  State<_TransactionDetailDialog> createState() =>
      _TransactionDetailDialogState();
}

class _TransactionDetailDialogState extends State<_TransactionDetailDialog> {
  late final AdminManualRefundsApi _refunds = AdminManualRefundsApi();

  @override
  void dispose() {
    _refunds.close();
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map(_map).toList()
      : <Map<String, dynamic>>[];

  Future<void> _refund() async {
    final id = '${widget.row['id'] ?? widget.row['_id'] ?? ''}';
    try {
      final response = await _refunds.transaction(id);
      final transaction = _map(response['transaction']);
      if (!mounted || transaction.isEmpty) return;
      final eligibility = _map(widget.detail['refundEligibility']);
      if (eligibility.isNotEmpty) transaction['refund'] = eligibility;
      final intent = await _refunds.loadIntent(id);
      if (!mounted) return;
      final completed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => ManualRefundDialog(
          transaction: transaction,
          canExecute: response['canExecute'] == true,
          initialReason: intent?.reason ?? '',
          reasonLocked: intent != null,
          initialProviderRiskAcknowledged:
              intent?.providerRiskAcknowledged ?? false,
          formatMoney: (value) => widget.money(value),
          formatText: widget.titleCase,
          formatDate: (value) => '$value',
          onSubmit: (reason, riskAcknowledged) async {
            try {
              await _refunds.submitRefund(
                id,
                reason: reason,
                providerRiskAcknowledged: riskAcknowledged,
              );
              await widget.onRefundDone();
              return null;
            } on ManualRefundApiException catch (error) {
              return error.message;
            } catch (_) {
              return 'The request could not be confirmed. Retry using the same request.';
            }
          },
        ),
      );
      if (completed == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Refund request confirmed.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaction = _map(widget.detail['transaction']);
    final customer = _map(widget.detail['customer']);
    final diagnostic = _map(widget.detail['providerDiagnostics']);
    final eligibility = _map(widget.detail['refundEligibility']);
    final blockers = eligibility['blockers'] is List
        ? (eligibility['blockers'] as List).map((item) => '$item').toList()
        : <String>[];
    return AlertDialog(
      title: Text(
          '${transaction['reference'] ?? widget.row['reference'] ?? 'Transaction detail'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detail('Status', widget.titleCase(transaction['status'])),
              _detail(
                  'Service',
                  widget.titleCase(
                      transaction['service'] ?? transaction['type'])),
              _detail('Amount', widget.money(transaction['amount'])),
              _detail(
                  'Created', '${transaction['createdAt'] ?? 'Unavailable'}'),
              _detail(
                  'Refund eligibility',
                  eligibility['eligible'] == true
                      ? 'Eligible'
                      : 'Not eligible'),
              if (blockers.isNotEmpty)
                _detail('Eligibility blockers', blockers.join(' · ')),
              if (eligibility['overrideAcknowledgementRequired'] == true)
                _detail(
                  'Override acknowledgement',
                  '${eligibility['overrideWarning'] ?? 'Additional acknowledgement is required.'}',
                ),
              const Divider(),
              const Text('Customer · masked',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              _detail('Phone', '${customer['phone'] ?? 'Unavailable'}'),
              _detail('Email', '${customer['email'] ?? 'Unavailable'}'),
              _detail('Wallet balance · view only',
                  widget.money(customer['walletBalance'])),
              const Divider(),
              const Text('Provider diagnostics · safe summary',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              _detail('Code', '${diagnostic['code'] ?? 'Unavailable'}'),
              _detail('Status', '${diagnostic['status'] ?? 'Unavailable'}'),
              _detail('Message', '${diagnostic['message'] ?? 'Unavailable'}'),
              _detail('Processing duration',
                  '${widget.detail['processingDurationMs'] ?? 'Unavailable'} ms'),
              const Divider(),
              const Text('Transaction history',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              ..._rows(widget.detail['history']).map((item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title:
                        Text('${item['action'] ?? item['status'] ?? 'Update'}'),
                    subtitle: Text('${item['createdAt'] ?? ''}'),
                  )),
              if (_rows(widget.detail['history']).isEmpty)
                const Text('No transaction history records were returned.'),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.permissions['refund'] == true &&
            widget.detail['canRefund'] == true)
          FilledButton.tonalIcon(
            onPressed: _refund,
            icon: const Icon(Icons.undo),
            label: const Text('Review refund'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 155,
              child: Text(label,
                  style:
                      const TextStyle(color: Color(0xff708279), fontSize: 12))),
          Expanded(
              child: SelectableText(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12))),
        ]),
      );
}

class _CustomerStatusForm extends StatefulWidget {
  const _CustomerStatusForm({required this.api, required this.enabled});
  final AdminStaffWorkspaceApi api;
  final bool enabled;

  @override
  State<_CustomerStatusForm> createState() => _CustomerStatusFormState();
}

class _CustomerStatusFormState extends State<_CustomerStatusForm> {
  final _id = TextEditingController();
  final _reason = TextEditingController();
  String _status = 'SUSPENDED';
  bool _saving = false;

  @override
  void dispose() {
    _id.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await widget.api.updateCustomerStatus(
        _id.text.trim(),
        status: _status,
        reason: _reason.text.trim(),
      );
      if (!mounted) return;
      _reason.clear();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer status request recorded.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        TextField(
          controller: _id,
          enabled: widget.enabled && !_saving,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'Customer ID',
              hintText: 'Enter an ordinary customer account ID'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _status,
          decoration: const InputDecoration(labelText: 'Requested status'),
          items: const [
            DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
            DropdownMenuItem(value: 'SUSPENDED', child: Text('Suspended')),
          ],
          onChanged: widget.enabled && !_saving
              ? (value) => setState(() => _status = value ?? 'SUSPENDED')
              : null,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _reason,
          enabled: widget.enabled && !_saving,
          onChanged: (_) => setState(() {}),
          minLines: 2,
          maxLines: 3,
          decoration:
              const InputDecoration(labelText: 'Reason required for audit'),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: !widget.enabled ||
                    _saving ||
                    _id.text.trim().isEmpty ||
                    _reason.text.trim().length < 4
                ? null
                : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.shield_outlined),
            label: const Text('Apply status change'),
          ),
        ),
        if (!widget.enabled)
          const Align(
              alignment: Alignment.centerLeft,
              child: Text('Requires explicit customer-management permission.',
                  style: TextStyle(fontSize: 11))),
      ]);
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 160,
                height: 13,
                decoration: BoxDecoration(
                    color: const Color(0xffe5eee8),
                    borderRadius: BorderRadius.circular(5))),
            const SizedBox(height: 12),
            Container(
                width: double.infinity,
                height: 9,
                decoration: BoxDecoration(
                    color: const Color(0xffedf2ee),
                    borderRadius: BorderRadius.circular(5))),
          ]),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: const Color(0xfff7faf7),
            border: Border.all(color: const Color(0xffdfe9e3)),
            borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          const Icon(Icons.inbox_outlined, color: Color(0xff668176)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xff60756b))),
        ]),
      );
}

Widget _tag(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
          color: const Color(0xffedf4ef),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: const TextStyle(fontSize: 10, color: Color(0xff436557))),
    );
