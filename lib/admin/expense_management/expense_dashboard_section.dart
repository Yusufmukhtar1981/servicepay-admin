import 'package:flutter/material.dart';

import 'expense_charts.dart';
import 'expense_common.dart';
import 'expense_filters.dart';
import 'expense_management_screen.dart';

class ExpenseDashboardSection extends StatefulWidget {
  const ExpenseDashboardSection({super.key, required this.ctx});
  final ExpenseModuleContext ctx;
  @override
  State<ExpenseDashboardSection> createState() => _ExpenseDashboardSectionState();
}

class _ExpenseDashboardSectionState extends State<ExpenseDashboardSection> {
  ExpenseFilters _filters = ExpenseFilters.thisMonth();
  Map<String, dynamic>? _summary;
  String? _error;
  bool _loading = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final int request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> data = await widget.ctx.api.summary(_filters.toQuery(includeSearch: false));
      if (!mounted || request != _request) return;
      setState(() {
        _summary = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _summary = null;
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ExpenseModuleContext ctx = widget.ctx;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      ExpenseFilterBar(
        value: _filters,
        categories: ctx.categories,
        vendors: ctx.vendors,
        showSearch: false,
        busy: _loading,
        onApply: (ExpenseFilters f) {
          setState(() => _filters = f);
          _load();
        },
      ),
      const SizedBox(height: 14),
      if (!ctx.workflowConfigured) ...<Widget>[
        ExpenseNotice(
          'No approval policy is configured. Expenses can be recorded but cannot be submitted for approval until a Head Office policy manager configures reviewers in Pending Approvals.',
          tone: 'warn',
        ),
        const SizedBox(height: 12),
      ],
      if (_loading)
        const ExpenseSkeleton(rows: 5)
      else if (_summary == null)
        ExpenseErrorState(message: 'Dashboard figures are unavailable. Nothing is estimated. ${_error ?? ''}', onRetry: _load)
      else
        _body(_summary!),
    ]);
  }

  Widget _body(Map<String, dynamic> s) {
    final Map<String, dynamic> totals = asMap(s['totals']);
    final Map<String, dynamic> period = asMap(s['period']);
    final String currency = text(s['currency'], fallback: 'NGN');
    final List<(String, String, String)> metrics = <(String, String, String)>[
      ('Total expenses', money(totals['totalMinor'], currency: currency), 'Approved + paid recorded company costs in period'),
      ('Monthly expenses', money(totals['monthlyMinor'], currency: currency), 'Current Lagos calendar month'),
      ('Yearly expenses', money(totals['yearlyMinor'], currency: currency), 'Current Lagos calendar year'),
      ('Pending approvals', money(totals['pendingMinor'], currency: currency), '${count(totals['pendingCount'])} awaiting review; not costs yet'),
      ('Approved expenses', money(totals['approvedMinor'], currency: currency), '${count(totals['approvedCount'])} approved, not yet recorded paid'),
      ('Rejected expenses', count(totals['rejectedCount']), 'Requests rejected in period'),
      ('Paid (recorded)', money(totals['paidMinor'], currency: currency), '${count(totals['paidCount'])} manually recorded; not bank-verified'),
      ('Reversed', money(totals['reversedMinor'], currency: currency), 'Recorded external returns'),
      ('Cancelled', money(totals['cancelledMinor'], currency: currency), 'Withdrawn requests'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      ExpenseNotice(
        'Period ${text(period['from'], fallback: ymd(_filters.from))} to ${text(period['to'], fallback: ymd(_filters.to))} (Africa/Lagos), $currency. '
        'Total Expenses counts approved and paid company operating costs only. It excludes customer funds, pending requests and is not proof of bank settlement.'
        '${text(s['coverageNote']).isEmpty ? '' : '\n${text(s['coverageNote'])}'}',
      ),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final int cols = c.maxWidth >= 1000 ? 3 : c.maxWidth >= 560 ? 2 : 1;
        final double w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
          for (final (String, String, String) m in metrics) SizedBox(width: w, child: _metric(m.$1, m.$2, m.$3)),
        ]);
      }),
      const SizedBox(height: 14),
      ExpensePanel(
        title: 'Daily recorded expenses',
        subtitle: 'Amount per expense date in NGN, from server values only',
        child: ExpenseDailyChart(points: asList(s['daily'])),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final bool two = c.maxWidth >= 900;
        final List<Widget> panels = <Widget>[
          ExpensePanel(title: 'By category', child: ExpenseBreakdownChart(rows: asList(s['byCategory']), emptyLabel: 'No category totals for this period.')),
          ExpensePanel(title: 'By department', child: ExpenseBreakdownChart(rows: asList(s['byDepartment']), emptyLabel: 'No department totals for this period.')),
          ExpensePanel(title: 'By vendor', child: ExpenseBreakdownChart(rows: asList(s['byVendor']), emptyLabel: 'No vendor totals for this period.')),
        ];
        if (!two) {
          return Column(children: <Widget>[for (final Widget p in panels) Padding(padding: const EdgeInsets.only(bottom: 12), child: p)]);
        }
        return Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
          for (final Widget p in panels) SizedBox(width: (c.maxWidth - 12) / 2, child: p),
        ]);
      }),
    ]);
  }

  Widget _metric(String label, String value, String note) => Container(
        key: Key('expense-metric-${label.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '-')}'),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: expCard, border: Border.all(color: expLine), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(label.toUpperCase(), style: const TextStyle(color: Color(0xff687b73), fontSize: 10, letterSpacing: 0.8, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SelectableText(value,
              style: TextStyle(
                  color: value == 'Unavailable' ? expAmber : expInk,
                  fontSize: value == 'Unavailable' ? 13 : 19,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
          const SizedBox(height: 4),
          Text(note, style: const TextStyle(color: Color(0xff75867f), fontSize: 11, height: 1.25)),
        ]),
      );
}
