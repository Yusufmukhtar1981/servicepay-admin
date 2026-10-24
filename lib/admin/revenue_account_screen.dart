import 'dart:async';

import 'package:flutter/material.dart';

import 'revenue_account_api.dart';

part 'revenue_account_charts.dart';
part 'revenue_account_widgets.dart';

@visibleForTesting
bool canViewRevenueAccount({
  required String role,
  required Set<String> permissions,
}) {
  final String normalized = role.trim().toUpperCase().replaceAll(
        RegExp(r'[\s-]+'),
        '_',
      );
  final bool headOffice = const <String>{
    'HEAD_OFFICE',
    'HEAD_OFFICE_ADMIN',
    'ADMIN',
    'SUPER_ADMIN',
    'SERVICEPAY_SUPER_ADMIN',
  }.contains(normalized);
  if (!headOffice) return false;
  return permissions.any(
        (String value) => value.trim().toLowerCase() == 'transactions.view',
      ) ||
      const <String>{
        'HEAD_OFFICE',
        'ADMIN',
        'SUPER_ADMIN',
        'HEAD_OFFICE_ADMIN',
        'SERVICEPAY_SUPER_ADMIN',
      }.contains(normalized);
}

class RevenueAccountScreen extends StatefulWidget {
  const RevenueAccountScreen({super.key, this.api});

  final RevenueAccountApi? api;

  @override
  State<RevenueAccountScreen> createState() => _RevenueAccountScreenState();
}

class _RevenueAccountScreenState extends State<RevenueAccountScreen>
    with SingleTickerProviderStateMixin {
  late final RevenueAccountApi _api = widget.api ?? RevenueAccountApi();
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(_tabChanged);
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _transactionResult;
  Map<String, dynamic>? _ledgerResult;
  bool _loading = true;
  bool _transactionsLoading = false;
  bool _ledgerLoading = false;
  bool _busy = false;
  String? _error;
  String _service = '';
  String _status = '';
  DateTime? _from;
  DateTime? _to;
  int _page = 1;
  static const int _limit = 25;
  int _activeTab = 0;
  int _summaryRequestId = 0;
  int _transactionsRequestId = 0;
  int _ledgerRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _tabs
      ..removeListener(_tabChanged)
      ..dispose();
    super.dispose();
  }

  void _tabChanged() {
    if (_tabs.indexIsChanging || _tabs.index == _activeTab) return;
    _activeTab = _tabs.index;
    if (_activeTab == 1 && _transactionResult == null) _loadTransactions();
    if (_activeTab == 2 && _ledgerResult == null) _loadLedger();
  }

  Map<String, String> get _filters => <String, String>{
        if (_from != null) 'from': _day(_from!),
        if (_to != null) 'to': _day(_to!),
        if (_service.isNotEmpty) 'service': _service,
        if (_status.isNotEmpty) 'status': _status,
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
        'page': '$_page',
        'limit': '$_limit',
      };

  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _loadAll({bool refresh = false}) async {
    final int requestId = ++_summaryRequestId;
    setState(() {
      _loading = !refresh && _summary == null;
      _error = null;
    });
    try {
      final Map<String, dynamic> result = await _api.summary(filters: _filters);
      if (!mounted || requestId != _summaryRequestId) return;
      setState(() {
        _summary = result;
        _loading = false;
      });
      if (_activeTab == 1) await _loadTransactions();
      if (_activeTab == 2) await _loadLedger();
    } catch (error) {
      if (!mounted || requestId != _summaryRequestId) return;
      setState(() {
        _loading = false;
        _error = _errorText(error);
      });
    }
  }

  String _errorText(Object error) => error is RevenueAccountException
      ? error.message
      : 'Could not reach Revenue Account. Check your connection and retry.';

  Future<void> _loadTransactions() async {
    final int requestId = ++_transactionsRequestId;
    if (mounted) setState(() => _transactionsLoading = true);
    try {
      final Map<String, dynamic> result =
          await _api.transactions(filters: _filters);
      if (!mounted || requestId != _transactionsRequestId) return;
      setState(() {
        _transactionResult = result;
        _error = null;
        _transactionsLoading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _transactionsRequestId) return;
      setState(() {
        _error = _errorText(error);
        _transactionsLoading = false;
      });
    }
  }

  Future<void> _loadLedger() async {
    final int requestId = ++_ledgerRequestId;
    if (mounted) setState(() => _ledgerLoading = true);
    try {
      final Map<String, dynamic> result = await _api.ledger(filters: _filters);
      if (!mounted || requestId != _ledgerRequestId) return;
      setState(() {
        _ledgerResult = result;
        _error = null;
        _ledgerLoading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _ledgerRequestId) return;
      setState(() {
        _error = _errorText(error);
        _ledgerLoading = false;
      });
    }
  }

  Future<void> _applyFilters() async {
    setState(() {
      _page = 1;
      _transactionResult = null;
      _ledgerResult = null;
    });
    await _loadAll(refresh: true);
  }

  Future<void> _pickDate({required bool start}) async {
    final DateTime now = DateTime.now();
    final DateTime? value = await showDatePicker(
      context: context,
      initialDate: (start ? _from : _to) ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: start ? 'Start date' : 'End date',
    );
    if (value == null || !mounted) return;
    setState(() {
      if (start) {
        _from = value;
      } else {
        _to = value;
      }
    });
    await _applyFilters();
  }

  Future<void> _setPage(int page) async {
    if (page < 1) return;
    setState(() {
      _page = page;
      _transactionResult = null;
      _ledgerResult = null;
    });
    if (_activeTab == 1) await _loadTransactions();
    if (_activeTab == 2) await _loadLedger();
  }

  Future<void> _export(String format) async {
    setState(() => _busy = true);
    try {
      await _api.export(format: format, filters: _filters);
      if (mounted) _message('Revenue $format export downloaded.');
    } catch (error) {
      if (mounted) _message(_errorText(error), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconcile() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Run bookkeeping reconciliation?'),
        content: const Text(
          'This processes existing confirmed accounting records only. It will not initiate purchases, refunds, or provider requests.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Run reconciliation'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final Map<String, dynamic> result = await _api.reconcile();
      if (!mounted) return;
      _message(
        'Processed ${result['processed'] ?? 0}: recognized ${result['recognized'] ?? 0}, reversed ${result['reversed'] ?? 0}, adjusted ${result['adjusted'] ?? 0}${result['hasMore'] == true ? '. Another bounded batch remains; run it when ready.' : '.'}',
      );
      await _applyFilters();
    } catch (error) {
      if (mounted) _message(_errorText(error), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: isError ? const Color(0xffa9423d) : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xfff4f6f4),
      body: SafeArea(
        child: _loading
            ? const _RevenueSkeleton()
            : _error != null && _summary == null
                ? _ErrorState(message: _error!, onRetry: () => _loadAll())
                : RefreshIndicator(
                    onRefresh: () => _loadAll(refresh: true),
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: <Widget>[
                        SliverToBoxAdapter(child: _header(colors)),
                        SliverToBoxAdapter(child: _filterPanel(colors)),
                        if (_error != null)
                          SliverToBoxAdapter(child: _inlineError(colors)),
                        SliverToBoxAdapter(
                          child: TabBar(
                            controller: _tabs,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            labelColor: const Color(0xff176b58),
                            indicatorColor: const Color(0xff176b58),
                            tabs: const <Widget>[
                              Tab(text: 'Overview'),
                              Tab(text: 'Transactions'),
                              Tab(text: 'Accounting ledger'),
                            ],
                          ),
                        ),
                        SliverFillRemaining(
                          hasScrollBody: true,
                          child: TabBarView(
                            controller: _tabs,
                            children: <Widget>[
                              _overview(),
                              _transactions(),
                              _ledger(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _header(ColorScheme colors) {
    final Map<String, dynamic> reconciliation =
        _map(_summary?['reconciliation']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 660;
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
                        Text('FINANCE  /  PERFORMANCE',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            )),
                        const SizedBox(height: 7),
                        Text('Revenue Account',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  color: const Color(0xff18352e),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.8,
                                )),
                        const SizedBox(height: 5),
                        const Text(
                          'Sales are not profit. Only verified cost evidence earns a profit figure.',
                          style: TextStyle(color: Color(0xff60716c)),
                        ),
                      ],
                    ),
                  ),
                  if (!compact) ...<Widget>[
                    const SizedBox(width: 14),
                    _reconcileButton(),
                  ],
                ],
              ),
              if (compact) ...<Widget>[
                const SizedBox(height: 12),
                _reconcileButton(),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 9,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _pill(
                    icon: Icons.lock_outline,
                    text: 'Source report · refreshed live',
                    color: const Color(0xff176b58),
                  ),
                  _pill(
                    icon: Icons.schedule_outlined,
                    text: 'Periods · Nigeria calendar',
                    color: const Color(0xff396b89),
                  ),
                  _pill(
                    icon: Icons.sync_outlined,
                    text:
                        'Reconciliation: ${_text(reconciliation['status'], fallback: 'Not reported')}',
                    color: const Color(0xff68746f),
                  ),
                  if (_text(reconciliation['lastRunAt']).isNotEmpty)
                    Text('Last run ${_text(reconciliation['lastRunAt'])}',
                        style: const TextStyle(
                            color: Color(0xff71807b), fontSize: 12)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _reconcileButton() => OutlinedButton.icon(
        onPressed: _busy ? null : _reconcile,
        icon: const Icon(Icons.fact_check_outlined, size: 18),
        label: const Text('Reconcile records'),
      );

  Widget _pill({
    required IconData icon,
    required String text,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              )),
        ]),
      );

  Widget _filterPanel(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xffe9efeb),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xffdce5df)),
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth;
            final double itemWidth = width > 900
                ? (width - 48) / 4
                : width > 600
                    ? (width - 24) / 2
                    : width;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: itemWidth,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 350),
                        _applyFilters,
                      );
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 19),
                      hintText: 'Search reference or customer',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xfffbfcfa),
                    ),
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: DropdownButtonFormField<String>(
                    value: _service,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Service',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xfffbfcfa),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: '', child: Text('All services')),
                      DropdownMenuItem(value: 'DATA', child: Text('Data')),
                      DropdownMenuItem(
                          value: 'AIRTIME', child: Text('Airtime')),
                      DropdownMenuItem(
                          value: 'ELECTRICITY', child: Text('Electricity')),
                      DropdownMenuItem(value: 'CABLE', child: Text('Cable TV')),
                    ],
                    onChanged: (String? value) {
                      setState(() => _service = value ?? '');
                      _applyFilters();
                    },
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: DropdownButtonFormField<String>(
                    value: _status,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Transaction status',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xfffbfcfa),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: '', child: Text('All statuses')),
                      DropdownMenuItem(
                          value: 'SUCCESSFUL', child: Text('Successful')),
                      DropdownMenuItem(
                          value: 'PENDING', child: Text('Pending')),
                      DropdownMenuItem(value: 'FAILED', child: Text('Failed')),
                      DropdownMenuItem(
                          value: 'REFUNDED', child: Text('Refunded')),
                      DropdownMenuItem(
                          value: 'REVERSED', child: Text('Reversed')),
                    ],
                    onChanged: (String? value) {
                      setState(() => _status = value ?? '');
                      _applyFilters();
                    },
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: Row(children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(start: true),
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_from == null ? 'From date' : _day(_from!)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(start: false),
                        icon: const Icon(Icons.event, size: 16),
                        label: Text(_to == null ? 'To date' : _day(_to!)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Clear date range',
                      onPressed: _from == null && _to == null
                          ? null
                          : () {
                              setState(() {
                                _from = null;
                                _to = null;
                              });
                              _applyFilters();
                            },
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                ),
                SizedBox(
                  width: itemWidth,
                  child: Wrap(
                    spacing: 4,
                    children: <Widget>[
                      _exportButton('CSV', 'csv'),
                      _exportButton('Excel', 'xlsx'),
                      _exportButton('PDF', 'pdf'),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _exportButton(String label, String format) => TextButton.icon(
        onPressed: _busy ? null : () => _export(format),
        icon: const Icon(Icons.download_outlined, size: 16),
        label: Text(label),
      );

  Widget _inlineError(ColorScheme colors) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Material(
          color: const Color(0xffffece8),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(children: <Widget>[
              const Icon(Icons.error_outline, color: Color(0xffa9423d)),
              const SizedBox(width: 9),
              Expanded(child: Text(_error!)),
              TextButton(onPressed: _loadAll, child: const Text('Retry')),
            ]),
          ),
        ),
      );

  Widget _overview() {
    final Map<String, dynamic> totals = _map(_summary?['totals']);
    final Map<String, dynamic> periods = _map(_summary?['periods']);
    final List<dynamic> services = _list(_summary?['services']);
    final List<dynamic> trend = _list(_summary?['trend']);
    final bool complete = totals['accountingComplete'] == true;
    final int uncosted = _integer(totals['uncostedTransactions']);
    final int unverified = _integer(totals['unverifiedTransactions']);
    final int knownCosts = _integer(totals['costedTransactions']);
    final bool showCoverageWarning =
        !complete || uncosted > 0 || unverified > 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
      children: <Widget>[
        if (showCoverageWarning)
          _coverageWarning(
            'Profit coverage is incomplete',
            '$unverified successful transaction${unverified == 1 ? '' : 's'} still need provider confirmation. $uncosted confirmed sale${uncosted == 1 ? '' : 's'} have no verified invoice cost. Known-cost profit below is partial—not total profit.',
          ),
        const SizedBox(height: 12),
        _kpiGrid(<_KpiData>[
          _KpiData(
              'Gross revenue',
              _money(totals['grossRevenue']),
              'Confirmed customer sales',
              Icons.south_west,
              const Color(0xff176b58)),
          _KpiData(
              'Net profit',
              _profit(totals['netProfit'], complete),
              complete
                  ? 'Costs fully accounted'
                  : '$knownCosts with verified costs',
              Icons.account_balance,
              const Color(0xff255e73)),
          _KpiData(
              'Gross profit',
              _profit(totals['grossProfit'], complete),
              'After verified provider cost',
              Icons.trending_up,
              const Color(0xff176b58)),
          _KpiData('Today', _money(periods['today']),
              'Nigeria calendar revenue', Icons.today, const Color(0xff8b6720)),
          _KpiData(
              'Yesterday',
              _money(periods['yesterday']),
              'Nigeria calendar revenue',
              Icons.history,
              const Color(0xff685e8f)),
          _KpiData(
              'This week',
              _money(periods['week']),
              'Nigeria calendar revenue',
              Icons.date_range,
              const Color(0xff396b89)),
          _KpiData(
              'This month',
              _money(periods['month']),
              'Nigeria calendar revenue',
              Icons.calendar_month,
              const Color(0xff8a5d49)),
          _KpiData(
              'Provider costs',
              _money(totals['providerCosts']),
              '${_integer(totals['costedTransactions'])} with cost evidence',
              Icons.receipt_long,
              const Color(0xff586d63)),
          _KpiData(
              'Other direct costs',
              _money(totals['otherDirectCosts']),
              'Transaction-level deductions',
              Icons.call_made_outlined,
              const Color(0xff8a5d49)),
          _KpiData(
              'Fees & commissions',
              _money(_number(totals['fees']) + _number(totals['commissions'])),
              'Direct transaction deductions',
              Icons.call_made,
              const Color(0xff8a5d49)),
          _KpiData(
              'Successful transactions',
              _integer(totals['successfulTransactions']).toString(),
              '${_integer(totals['excludedTransactions'])} excluded from revenue',
              Icons.check_circle_outline,
              const Color(0xff176b58)),
        ]),
        const SizedBox(height: 14),
        _chartPanel(
          title: 'Revenue and verified profit',
          subtitle:
              'Daily values from recorded transactions · profit is unavailable without cost evidence',
          child: _TrendChart(points: trend),
          height: 250,
        ),
        const SizedBox(height: 14),
        _chartPanel(
          title: 'Service revenue',
          subtitle: 'Customer payments by service · NAIRA',
          child: _ServiceBars(services: services),
          height: 235,
        ),
        const SizedBox(height: 14),
        _serviceTable(services),
        const SizedBox(height: 14),
        _coverageStats(totals, complete),
        const SizedBox(height: 14),
        _ledgerSummary(),
      ],
    );
  }

  Widget _coverageWarning(String title, String message) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xfffff4dc),
          border: Border.all(color: const Color(0xffe6c67e)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.warning_amber_rounded, color: Color(0xff805b15)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title,
                          style: const TextStyle(
                              color: Color(0xff63460d),
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(message,
                          style: const TextStyle(
                              color: Color(0xff705a30), height: 1.35)),
                    ]),
              ),
            ]),
      );

  Widget _kpiGrid(List<_KpiData> data) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final int columns = constraints.maxWidth >= 1100
              ? 3
              : constraints.maxWidth >= 650
                  ? 2
                  : 1;
          final double cardWidth =
              (constraints.maxWidth - ((columns - 1) * 10)) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: data.map((_KpiData item) {
              return SizedBox(
                width: cardWidth,
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xfffbfcfa),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: const Color(0xffe0e7e2)),
                  ),
                  child: Row(children: <Widget>[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(item.icon, color: item.color, size: 19),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(item.label,
                                style: const TextStyle(
                                    color: Color(0xff687871),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(item.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Color(0xff18352e),
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(item.note,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Color(0xff87938e), fontSize: 10)),
                          ]),
                    ),
                  ]),
                ),
              );
            }).toList(),
          );
        },
      );

  Widget _chartPanel({
    required String title,
    required String subtitle,
    required Widget child,
    required double height,
  }) =>
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: _panelDecoration(),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title,
                  style: const TextStyle(
                      color: Color(0xff243b34),
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style:
                      const TextStyle(color: Color(0xff73817b), fontSize: 11)),
              SizedBox(height: height, child: child),
            ]),
      );

  Widget _serviceTable(List<dynamic> services) => Container(
        padding: const EdgeInsets.all(16),
        decoration: _panelDecoration(),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Service performance',
                  style: TextStyle(
                      color: Color(0xff243b34),
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
              const SizedBox(height: 12),
              if (services.isEmpty)
                const _EmptyState(
                    title: 'No service activity in this period',
                    message: 'Try a wider date range.'),
              for (final dynamic row in services)
                if (row is Map) _serviceRow(Map<String, dynamic>.from(row)),
            ]),
      );

  Widget _serviceRow(Map<String, dynamic> row) {
    final String title = _serviceName(_text(row['serviceType']));
    final dynamic profit = row['netProfit'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xffedf0ed)))),
      child: Row(children: <Widget>[
        Expanded(
          flex: 2,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                    '${_integer(row['successfulTransactions'])} successful · ${_integer(row['uncostedTransactions'])} uncosted',
                    style: const TextStyle(
                        color: Color(0xff7c8983), fontSize: 11)),
              ]),
        ),
        Expanded(child: _numericCell('Revenue', _money(row['grossRevenue']))),
        Expanded(
            child: _numericCell(
                'Provider cost',
                row['providerCosts'] == null
                    ? 'Unresolved'
                    : _money(row['providerCosts']))),
        Expanded(
            child: _numericCell('Known-cost profit',
                profit == null ? 'Unresolved' : _money(profit))),
      ]),
    );
  }

  Widget _numericCell(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xff7c8983), fontSize: 10)),
          const SizedBox(height: 3),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Color(0xff30453d),
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
        ],
      );

  Widget _coverageStats(Map<String, dynamic> totals, bool complete) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: _panelDecoration(),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Accounting coverage',
                  style: TextStyle(
                      color: Color(0xff243b34),
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
              const SizedBox(height: 10),
              Wrap(spacing: 24, runSpacing: 12, children: <Widget>[
                _coverageItem('Costed transactions',
                    _integer(totals['costedTransactions']).toString()),
                _coverageItem('Uncosted transactions',
                    _integer(totals['uncostedTransactions']).toString()),
                _coverageItem('Unverified transactions',
                    _integer(totals['unverifiedTransactions']).toString()),
                _coverageItem('Excluded transactions',
                    _integer(totals['excludedTransactions']).toString()),
                _coverageItem(
                    'Other direct costs', _money(totals['otherDirectCosts'])),
              ]),
              const SizedBox(height: 11),
              Text(
                complete
                    ? 'Cost evidence is complete for this result set.'
                    : 'Profit figures represent known-cost transactions only. Missing invoice costs remain unresolved, not zero.',
                style: TextStyle(
                  color: complete
                      ? const Color(0xff176b58)
                      : const Color(0xff805b15),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ]),
      );

  Widget _coverageItem(String label, String value) => SizedBox(
        width: 190,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label,
                  style:
                      const TextStyle(color: Color(0xff7c8983), fontSize: 11)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      color: Color(0xff30453d),
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ]),
      );

  Widget _ledgerSummary() {
    final Map<String, dynamic> ledger = _map(_summary?['ledger']);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Row(children: <Widget>[
        const Icon(Icons.menu_book_outlined, color: Color(0xff176b58)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('All-time posted ledger',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                Text(
                    'ALL SERVICES / ALL_TIME_POSTED · as of ${_text(ledger['asOf'], fallback: 'timestamp unavailable')} · ${_integer(ledger['entries'])} entries · ${_integer(ledger['uncostedTransactions'])} uncosted · may lag live source reports',
                    style: const TextStyle(
                        color: Color(0xff7c8983), fontSize: 11)),
              ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
          Text(
              'Posted net profit · ${ledger['netProfit'] == null ? 'Unresolved' : _money(ledger['netProfit'])}',
              style: const TextStyle(
                  color: Color(0xff176b58), fontWeight: FontWeight.w800)),
          Text('Gross revenue · ${_money(ledger['grossRevenue'])}',
              style: const TextStyle(color: Color(0xff71807b), fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _transactions() {
    final Map<String, dynamic> result =
        _transactionResult ?? <String, dynamic>{};
    final List<dynamic> rows = _list(result['items']);
    return Column(children: <Widget>[
      Expanded(
        child: _transactionsLoading
            ? const _RevenueSkeleton()
            : rows.isEmpty
                ? _error != null
                    ? _ErrorState(message: _error!, onRetry: _loadTransactions)
                    : const _EmptyState(
                        title: 'No transactions match these filters',
                        message:
                            'Adjust the dates or search to see another period.',
                      )
                : LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                      if (constraints.maxWidth < 760) {
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                          itemCount: rows.length,
                          itemBuilder: (BuildContext context, int index) {
                            final Map<String, dynamic> row = _map(rows[index]);
                            return _transactionCard(row);
                          },
                        );
                      }
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                                const Color(0xffe9efeb)),
                            columns: const <DataColumn>[
                              DataColumn(label: Text('Transaction / customer')),
                              DataColumn(label: Text('Service')),
                              DataColumn(label: Text('Customer payment')),
                              DataColumn(label: Text('Provider cost')),
                              DataColumn(label: Text('Gross profit')),
                              DataColumn(label: Text('Fees')),
                              DataColumn(label: Text('Commissions')),
                              DataColumn(label: Text('Other costs')),
                              DataColumn(label: Text('Known-cost profit')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Accounting status')),
                              DataColumn(label: Text('Date')),
                            ],
                            rows: rows.map((dynamic value) {
                              final Map<String, dynamic> row = _map(value);
                              final String profit = _profit(
                                  row['netProfit'] ?? row['grossProfit'],
                                  row['accountingStatus'] == 'COMPLETE');
                              return DataRow(cells: <DataCell>[
                                DataCell(SizedBox(
                                  width: 190,
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: <Widget>[
                                        Text(
                                            _text(row['reference'],
                                                fallback: _text(
                                                    row['transactionId'])),
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        Text(
                                            'ID ${_text(row['transactionId'], fallback: '—')} · ${_text(row['customerName'], fallback: 'Customer unavailable')} · ${_text(row['provider'], fallback: 'Provider unavailable')}',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xff7c8983))),
                                      ]),
                                )),
                                DataCell(Text(
                                    _serviceName(_text(row['serviceType'])))),
                                DataCell(Text(_money(row['customerPayment']))),
                                DataCell(Text(row['providerCost'] == null
                                    ? 'Unresolved'
                                    : _money(row['providerCost']))),
                                DataCell(Text(row['grossProfit'] == null
                                    ? 'Unresolved'
                                    : _money(row['grossProfit']))),
                                DataCell(Text(_money(row['fees']))),
                                DataCell(Text(_money(row['commissions']))),
                                DataCell(Text(_money(row['otherDirectCosts']))),
                                DataCell(Text(row['netProfit'] == null
                                    ? 'Unresolved'
                                    : profit)),
                                DataCell(_statusBadge(_text(row['status']))),
                                DataCell(_accountingStatus(
                                    _text(row['accountingStatus']))),
                                DataCell(Text(_dateLabel(row['date']))),
                              ]);
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  ),
      ),
      _pagination(result, rows),
    ]);
  }

  Widget _transactionCard(Map<String, dynamic> row) {
    final bool missing =
        row['providerCost'] == null || row['netProfit'] == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: _panelDecoration(),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                          _text(row['reference'],
                              fallback: _text(row['transactionId'])),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(
                          '${_text(row['customerName'], fallback: 'Customer unavailable')} · ${_text(row['provider'], fallback: 'Provider unavailable')}',
                          style: const TextStyle(
                              color: Color(0xff74817b), fontSize: 12)),
                    ]),
              ),
              _statusBadge(_text(row['status'])),
            ]),
            if (_text(row['accountingStatus']).isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              _accountingStatus(_text(row['accountingStatus'])),
            ],
            const Divider(height: 20),
            Wrap(spacing: 18, runSpacing: 12, children: <Widget>[
              _coverageItem('Transaction ID', _text(row['transactionId'])),
              _coverageItem('Provider', _text(row['provider'], fallback: '—')),
              _coverageItem('Service', _serviceName(_text(row['serviceType']))),
              _coverageItem('Customer payment', _money(row['customerPayment'])),
              _coverageItem(
                  'Provider cost',
                  row['providerCost'] == null
                      ? 'Unresolved'
                      : _money(row['providerCost'])),
              _coverageItem(
                  'Gross profit',
                  row['grossProfit'] == null
                      ? 'Unresolved'
                      : _money(row['grossProfit'])),
              _coverageItem('Fees', _money(row['fees'])),
              _coverageItem('Commissions', _money(row['commissions'])),
              _coverageItem(
                  'Other direct costs', _money(row['otherDirectCosts'])),
              _coverageItem(
                  'Profit',
                  row['netProfit'] == null
                      ? 'Unresolved'
                      : _money(row['netProfit'])),
              _coverageItem('Date', _dateLabel(row['date'])),
            ]),
            if (missing)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                    'Missing verified cost evidence — profit is unresolved.',
                    style: TextStyle(
                        color: Color(0xff805b15),
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
    );
  }

  Widget _pagination(Map<String, dynamic> result, List<dynamic> rows) {
    final int page = _integer(result['page'], fallback: _page);
    final int pages = _integer(result['pages'], fallback: 1).clamp(1, 999999);
    final int total = _integer(result['total']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: Row(children: <Widget>[
        Expanded(
          child: Text(
            total == 0 ? 'No records' : 'Page $page of $pages · $total records',
            style: const TextStyle(color: Color(0xff74817b), fontSize: 12),
          ),
        ),
        IconButton(
          tooltip: 'Previous page',
          onPressed: page <= 1 ? null : () => _setPage(page - 1),
          icon: const Icon(Icons.chevron_left),
        ),
        Text('$page', style: const TextStyle(fontWeight: FontWeight.w800)),
        IconButton(
          tooltip: 'Next page',
          onPressed:
              page >= pages || rows.isEmpty ? null : () => _setPage(page + 1),
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
    );
  }

  Widget _ledger() {
    final Map<String, dynamic> result = _ledgerResult ?? <String, dynamic>{};
    final List<dynamic> rows = _list(result['items']);
    final Map<String, dynamic> postedLedger = _map(_summary?['ledger']);
    final int ledgerUncosted = _integer(postedLedger['uncostedTransactions']);
    final bool ledgerProfitUnresolved = postedLedger['netProfit'] == null &&
        _integer(postedLedger['entries']) > 0;
    return Column(children: <Widget>[
      Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xffe9efeb),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: <Widget>[
          const Icon(Icons.lock_outline, size: 18, color: Color(0xff176b58)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ALL SERVICES / ALL_TIME_POSTED · as of ${_text(postedLedger['asOf'], fallback: 'timestamp unavailable')}. This posted book can lag the fresh source transaction report and is independent of selected source filters. Ledger entries never alter customer wallet balances.',
              style: const TextStyle(color: Color(0xff475951), fontSize: 12),
            ),
          ),
        ]),
      ),
      if (ledgerUncosted > 0 || ledgerProfitUnresolved)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: _coverageWarning(
            'Posted ledger profit is unresolved',
            '$ledgerUncosted posted transaction${ledgerUncosted == 1 ? '' : 's'} have no confirmed provider cost. Null ledger profit is unresolved, not zero; verified known-cost figures are only partial.',
          ),
        ),
      Expanded(
        child: _ledgerLoading
            ? const _RevenueSkeleton()
            : rows.isEmpty
                ? _error != null
                    ? _ErrorState(message: _error!, onRetry: _loadLedger)
                    : const _EmptyState(
                        title: 'No accounting entries',
                        message:
                            'Recognized revenue and linked adjustments will appear here.',
                      )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 7),
                    itemBuilder: (BuildContext context, int index) {
                      final Map<String, dynamic> row = _map(rows[index]);
                      return Container(
                        padding: const EdgeInsets.all(13),
                        decoration: _panelDecoration(),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(children: <Widget>[
                                Expanded(
                                  child: Text(
                                      _text(row['eventType'],
                                              fallback: 'Accounting entry')
                                          .replaceAll('_', ' '),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800)),
                                ),
                                Text(_money(row['netProfit']),
                                    style: const TextStyle(
                                        color: Color(0xff176b58),
                                        fontWeight: FontWeight.w800)),
                              ]),
                              const SizedBox(height: 8),
                              Wrap(
                                  spacing: 18,
                                  runSpacing: 8,
                                  children: <Widget>[
                                    _coverageItem('Entry', _text(row['id'])),
                                    _coverageItem('Transaction',
                                        _text(row['transactionId'])),
                                    _coverageItem(
                                        'Linked entry',
                                        _text(row['linkedEntryId'],
                                            fallback: '—')),
                                    _coverageItem(
                                        'Cost source',
                                        _text(row['costSource'],
                                            fallback: 'Unresolved')),
                                    _coverageItem('Customer payment',
                                        _money(row['customerPayment'])),
                                    _coverageItem(
                                        'Provider cost',
                                        row['providerCost'] == null
                                            ? 'Unresolved'
                                            : _money(row['providerCost'])),
                                    _coverageItem(
                                        'Gross profit',
                                        row['grossProfit'] == null
                                            ? 'Unresolved'
                                            : _money(row['grossProfit'])),
                                    _coverageItem('Fees', _money(row['fees'])),
                                    _coverageItem('Commissions',
                                        _money(row['commissions'])),
                                    _coverageItem(
                                        'Date', _dateLabel(row['date'])),
                                  ]),
                              if (_text(row['reason']).isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(_text(row['reason']),
                                      style: const TextStyle(
                                          color: Color(0xff74817b),
                                          fontSize: 12)),
                                ),
                            ]),
                      );
                    },
                  ),
      ),
      _pagination(result, rows),
    ]);
  }

  Widget _statusBadge(String status) {
    final String normalized = status.toUpperCase();
    final Color color = normalized == 'SUCCESSFUL'
        ? const Color(0xff176b58)
        : normalized == 'FAILED' || normalized == 'REFUNDED'
            ? const Color(0xffa9423d)
            : const Color(0xff805b15);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(20)),
      child: Text(status.isEmpty ? 'UNKNOWN' : status,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }

  Widget _accountingStatus(String status) {
    final String normalized = status.toUpperCase();
    final String label = switch (normalized) {
      'PROVIDER_EVIDENCE_REQUIRED' => 'Provider evidence required',
      'PROVIDER_COST_UNCONFIRMED' || 'UNCOSTED' => 'Provider cost unconfirmed',
      '' => 'Accounting status unavailable',
      _ => status.replaceAll('_', ' '),
    };
    final bool unresolved = normalized == 'PROVIDER_EVIDENCE_REQUIRED' ||
        normalized == 'PROVIDER_COST_UNCONFIRMED' ||
        normalized == 'UNCOSTED';
    final Color color =
        unresolved ? const Color(0xff805b15) : const Color(0xff176b58);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
        color: const Color(0xfffbfcfa),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xffe0e7e2)),
      );

  String _money(dynamic value) {
    if (value == null) return '—';
    final double amount = _number(value);
    final String digits = amount.abs().toStringAsFixed(2);
    final List<String> parts = digits.split('.');
    final String whole = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (Match match) => '${match[1]},',
    );
    return '${amount < 0 ? '-' : ''}₦$whole.${parts.last}';
  }

  String _profit(dynamic value, bool complete) => value == null
      ? 'Unresolved'
      : '${complete ? '' : 'Known-cost '}${_money(value)}';

  String _serviceName(String value) => switch (value.toUpperCase()) {
        'DATA' => 'Data',
        'AIRTIME' => 'Airtime',
        'ELECTRICITY' => 'Electricity',
        'CABLE' || 'CABLE_TV' => 'Cable TV',
        '' => 'Other',
        _ => value.replaceAll('_', ' '),
      };

  String _dateLabel(dynamic value) {
    final String text = _text(value);
    if (text.isEmpty) return '—';
    return text.length > 10 ? text.substring(0, 10) : text;
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<dynamic> _list(dynamic value) => value is List ? value : <dynamic>[];

  String _text(dynamic value, {String fallback = ''}) =>
      value == null ? fallback : value.toString().trim();

  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  int _integer(dynamic value, {int fallback = 0}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
}
