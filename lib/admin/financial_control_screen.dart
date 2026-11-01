import 'dart:convert';

import 'package:flutter/material.dart';

import 'financial_control_api.dart';
import 'financial_control_charts.dart';

const Color _ink = Color(0xff173e35);
const Color _green = Color(0xff176b58);
const Color _paper = Color(0xfff3f7f4);
const Color _line = Color(0xffdce7e1);

class FinancialControlScreen extends StatefulWidget {
  const FinancialControlScreen({super.key, this.api});
  final FinancialControlApi? api;

  @override
  State<FinancialControlScreen> createState() => _FinancialControlScreenState();
}

class _FinancialControlScreenState extends State<FinancialControlScreen>
    with SingleTickerProviderStateMixin {
  late final FinancialControlApi _api = widget.api ?? FinancialControlApi();
  late final TabController _tabs = TabController(length: 7, vsync: this)
    ..addListener(_onTabChanged);
  final TextEditingController _service = TextEditingController();
  final TextEditingController _network = TextEditingController();
  final TextEditingController _branch = TextEditingController();

  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _expenseResult;
  DateTime? _from;
  DateTime? _to;
  String _preset = 'ThisMonth';
  bool _loading = true;
  bool _expenseLoading = false;
  bool _busy = false;
  String? _error;
  int _request = 0;

  static const List<String> _tabsNames = <String>[
    'Overview',
    'Services',
    'Data Plans',
    'Analytics',
    'Expenses',
    'Reconciliation',
    'Reports',
  ];

  @override
  void initState() {
    super.initState();
    final DateTime now = _nigeriaToday();
    _from = DateTime(now.year, now.month);
    _to = now;
    _loadSummary();
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    _service.dispose();
    _network.dispose();
    _branch.dispose();
    super.dispose();
  }

  DateTime _nigeriaToday() {
    final DateTime utc = DateTime.now().toUtc().add(const Duration(hours: 1));
    return DateTime(utc.year, utc.month, utc.day);
  }

  String _day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Map<String, String> get _filters => <String, String>{
        if (_from != null) 'from': _day(_from!),
        if (_to != null) 'to': _day(_to!),
        if (_service.text.trim().isNotEmpty) 'service': _service.text.trim(),
        if (_network.text.trim().isNotEmpty) 'network': _network.text.trim(),
        if (_branch.text.trim().isNotEmpty) 'branch': _branch.text.trim(),
      };

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<dynamic> _list(dynamic value) =>
      value is List ? List<dynamic>.from(value) : <dynamic>[];

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 4 && _expenseResult == null && !_expenseLoading) {
      _loadExpenses();
    }
  }

  int _expenseRequest = 0;

  Future<void> _loadSummary({bool refresh = false}) async {
    final int request = ++_request;
    setState(() {
      _loading = _summary == null;
      _error = null;
    });
    try {
      final Map<String, dynamic> result = await _api.summary(filters: _filters);
      if (!mounted || request != _request) return;
      setState(() {
        _summary = result;
        _loading = false;
      });
      if (_tabs.index == 4) await _loadExpenses();
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = _errorMessage(error);
      });
    }
  }

  Future<void> _loadExpenses() async {
    final int request = ++_expenseRequest;
    setState(() => _expenseLoading = true);
    try {
      final Map<String, dynamic> result =
          await _api.expenses(filters: _filters);
      if (!mounted || request != _expenseRequest) return;
      setState(() {
        _expenseResult = result;
        _expenseLoading = false;
      });
    } catch (error) {
      if (!mounted || request != _expenseRequest) return;
      setState(() {
        _error = _errorMessage(error);
        _expenseLoading = false;
      });
    }
  }

  String _errorMessage(Object error) => error is FinancialControlException
      ? error.message
      : 'Financial data could not be loaded. Check your connection and retry.';

  Future<void> _applyFilters() async {
    ++_expenseRequest;
    setState(() {
      _summary = null;
      _expenseResult = null;
      _expenseLoading = false;
    });
    await _loadSummary(refresh: true);
  }

  Future<void> _setPreset(String value) async {
    final DateTime today = _nigeriaToday();
    DateTime from = today;
    DateTime to = today;
    switch (value) {
      case 'Yesterday':
        from = today.subtract(const Duration(days: 1));
        to = from;
        break;
      case 'Last7':
        from = today.subtract(const Duration(days: 6));
        break;
      case 'ThisMonth':
        from = DateTime(today.year, today.month);
        break;
      case 'LastMonth':
        from = DateTime(today.year, today.month - 1);
        to = DateTime(today.year, today.month, 0);
        break;
      case 'Today':
      case 'Custom':
        break;
    }
    setState(() {
      _preset = value;
      _from = from;
      _to = to;
    });
    await _applyFilters();
  }

  Future<void> _pickCustomDates() async {
    final DateTime today = _nigeriaToday();
    final DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: _from ?? today,
        end: _to ?? today,
      ),
      helpText: 'CUSTOM REPORTING PERIOD',
    );
    if (range == null || !mounted) return;
    setState(() {
      _preset = 'Custom';
      _from = range.start;
      _to = range.end;
    });
    await _applyFilters();
  }

  Future<void> _export(String format) async {
    setState(() => _busy = true);
    try {
      await _api.downloadReport(format: format, filters: _filters);
      if (mounted) {
        _message(format == 'pdf'
            ? 'Authenticated PDF report downloaded. Open it to print.'
            : 'CSV report downloaded.');
      }
    } catch (error) {
      if (mounted) _message(_errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? const Color(0xff9b403b) : _green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _FinancialLoading();
    if (_summary == null) {
      return _FinancialFailure(
        message: _error ?? 'Financial summary is not available.',
        onRetry: () => _loadSummary(),
      );
    }
    final Map<String, dynamic> reconciliation =
        _map(_summary!['reconciliation']);
    return ColoredBox(
      color: _paper,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: RefreshIndicator(
            color: _green,
            onRefresh: () => _loadSummary(refresh: true),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                SliverToBoxAdapter(child: _header()),
                SliverToBoxAdapter(child: _filterPanel()),
                if (_error != null)
                  SliverToBoxAdapter(
                    child: _inlineError(
                        _error!, () => _loadSummary(refresh: true)),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: _caveat(reconciliation),
                  ),
                ),
                SliverToBoxAdapter(
                  child: TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: _green,
                    unselectedLabelColor: const Color(0xff64776f),
                    indicatorColor: _green,
                    indicatorWeight: 3,
                    tabs: _tabsNames
                        .map((String value) => Tab(text: value))
                        .toList(),
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: TabBarView(
                    controller: _tabs,
                    children: <Widget>[
                      _overview(),
                      _services(),
                      _plans(),
                      _analytics(),
                      _expenses(),
                      _reconciliation(),
                      _reports(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final Map<String, dynamic> period = _map(_summary?['period']);
    final String generated = _text(_summary?['generatedAt']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child:
          LayoutBuilder(builder: (BuildContext context, BoxConstraints size) {
        final bool compact = size.maxWidth < 720;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('SERVICEPAY  /  HEAD OFFICE FINANCE',
                          style: TextStyle(
                              color: _green,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w800,
                              fontSize: 10)),
                      const SizedBox(height: 8),
                      Text('Financial Control Center',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: _ink,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.7,
                              )),
                      const SizedBox(height: 5),
                      const Text(
                        'A reporting view of known earned margins, costs and exposure.',
                        style:
                            TextStyle(color: Color(0xff61756c), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (!compact) _reportButton(),
              ],
            ),
            if (compact) ...<Widget>[
              const SizedBox(height: 12),
              _reportButton(),
            ],
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              runSpacing: 7,
              children: <Widget>[
                _statusChip(Icons.calendar_month_outlined,
                    '${_text(period['from'], fallback: _from == null ? '—' : _day(_from!))} — ${_text(period['to'], fallback: _to == null ? '—' : _day(_to!))}'),
                _statusChip(Icons.public_outlined,
                    'Timezone · ${_text(period['timezone'], fallback: 'Africa/Lagos')}'),
                _statusChip(Icons.currency_exchange_outlined,
                    'Currency · ${_text(_summary?['currency'], fallback: 'NGN')}'),
                if (generated.isNotEmpty)
                  _statusChip(
                      Icons.schedule_outlined, 'Generated · $generated'),
              ],
            ),
          ],
        );
      }),
    );
  }

  Widget _reportButton() => OutlinedButton.icon(
        onPressed: _busy ? null : () => _export('pdf'),
        icon: const Icon(Icons.print_outlined, size: 18),
        label: Text(_busy ? 'Preparing…' : 'Print / PDF report'),
      );

  Widget _statusChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xffe8f0eb),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(icon, size: 14, color: _green),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Color(0xff466158),
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _filterPanel() {
    final List<String> presets = <String>[
      'Today',
      'Yesterday',
      'Last7',
      'ThisMonth',
      'LastMonth',
      'Custom',
    ];
    final Map<String, String> names = <String, String>{
      'Last7': 'Last 7 days',
      'ThisMonth': 'This month',
      'LastMonth': 'Last month',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 7, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xffe8f0eb),
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: presets.map((String key) {
                return ChoiceChip(
                  label: Text(names[key] ?? key),
                  selected: _preset == key,
                  onSelected: (_) =>
                      key == 'Custom' ? _pickCustomDates() : _setPreset(key),
                  selectedColor: const Color(0xffcee1d6),
                  labelStyle: TextStyle(
                      color: _preset == key ? _green : const Color(0xff52665e),
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(
                      color: _preset == key ? const Color(0xffa8caba) : _line),
                );
              }).toList(),
            ),
            const SizedBox(height: 11),
            LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
              final double width =
                  c.maxWidth < 620 ? c.maxWidth : (c.maxWidth - 18) / 3;
              return Wrap(
                spacing: 9,
                runSpacing: 8,
                children: <Widget>[
                  _filterWithOptions(_service, 'Service',
                      'Service code, name or ID', width, 'services'),
                  _filterWithOptions(_network, 'Network', 'Network name or ID',
                      width, 'networks'),
                  _filterWithOptions(_branch, 'Branch', 'Branch name or ID',
                      width, 'branches'),
                ],
              );
            }),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _loading ? null : _applyFilters,
                icon: const Icon(Icons.filter_alt_outlined, size: 17),
                label: const Text('Apply filters'),
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterInput(
    TextEditingController controller,
    String label,
    String hint,
    double width,
  ) =>
      SizedBox(
        width: width,
        child: TextField(
          controller: controller,
          onSubmitted: (_) => _applyFilters(),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: const Color(0xfff8faf8),
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
          ),
        ),
      );

  Widget _filterWithOptions(
    TextEditingController controller,
    String label,
    String hint,
    double width,
    String key,
  ) {
    final List<dynamic> options = _list(_map(_summary?['filters'])[key]);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _filterInput(controller, label, hint, width),
          if (options.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 2),
              child: Wrap(
                spacing: 3,
                runSpacing: 1,
                children: options.take(8).map((dynamic option) {
                  final Map<String, dynamic> row = _map(option);
                  final String value = option is Map
                      ? _text(
                          row['id'] ??
                              row['value'] ??
                              row['service'] ??
                              row['network'] ??
                              row['branch'],
                          fallback: '',
                        )
                      : option.toString();
                  final String optionLabel = option is Map
                      ? _text(
                          row['name'] ??
                              row['label'] ??
                              row['service'] ??
                              row['network'] ??
                              row['branch'] ??
                              row['id'],
                          fallback: value,
                        )
                      : option.toString();
                  if (value.isEmpty) return const SizedBox.shrink();
                  return ActionChip(
                    label: Text(optionLabel),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      controller.text = value;
                      _applyFilters();
                    },
                  );
                }).toList(),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 2),
              child: Text(
                'Free entry · names and IDs accepted',
                style: TextStyle(color: Color(0xff77877f), fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _caveat(Map<String, dynamic> reconciliation) {
    final String status =
        _text(reconciliation['status'], fallback: 'NOT REPORTED');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xfffff4de),
        border: Border.all(color: const Color(0xffead5a9)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline, color: Color(0xff8a641c), size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Reconciliation status: $status. Recorded revenue is the known earned-margin / fee subtotal, not transaction value or a complete-company earnings claim; it may be incomplete. Net profit is shown only when the accounting source reports a complete value. A reported status is not a claim that all data is reconciled.',
              style: const TextStyle(
                  color: Color(0xff6d5524),
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overview() {
    final Map<String, dynamic> totals = _map(_summary?['totals']);
    final String currency = _text(_summary?['currency'], fallback: 'NGN');
    final List<_Metric> metrics = <_Metric>[
      _Metric('Transaction value', totals['transactionValue'],
          'Eligible payment value'),
      _Metric('Known recorded revenue', totals['recordedRevenue'],
          'Known earned margins / fees; may be incomplete'),
      _Metric(
          'Provider costs', totals['providerCosts'], 'Recorded service costs'),
      _Metric('Known provider costs', totals['knownProviderCosts'],
          'Known subtotal; unresolved costs excluded'),
      _Metric(
          'Gross profit', totals['grossProfit'], 'Before operating expenses'),
      _Metric(
          'Operating expenses',
          totals['operatingExpenses'],
          totals['operatingExpenses'] == null
              ? 'Not allocated to service / network / branch views'
              : 'Separately recorded; period coverage is incomplete'),
      _Metric('Net profit', totals['netProfit'],
          'Unavailable until accounting is complete'),
      _Metric('Pending', totals['pending'], 'Transactions awaiting outcome',
          isCount: true),
      _Metric('Failed', totals['failed'], 'Failed transactions', isCount: true),
      _Metric('Refunds', totals['refunds'], 'Refunded value'),
      _Metric('Outstanding settlements', totals['outstandingSettlements'],
          'Awaiting settlement'),
      _Metric('Unreconciled', totals['unreconciled'], 'Open financial items',
          isCount: true),
    ];
    final List<dynamic> daily = _list(_map(_summary?['trends'])['daily']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: metrics
              .map((_Metric value) => _metricCard(value, currency))
              .toList(),
        ),
        const SizedBox(height: 13),
        _panel(
          title: 'Known recorded revenue · daily',
          subtitle:
              'Only values returned by the reporting service are plotted.',
          child: FinancialTrendChart(
            points: daily,
            currency: currency,
          ),
        ),
        const SizedBox(height: 13),
        _panel(
          title: 'Data coverage',
          subtitle: 'Source availability supplied for this reporting period.',
          child: _coverageTable(_list(_summary?['sourceCoverage'])),
        ),
      ],
    );
  }

  Widget _metricCard(_Metric metric, String currency) {
    final String value =
        metric.isCount ? _count(metric.value) : _money(metric.value, currency);
    final bool unavailable = metric.value == null;
    final bool netProfit = metric.label == 'Net profit';
    return SizedBox(
      width: 214,
      child: Container(
        key: Key(
            'financial-metric-${metric.label.toLowerCase().replaceAll(' ', '-')}'),
        padding: const EdgeInsets.fromLTRB(14, 13, 13, 13),
        decoration: BoxDecoration(
          color: netProfit ? const Color(0xffe2efea) : const Color(0xfffbfcfa),
          border:
              Border.all(color: netProfit ? const Color(0xffbad4c8) : _line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(metric.label.toUpperCase(),
                style: const TextStyle(
                    color: Color(0xff687b73),
                    fontSize: 9,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 9),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: unavailable ? const Color(0xff8b6d36) : _ink,
                    fontSize: unavailable ? 12 : 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(metric.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xff75867f), fontSize: 10, height: 1.25)),
          ],
        ),
      ),
    );
  }

  Widget _services() {
    final List<dynamic> rows = _list(_summary?['services']);
    final String currency = _text(_summary?['currency'], fallback: 'NGN');
    return _tabContent(
      child: _dataTable(
        headers: const <String>[
          'Service',
          'Count',
          'Transaction value',
          'Known recorded revenue',
          'Missing revenue evidence',
          'Provider costs',
          'Gross profit',
          'Net profit',
        ],
        rows: rows,
        cells: (Map<String, dynamic> row) => <String>[
          _text(row['service']),
          _count(row['count']),
          _money(row['transactionValue'], currency),
          _money(row['recordedRevenue'], currency),
          _count(row['missingRevenueCount']),
          _money(row['providerCosts'], currency),
          _money(row['grossProfit'], currency),
          _money(row['netProfit'], currency),
        ],
        empty: 'No service breakdown is available for this period.',
      ),
    );
  }

  Widget _plans() {
    final List<dynamic> rows = _list(_summary?['plans']);
    final String currency = _text(_summary?['currency'], fallback: 'NGN');
    return _tabContent(
      child: _dataTable(
        headers: const <String>[
          'Network',
          'Plan',
          'Count',
          'Selling price',
          'Provider cost',
          'Gross margin',
          'Margin %',
          'Known recorded earnings',
        ],
        rows: rows,
        cells: (Map<String, dynamic> row) => <String>[
          _text(row['network']),
          _text(row['plan']),
          _count(row['count']),
          _money(row['sellingPrice'], currency),
          _money(row['providerCost'], currency),
          _money(row['grossMargin'], currency),
          row['marginPercent'] == null
              ? 'DATA UNAVAILABLE'
              : '${_displayNumber(row['marginPercent'])}%',
          _money(row['recordedEarnings'], currency),
        ],
        empty: 'No plan-level results were returned.',
      ),
    );
  }

  Widget _analytics() {
    final Map<String, dynamic> trends = _map(_summary?['trends']);
    final Map<String, dynamic> growth = _map(_summary?['growth']);
    final Map<String, dynamic> totals = _map(_summary?['totals']);
    final String currency = _text(_summary?['currency'], fallback: 'NGN');
    final List<dynamic> services = _list(_summary?['services']);
    final List<dynamic> networks = _list(_summary?['networks']);
    final List<dynamic> branches = _list(_summary?['branches']);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _insightCard(
                'Revenue growth',
                growth['percent'] == null
                    ? 'DATA UNAVAILABLE'
                    : '${_displayNumber(growth['percent'])}%',
                _text(growth['note'],
                    fallback: 'Comparison note not provided.')),
            _insightCard(
                'Successful transactions',
                _count(totals['successful']),
                'Count returned by the financial reporting service.'),
            _insightCard('Total transactions', _count(totals['totalCount']),
                'Count returned by the financial reporting service.'),
            _insightCard(
                'Refunded transactions',
                _count(totals['refundedCount']),
                'Count returned by the financial reporting service.'),
            _insightCard(
                'Success rate',
                totals['successRate'] == null
                    ? 'DATA UNAVAILABLE'
                    : '${_displayNumber(totals['successRate'])}%',
                'Successful count divided by total count, as reported.'),
          ],
        ),
        const SizedBox(height: 13),
        _panel(
          title: 'Revenue trend',
          subtitle: 'Switch aggregation to inspect the returned series.',
          child: _TrendPeriodSelector(trends: trends, currency: currency),
        ),
        const SizedBox(height: 13),
        LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
          final double width =
              c.maxWidth < 880 ? c.maxWidth : (c.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              SizedBox(
                width: width,
                child: _panel(
                  title: 'Known recorded revenue by service',
                  subtitle:
                      'Known subtotal; tables report missing revenue evidence.',
                  child: FinancialCategoryChart(
                    rows: services,
                    nameKey: 'service',
                    valueKey: 'recordedRevenue',
                    currency: currency,
                  ),
                ),
              ),
              SizedBox(
                width: width,
                child: _panel(
                  title: 'Known recorded revenue by network',
                  subtitle:
                      'Known subtotal; tables report missing revenue evidence.',
                  child: FinancialCategoryChart(
                    rows: networks,
                    nameKey: 'network',
                    valueKey: 'recordedRevenue',
                    currency: currency,
                  ),
                ),
              ),
            ],
          );
        }),
        const SizedBox(height: 13),
        _panel(
          title: 'Network comparison',
          subtitle:
              'Flat network totals from the report; known revenue may be incomplete.',
          child: _dataTable(
            headers: const <String>[
              'Network',
              'Count',
              'Transaction value',
              'Known recorded revenue',
              'Missing revenue evidence',
              'Provider costs',
              'Gross profit',
            ],
            rows: networks,
            cells: (Map<String, dynamic> row) => <String>[
              _text(row['network']),
              _count(row['count']),
              _money(row['transactionValue'], currency),
              _money(row['recordedRevenue'], currency),
              _count(row['missingRevenueCount']),
              _money(row['providerCosts'], currency),
              _money(row['grossProfit'], currency),
            ],
            empty: 'No network comparisons are available.',
          ),
        ),
        const SizedBox(height: 13),
        _panel(
          title: 'Branch comparison',
          subtitle: 'Returned branch totals; unknown values remain visible.',
          child: _dataTable(
            headers: const <String>[
              'Branch',
              'Count',
              'Transaction value',
              'Known recorded revenue',
              'Missing revenue evidence',
              'Operating expenses',
              'Net profit'
            ],
            rows: branches,
            cells: (Map<String, dynamic> row) {
              return <String>[
                _text(row['branch']),
                _count(row['count']),
                _money(row['transactionValue'], currency),
                _money(row['recordedRevenue'], currency),
                _count(row['missingRevenueCount']),
                _money(row['operatingExpenses'], currency),
                _money(row['netProfit'], currency),
              ];
            },
            empty: 'No branch comparisons are available.',
          ),
        ),
      ],
    );
  }

  Widget _expenses() {
    if (_expenseLoading && _expenseResult == null) {
      return const _FinancialLoading(compact: true);
    }
    final List<dynamic> items = _list(_expenseResult?['items']);
    final String currency = _text(_summary?['currency'], fallback: 'NGN');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget summary = _panel(
              title: 'Separately incurred expenses',
              subtitle:
                  'Record only costs not already deducted in transaction margins.',
              child: Text(
                'Recorded total  ·  ${_money(_expenseResult?['totalRecorded'], currency)}'
                '       Reconciliation  ·  ${_text(_expenseResult?['status'], fallback: 'Not reported')}',
                style: const TextStyle(
                    color: _ink, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            );
            final Widget action = FilledButton.icon(
              onPressed: _busy ? null : _showExpenseForm,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Record expense'),
              style: FilledButton.styleFrom(backgroundColor: _green),
            );
            if (constraints.maxWidth < 680) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  summary,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(child: summary),
                const SizedBox(width: 10),
                action,
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _dataTable(
          headers: const <String>[
            'Date',
            'Category',
            'Description',
            'Reference',
            'Recorded by',
            'Amount',
            'Document',
          ],
          rows: items,
          cells: (Map<String, dynamic> row) {
            final Map<String, dynamic> doc = _map(row['supportingDocument']);
            return <String>[
              _text(row['date']),
              _text(row['category']),
              _text(row['description']),
              _text(row['reference']),
              _text(row['recordedBy']),
              _money(row['amount'], currency),
              doc.isEmpty
                  ? 'None'
                  : '${_text(doc['name'], fallback: 'Document')} · ${_text(doc['size'], fallback: 'size unknown')}',
            ];
          },
          empty: 'No separately recorded expenses in this period.',
        ),
        if (_text(_expenseResult?['coverage'], fallback: '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _UnknownNotice(message: _text(_expenseResult?['coverage'])),
          ),
        for (final dynamic row in items.whereType<Map>())
          if (_map(row['supportingDocument']).isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    _downloadDocument(Map<String, dynamic>.from(row)),
                icon: const Icon(Icons.download_outlined, size: 17),
                label: Text(
                    'Download ${_text(_map(row['supportingDocument'])['name'])}'),
              ),
            ),
      ],
    );
  }

  Future<void> _downloadDocument(Map<String, dynamic> row) async {
    final Map<String, dynamic> doc = _map(row['supportingDocument']);
    try {
      await _api.downloadSupportingDocument(
        id: _text(row['id']),
        name: _text(doc['name'], fallback: 'supporting-document'),
      );
    } catch (error) {
      if (mounted) _message(_errorMessage(error), error: true);
    }
  }

  Future<void> _showExpenseForm() async {
    final bool? recorded = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _ExpenseDialog(
        onSubmit: (Map<String, dynamic> body) => _api.createExpense(body),
      ),
    );
    if (recorded == true && mounted) {
      setState(() {
        _expenseResult = null;
        _busy = true;
      });
      try {
        final Map<String, dynamic> result =
            await _api.expenses(filters: _filters);
        final Map<String, dynamic> summary =
            await _api.summary(filters: _filters);
        if (!mounted) return;
        setState(() {
          _expenseResult = result;
          _summary = summary;
          _busy = false;
        });
        _message(
            'Expense recorded. No wallet or provider action was initiated.');
      } catch (error) {
        if (mounted) {
          setState(() => _busy = false);
          _message(_errorMessage(error), error: true);
        }
      }
    }
  }

  Widget _reconciliation() {
    final Map<String, dynamic> reconciliation =
        _map(_summary?['reconciliation']);
    final List<dynamic> issues = _list(reconciliation['issues']);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        _panel(
          title: 'Reconciliation status',
          subtitle: 'Read-only status from the financial control report.',
          child: Row(
            children: <Widget>[
              const Icon(Icons.fact_check_outlined, color: _green, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _text(reconciliation['status'],
                      fallback: 'STATUS UNAVAILABLE'),
                  style: const TextStyle(
                      color: _ink, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              const Text('No reconciliation action is run here.',
                  style: TextStyle(color: Color(0xff6a7c74), fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _dataTable(
          headers: const <String>['Issue code', 'Count', 'Note'],
          rows: issues,
          cells: (Map<String, dynamic> row) => <String>[
            _text(row['code']),
            _count(row['count']),
            _text(row['note']),
          ],
          empty:
              'No issue rows were returned. This does not imply full reconciliation.',
        ),
        const SizedBox(height: 12),
        _panel(
          title: 'Source coverage',
          subtitle: 'Rows may be partial or unavailable.',
          child: _coverageTable(_list(_summary?['sourceCoverage'])),
        ),
      ],
    );
  }

  Widget _reports() {
    final List<dynamic> methodology = _list(_summary?['methodology']);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        _panel(
          title: 'Export full financial report',
          subtitle:
              'Uses the selected date period and service, network and branch filters.',
          child: Wrap(
            spacing: 10,
            runSpacing: 9,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _busy ? null : () => _export('csv'),
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('Download CSV'),
                style: FilledButton.styleFrom(backgroundColor: _green),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _export('pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Download PDF / print'),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _panel(
          title: 'Reporting methodology',
          subtitle: 'As supplied by the reporting service.',
          child: methodology.isEmpty
              ? const _UnknownNotice(
                  message: 'Methodology was not provided for this report.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: methodology
                      .map((dynamic item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text('•  ',
                                    style: TextStyle(
                                        color: _green,
                                        fontWeight: FontWeight.w800)),
                                Expanded(
                                    child: Text(item.toString(),
                                        style: const TextStyle(
                                            color: Color(0xff53675f),
                                            height: 1.35))),
                              ],
                            ),
                          ))
                      .toList(),
                ),
        ),
        const SizedBox(height: 12),
        _panel(
          title: 'Report contents',
          subtitle: 'Backend report is expected to include',
          child: const Text(
            'Selected period and generated timestamp · transaction and record counts · amounts and unknown values · reconciliation issues · source coverage · methodology.',
            style: TextStyle(color: Color(0xff53675f), height: 1.45),
          ),
        ),
      ],
    );
  }

  Widget _coverageTable(List<dynamic> rows) => _dataTable(
        headers: const <String>['Service', 'Source', 'Status', 'Count', 'Note'],
        rows: rows,
        cells: (Map<String, dynamic> row) => <String>[
          _text(row['service']),
          _text(row['source']),
          _text(row['status'], fallback: 'DATA UNAVAILABLE'),
          _count(row['count']),
          _text(row['note']),
        ],
        empty: 'Source coverage was not reported.',
      );

  Widget _tabContent({required Widget child}) => ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[child],
      );

  Widget _dataTable({
    required List<String> headers,
    required List<dynamic> rows,
    required List<String> Function(Map<String, dynamic>) cells,
    required String empty,
  }) {
    if (rows.isEmpty) return _UnknownNotice(message: empty);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xfffbfcfa),
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: const WidgetStatePropertyAll(Color(0xffeaf1ed)),
          dataRowMinHeight: 44,
          dataRowMaxHeight: 60,
          headingRowHeight: 42,
          columnSpacing: 24,
          columns: headers
              .map((String value) => DataColumn(
                    label: Text(value.toUpperCase(),
                        style: const TextStyle(
                            color: Color(0xff4b6259),
                            fontSize: 9,
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.w800)),
                  ))
              .toList(),
          rows: rows.whereType<Map>().map((Map raw) {
            final List<String> values = cells(Map<String, dynamic>.from(raw));
            return DataRow(
                cells: List<DataCell>.generate(headers.length, (int index) {
              final String value =
                  index < values.length ? values[index] : 'DATA UNAVAILABLE';
              return DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 250),
                  child: Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: value == 'DATA UNAVAILABLE'
                          ? const Color(0xff8a6b32)
                          : const Color(0xff344c43),
                      fontSize: 11,
                      fontWeight:
                          index == 0 ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }));
          }).toList(),
        ),
      ),
    );
  }

  Widget _panel({
    required String title,
    required String subtitle,
    required Widget child,
  }) =>
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xfffbfcfa),
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title,
                style: const TextStyle(
                    color: _ink, fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(subtitle,
                style: const TextStyle(color: Color(0xff73847c), fontSize: 11)),
            const SizedBox(height: 13),
            child,
          ],
        ),
      );

  Widget _insightCard(String title, String value, String note) => SizedBox(
        width: 220,
        child: _panel(
          title: title,
          subtitle: note,
          child: Text(value,
              style: TextStyle(
                color: value == 'DATA UNAVAILABLE'
                    ? const Color(0xff8a6b32)
                    : _green,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              )),
        ),
      );

  Widget _inlineError(String message, VoidCallback retry) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Material(
          color: const Color(0xffffe9e6),
          borderRadius: BorderRadius.circular(7),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.error_outline, color: Color(0xffa43e38)),
            title:
                Text(message, style: const TextStyle(color: Color(0xff823e39))),
            trailing: TextButton(onPressed: retry, child: const Text('Retry')),
          ),
        ),
      );

  String _text(dynamic value, {String fallback = '—'}) =>
      value == null || value.toString().trim().isEmpty
          ? fallback
          : value.toString();

  String _money(dynamic value, String currency) =>
      value == null ? 'DATA UNAVAILABLE' : '$currency ${_displayNumber(value)}';

  String _count(dynamic value) =>
      value == null ? 'DATA UNAVAILABLE' : _displayNumber(value);

  String _displayNumber(dynamic value) {
    final num? number =
        value is num ? value : num.tryParse(value?.toString() ?? '');
    if (number == null) return 'DATA UNAVAILABLE';
    final String string = number.toString();
    if (number is int || number == number.roundToDouble()) {
      final String raw = number.toInt().toString();
      return raw.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (Match match) => '${match[1]},',
      );
    }
    return string;
  }
}

class _Metric {
  const _Metric(
    this.label,
    this.value,
    this.note, {
    this.isCount = false,
  });
  final String label;
  final dynamic value;
  final String note;
  final bool isCount;
}

class _TrendPeriodSelector extends StatefulWidget {
  const _TrendPeriodSelector({required this.trends, required this.currency});
  final Map<String, dynamic> trends;
  final String currency;
  @override
  State<_TrendPeriodSelector> createState() => _TrendPeriodSelectorState();
}

class _TrendPeriodSelectorState extends State<_TrendPeriodSelector> {
  String _period = 'daily';
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SegmentedButton<String>(
          segments: const <ButtonSegment<String>>[
            ButtonSegment(value: 'daily', label: Text('Daily')),
            ButtonSegment(value: 'weekly', label: Text('Weekly')),
            ButtonSegment(value: 'monthly', label: Text('Monthly')),
          ],
          selected: <String>{_period},
          onSelectionChanged: (Set<String> value) =>
              setState(() => _period = value.first),
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
        const SizedBox(height: 12),
        FinancialTrendChart(
          key: ValueKey<String>(_period),
          points: widget.trends[_period] is List
              ? List<dynamic>.from(widget.trends[_period] as List)
              : const <dynamic>[],
          currency: widget.currency,
        ),
      ],
    );
  }
}

class _UnknownNotice extends StatelessWidget {
  const _UnknownNotice({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xfff1f5f2),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _line),
        ),
        child: Row(children: <Widget>[
          const Icon(Icons.info_outline, color: Color(0xff71847c), size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style:
                      const TextStyle(color: Color(0xff697c74), fontSize: 12))),
        ]),
      );
}

class _FinancialLoading extends StatelessWidget {
  const _FinancialLoading({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: _paper,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: List<Widget>.generate(
            compact ? 3 : 8,
            (int i) => Container(
              height: i == 0 ? 60 : 75,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xffe5ece8),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      );
}

class _FinancialFailure extends StatelessWidget {
  const _FinancialFailure({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: _paper,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.cloud_off_outlined,
                    color: Color(0xffa34c43), size: 36),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
}

typedef _ExpenseSubmit = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> body);

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({required this.onSubmit});
  final _ExpenseSubmit onSubmit;
  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _docName = TextEditingController();
  final TextEditingController _docBase64 = TextEditingController();
  String _category = 'OTHER';
  late DateTime _date = _todayInNigeria;
  bool _acknowledged = false;
  bool _saving = false;
  String? _error;

  static const List<String> _categories = <String>[
    'SALARY',
    'RENT',
    'MARKETING',
    'HOSTING',
    'PROVIDER_CHARGE',
    'LOGISTICS',
    'ADMINISTRATION',
    'OTHER',
  ];

  DateTime get _todayInNigeria {
    final DateTime now = DateTime.now().toUtc().add(const Duration(hours: 1));
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _reference.dispose();
    _docName.dispose();
    _docBase64.dispose();
    super.dispose();
  }

  String get _expenseDate =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  String? _validateDocument() {
    final String data = _docBase64.text.trim();
    if (data.isEmpty && _docName.text.trim().isEmpty) return null;
    if (data.isEmpty || _docName.text.trim().isEmpty) {
      return 'Provide both a document name and file data.';
    }
    final String lower = _docName.text.toLowerCase();
    if (!(lower.endsWith('.pdf') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg'))) {
      return 'Only PDF, PNG or JPEG supporting documents are accepted.';
    }
    try {
      if (!RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(data)) {
        return 'Document data must be valid base64.';
      }
      final List<int> bytes = base64Decode(data);
      if (bytes.length > 256 * 1024) {
        return 'Supporting document must be 256 KiB or smaller.';
      }
      final bool pdf = bytes.length >= 5 &&
          bytes.take(5).toList().join(',') == '37,80,68,70,45';
      final bool png = bytes.length >= 8 &&
          bytes.take(8).toList().join(',') == '137,80,78,71,13,10,26,10';
      final bool jpeg = bytes.length >= 3 &&
          bytes[0] == 255 &&
          bytes[1] == 216 &&
          bytes[2] == 255;
      final bool extensionPdf = lower.endsWith('.pdf');
      final bool extensionPng = lower.endsWith('.png');
      if ((extensionPdf && !pdf) ||
          (extensionPng && !png) ||
          (!extensionPdf && !extensionPng && !jpeg)) {
        return 'File contents must match the PDF, PNG or JPEG filename.';
      }
    } on FormatException {
      return 'Document data must be valid base64.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_acknowledged) {
      setState(() => _error = 'Confirm that this is a separate expense first.');
      return;
    }
    final String? docError = _validateDocument();
    if (docError != null) {
      setState(() => _error = docError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final String docData = _docBase64.text.trim();
    final Map<String, dynamic> body = <String, dynamic>{
      'amount': num.parse(_amount.text.trim()),
      'category': _category,
      'date': _expenseDate,
      'description': _description.text.trim(),
      'reference': _reference.text.trim(),
      'costNotAlreadyDeducted': true,
      if (docData.isNotEmpty)
        'supportingDocument': <String, dynamic>{
          'name': _docName.text.trim(),
          'type': _docName.text.toLowerCase().endsWith('.pdf')
              ? 'application/pdf'
              : _docName.text.toLowerCase().endsWith('.png')
                  ? 'image/png'
                  : 'image/jpeg',
          'dataBase64': docData,
        },
    };
    try {
      await widget.onSubmit(body);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is FinancialControlException
              ? error.message
              : 'Expense was not recorded. Check the details and retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record a separate expense'),
      content: SizedBox(
        width: 540,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'No wallet, bank, or provider action is initiated. Submission is explicit and requires a reference.',
                  style: TextStyle(color: Color(0xff61756c), fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Amount (NGN)', border: OutlineInputBorder()),
                  validator: (String? value) {
                    final num? amount = num.tryParse(value?.trim() ?? '');
                    return amount == null || amount <= 0
                        ? 'Enter an amount greater than zero.'
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _category,
                  decoration: const InputDecoration(
                      labelText: 'Category', border: OutlineInputBorder()),
                  items: _categories
                      .map((String value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.replaceAll('_', ' '))))
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (String? value) =>
                          setState(() => _category = value ?? 'OTHER'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          final DateTime? date = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2020),
                            lastDate: _todayInNigeria,
                          );
                          if (date != null) setState(() => _date = date);
                        },
                  icon: const Icon(Icons.calendar_today_outlined, size: 17),
                  label: Text('Expense date · $_expenseDate'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                      labelText: 'Description', border: OutlineInputBorder()),
                  validator: (String? value) {
                    final String description = value?.trim() ?? '';
                    if (description.isEmpty) return 'Description is required.';
                    if (description.length < 5) {
                      return 'Description must be at least 5 characters.';
                    }
                    if (description.length > 500) {
                      return 'Description must be 500 characters or fewer.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _reference,
                  decoration: const InputDecoration(
                      labelText: 'Unique reference (required)',
                      border: OutlineInputBorder()),
                  validator: (String? value) {
                    final String reference = value?.trim() ?? '';
                    if (reference.length < 3) {
                      return 'Reference must be at least 3 characters.';
                    }
                    if (reference.length > 120) {
                      return 'Reference must be 120 characters or fewer.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 13),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _acknowledged,
                  onChanged: _saving
                      ? null
                      : (bool? value) =>
                          setState(() => _acknowledged = value ?? false),
                  title: const Text(
                    'I confirm this is separately incurred and has not already been deducted in transaction margins.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                const Text(
                    'Supporting document · optional · PDF / PNG / JPEG · maximum 256 KiB',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xff53675f))),
                const SizedBox(height: 7),
                TextField(
                  controller: _docName,
                  decoration: const InputDecoration(
                      labelText: 'Document filename',
                      hintText: 'invoice.pdf',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _docBase64,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: 'Document base64 data',
                      border: OutlineInputBorder()),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: const TextStyle(
                          color: Color(0xffa13e39), fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined, size: 17),
          label: Text(_saving ? 'Recording…' : 'Record expense'),
          style: FilledButton.styleFrom(backgroundColor: _green),
        ),
      ],
    );
  }
}
