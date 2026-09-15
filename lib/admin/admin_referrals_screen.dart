import 'package:flutter/material.dart';

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
      });
    }
    try {
      final responses = await Future.wait(<Future<Map<String, dynamic>>>[
        _api.summary(),
        _api.search(
          query: _search.text,
          category: _category,
          rewardStatus: _rewardStatus,
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
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
                    _text(progress['rewardReference'] ?? _rewardReference(row)),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Qualification progress',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(_progressLabel(progress.isEmpty ? row : progress)),
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
                        title: Text(
                          _text(
                            event['event'] ?? event['action'],
                            'Audit event',
                          ),
                        ),
                        subtitle: Text(
                          _text(
                            event['occurredAt'] ??
                                event['createdAt'] ??
                                event['timestamp'],
                          ),
                        ),
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
                  onSubmitted: (_) => _load(page: 1),
                  decoration: const InputDecoration(
                    labelText: 'Search referrals',
                    hintText: 'Name or customer code',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              DropdownButton<String>(
                value: _category,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: '', child: Text('All categories')),
                  DropdownMenuItem(value: 'DATA', child: Text('Data')),
                  DropdownMenuItem(value: 'DELIVERY', child: Text('Delivery')),
                  DropdownMenuItem(
                    value: 'MARKETPLACE',
                    child: Text('Marketplace'),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _category = value ?? '');
                  _load(page: 1);
                },
              ),
              DropdownButton<String>(
                value: _rewardStatus,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: '', child: Text('All rewards')),
                  DropdownMenuItem(value: 'AWARDED', child: Text('Paid')),
                ],
                onChanged: (value) {
                  setState(() => _rewardStatus = value ?? '');
                  _load(page: 1);
                },
              ),
              FilledButton.icon(
                onPressed: () => _load(page: 1),
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Apply filters'),
              ),
            ],
          ),
        ),
      );

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
                      _status(row['qualificationStatus']),
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
                Wrap(
                  spacing: 14,
                  runSpacing: 5,
                  children: <Widget>[
                    Text('Category: ${_text(row['category'], 'Not selected')}'),
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
