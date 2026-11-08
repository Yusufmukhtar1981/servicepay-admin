import 'package:flutter/material.dart';

import 'pending_resolution_api.dart';

class PendingResolutionScreen extends StatefulWidget {
  const PendingResolutionScreen({
    super.key,
    this.api,
  });

  final PendingResolutionApi? api;

  @override
  State<PendingResolutionScreen> createState() =>
      _PendingResolutionScreenState();
}

class _PendingResolutionScreenState extends State<PendingResolutionScreen> {
  late final PendingResolutionApi _api = widget.api ?? PendingResolutionApi();
  final TextEditingController _search = TextEditingController();
  final TextEditingController _minAmount = TextEditingController();
  final TextEditingController _maxAmount = TextEditingController();
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  String? _readError;
  String _status = 'PENDING';
  String _duration = 'ALL';
  String _type = '';
  int _page = 1;
  int _pages = 1;
  int _total = 0;
  bool _loading = true;
  bool _busy = false;
  DateTime? _from;
  DateTime? _to;
  String _searchTerm = '';

  static const Color _ink = Color(0xFF18353B);
  static const Color _muted = Color(0xFF647A7D);
  static const Color _teal = Color(0xFF087E79);
  static const Color _paper = Color(0xFFF3F7F5);
  static const Color _line = Color(0xFFDCE7E3);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _minAmount.dispose();
    _maxAmount.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _readError = null;
      });
    }
    try {
      final List<dynamic> results =
          await Future.wait<dynamic>(<Future<dynamic>>[
        _api.summary(),
        _api.transactions(
          page: _page,
          limit: 20,
          search: _searchTerm,
          type: _type,
          from: _isoDay(_from) ?? '',
          to: _isoDay(_to) ?? '',
          minAmount: _minAmount.text.trim(),
          maxAmount: _maxAmount.text.trim(),
          duration: _duration,
          status: _status,
        ),
      ]);
      final Map<String, dynamic> summaryEnvelope =
          Map<String, dynamic>.from(results[0] as Map);
      final Map<String, dynamic> pageEnvelope =
          Map<String, dynamic>.from(results[1] as Map);
      final Map<String, dynamic> summary = _map(summaryEnvelope['data']);
      final Map<String, dynamic> data = _map(pageEnvelope['data']);
      final dynamic rawItems = data['items'];
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _rows = rawItems is List
            ? rawItems
                .whereType<Map>()
                .map((Map item) => Map<String, dynamic>.from(item))
                .toList()
            : <Map<String, dynamic>>[];
        _page = _int(data['page'], _page);
        _pages = _int(data['pages'], 1).clamp(1, 999999).toInt();
        _total = _int(data['total'], 0);
        _readError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _readError = _message(error);
        _loading = false;
      });
    }
  }

  Future<void> _updateFilters() async {
    setState(() => _page = 1);
    await _load();
  }

  Future<void> _pickDate({required bool start}) async {
    final DateTime now = DateTime.now();
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: (start ? _from : _to) ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      helpText: start ? 'Filter from date' : 'Filter through date',
    );
    if (selected == null) return;
    setState(() {
      if (start) {
        _from = selected;
      } else {
        _to = selected;
      }
      _page = 1;
    });
    await _load();
  }

  Future<void> _openTransaction(
    Map<String, dynamic> row, {
    PendingResolutionAction? initialAction,
  }) async {
    final String id = '${row['id'] ?? ''}';
    if (id.isEmpty) return;
    Map<String, dynamic>? detail;
    PendingResolutionIntent? intent;
    String? error;
    try {
      final List<dynamic> values = await Future.wait<dynamic>(<Future<dynamic>>[
        _api.transaction(id),
        _api.loadIntent(id),
      ]);
      detail = _map(_map(values[0])['data']);
      intent = values[1] as PendingResolutionIntent?;
    } catch (failure) {
      error = _message(failure);
    }
    if (!mounted) return;
    if (detail == null) {
      _showMessage(error ?? 'Transaction details could not be loaded.');
      return;
    }
    if (initialAction != null) {
      final Map<String, dynamic> permissions = _map(detail['permissions']);
      final Map<String, dynamic> capabilities =
          initialAction == PendingResolutionAction.refund
              ? _map(detail['refund'])
              : initialAction == PendingResolutionAction.markSuccessful
                  ? _map(detail['success'])
                  : _map(detail['retry']);
      final bool permitted =
          permissions[initialAction == PendingResolutionAction.refund
                  ? 'refund'
                  : initialAction == PendingResolutionAction.markSuccessful
                      ? 'success'
                      : 'retry'] ==
              true;
      final bool eligible = capabilities['eligible'] == true;
      final List<String> blockers = _strings(capabilities['blockers']);
      final bool replayingSavedAction = intent?.action == initialAction;
      if (!replayingSavedAction &&
          (!permitted || !eligible || blockers.isNotEmpty)) {
        _showMessage(
          !permitted
              ? 'Your account does not have permission for ${_actionLabel(initialAction).toLowerCase()}.'
              : blockers.isNotEmpty
                  ? blockers.join(' ')
                  : _text(capabilities['reason'],
                      fallback:
                          'This transaction is not eligible for this action.'),
        );
        return;
      }
      await _openAction(row, detail, initialAction, intent);
      return;
    }
    final bool? changed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => _TransactionDetailDialog(
        detail: detail!,
        savedIntent: intent,
        onChooseAction: (PendingResolutionAction action) async {
          Navigator.of(dialogContext).pop(false);
          await _openAction(row, detail!, action, intent);
        },
      ),
    );
    if (changed == true) await _load(silent: true);
  }

  Future<void> _openAction(
    Map<String, dynamic> row,
    Map<String, dynamic> detail,
    PendingResolutionAction action,
    PendingResolutionIntent? savedIntent,
  ) async {
    if (_busy) return;
    final PendingResolutionIntent? currentIntent =
        savedIntent ?? await _api.loadIntent('${row['id']}');
    if (!mounted) return;
    if (currentIntent != null && currentIntent.action != action) {
      _showMessage(
        'An earlier ${_actionLabel(currentIntent.action).toLowerCase()} request is still unresolved. Replay it first using the saved details.',
      );
      return;
    }
    final bool? completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _ActionDialog(
        row: row,
        action: action,
        savedIntent: currentIntent,
        actionWarning: action == PendingResolutionAction.refund
            ? _text(_map(detail['refund'])['overrideWarning'])
            : '',
        onSubmit: ({
          required String reason,
          required String evidence,
          required bool deliveryConfirmed,
          required bool riskAcknowledged,
        }) async {
          setState(() => _busy = true);
          try {
            final Map<String, dynamic> response =
                action == PendingResolutionAction.retry
                    ? await _api.submitRetry('${row['id']}', reason: reason)
                    : await _api.submitAction(
                        '${row['id']}',
                        action: action,
                        reason: reason,
                        evidenceReference: evidence,
                        deliveryConfirmed: deliveryConfirmed,
                        providerRiskAcknowledged: riskAcknowledged,
                      );
            final Map<String, dynamic> data = _map(response['data']);
            final bool processing =
                '${data['state'] ?? ''}'.toUpperCase() == 'PROCESSING';
            if (!context.mounted) return null;
            Navigator.of(context).pop(true);
            _showMessage(
              processing
                  ? 'Status check is processing. The saved request remains available for a safe replay.'
                  : '${_actionLabel(action)} recorded.',
            );
            return null;
          } catch (failure) {
            return _message(failure);
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        },
      ),
    );
    if (completed == true && mounted) await _load(silent: true);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      body: SafeArea(
        child: RefreshIndicator(
          color: _teal,
          onRefresh: () => _load(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(child: _header()),
              if (_loading && _summary == null)
                SliverToBoxAdapter(child: _loadingState())
              else if (_readError != null && _summary == null)
                SliverToBoxAdapter(child: _errorState())
              else ...<Widget>[
                if (_readError != null)
                  SliverToBoxAdapter(child: _inlineError()),
                SliverToBoxAdapter(child: _summarySection()),
                SliverToBoxAdapter(child: _monitorBanner()),
                SliverToBoxAdapter(child: _filters()),
                if (_loading)
                  SliverToBoxAdapter(child: _rowsSkeleton())
                else if (_readError != null)
                  SliverToBoxAdapter(child: _errorPanel())
                else if (_rows.isEmpty)
                  SliverToBoxAdapter(child: _emptyState())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    sliver: SliverList.builder(
                      itemCount: _rows.length,
                      itemBuilder: (BuildContext context, int index) =>
                          _transactionCard(_rows[index]),
                    ),
                  ),
                if (!_loading && _readError == null)
                  SliverToBoxAdapter(child: _pagination()),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFFE2F0EC), Color(0xFFF3F7F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.fact_check_outlined, color: _teal),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Pending Transactions Resolution Center',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 21,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Investigate provider uncertainty. Record only what the evidence supports.',
                    style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh pending transactions',
              onPressed: _loading ? null : () => _load(),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      );

  Widget _summarySection() {
    final Map<String, dynamic> s = _summary ?? <String, dynamic>{};
    final List<_Metric> metrics = <_Metric>[
      _Metric('Pending', _count(s['totalPending']), Icons.hourglass_top_rounded,
          const Color(0xFF9A5A10)),
      _Metric('Pending value', _money(s['pendingAmount']),
          Icons.account_balance_wallet_outlined, _teal),
      _Metric('< 5 minutes', _count(s['below5Minutes']), Icons.schedule_rounded,
          const Color(0xFF4E7775)),
      _Metric('≥ 5 minutes', _count(s['above5Minutes']),
          Icons.timelapse_rounded, const Color(0xFF9A5A10)),
      _Metric('≥ 30 minutes', _count(s['above30Minutes']),
          Icons.warning_amber_rounded, const Color(0xFFB65B3E)),
      _Metric('≥ 1 hour', _count(s['above1Hour']), Icons.priority_high_rounded,
          const Color(0xFF9E3F3A)),
      _Metric('Resolved manually', _count(s['resolvedCount']),
          Icons.task_alt_rounded, _teal),
      _Metric('Refunded historically', _money(s['refundedAmount']),
          Icons.receipt_long_outlined, const Color(0xFF517C76)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('Live operating picture',
                  style: TextStyle(
                      color: _ink, fontWeight: FontWeight.w800, fontSize: 15)),
              const Spacer(),
              if (s['generatedAt'] != null)
                Text('Updated ${_dateTime(s['generatedAt'])}',
                    style: const TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final int columns = constraints.maxWidth >= 1050
                  ? 4
                  : constraints.maxWidth >= 620
                      ? 2
                      : 1;
              final double gap = 9;
              final double width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: metrics
                    .map((metric) => SizedBox(
                          width: width,
                          child: _metricCard(metric),
                        ))
                    .toList(),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Age thresholds overlap: ≥5m includes ≥30m and ≥1h. Historical figures reflect manual actions recorded in Admin audit, not all provider settlements.',
              style: TextStyle(color: _muted, fontSize: 11, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(_Metric metric) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFEFC),
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: <Widget>[
            Icon(metric.icon, color: metric.color, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(metric.label,
                      style: const TextStyle(color: _muted, fontSize: 11)),
                  const SizedBox(height: 3),
                  Text(metric.value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 17)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _monitorBanner() {
    final Map<String, dynamic> monitor = _map(_summary?['monitor']);
    final bool healthy = monitor['healthy'] == true;
    final String rootNotice = _text(_summary?['notice']);
    final String monitorNotice = _text(monitor['notice']);
    final String combinedNotice = <String>[rootNotice, monitorNotice]
        .where((String value) => value.isNotEmpty)
        .toSet()
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 15),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: healthy ? const Color(0xFFE8F3EF) : const Color(0xFFFFF0E8),
          border: Border.all(
              color:
                  healthy ? const Color(0xFFB7D6CA) : const Color(0xFFECC9B4)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              healthy ? Icons.monitor_heart_outlined : Icons.warning_amber,
              color: healthy ? _teal : const Color(0xFF9B4C21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${healthy ? 'Provider monitoring healthy' : 'Provider monitoring needs attention'}${combinedNotice.isNotEmpty ? ' · $combinedNotice' : ''}',
                style: TextStyle(
                  color: healthy
                      ? const Color(0xFF285F54)
                      : const Color(0xFF85411E),
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (monitor['checkedAt'] != null)
              Text('Checked ${_dateTime(monitor['checkedAt'])}',
                  style: const TextStyle(color: _muted, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _filters() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFEFC),
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: <Widget>[
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  final bool compact = box.maxWidth < 700;
                  final List<Widget> controls = <Widget>[
                    SizedBox(
                      width: compact ? double.infinity : 280,
                      child: TextField(
                        controller: _search,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (String value) {
                          _searchTerm = value.trim();
                          _updateFilters();
                        },
                        decoration: InputDecoration(
                          labelText: 'Search transactions or customer',
                          hintText: 'Name, phone, email, reference or ID',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: IconButton(
                            tooltip: 'Apply search',
                            onPressed: () {
                              _searchTerm = _search.text.trim();
                              _updateFilters();
                            },
                            icon: const Icon(Icons.arrow_forward_rounded),
                          ),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    _dropdown(
                      'Status',
                      _status,
                      const <String>['PENDING', 'FAILED', 'RESOLVED', 'ALL'],
                      (String value) {
                        _status = value;
                        _updateFilters();
                      },
                    ),
                    _dropdown(
                      'Age',
                      _duration,
                      const <String>[
                        'ALL',
                        'RECENT',
                        'DELAYED',
                        'LONG_STANDING',
                        'ATTENTION'
                      ],
                      (String value) {
                        _duration = value;
                        _updateFilters();
                      },
                    ),
                    _dropdown(
                      'Service type',
                      _type,
                      const <String>[
                        '',
                        'AIRTIME',
                        'DATA',
                        'ELECTRICITY',
                        'TV'
                      ],
                      (String value) {
                        _type = value;
                        _updateFilters();
                      },
                      labels: const <String, String>{
                        '': 'All types',
                        'AIRTIME': 'Airtime',
                        'DATA': 'Data',
                        'ELECTRICITY': 'Electricity',
                        'TV': 'TV',
                      },
                    ),
                  ];
                  return Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: controls
                        .map((Widget child) => compact
                            ? SizedBox(width: box.maxWidth, child: child)
                            : child)
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  final bool compact = box.maxWidth < 700;
                  return Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _dateButton(
                        _from == null ? 'From date' : _isoDay(_from)!,
                        onPressed: () => _pickDate(start: true),
                      ),
                      _dateButton(
                        _to == null ? 'To date' : _isoDay(_to)!,
                        onPressed: () => _pickDate(start: false),
                      ),
                      SizedBox(
                        width: compact ? (box.maxWidth - 9) / 2 : 130,
                        child: TextField(
                          controller: _minAmount,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Min amount',
                            prefixText: '₦ ',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _updateFilters(),
                        ),
                      ),
                      SizedBox(
                        width: compact ? (box.maxWidth - 9) / 2 : 130,
                        child: TextField(
                          controller: _maxAmount,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Max amount',
                            prefixText: '₦ ',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _updateFilters(),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          _search.clear();
                          _searchTerm = '';
                          _minAmount.clear();
                          _maxAmount.clear();
                          _from = null;
                          _to = null;
                          _type = '';
                          _status = 'PENDING';
                          _duration = 'ALL';
                          _updateFilters();
                        },
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('Clear filters'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Showing $_total matching transactions · dates use ISO calendar days',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _dropdown(
    String label,
    String value,
    List<String> values,
    ValueChanged<String> onChanged, {
    Map<String, String> labels = const <String, String>{},
  }) =>
      SizedBox(
        width: 150,
        child: DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          items: values
              .map((String option) => DropdownMenuItem<String>(
                    value: option,
                    child: Text(
                      labels[option] ?? _title(option),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: (String? next) {
            if (next != null) onChanged(next);
          },
        ),
      );

  Widget _dateButton(String label, {required VoidCallback onPressed}) =>
      OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.calendar_today_outlined, size: 16),
        label: Text(label),
      );

  Widget _transactionCard(Map<String, dynamic> row) {
    final Map<String, dynamic> customer = _map(row['customer']);
    final String status = _text(row['status']).toUpperCase();
    final String category = _text(row['category']);
    final Color statusColor = status == 'PENDING'
        ? const Color(0xFF9A5A10)
        : status == 'RESOLVED'
            ? _teal
            : const Color(0xFF9B4C42);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      elevation: 0,
      color: const Color(0xFFFFFEFC),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: _line),
        borderRadius: BorderRadius.circular(13),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => _openTransaction(row),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool narrow = constraints.maxWidth < 620;
              final Widget identity = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _text(customer['name'], fallback: 'Customer unavailable'),
                    style: const TextStyle(
                        color: _ink, fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_text(customer['phone'], fallback: 'No phone')}  ·  ${_text(customer['email'], fallback: 'No email')}',
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    '${_text(row['serviceType'], fallback: 'Service')} · ${_text(row['provider'], fallback: 'Provider unavailable')}',
                    style:
                        const TextStyle(color: Color(0xFF3C5B5C), fontSize: 12),
                  ),
                ],
              );
              final Widget financial = Column(
                crossAxisAlignment:
                    narrow ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: <Widget>[
                  Text(_money(row['amount']),
                      style: const TextStyle(
                          color: _ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  _tag(status, statusColor),
                ],
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        narrow
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  identity,
                                  const SizedBox(height: 12),
                                  financial,
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Expanded(flex: 5, child: identity),
                                  const SizedBox(width: 14),
                                  financial,
                                ],
                              ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 14,
                          runSpacing: 5,
                          children: <Widget>[
                            _metadata('Reference',
                                _text(row['reference'], fallback: '—')),
                            _metadata('ID', _text(row['id'], fallback: '—')),
                            _metadata('Created', _dateTime(row['createdAt'])),
                            _metadata(
                                'Age', _durationText(row['pendingSeconds'])),
                            _metadata('Bucket',
                                category.isEmpty ? '—' : _title(category)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  PopupMenuButton<String>(
                    tooltip: 'Transaction actions',
                    onSelected: (String action) {
                      if (action == 'resolve') {
                        _openTransaction(row);
                      } else {
                        _openTransaction(
                          row,
                          initialAction:
                              PendingResolutionAction.values.firstWhere(
                            (PendingResolutionAction value) =>
                                value.name == action,
                          ),
                        );
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'markSuccessful',
                        child: Text('Mark as Successful'),
                      ),
                      PopupMenuItem<String>(
                        value: 'refund',
                        child: Text('Refund Customer'),
                      ),
                      PopupMenuItem<String>(
                        value: 'retry',
                        child: Text('Retry Transaction'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'resolve',
                        child: Text('Resolve Transaction'),
                      ),
                    ],
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _metadata(String label, String value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('$label  ', style: const TextStyle(color: _muted, fontSize: 10)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _ink, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ],
      );

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w800)),
      );

  Widget _pagination() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Row(
          children: <Widget>[
            Text('Page $_page of $_pages',
                style: const TextStyle(color: _muted, fontSize: 12)),
            const Spacer(),
            IconButton(
              tooltip: 'Previous page',
              onPressed: _page > 1
                  ? () {
                      setState(() => _page--);
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              tooltip: 'Next page',
              onPressed: _page < _pages
                  ? () {
                      setState(() => _page++);
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      );

  Widget _loadingState() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            for (int i = 0; i < 3; i++)
              Container(
                height: 72,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5EEEA),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            const Text('Loading live transaction information…',
                style: TextStyle(color: _muted)),
          ],
        ),
      );

  Widget _rowsSkeleton() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          children: List<Widget>.generate(
            3,
            (_) => Container(
              height: 100,
              margin: const EdgeInsets.only(bottom: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFE5EEEA),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      );

  Widget _errorState() => Padding(
        padding: const EdgeInsets.all(24),
        child: _errorPanel(),
      );

  Widget _errorPanel() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1EC),
          border: Border.all(color: const Color(0xFFE8C7B8)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: <Widget>[
            const Icon(Icons.cloud_off_outlined,
                size: 30, color: Color(0xFF9B4C42)),
            const SizedBox(height: 8),
            const Text('Live data is unavailable',
                style: TextStyle(
                    color: _ink, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(
              _readError ?? 'The server did not return a valid response.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );

  Widget _inlineError() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        color: const Color(0xFFFFF1EC),
        child: Text(
          'Refresh failed: $_readError',
          style: const TextStyle(color: Color(0xFF8B443B), fontSize: 12),
        ),
      );

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFEFC),
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            children: <Widget>[
              const Icon(Icons.inbox_outlined, size: 34, color: _teal),
              const SizedBox(height: 9),
              const Text('No transactions match these filters',
                  style: TextStyle(
                      color: _ink, fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 5),
              const Text(
                'Try a wider date range or clear one or more filters. This view never invents missing transaction totals.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, height: 1.4),
              ),
            ],
          ),
        ),
      );
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _TransactionDetailDialog extends StatelessWidget {
  const _TransactionDetailDialog({
    required this.detail,
    required this.savedIntent,
    required this.onChooseAction,
  });

  final Map<String, dynamic> detail;
  final PendingResolutionIntent? savedIntent;
  final Future<void> Function(PendingResolutionAction) onChooseAction;

  Map<String, dynamic> get transaction => _map(detail['transaction']);
  Map<String, dynamic> get customer => _map(transaction['customer']);
  Map<String, dynamic> get refund => _map(detail['refund']);
  Map<String, dynamic> get success => _map(detail['success']);
  Map<String, dynamic> get retry => _map(detail['retry']);
  Map<String, dynamic> get permissions => _map(detail['permissions']);

  @override
  Widget build(BuildContext context) {
    final List<String> refundBlockers = _strings(refund['blockers']);
    final List<String> successBlockers = _strings(success['blockers']);
    final List<dynamic> history = detail['history'] is List
        ? detail['history'] as List<dynamic>
        : <dynamic>[];
    final bool canRefund = refund['eligible'] == true &&
        permissions['refund'] == true &&
        refundBlockers.isEmpty;
    final bool canSuccess = success['eligible'] == true &&
        permissions['success'] == true &&
        successBlockers.isEmpty;
    final bool canRetry =
        retry['eligible'] == true && permissions['retry'] == true;
    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 780),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text('Transaction investigation',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: _PendingResolutionScreenState._ink)),
                  ),
                  IconButton(
                    tooltip: 'Close details',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Divider(),
              Wrap(
                spacing: 22,
                runSpacing: 12,
                children: <Widget>[
                  _detailValue('Customer', _text(customer['name'])),
                  _detailValue('Phone', _text(customer['phone'])),
                  _detailValue('Email', _text(customer['email'])),
                  _detailValue('Reference', _text(transaction['reference'])),
                  _detailValue('Transaction ID', _text(transaction['id'])),
                  _detailValue('Service', _text(transaction['serviceType'])),
                  _detailValue('Provider', _text(transaction['provider'])),
                  _detailValue('Amount', _money(transaction['amount'])),
                  _detailValue('Status', _text(transaction['status'])),
                  _detailValue('Created', _dateTime(transaction['createdAt'])),
                  _detailValue(
                      'Age', _durationText(transaction['pendingSeconds'])),
                  _detailValue(
                      'Age bucket', _title(_text(transaction['category']))),
                ],
              ),
              if (savedIntent != null) ...<Widget>[
                const SizedBox(height: 14),
                _noticeBox(
                  'Unresolved saved request',
                  'A ${_actionLabel(savedIntent!.action).toLowerCase()} is preserved with its original details. Replay that exact request; do not create a replacement.',
                ),
              ],
              if (_text(refund['overrideWarning']).isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                _noticeBox(
                  'Refund override warning',
                  _text(refund['overrideWarning']),
                ),
              ],
              const SizedBox(height: 16),
              const Text('Available actions',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _actionButton(
                    context,
                    'Mark as Successful',
                    Icons.verified_outlined,
                    canSuccess,
                    _blockReason(
                      permission: permissions['success'] == true,
                      eligible: success['eligible'] == true,
                      blockers: successBlockers,
                      fallback:
                          'Requires explicit transaction reconciliation permission.',
                    ),
                    () =>
                        onChooseAction(PendingResolutionAction.markSuccessful),
                    isEnabledBySavedIntent(
                        savedIntent, PendingResolutionAction.markSuccessful),
                  ),
                  _actionButton(
                    context,
                    'Refund Customer',
                    Icons.currency_exchange_rounded,
                    canRefund,
                    _blockReason(
                      permission: permissions['refund'] == true,
                      eligible: refund['eligible'] == true,
                      blockers: refundBlockers,
                      fallback: _text(refund['overrideWarning']).isNotEmpty
                          ? _text(refund['overrideWarning'])
                          : 'Requires explicit transactions.refund permission and eligibility.',
                    ),
                    () => onChooseAction(PendingResolutionAction.refund),
                    isEnabledBySavedIntent(
                        savedIntent, PendingResolutionAction.refund),
                  ),
                  _actionButton(
                    context,
                    'Retry Transaction',
                    Icons.sync_rounded,
                    canRetry,
                    _text(retry['reason']).isNotEmpty
                        ? _text(retry['reason'])
                        : 'Rechecks existing provider status only; it never resends the purchase.',
                    () => onChooseAction(PendingResolutionAction.retry),
                    isEnabledBySavedIntent(
                        savedIntent, PendingResolutionAction.retry),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              const Text(
                'Resolve Transaction means choosing a verified manual success, an eligible refund, or a safe provider status recheck above.',
                style: TextStyle(
                    color: _PendingResolutionScreenState._muted, fontSize: 11),
              ),
              const SizedBox(height: 6),
              const Text(
                'Retry is a status query only. It does not submit a purchase or debit money.',
                style: TextStyle(
                    color: _PendingResolutionScreenState._muted, fontSize: 11),
              ),
              const SizedBox(height: 18),
              const Text('Resolution history',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (history.isEmpty)
                const Text('No manual resolution events are recorded.',
                    style:
                        TextStyle(color: _PendingResolutionScreenState._muted))
              else
                ...history.map((dynamic item) {
                  final Map<String, dynamic> event = _map(item);
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F7F5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                '${_title(_text(event['action']))} · ${_text(event['previousStatus'])} → ${_text(event['newStatus'])}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            Text(_dateTime(event['createdAt']),
                                style: const TextStyle(
                                    color: _PendingResolutionScreenState._muted,
                                    fontSize: 10)),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                            'Administrator: ${_text(event['administrator'], fallback: _text(event['administratorId'], fallback: 'Not supplied'))}'),
                        if (event['amountRefunded'] != null)
                          Text(
                              'Amount refunded: ${_money(event['amountRefunded'])}'),
                        if (_text(event['evidenceReference']).isNotEmpty)
                          Text(
                              'Evidence reference: ${_text(event['evidenceReference'])}'),
                        if (_text(event['reason']).isNotEmpty)
                          Text('Recorded reason: ${_text(event['reason'])}'),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  bool isEnabledBySavedIntent(
    PendingResolutionIntent? intent,
    PendingResolutionAction action,
  ) =>
      intent == null || intent.action == action;

  Widget _actionButton(
    BuildContext context,
    String label,
    IconData icon,
    bool eligible,
    String reason,
    VoidCallback onPressed,
    bool matchesSavedIntent,
  ) {
    final bool replay =
        savedIntent != null && _actionLabel(savedIntent!.action) == label;
    final bool enabled = replay || (eligible && matchesSavedIntent);
    final String disabledReason =
        !matchesSavedIntent ? 'Replay the saved request first.' : reason;
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Tooltip(
            message: enabled ? label : disabledReason,
            child: OutlinedButton.icon(
              onPressed: enabled ? onPressed : null,
              icon: Icon(icon, size: 17),
              label: Text(replay ? 'Replay saved request' : label),
            ),
          ),
          if (!enabled)
            Padding(
              padding: const EdgeInsets.only(left: 5, top: 3),
              child: Text(
                disabledReason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _PendingResolutionScreenState._muted,
                    fontSize: 10,
                    height: 1.2),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionDialog extends StatefulWidget {
  const _ActionDialog({
    required this.row,
    required this.action,
    required this.savedIntent,
    required this.actionWarning,
    required this.onSubmit,
  });
  final Map<String, dynamic> row;
  final PendingResolutionAction action;
  final PendingResolutionIntent? savedIntent;
  final String actionWarning;
  final Future<String?> Function({
    required String reason,
    required String evidence,
    required bool deliveryConfirmed,
    required bool riskAcknowledged,
  }) onSubmit;

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  late final TextEditingController _reason = TextEditingController(
    text: widget.savedIntent?.reason ?? '',
  );
  late final TextEditingController _evidence = TextEditingController(
    text: widget.savedIntent?.evidenceReference ?? '',
  );
  late bool _deliveryConfirmed = widget.savedIntent?.deliveryConfirmed ?? false;
  late bool _riskAcknowledged =
      widget.savedIntent?.providerRiskAcknowledged ?? false;
  bool _confirmed = false;
  bool _submitting = false;
  bool _attempted = false;
  String _error = '';

  @override
  void dispose() {
    _reason.dispose();
    _evidence.dispose();
    super.dispose();
  }

  bool get _locked => widget.savedIntent != null;

  Future<void> _submit() async {
    final String reason = _reason.text.trim();
    if (reason.length < 10 || reason.length > 500 || !_confirmed) {
      setState(() => _error =
          'Enter a 10–500 character reason and confirm that you intend this action.');
      return;
    }
    if (widget.action == PendingResolutionAction.markSuccessful &&
        (_evidence.text.trim().length < 6 ||
            _evidence.text.trim().length > 200 ||
            !_deliveryConfirmed)) {
      setState(() => _error =
          'Add an evidence reference of 6–200 characters and explicitly confirm delivery.');
      return;
    }
    if (widget.action == PendingResolutionAction.refund && !_riskAcknowledged) {
      setState(() => _error =
          'Acknowledge the possible financial loss before submitting a refund.');
      return;
    }
    setState(() {
      _submitting = true;
      _attempted = true;
      _error = '';
    });
    final String? failure = await widget.onSubmit(
      reason: reason,
      evidence: _evidence.text.trim(),
      deliveryConfirmed: _deliveryConfirmed,
      riskAcknowledged: _riskAcknowledged,
    );
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _submitting = false;
        _error = failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool refund = widget.action == PendingResolutionAction.refund;
    final bool success =
        widget.action == PendingResolutionAction.markSuccessful;
    final bool retry = widget.action == PendingResolutionAction.retry;
    final String heading = _actionLabel(widget.action);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(heading,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: _PendingResolutionScreenState._ink)),
                  ),
                  IconButton(
                    tooltip: 'Close action confirmation',
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                '${_text(_map(widget.row['customer'])['name'], fallback: 'Customer')} · ${_money(widget.row['amount'])} · ${_text(widget.row['reference'], fallback: _text(widget.row['id']))}',
                style: const TextStyle(
                    color: _PendingResolutionScreenState._muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              if (_locked)
                _noticeBox(
                  'Exact request replay',
                  'The original request details and idempotency key are saved. They cannot be changed. Retrying sends the exact same request.',
                )
              else if (retry)
                _noticeBox(
                  'Status query only',
                  'This rechecks the existing provider outcome. It never resends a purchase or debits the customer.',
                )
              else if (refund)
                _noticeBox(
                  'Financial-loss warning',
                  'Provider outcome is uncertain. Refunding when service was delivered can cause a financial loss. ServicePay determines the original debit; no amount is entered here.${widget.actionWarning.isNotEmpty ? '\n${widget.actionWarning}' : ''}',
                )
              else if (success)
                _noticeBox(
                  'Record only verified delivery',
                  'Mark success only when service delivery is confirmed by reviewable evidence. This records a manual resolution; it does not query or alter the provider.',
                ),
              const SizedBox(height: 13),
              TextField(
                controller: _reason,
                minLines: 3,
                maxLines: 5,
                maxLength: 500,
                readOnly: _locked || _attempted || _submitting,
                decoration: InputDecoration(
                  labelText: retry
                      ? 'Reason for status recheck'
                      : 'Investigation reason',
                  hintText: 'Record the checks and decision basis',
                  helperText: '10–500 characters',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (success) ...<Widget>[
                const SizedBox(height: 6),
                TextField(
                  controller: _evidence,
                  maxLength: 200,
                  readOnly: _locked || _attempted || _submitting,
                  decoration: const InputDecoration(
                    labelText: 'Delivery evidence reference',
                    hintText:
                        'Internal case, provider reference or evidence ID',
                    helperText:
                        '6–200 characters; do not paste private customer data',
                    border: OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _deliveryConfirmed,
                  onChanged: _locked || _attempted || _submitting
                      ? null
                      : (bool? value) =>
                          setState(() => _deliveryConfirmed = value == true),
                  title:
                      const Text('I verified that the service was delivered.'),
                  subtitle:
                      const Text('Evidence reference is required for audit.'),
                ),
              ],
              if (refund)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _riskAcknowledged,
                  onChanged: _locked || _attempted || _submitting
                      ? null
                      : (bool? value) =>
                          setState(() => _riskAcknowledged = value == true),
                  title: const Text(
                    'I acknowledge this refund may create financial loss if the service was delivered.',
                  ),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _confirmed,
                onChanged: _submitting
                    ? null
                    : (bool? value) =>
                        setState(() => _confirmed = value == true),
                title: Text(
                  retry
                      ? 'I confirm this status recheck.'
                      : refund
                          ? 'I confirm this refund is authorized for the original debit.'
                          : 'I confirm the manual success decision is supported by the cited evidence.',
                ),
              ),
              if (_error.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0EC),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(_error,
                      style: const TextStyle(color: Color(0xFF8B443B))),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.lock_outline_rounded),
                  label: Text(
                    _submitting
                        ? 'Submitting safely…'
                        : _locked
                            ? 'Replay saved request'
                            : 'Confirm $heading',
                  ),
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'If the response times out or the server is unavailable, keep this request and retry with the same details.',
                style: TextStyle(
                    color: _PendingResolutionScreenState._muted,
                    fontSize: 11,
                    height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _detailValue(String label, String value) => SizedBox(
      width: 205,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: const TextStyle(
                  color: _PendingResolutionScreenState._muted, fontSize: 11)),
          const SizedBox(height: 3),
          SelectableText(value.isEmpty ? 'Not supplied' : value,
              style: const TextStyle(
                  color: _PendingResolutionScreenState._ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );

Widget _noticeBox(String title, String message) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E8),
        border: Border.all(color: const Color(0xFFE9D5AC)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: const TextStyle(
                  color: Color(0xFF78511C), fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(message,
              style: const TextStyle(
                  color: Color(0xFF78511C), fontSize: 12, height: 1.4)),
        ],
      ),
    );

String _blockReason({
  required bool permission,
  required bool eligible,
  required List<String> blockers,
  required String fallback,
}) {
  if (!permission) {
    return 'Your account does not have the required action permission.';
  }
  if (blockers.isNotEmpty) {
    return blockers.join(' ');
  }
  if (!eligible) {
    return fallback;
  }
  return fallback;
}

String _actionLabel(PendingResolutionAction action) {
  switch (action) {
    case PendingResolutionAction.markSuccessful:
      return 'Mark as Successful';
    case PendingResolutionAction.refund:
      return 'Refund Customer';
    case PendingResolutionAction.retry:
      return 'Retry Transaction';
  }
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<String> _strings(dynamic value) => value is List
    ? value.map((dynamic item) => item.toString()).toList()
    : <String>[];

String _text(dynamic value, {String fallback = ''}) {
  final String result = value?.toString().trim() ?? '';
  return result.isEmpty || result.toLowerCase() == 'null' ? fallback : result;
}

String _message(Object error) {
  if (error is PendingResolutionApiException) return error.message;
  return error.toString().replaceFirst('Exception: ', '');
}

int _int(dynamic value, int fallback) {
  if (value is num) return value.round();
  return int.tryParse('$value') ?? fallback;
}

String _money(dynamic value) {
  final num? amount =
      value is num ? value : (value == null ? null : num.tryParse('$value'));
  if (amount == null || !amount.isFinite) return 'Not supplied';
  final String fixed = amount.toStringAsFixed(2);
  final List<String> parts = fixed.split('.');
  final String integer = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (Match match) => ',',
  );
  return '₦$integer.${parts.last}';
}

String _count(dynamic value) {
  final int? parsed = value is num
      ? (value.isFinite ? value.round() : null)
      : int.tryParse('$value');
  if (parsed == null) return 'Unavailable';
  return parsed.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (Match match) => ',',
      );
}

String _dateTime(dynamic value) {
  final DateTime? date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) {
    return 'Not supplied';
  }
  String twoDigit(int number) => number.toString().padLeft(2, '0');
  return '${date.year}-${twoDigit(date.month)}-${twoDigit(date.day)} ${twoDigit(date.hour)}:${twoDigit(date.minute)}';
}

String _durationText(dynamic value) {
  final int? parsed = value is num
      ? (value.isFinite ? value.round() : null)
      : int.tryParse('$value');
  if (parsed == null) return 'Not supplied';
  final int seconds = parsed.clamp(0, 1 << 31).toInt();
  if (seconds < 60) return '${seconds}s';
  final int minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

String? _isoDay(DateTime? value) {
  if (value == null) return null;
  final String month = value.month.toString().padLeft(2, '0');
  final String day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _title(String value) => value
    .replaceAll('_', ' ')
    .toLowerCase()
    .split(' ')
    .where((String part) => part.isNotEmpty)
    .map((String part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
