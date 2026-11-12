import 'package:flutter/material.dart';
import 'admin_control_center_download.dart';
import 'admin_permissions.dart';
import 'customer_intelligence_screen.dart';
import 'executive_control_api.dart';
import 'executive_control_widgets.dart';

class ExecutiveControlScreen extends StatefulWidget {
  const ExecutiveControlScreen({
    super.key,
    this.api,
    this.initialAccess,
  });
  final ExecutiveControlApi? api;
  final AdminAccess? initialAccess;

  @override
  State<ExecutiveControlScreen> createState() => _ExecutiveControlScreenState();
}

class ExecutiveControlRoute extends StatefulWidget {
  const ExecutiveControlRoute({super.key});

  @override
  State<ExecutiveControlRoute> createState() => _ExecutiveControlRouteState();
}

class _ExecutiveControlRouteState extends State<ExecutiveControlRoute> {
  late final Future<AdminAccess> _access = AdminSessionStore.loadAccess();

  @override
  Widget build(BuildContext context) => FutureBuilder<AdminAccess>(
        future: _access,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final access = snapshot.data ??
              const AdminAccess(role: '', permissions: <String>{});
          final allowed = access.isHeadOffice ||
              (access.permissions.contains('executive.control_center.view') &&
                  access.has(AdminPermissions.usersView) &&
                  access.has(AdminPermissions.transactionsView));
          if (!allowed) {
            return const Scaffold(
              body: Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                      'Executive Control Center access is not available for this account.'),
                ),
              ),
            );
          }
          return ExecutiveControlScreen(initialAccess: access);
        },
      );
}

class _ExecutiveControlScreenState extends State<ExecutiveControlScreen> {
  late final ExecutiveControlApi _api;
  late final bool _ownsApi;
  Map<String, dynamic> _overview = {};
  final Map<String, Map<String, dynamic>> _sections = {};
  final Map<String, String> _sectionErrors = {};
  final Set<String> _loadingSections = {};
  final Set<String> _loadedSections = {};
  String _range = '7d';
  DateTimeRange? _custom;
  String _section = 'Overview';
  String _status = '';
  String _service = '';
  String _provider = '';
  String _transactionSort = 'date';
  bool _sortAscending = false;
  String _trendMeasure = 'count';
  String _fieldDimension = 'agent';
  int _fieldPage = 1;
  static const int _fieldLimit = 25;
  int _page = 1;
  int _limit = 20;
  bool _overviewLoading = true;
  int _requestGeneration = 0;
  String? _overviewError;
  DateTime? _lastUpdated;

  static const _ranges = <String, String>{
    'Today': 'today',
    'Yesterday': 'yesterday',
    '7 days': '7d',
    '30 days': '30d',
    'This month': 'thisMonth',
    'Last month': 'lastMonth',
    'This year': 'thisYear',
    'Custom': 'custom',
  };
  static const _allSections = [
    'Overview',
    'Customers',
    'Transactions',
    'Finance',
    'Marketing',
    'Field',
    'Health',
    'Reports',
  ];

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ExecutiveControlApi();
    _ownsApi = widget.api == null;
    _loadOverview();
  }

  @override
  void dispose() {
    if (_ownsApi) _api.close();
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  List<dynamic> _list(dynamic value) => value is List ? value : <dynamic>[];
  num _num(dynamic value) => value is num ? value : num.tryParse('$value') ?? 0;
  String _groupDigits(String value) => value.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]},');
  String _money(dynamic value) {
    if (value == null || (value is! num && num.tryParse('$value') == null)) {
      return 'Unavailable';
    }
    final parts = _num(value).toStringAsFixed(2).split('.');
    return '₦${_groupDigits(parts.first)}.${parts.last}';
  }

  String _count(dynamic value) => _groupDigits(_num(value).round().toString());
  String _formatDate(DateTime value) =>
      '${value.day} ${_month(value.month)} ${value.year}';
  String _formatDateTime(DateTime value) =>
      '${value.day} ${_month(value.month)}, ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  String _month(int month) => const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][month - 1];

  Map<String, dynamic> get _dateFilters => {
        'range': _range == 'custom' ? 'custom' : _range,
        if (_range == 'custom' && _custom != null)
          'from': _isoDay(_custom!.start),
        if (_range == 'custom' && _custom != null) 'to': _isoDay(_custom!.end),
      };

  Map<String, dynamic> get _financeFilters => {
        ..._dateFilters,
        if (_service.isNotEmpty) 'serviceType': _service,
      };

  Map<String, dynamic> get _filters => {
        ..._dateFilters,
        if (_service.isNotEmpty) 'serviceType': _service,
        if (_status.isNotEmpty) 'status': _status,
        if (_provider.isNotEmpty) 'provider': _provider,
      };

  String _isoDay(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _loadOverview() async {
    final generation = ++_requestGeneration;
    setState(() {
      _overviewLoading = true;
      _overviewError = null;
      _loadedSections.clear();
      _loadingSections.clear();
      _sections.clear();
      _fieldPage = 1;
    });
    try {
      final data = await _api
          .get('overview', {..._filters, 'page': _page, 'limit': _limit});
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _overview = data;
        _overviewLoading = false;
        _lastUpdated = DateTime.tryParse('${data['generatedAt']}')?.toLocal();
      });
      if (_section != 'Overview') {
        _loadSection(_section);
      }
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _overviewLoading = false;
        _overviewError = e.toString();
      });
    }
  }

  Future<void> _loadSection(String section, {bool retry = false}) async {
    final generation = _requestGeneration;
    final endpoint = switch (section) {
      'Finance' => 'finance',
      'Marketing' => 'marketing',
      'Field' => 'field',
      'Health' => 'health',
      _ => null,
    };
    if (endpoint == null || (_loadedSections.contains(section) && !retry)) {
      return;
    }
    setState(() {
      _loadingSections.add(section);
      _sectionErrors.remove(section);
    });
    try {
      final query = switch (section) {
        'Finance' => _financeFilters,
        'Marketing' || 'Health' || 'Field' => _dateFilters,
        _ => _filters,
      };
      if (section == 'Field') {
        query['dimension'] = _fieldDimension;
        query['page'] = _fieldPage;
        query['limit'] = _fieldLimit;
      }
      final data = await _api.get(endpoint, query);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _sections[section] = data;
        _loadedSections.add(section);
        _loadingSections.remove(section);
      });
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loadingSections.remove(section);
        _sectionErrors[section] = e.toString();
      });
    }
  }

  Future<void> _selectSection(String section) async {
    setState(() => _section = section);
    await _loadSection(section);
  }

  Future<void> _chooseCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2018),
      lastDate: now,
      initialDateRange: _custom ??
          DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
    );
    if (picked == null) return;
    setState(() {
      _custom = picked;
      _range = 'custom';
    });
    await _loadOverview();
  }

  Future<void> _setRange(String value) async {
    if (value == 'custom') return _chooseCustomRange();
    setState(() => _range = value);
    await _loadOverview();
  }

  Future<void> _export(String kind, String format) async {
    try {
      final filters = kind == 'finance'
          ? _financeFilters
          : kind == 'marketing'
              ? _dateFilters
              : _filters;
      final file =
          await _api.report(kind: kind, format: format, filters: filters);
      await downloadControlCenterBytes(
          file.bytes, file.contentType, file.filename);
    } catch (e) {
      if (mounted) _message(e.toString());
    }
  }

  void _message(String value) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(value)));

  bool get _financeAllowed =>
      _map(_overview['capabilities'])['finance'] == true;
  bool get _exportAllowed => _map(_overview['capabilities'])['export'] == true;
  Map<String, dynamic> get _overviewData => _map(_overview['overview']);
  Map<String, dynamic> get _customers => _map(_overview['customers']);
  Map<String, dynamic> get _transactions => _map(_overview['transactions']);

  void _drill(String? status, {bool customers = false}) {
    if (customers) {
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const CustomerIntelligenceScreen()));
      return;
    }
    setState(() {
      _section = 'Transactions';
      _status = status ?? '';
      _page = 1;
    });
    _loadOverview();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: executiveCanvas,
      body: SafeArea(
        child: Column(children: [
          _header(),
          Expanded(
            child: _overviewLoading
                ? _loading()
                : _overviewError != null
                    ? ExecutiveSectionError(
                        message: _overviewError!, onRetry: _loadOverview)
                    : _content(),
          ),
        ]),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
        decoration: const BoxDecoration(
          color: Color(0xFFFCFDFC),
          border: Border(bottom: BorderSide(color: Color(0xFFDCE6DF))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: executiveMint,
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.account_balance_outlined,
                  color: executiveGreen),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EXECUTIVE CONTROL CENTER',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800,
                            color: executiveGreen)),
                    Text('Business at a glance',
                        style: TextStyle(
                            color: executiveInk,
                            fontSize: 21,
                            fontWeight: FontWeight.w700)),
                  ]),
            ),
            IconButton(
                tooltip: 'Refresh overview',
                onPressed: _loadOverview,
                icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final entry in _ranges.entries)
                ChoiceChip(
                  key: Key('executive-range-${entry.value}'),
                  label: Text(entry.key),
                  selected: _range == entry.value,
                  onSelected: (_) => _setRange(entry.value),
                ),
              if (_lastUpdated != null)
                Text(
                  'Updated ${_formatDateTime(_lastUpdated!)} · Africa/Lagos',
                  style: const TextStyle(fontSize: 11, color: executiveMuted),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _visibleSections.map((name) {
                final selected = _section == name;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    key: Key('executive-section-$name'),
                    onPressed: () => _selectSection(name),
                    style: TextButton.styleFrom(
                      foregroundColor: selected ? Colors.white : executiveMuted,
                      backgroundColor:
                          selected ? executiveInk : Colors.transparent,
                    ),
                    child: Text(name),
                  ),
                );
              }).toList(),
            ),
          ),
        ]),
      );

  List<String> get _visibleSections => _allSections.where((section) {
        if (section == 'Finance') return _financeAllowed;
        if (section == 'Reports') return _exportAllowed;
        return true;
      }).toList();

  Widget _loading() => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Container(height: 120, decoration: _skeleton()),
          const SizedBox(height: 16),
          Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(
                  4,
                  (_) => Container(
                      width: 220, height: 132, decoration: _skeleton()))),
          const SizedBox(height: 18),
          Container(height: 280, decoration: _skeleton()),
        ],
      );
  BoxDecoration _skeleton() => BoxDecoration(
      color: const Color(0xFFE4EBE6), borderRadius: BorderRadius.circular(16));

  Widget _content() {
    if (_section == 'Overview') return _overviewContent();
    if (_section == 'Transactions' || _section == 'Customers') {
      return _overviewContent();
    }
    if (_section == 'Reports') return _reports();
    final error = _sectionErrors[_section];
    if (error != null) {
      return ExecutiveSectionError(
          message: error, onRetry: () => _loadSection(_section, retry: true));
    }
    if (_loadingSections.contains(_section)) return _loading();
    final data = _sections[_section];
    if (data == null) {
      return Center(
          child: OutlinedButton.icon(
              onPressed: () => _loadSection(_section),
              icon: const Icon(Icons.download_outlined),
              label: Text('Load $_section')));
    }
    return _sectionDetail();
  }

  Widget _overviewContent() {
    final overview = _overviewData;
    final metrics = [
      (
        'Registered customers',
        _count(overview['registeredCustomers']),
        'All registered accounts',
        Icons.groups_outlined,
        true,
        null
      ),
      (
        'Active customers',
        _count(overview['activeCustomers']),
        'Active in rolling window',
        Icons.person_outline,
        false,
        null
      ),
      (
        'Transactions',
        _count(overview['total']),
        'Canonical records · selected dates',
        Icons.receipt_long_outlined,
        false,
        ''
      ),
      (
        'Successful',
        _count(overview['successful']),
        'Completed transaction count',
        Icons.check_circle_outline,
        false,
        'SUCCESSFUL'
      ),
      (
        'Pending',
        _count(overview['pending']),
        'Awaiting final status',
        Icons.hourglass_empty,
        false,
        'PENDING'
      ),
      (
        'Failed',
        _count(overview['failed']),
        'Unsuccessful transaction count',
        Icons.error_outline,
        false,
        'FAILED'
      ),
      (
        'Successful volume',
        _money(overview['successfulVolume']),
        'Customer transaction value · not revenue',
        Icons.swap_horiz,
        true,
        'SUCCESSFUL'
      ),
    ];
    final finance = _map(_sections['Finance']);
    final financeTotals = _map(finance['totals']);
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: executiveInk,
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
                colors: [Color(0xFF173B35), Color(0xFF24594B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 12,
            children: [
              const SizedBox(
                width: 420,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('One business. Clear money lines.',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 7),
                      Text(
                          'Customer funds and transaction volume are not company revenue. Figures reflect the selected reporting window.',
                          style:
                              TextStyle(color: Color(0xFFD1E1D6), height: 1.4)),
                    ]),
              ),
              if (_financeAllowed)
                OutlinedButton.icon(
                  onPressed: () => _selectSection('Finance'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF8EBA9A))),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Review recorded revenue'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final cols = constraints.maxWidth >= 1080
              ? 4
              : constraints.maxWidth >= 620
                  ? 2
                  : 1;
          return GridView.count(
            crossAxisCount: cols,
            childAspectRatio: constraints.maxWidth < 620 ? 2.05 : 1.65,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: metrics
                .map((m) => ExecutiveMetric(
                      key: Key('executive-kpi-${m.$1}'),
                      label: m.$1,
                      value: m.$2,
                      note: m.$3,
                      icon: m.$4,
                      emphasis: m.$5,
                      onTap: m.$6 == null
                          ? (m.$1.contains('customer')
                              ? () => _drill(null, customers: true)
                              : null)
                          : () => _drill(m.$6),
                    ))
                .toList(),
          );
        }),
        if (_financeAllowed) ...[
          const SizedBox(height: 14),
          ExecutivePanel(
            title: 'Recorded revenue · known subtotal',
            subtitle:
                'Not complete company revenue. Customer-fund liabilities are separate and unavailable unless reconciled.',
            action: TextButton(
                onPressed: () => _loadSection('Finance'),
                child: const Text('Load finance')),
            child: _sections['Finance'] == null
                ? const Text('Finance data loads only when requested.',
                    style: TextStyle(color: executiveMuted))
                : Wrap(spacing: 28, runSpacing: 14, children: [
                    _fact(
                        'Known recorded revenue',
                        _nullableMoney(
                            financeTotals['recordedRevenue'], finance)),
                    _fact('Gross profit / margin',
                        _nullableMoney(financeTotals['grossProfit'], finance)),
                    _fact('Net profit', 'Unavailable'),
                  ]),
          ),
        ],
        const SizedBox(height: 14),
        _transactionPanel(),
        const SizedBox(height: 14),
        _customerPanel(),
        const SizedBox(height: 10),
        Text(
          'Timezone: Africa/Lagos · Customer categories use all-services rolling 30/60-day windows and are not changed by transaction filters.',
          style: const TextStyle(color: executiveMuted, fontSize: 11),
        ),
      ],
    );
  }

  Widget _transactionPanel() {
    final tx = _transactions;
    final items = _list(tx['items']).toList()
      ..sort((a, b) {
        final left = _map(a);
        final right = _map(b);
        int result;
        if (_transactionSort == 'amount') {
          result = _num(left['amount']).compareTo(_num(right['amount']));
        } else if (_transactionSort == 'status') {
          result = '${left['status']}'.compareTo('${right['status']}');
        } else {
          result = '${left['date']}'.compareTo('${right['date']}');
        }
        return _sortAscending ? result : -result;
      });
    final services = _list(tx['services']);
    final providers = _list(tx['providers']);
    return ExecutivePanel(
      title: 'Transaction monitor',
      subtitle: 'Canonical, deduplicated transactions · server-paginated',
      action: TextButton(
          onPressed: () => _selectSection('Transactions'),
          child: const Text('View monitor')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 8, children: [
          _dropdown(
              'Service',
              _service,
              [
                '',
                ...services.map((e) => '${_map(e)['service']}'),
              ],
              (v) => setState(() => _service = v)),
          _dropdown(
              'Status',
              _status,
              const [
                '',
                'SUCCESSFUL',
                'PENDING',
                'FAILED',
                'REFUNDED',
                'OTHER'
              ],
              (v) => setState(() => _status = v)),
          _dropdown(
              'Provider',
              _provider,
              ['', ...providers.map((e) => '${_map(e)['provider']}')],
              (v) => setState(() => _provider = v)),
          FilledButton.tonal(
              key: const Key('executive-filter-apply'),
              onPressed: () {
                _page = 1;
                _loadOverview();
              },
              child: const Text('Apply')),
          TextButton(
              key: const Key('executive-filter-reset'),
              onPressed: () {
                setState(() {
                  _service = '';
                  _status = '';
                  _provider = '';
                  _page = 1;
                });
                _loadOverview();
              },
              child: const Text('Reset')),
        ]),
        const SizedBox(height: 14),
        _trendPanel(),
        const SizedBox(height: 10),
        Row(children: [
          const Text('Current page sort',
              style: TextStyle(color: executiveMuted, fontSize: 12)),
          const SizedBox(width: 8),
          DropdownButton<String>(
            key: const Key('executive-sort-by'),
            value: _transactionSort,
            items: const [
              DropdownMenuItem(value: 'date', child: Text('Date')),
              DropdownMenuItem(value: 'amount', child: Text('Amount')),
              DropdownMenuItem(value: 'status', child: Text('Status')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _transactionSort = value);
            },
          ),
          IconButton(
            tooltip: _sortAscending ? 'Ascending' : 'Descending',
            onPressed: () => setState(() => _sortAscending = !_sortAscending),
            icon: Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
          ),
        ]),
        if (items.isEmpty)
          const Padding(
              padding: EdgeInsets.all(18),
              child: Text('No transactions match these dates and filters.'))
        else
          ...items.take(8).map(_transactionRow),
        const SizedBox(height: 8),
        Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                  'Page ${_map(tx['pagination'])['page'] ?? _page} of ${_map(tx['pagination'])['totalPages'] ?? 1}',
                  style: const TextStyle(color: executiveMuted, fontSize: 12)),
              IconButton(
                  tooltip: 'Previous page',
                  onPressed: _page > 1
                      ? () {
                          setState(() => _page--);
                          _loadOverview();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left)),
              DropdownButton<int>(
                value: _limit,
                items: const [10, 20, 50, 100]
                    .map((n) =>
                        DropdownMenuItem(value: n, child: Text('$n / page')))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _limit = value;
                    _page = 1;
                  });
                  _loadOverview();
                },
              ),
              IconButton(
                  tooltip: 'Next page',
                  onPressed: _page <
                          (_num(_map(tx['pagination'])['totalPages']).toInt())
                      ? () {
                          setState(() => _page++);
                          _loadOverview();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right)),
            ]),
      ]),
    );
  }

  Widget _trendPanel() {
    final trend = _list(_transactions['trend']).map(_map).toList();
    final volume = _trendMeasure == 'volume';
    final values = trend
        .map((row) =>
            _num(row[volume ? 'successfulVolume' : 'successful']).toDouble())
        .toList();
    final maxValue = values.fold<double>(0, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: executiveCanvas,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 8, children: [
          SizedBox(
            width: 280,
            child: Text(
              volume
                  ? 'Successful transaction volume · NGN'
                  : 'Successful transactions · count',
              style: const TextStyle(
                  color: executiveInk, fontWeight: FontWeight.w700),
            ),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'count', label: Text('Count')),
              ButtonSegment(value: 'volume', label: Text('Volume')),
            ],
            selected: {_trendMeasure},
            onSelectionChanged: (value) =>
                setState(() => _trendMeasure = value.first),
          ),
        ]),
        const SizedBox(height: 14),
        if (trend.isEmpty)
          const Text('No daily series returned for this period.',
              style: TextStyle(color: executiveMuted, fontSize: 12))
        else
          SizedBox(
            height: 108,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < trend.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Tooltip(
                        message:
                            '${trend[i]['date']}: ${volume ? _money(values[i]) : _count(values[i])}',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              i == 0 ||
                                      i == trend.length - 1 ||
                                      (i % ((trend.length / 5).ceil()) == 0)
                                  ? _compactDate('${trend[i]['date'] ?? ''}')
                                  : '',
                              maxLines: 1,
                              style: const TextStyle(
                                  color: executiveMuted, fontSize: 9),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height:
                                  maxValue == 0 ? 2 : 68 * values[i] / maxValue,
                              decoration: BoxDecoration(
                                color: const Color(0xFF4F9972),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ]),
    );
  }

  String _compactDate(String value) {
    final date = DateTime.tryParse(value);
    return date == null ? value : '${date.day}/${date.month}';
  }

  Widget _transactionRow(dynamic raw) {
    final item = _map(raw);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE8EEEA)))),
      child: Row(children: [
        const Icon(Icons.receipt_long_outlined,
            size: 17, color: executiveGreen),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '${item['service'] ?? 'Service'} · ${item['provider'] ?? 'Provider'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('${item['date'] ?? ''} · ${item['status'] ?? 'Unknown'}',
              style: const TextStyle(color: executiveMuted, fontSize: 11)),
        ])),
        Text(_money(item['amount']),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _customerPanel() {
    final summary = _map(_customers['summary']);
    final top = _list(_customers['topCount']).take(5);
    return ExecutivePanel(
      title: 'Customer pulse',
      subtitle: 'Categories are all-services rolling 30/60-day activity',
      action: TextButton(
          onPressed: () => _drill(null, customers: true),
          child: const Text('Customer intelligence')),
      child: Column(children: [
        Wrap(spacing: 20, runSpacing: 10, children: [
          for (final key in const [
            'frequent',
            'regular',
            'occasional',
            'declining',
            'inactive',
            'never'
          ])
            _fact(_title(key), _count(summary[key])),
          _fact('Retention',
              '${_num(summary['retentionRate']).toStringAsFixed(1)}%'),
          _fact('New registrations', _count(summary['newRegistrations'])),
        ]),
        const Divider(height: 28),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Most frequent customers',
              style: Theme.of(context).textTheme.titleSmall),
        ),
        const SizedBox(height: 8),
        if (top.isEmpty)
          const Align(
              alignment: Alignment.centerLeft,
              child: Text('No customer ranking is available for this period.'))
        else
          ...top.map((row) {
            final item = _map(row);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${item['name'] ?? 'Customer'}'),
              trailing: Text('${_count(item['count'])} transactions'),
            );
          }),
      ]),
    );
  }

  Widget _sectionDetail() {
    final data = _map(_sections[_section]);
    if (_section == 'Finance') {
      final financial = data;
      final totals = _map(financial['totals']);
      return ListView(padding: const EdgeInsets.all(22), children: [
        ExecutivePanel(
          title: 'Financial control',
          subtitle:
              'Recorded revenue is a known subtotal, not complete company revenue.',
          action: IconButton(
              tooltip: 'Refresh finance',
              onPressed: () => _loadSection('Finance', retry: true),
              icon: const Icon(Icons.refresh)),
          child: Wrap(spacing: 30, runSpacing: 22, children: [
            _fact('Recorded revenue · known subtotal',
                _nullableMoney(totals['recordedRevenue'], financial)),
            _fact('Eligible transaction value · not revenue',
                _nullableMoney(totals['transactionValue'], financial)),
            _fact('Provider costs',
                _nullableMoney(totals['providerCosts'], financial)),
            _fact('Known provider cost subtotal',
                _nullableMoney(totals['knownProviderCosts'], financial)),
            _fact(
                'Commissions',
                _nullableMoney(totals['commissions'], financial,
                    unavailableReason:
                        'No aggregate commissions total is supplied.')),
            _fact(
                'Gross profit',
                _nullableMoney(totals['grossProfit'], financial,
                    unavailableReason:
                        'Recorded direct-cost evidence is incomplete.')),
            _fact(
                'Net profit',
                _nullableMoney(totals['netProfit'], financial,
                    unavailableReason:
                        'Complete period expense coverage is unavailable.')),
            _fact(
                'Customer wallet liabilities',
                _nullableMoney(data['walletLiabilities'], data,
                    unavailableReason:
                        'Source-specific custody evidence is unreconciled.')),
            _fact(
                'Funding reconciliation',
                _nullableMoney(data['fundingReconciliation'], data,
                    unavailableReason:
                        'Funding records are not reconciled to custody.')),
            _fact(
                'Settlement liabilities',
                _nullableMoney(data['settlementLiabilities'], data,
                    unavailableReason:
                        'Source-specific settlement evidence is unavailable.')),
          ]),
        ),
        const SizedBox(height: 14),
        _dataRows('Services', _rows(financial['services'])),
        _financialRevenueChart(_map(financial['trends'])['daily']),
        _dataRows('Weekly financial trends',
            _rows(_map(financial['trends'])['weekly'])),
        _dataRows('Monthly financial trends',
            _rows(_map(financial['trends'])['monthly'])),
        _dataRows('Methodology', _rows(financial['methodology'])),
        _dataRows('Reconciliation', _rows(financial['reconciliation'])),
        _dataRows('Source coverage', _rows(financial['sourceCoverage'])),
      ]);
    }
    if (_section == 'Marketing') {
      return ListView(padding: const EdgeInsets.all(22), children: [
        ExecutivePanel(
          title: 'Marketing performance',
          action: IconButton(
              onPressed: () => _loadSection('Marketing', retry: true),
              icon: const Icon(Icons.refresh)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _metricFacts(_map(data['metrics'])),
            _dataRows('Campaigns', _rows(data['campaigns'])),
            _dataRows('Officers', _rows(data['officers'])),
            _dataRows('Marketing series', _rows(data['series'])),
            _dataRows('Methodology', _rows(data['methodology'])),
            _dataRows('Limitations', _rows(data['limitations'])),
            _departmentPerformance(_map(data['departmentPerformance'])),
          ]),
        ),
      ]);
    }
    if (_section == 'Field') {
      return ListView(padding: const EdgeInsets.all(22), children: [
        ExecutivePanel(
          title: 'Field performance · ${_title(_fieldDimension)}',
          subtitle:
              'Existing customer-intelligence attribution. BRM and CM mappings are not defined.',
          action: PopupMenuButton<String>(
            onSelected: (dimension) {
              setState(() {
                _fieldDimension = dimension;
                _fieldPage = 1;
                _sections.remove('Field');
                _loadedSections.remove('Field');
              });
              _loadSection('Field', retry: true);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'agent', child: Text('Agent')),
              PopupMenuItem(
                  value: 'stateManager', child: Text('State manager')),
              PopupMenuItem(
                  value: 'zonalManager', child: Text('Zonal manager')),
            ],
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _dataRows('Performance rows', _rows(data['items'])),
            _fieldPagination(_map(data['pagination'])),
            const Text('BRM / CM: unavailable — mappings are not defined.',
                style: TextStyle(color: executiveMuted)),
          ]),
        ),
      ]);
    }
    final providers = _list(data['providers']);
    final errors = _list(data['errors']);
    return ListView(padding: const EdgeInsets.all(22), children: [
      ExecutivePanel(
        title: 'System & provider health',
        subtitle:
            'Recorded transaction status only; providers are not actively probed.',
        action: IconButton(
            onPressed: () => _loadSection('Health', retry: true),
            icon: const Icon(Icons.refresh)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _dataRows('Backend / database',
              [data['backend'], data['database'], data['webhooks']]),
          _dataRows('Providers', providers),
          _dataRows('Recent action errors', errors),
          if (data['notice'] != null) Text('${data['notice']}'),
        ]),
      ),
    ]);
  }

  String _nullableMoney(dynamic value, Map<String, dynamic> source,
      {String? unavailableReason}) {
    if (value != null) return _money(value);
    final reason = unavailableReason ??
        source['reason']?.toString() ??
        source['unavailableReason']?.toString() ??
        'No complete recorded value is available.';
    return 'Unavailable · $reason';
  }

  Widget _financialRevenueChart(dynamic dailyValue) {
    final daily = _rows(dailyValue).map(_map).toList();
    final known = daily
        .where((row) => row['revenue'] is num)
        .map((row) => (row['revenue'] as num).toDouble())
        .toList();
    final maximum = known.fold<double>(0, (a, b) => a > b ? a : b);
    return ExecutivePanel(
      title: 'Recorded revenue trend · NGN',
      subtitle:
          'Earned revenue only. Missing daily values remain unavailable; partial days are marked.',
      child: daily.isEmpty
          ? const Text('No daily recorded-revenue trend was returned.',
              style: TextStyle(color: executiveMuted))
          : SizedBox(
              height: 150,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final row in daily)
                      SizedBox(
                        width: 76,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Tooltip(
                            message:
                                '${row['date']}: ${row['revenue'] == null ? 'Unavailable' : _money(row['revenue'])}${row['partial'] == true ? ' · Partial' : ''}',
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  row['revenue'] == null
                                      ? 'Unavailable'
                                      : _money(row['revenue']),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: executiveMuted, fontSize: 9),
                                ),
                                const SizedBox(height: 5),
                                if (row['revenue'] == null)
                                  const SizedBox(height: 58)
                                else
                                  Container(
                                    height: maximum <= 0
                                        ? 2
                                        : 58 *
                                            (row['revenue'] as num).toDouble() /
                                            maximum,
                                    decoration: BoxDecoration(
                                      color: row['partial'] == true
                                          ? const Color(0xFFB98B3D)
                                          : const Color(0xFF4F9972),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                const SizedBox(height: 5),
                                Text(_compactDate('${row['date'] ?? ''}'),
                                    style: const TextStyle(
                                        color: executiveMuted, fontSize: 9)),
                                if (row['partial'] == true)
                                  const Text('Partial',
                                      style: TextStyle(
                                          color: Color(0xFF9A6A20),
                                          fontSize: 9)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _metricFacts(Map<String, dynamic> metrics) => ExecutivePanel(
        title: 'Marketing metrics',
        child: Wrap(
          spacing: 24,
          runSpacing: 18,
          children: metrics.entries.map((entry) {
            final key = entry.key.toLowerCase();
            final value = entry.value;
            final formatted = value == null
                ? 'Unavailable'
                : key.contains('naira')
                    ? _money(value)
                    : value is num && (key.contains('rate') || key == 'roi')
                        ? '${value.toStringAsFixed(1)}%'
                        : value is num
                            ? _count(value)
                            : value.toString();
            return _fact(_title(entry.key), formatted);
          }).toList(),
        ),
      );

  Widget _departmentPerformance(Map<String, dynamic> performance) {
    if (performance['available'] == false) {
      return _dataRows('Department performance', [
        {'reason': performance['reason'] ?? 'Unavailable'}
      ]);
    }
    return _dataRows('Department performance', _rows(performance['items']));
  }

  Widget _fieldPagination(Map<String, dynamic> pagination) {
    final page = _num(pagination['page']).toInt();
    final totalPages = _num(pagination['totalPages']).toInt();
    if (totalPages <= 1) return const SizedBox.shrink();
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Page $page of $totalPages',
            style: const TextStyle(color: executiveMuted, fontSize: 12)),
        IconButton(
          tooltip: 'Previous field page',
          onPressed: page > 1
              ? () {
                  setState(() => _fieldPage = page - 1);
                  _loadSection('Field', retry: true);
                }
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Next field page',
          onPressed: page < totalPages
              ? () {
                  setState(() => _fieldPage = page + 1);
                  _loadSection('Field', retry: true);
                }
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _reports() => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          ExecutivePanel(
            title: 'Reports for the selected dates',
            subtitle:
                'Daily, weekly, monthly and annual views are the current date range and report kind; the export includes its actual from/to dates.',
            child: Column(children: [
              for (final kind in const [
                'business',
                'customer-growth',
                'transactions',
                'finance',
                'marketing'
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_title(kind)),
                  subtitle: Text(_rangeDescription()),
                  trailing: Wrap(spacing: 2, children: [
                    for (final format in const ['csv', 'xlsx', 'pdf'])
                      TextButton(
                        key: Key('executive-export-$kind-$format'),
                        onPressed: _exportAllowed &&
                                (kind != 'finance' || _financeAllowed)
                            ? () => _export(kind, format)
                            : null,
                        child: Text(format.toUpperCase()),
                      ),
                  ]),
                ),
            ]),
          ),
        ],
      );

  String _rangeDescription() => _range == 'custom' && _custom != null
      ? '${_formatDate(_custom!.start)} — ${_formatDate(_custom!.end)}'
      : _ranges.entries
          .firstWhere((entry) => entry.value == _range,
              orElse: () => const MapEntry('Selected period', ''))
          .key;

  Widget _dataRows(String title, List<dynamic> rows) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: executiveInk)),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            const Text('Unavailable or no recorded rows.',
                style: TextStyle(color: executiveMuted))
          else
            ...rows.take(12).map((row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(_flatten(row)),
                )),
        ]),
      );

  List<dynamic> _rows(dynamic value) {
    if (value == null) return const [];
    if (value is List) return value;
    if (value is Map) return [value];
    if (value is String && value.trim().isEmpty) return const [];
    return [value];
  }

  String _flatten(dynamic value) {
    if (value == null) return 'Unavailable';
    if (value is Map) {
      return value.entries
          .map((e) => '${_title(e.key.toString())}: ${_flatten(e.value)}')
          .join('  ·  ');
    }
    if (value is List) {
      return value.map(_flatten).join('  |  ');
    }
    return value.toString();
  }

  Widget _fact(String label, String value) => SizedBox(
        width: 210,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: executiveInk,
                  fontWeight: FontWeight.w700,
                  fontSize: 17)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(color: executiveMuted, fontSize: 12)),
        ]),
      );

  Widget _dropdown(String label, String selected, List<String> values,
          ValueChanged<String> onChanged) =>
      SizedBox(
        width: 165,
        child: DropdownButtonFormField<String>(
          key: Key('executive-filter-${label.toLowerCase()}'),
          isExpanded: true,
          value: values.contains(selected) ? selected : '',
          decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          items: values
              .map((value) => DropdownMenuItem(
                  value: value,
                  child: Text(value.isEmpty ? 'All' : value,
                      overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      );

  String _title(String value) => value
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}')
      .replaceAll('-', ' ')
      .trim()
      .split(' ')
      .map((word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
