import 'package:flutter/material.dart';

import 'expense_common.dart';
import 'expense_filters.dart';
import 'expense_legacy_section.dart';
import 'expense_management_screen.dart';

export 'expense_detail_view.dart';

/// Paged expense list used by All Expenses and Pending Approvals.
class ExpenseListSection extends StatefulWidget {
  const ExpenseListSection({super.key, required this.ctx, this.fixedStatus, this.showFilters = true});
  final ExpenseModuleContext ctx;
  final String? fixedStatus;
  final bool showFilters;
  @override
  State<ExpenseListSection> createState() => _ExpenseListSectionState();
}

class _ExpenseListSectionState extends State<ExpenseListSection> {
  late ExpenseFilters _filters = widget.fixedStatus == null
      ? ExpenseFilters.thisMonth()
      : ExpenseFilters(from: DateTime(lagosToday().year - 1, lagosToday().month, lagosToday().day), to: lagosToday(), status: widget.fixedStatus!);
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  int _page = 1;
  static const int _pageSize = 25;
  int _request = 0;
  bool _legacy = false;

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
      final Map<String, dynamic> data = await widget.ctx.api.listExpenses(<String, String>{
        ..._filters.toQuery(),
        if (widget.fixedStatus != null) 'status': widget.fixedStatus!,
        'page': '$_page',
        'pageSize': '$_pageSize',
      });
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ExpenseModuleContext ctx = widget.ctx;
    final List<Map<String, dynamic>> items = asList(_data?['items']).map(asMap).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      if (widget.showFilters) ...<Widget>[
        ExpenseFilterBar(
          value: _filters,
          categories: ctx.categories,
          vendors: ctx.vendors,
          showStatus: widget.fixedStatus == null,
          busy: _loading,
          onApply: (ExpenseFilters f) {
            setState(() {
              _filters = f;
              _page = 1;
            });
            _load();
          },
        ),
        const SizedBox(height: 12),
      ],
      if (widget.fixedStatus == null) ...<Widget>[
        Wrap(spacing: 6, children: <Widget>[
          ChoiceChip(key: const Key('records-current'), label: const Text('Expense records'), selected: !_legacy,
              onSelected: (_) => setState(() => _legacy = false)),
          ChoiceChip(key: const Key('records-historical'), label: const Text('Historical records (read-only)'), selected: _legacy,
              onSelected: (_) => setState(() => _legacy = true)),
        ]),
        const SizedBox(height: 10),
      ],
      if (_legacy)
        ExpenseLegacySection(ctx: ctx, from: _filters.from, to: _filters.to)
      else ...<Widget>[
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
        Text(_data == null ? '' : '${count(_data!['total'])} expense${asInt(_data!['total']) == 1 ? '' : 's'} · ${text(_data!['currency'], fallback: 'NGN')}',
            style: const TextStyle(color: expMuted, fontWeight: FontWeight.w700)),
        OutlinedButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 17), label: const Text('Reload')),
        if (ctx.access.has(ExpensePermissions.create) && widget.fixedStatus == null)
          FilledButton.icon(
            onPressed: () => ctx.goTo('new'),
            style: FilledButton.styleFrom(backgroundColor: expGreen),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add new expense'),
          ),
      ]),
      const SizedBox(height: 10),
      if (_loading && _data == null)
        const ExpenseSkeleton()
      else if (_error != null)
        ExpenseErrorState(message: _error!, onRetry: _load)
      else if (items.isEmpty)
        ExpenseEmptyState(
          title: widget.fixedStatus == null ? 'No expenses in this range' : 'Nothing awaiting approval',
          message: widget.fixedStatus == null
              ? 'Adjust the dates or filters. Earlier records from before this module remain in the Financial Control Center.'
              : 'Expenses submitted for approval within the last year appear here.',
        )
      else
        LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
          if (c.maxWidth < 760) {
            return Column(children: items.map(_card).toList());
          }
          return ExpenseTable(
            headers: const <String>['Date', 'Title', 'Category', 'Payee', 'Amount', 'Status', 'Reference'],
            onTap: (int i) => ctx.openExpense(text(items[i]['id'])),
            rows: items
                .map((Map<String, dynamic> e) => <Widget>[
                      Text(text(e['expenseDate'])),
                      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240), child: Text(text(e['title']), overflow: TextOverflow.ellipsis)),
                      Text(text(e['categoryName'])),
                      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(text(e['vendorName'], fallback: text(e['beneficiary'])), overflow: TextOverflow.ellipsis)),
                      Text(money(e['amountMinor']), style: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()], fontWeight: FontWeight.w700)),
                      ExpenseStatusChip(text(e['status'])),
                      Text(text(e['reference'])),
                    ])
                .toList(),
          );
        }),
      if (_data != null && items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
            OutlinedButton(
              onPressed: _loading || _page <= 1 ? null : () {
                setState(() => _page--);
                _load();
              },
              child: const Text('Previous page'),
            ),
            Text('Page $_page'),
            OutlinedButton(
              onPressed: _loading || _data!['hasMore'] != true ? null : () {
                setState(() => _page++);
                _load();
              },
              child: const Text('Next page'),
            ),
          ]),
        ),
      ],
    ]);
  }

  Widget _card(Map<String, dynamic> e) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: expCard,
        elevation: 0,
        shape: RoundedRectangleBorder(side: const BorderSide(color: expLine), borderRadius: BorderRadius.circular(8)),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.ctx.openExpense(text(e['id'])),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Expanded(child: Text(text(e['title']), style: const TextStyle(fontWeight: FontWeight.w800, color: expInk))),
                const SizedBox(width: 8),
                ExpenseStatusChip(text(e['status'])),
              ]),
              const SizedBox(height: 6),
              Text(money(e['amountMinor']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: expInk)),
              const SizedBox(height: 4),
              Text('${text(e['expenseDate'])} · ${text(e['categoryName'])} · ${text(e['vendorName'], fallback: text(e['beneficiary']))}',
                  style: const TextStyle(color: expMuted, fontSize: 12)),
              Text('Ref ${text(e['reference'])}', style: const TextStyle(color: expMuted, fontSize: 12)),
            ]),
          ),
        ),
      );
}
