import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_customer_leaderboard_api.dart';
import 'admin_control_center_download.dart';

class AdminCustomerLeaderboardScreen extends StatefulWidget {
  const AdminCustomerLeaderboardScreen(
      {super.key, this.canUpdate = false, this.api});
  final bool canUpdate;
  final AdminCustomerLeaderboardApi? api;
  @override
  State<AdminCustomerLeaderboardScreen> createState() =>
      _AdminCustomerLeaderboardScreenState();
}

class _AdminCustomerLeaderboardScreenState
    extends State<AdminCustomerLeaderboardScreen> {
  late final AdminCustomerLeaderboardApi _api;
  bool _loading = true, _saving = false, _settingsLoading = true;
  String? _error;
  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _report = {};
  List<String> _months = [];
  List<String> _services = [];
  String _month = _currentLagosMonth();
  int _limit = 10;
  String _sort = 'count';
  bool _enabled = false;
  double _minimum = 0;
  int _revision = 0;
  final _minimumController = TextEditingController();
  static const _ink = Color(0xFF18382F);
  static const _green = Color(0xFF08783E);

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? AdminCustomerLeaderboardApi();
    _loadAll();
  }

  @override
  void dispose() {
    _minimumController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _settingsLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([_api.settings(), _api.history()]);
      final settings = Map<String, dynamic>.from(results[0]['data'] as Map);
      final historyData = Map<String, dynamic>.from(results[1]['data'] as Map);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _months = (historyData['months'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        _enabled = settings['enabled'] == true;
        _services = (settings['eligibleServices'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        _minimum = (settings['minAmount'] as num?)?.toDouble() ?? 0;
        _revision = (settings['revision'] as num?)?.toInt() ?? 0;
        _minimumController.text =
            _minimum.toStringAsFixed(_minimum % 1 == 0 ? 0 : 2);
        _settingsLoading = false;
      });
      await _loadReport();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
          _settingsLoading = false;
        });
      }
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.report(_month, _limit, _sort);
      if (mounted) {
        setState(() {
          _report = Map<String, dynamic>.from(result['data'] as Map);
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    final parsed = double.tryParse(_minimumController.text.trim());
    final rawAmount = _minimumController.text.trim();
    final decimals =
        rawAmount.contains('.') ? rawAmount.split('.').last.length : 0;
    if (_enabled && _services.isEmpty) {
      _notice(
          'Select at least one qualifying service before enabling Champions.');
      return;
    }
    if (parsed == null || parsed < 0 || parsed > 1000000000 || decimals > 2) {
      _notice(
          'Enter an amount from ₦0 to ₦1,000,000,000 with at most two decimal places.');
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await _api.updateSettings({
        'enabled': _enabled,
        'eligibleServices': _services,
        'minAmount': parsed,
        'revision': _revision
      });
      final data = Map<String, dynamic>.from(result['data'] as Map);
      if (mounted) {
        setState(() {
          _settings = data;
          _revision = (data['revision'] as num?)?.toInt() ?? _revision;
          _saving = false;
        });
      }
      await _loadReport();
      _notice(
          'Rules saved. Historical reports are recalculated using the currently selected rules.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _notice(error.toString());
      if (error is AdminCustomerLeaderboardException &&
          error.statusCode == 409) {
        await _loadAll();
      }
    }
  }

  Future<void> _export() async {
    try {
      final csv = await _api.export(_month, _limit, _sort);
      await downloadControlCenterCsv(
          csv, 'servicepay-champions-$_month-$_sort.csv');
      _notice('CSV export started.');
    } catch (error) {
      _notice(error.toString());
    }
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  String _naira(num value) {
    final whole = value.truncate().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]},');
    final fraction = value % 1 == 0
        ? ''
        : value.abs().remainder(1).toStringAsFixed(2).substring(1);
    return '₦$whole$fraction';
  }

  @override
  Widget build(BuildContext context) {
    final data = _report;
    final rows = (data['rows'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final available = (_settings['availableServices'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F3),
      appBar: AppBar(
        title: const Text('Customer Leaderboard'),
        backgroundColor: const Color(0xFFF4F7F3),
        foregroundColor: _ink,
        elevation: 0,
        actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh))
        ],
      ),
      body: RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
            children: [
              _hero(),
              const SizedBox(height: 16),
              if (widget.canUpdate) _settingsCard(available),
              if (widget.canUpdate) const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child:
                        _select<int>('Rows', _limit, const [10, 50, 100], (v) {
                  setState(() => _limit = v);
                  _loadReport();
                }, (v) => '$v')),
                const SizedBox(width: 10),
                Expanded(
                    child: _select<String>(
                        'Rank by', _sort, const ['count', 'value'], (v) {
                  setState(() => _sort = v);
                  _loadReport();
                }, (v) => v == 'count' ? 'Transactions' : 'Value')),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                IconButton(
                    onPressed: () => _stepMonth(-1),
                    tooltip: 'Previous month',
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                    child: Center(
                        child: DropdownButton<String>(
                  value: _months.contains(_month) ? _month : null,
                  hint: Text(_monthTitle(
                      DateTime.tryParse('$_month-01') ?? DateTime.now())),
                  items: _months
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _month = v);
                      _loadReport();
                    }
                  },
                ))),
                IconButton(
                    onPressed: () => _stepMonth(1),
                    tooltip: 'Next month',
                    icon: const Icon(Icons.chevron_right)),
                IconButton(
                    onPressed: _export,
                    tooltip: 'Export CSV',
                    icon: const Icon(Icons.download_outlined)),
              ]),
              if (_loading) const LinearProgressIndicator(color: _green),
              if (_error != null)
                _stateCard('Report unavailable', _error!, retry: _loadAll),
              if (!_loading && _error == null && data['enabled'] == false)
                _stateCard('Leaderboard disabled',
                    'Enable Champions in the rules panel to publish reports.'),
              if (!_loading && _error == null && data['enabled'] != false) ...[
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                        '${data['totalCustomers'] ?? 0} customers · $_month · Africa/Lagos',
                        style: const TextStyle(
                            color: Color(0xFF64766C), fontSize: 12))),
                if (rows.isEmpty)
                  _stateCard('No qualifying activity',
                      'No customer activity matched the current rules for this month.'),
                if (data['rules'] is Map)
                  _reportRules(Map<String, dynamic>.from(data['rules'] as Map)),
                for (final row in rows) _row(row),
                if (data['cachedUntil'] != null)
                  Center(
                      child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                              'Report cache expires ${data['cachedUntil']}',
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF75847B))))),
              ],
            ],
          )),
    );
  }

  Widget _hero() => Container(
        padding: const EdgeInsets.all(20),
        decoration:
            BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(20)),
        child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.emoji_events_rounded,
                  color: Color(0xFFF0C76A), size: 28),
              SizedBox(height: 11),
              Text('SERVICEPAY CHAMPIONS',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
              SizedBox(height: 5),
              Text(
                  'Privacy-safe monthly activity reporting. No rewards and no identifying customer details.',
                  style: TextStyle(color: Color(0xFFC6D8CD), height: 1.4)),
            ]),
      );

  Widget _settingsCard(List<String> available) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE1E9E2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text('Programme rules',
                    style: TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800))),
            if (_saving)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
          ]),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Champions'),
              subtitle: const Text(
                  'Controls dashboard visibility and report availability.'),
              value: _enabled,
              onChanged: _saving ? null : (v) => setState(() => _enabled = v)),
          const Text('Qualifying services',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          if (_settingsLoading) const LinearProgressIndicator(),
          if (!_settingsLoading && available.isEmpty)
            const Text('No services are currently available to select.'),
          for (final service in available)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(service),
              value: _services.contains(service),
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                        if (value == true) {
                          if (!_services.contains(service)) {
                            _services.add(service);
                          }
                        } else {
                          _services.remove(service);
                        }
                      }),
            ),
          TextField(
            controller: _minimumController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
            ],
            decoration: const InputDecoration(
                labelText: 'Minimum qualifying amount',
                prefixText: '₦ ',
                helperText:
                    'Successful transactions at or above this amount qualify.'),
          ),
          const SizedBox(height: 12),
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                  onPressed: _saving ? null : _saveSettings,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save rules'))),
          const Text(
              'Historical months are recalculated using the currently selected rules.',
              style: TextStyle(color: Color(0xFF687A70), fontSize: 11)),
        ]),
      );

  Widget _reportRules(Map<String, dynamic> rules) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
              color: const Color(0xFFEAF4EC),
              borderRadius: BorderRadius.circular(13)),
          child: Text(
            'Rules applied: ${(rules['eligibleServices'] as List? ?? []).join(', ')} · minimum ₦${rules['minAmount'] ?? 0} · period based on ${rules['periodBasis'] == 'createdAt' ? 'creation date' : 'report period'}. ${rules['historyUsesCurrentRules'] == true ? 'Historical reports use current rules.' : ''}',
            style: const TextStyle(
                color: Color(0xFF526A5D), fontSize: 11, height: 1.4),
          ),
        ),
      );

  Widget _select<T>(String label, T value, List<T> choices,
          ValueChanged<T> onChanged, String Function(T) title) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF687A70))),
        DropdownButton<T>(
            isExpanded: true,
            value: value,
            items: choices
                .map((v) => DropdownMenuItem(value: v, child: Text(title(v))))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            }),
      ]);

  Widget _row(Map<String, dynamic> row) {
    final rank = (row['rank'] as num?)?.toInt() ?? 0;
    const medals = [
      Icons.workspace_premium_rounded,
      Icons.military_tech_rounded,
      Icons.workspace_premium_outlined
    ];
    const colors = [Color(0xFFC38B2B), Color(0xFF86989B), Color(0xFFB67955)];
    return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          SizedBox(
              width: 34,
              child: rank <= 3 && rank > 0
                  ? Icon(medals[rank - 1], color: colors[rank - 1])
                  : Text('#$rank',
                      style: const TextStyle(fontWeight: FontWeight.w800))),
          Expanded(
              child: Text(
                  row['displayName']?.toString() ?? 'ServicePay customer',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${row['count'] ?? 0} txn',
                style:
                    const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
            Text(_naira((row['value'] as num?) ?? 0),
                style: const TextStyle(color: _green, fontSize: 12))
          ]),
        ]));
  }

  Widget _stateCard(String title, String body,
          {Future<void> Function()? retry}) =>
      Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center),
            if (retry != null)
              TextButton.icon(
                  onPressed: retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'))
          ]));
  Future<void> _stepMonth(int direction) async {
    final current = DateTime.tryParse('$_month-01') ?? DateTime.now();
    final next = DateTime(current.year, current.month + direction);
    final lagosNow = DateTime.now().toUtc().add(const Duration(hours: 1));
    if (next.year < 2010 ||
        next.isAfter(DateTime(lagosNow.year, lagosNow.month))) {
      return;
    }
    setState(
        () => _month = '${next.year}-${next.month.toString().padLeft(2, '0')}');
    await _loadReport();
  }

  String _monthTitle(DateTime date) {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  static String _currentLagosMonth() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 1));
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }
}
