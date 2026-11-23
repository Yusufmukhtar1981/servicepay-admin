import 'package:flutter/material.dart';

import 'expense_common.dart';

/// Immutable filter state. Query keys match the backend contract exactly so
/// dashboard, list and report exports stay consistent.
class ExpenseFilters {
  const ExpenseFilters({
    required this.from,
    required this.to,
    this.status = '',
    this.categoryId = '',
    this.vendorId = '',
    this.department = '',
    this.branch = '',
    this.search = '',
  });

  factory ExpenseFilters.thisMonth() {
    final DateTime t = lagosToday();
    return ExpenseFilters(from: DateTime(t.year, t.month), to: t);
  }

  final DateTime from;
  final DateTime to;
  final String status;
  final String categoryId;
  final String vendorId;
  final String department;
  final String branch;
  final String search;

  ExpenseFilters copyWith({
    DateTime? from,
    DateTime? to,
    String? status,
    String? categoryId,
    String? vendorId,
    String? department,
    String? branch,
    String? search,
  }) =>
      ExpenseFilters(
        from: from ?? this.from,
        to: to ?? this.to,
        status: status ?? this.status,
        categoryId: categoryId ?? this.categoryId,
        vendorId: vendorId ?? this.vendorId,
        department: department ?? this.department,
        branch: branch ?? this.branch,
        search: search ?? this.search,
      );

  Map<String, String> toQuery({bool includeSearch = true, bool includeStatus = true}) => <String, String>{
        'from': ymd(from),
        'to': ymd(to),
        if (includeStatus && status.isNotEmpty) 'status': status,
        if (categoryId.isNotEmpty) 'categoryId': categoryId,
        if (vendorId.isNotEmpty) 'vendorId': vendorId,
        if (department.trim().isNotEmpty) 'department': department.trim(),
        if (branch.trim().isNotEmpty) 'branch': branch.trim(),
        if (includeSearch && search.trim().isNotEmpty) 'search': search.trim(),
      };
}

/// Filter panel. Applying text filters never resets the date range.
class ExpenseFilterBar extends StatefulWidget {
  const ExpenseFilterBar({
    super.key,
    required this.value,
    required this.onApply,
    required this.categories,
    required this.vendors,
    this.showStatus = true,
    this.showSearch = true,
    this.busy = false,
  });
  final ExpenseFilters value;
  final ValueChanged<ExpenseFilters> onApply;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> vendors;
  final bool showStatus;
  final bool showSearch;
  final bool busy;

  @override
  State<ExpenseFilterBar> createState() => _ExpenseFilterBarState();
}

class _ExpenseFilterBarState extends State<ExpenseFilterBar> {
  late final TextEditingController _dept = TextEditingController(text: widget.value.department);
  late final TextEditingController _branch = TextEditingController(text: widget.value.branch);
  late final TextEditingController _search = TextEditingController(text: widget.value.search);
  late DateTime _from = widget.value.from;
  late DateTime _to = widget.value.to;
  late String _status = widget.value.status;
  late String _category = widget.value.categoryId;
  late String _vendor = widget.value.vendorId;

  @override
  void dispose() {
    _dept.dispose();
    _branch.dispose();
    _search.dispose();
    super.dispose();
  }

  void _apply() => widget.onApply(ExpenseFilters(
        from: _from,
        to: _to,
        status: _status,
        categoryId: _category,
        vendorId: _vendor,
        department: _dept.text,
        branch: _branch.text,
        search: _search.text,
      ));

  void _preset(String key) {
    final DateTime t = lagosToday();
    setState(() {
      switch (key) {
        case 'today':
          _from = t;
          _to = t;
        case 'last7':
          _from = t.subtract(const Duration(days: 6));
          _to = t;
        case 'month':
          _from = DateTime(t.year, t.month);
          _to = t;
        case 'lastMonth':
          _from = DateTime(t.year, t.month - 1);
          _to = DateTime(t.year, t.month, 0);
        case 'year':
          _from = DateTime(t.year);
          _to = t;
      }
    });
    _apply();
  }

  Future<void> _pickRange() async {
    final DateTime t = lagosToday();
    final DateTimeRange? r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: t,
      initialDateRange: DateTimeRange(start: _from, end: _to.isAfter(t) ? t : _to),
      helpText: 'SELECT EXPENSE DATE RANGE',
    );
    if (r == null || !mounted) return;
    setState(() {
      _from = r.start;
      _to = r.end;
    });
    _apply();
  }

  DropdownMenuItem<String> _registryItem(Map<String, dynamic> r) => DropdownMenuItem<String>(
        value: text(r['id']),
        child: Text('${text(r['name'], fallback: text(r['id']))}${r['active'] == false ? ' (inactive)' : ''}',
            overflow: TextOverflow.ellipsis),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: expSoft, border: Border.all(color: expLine), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
          for (final MapEntry<String, String> p in const <String, String>{
            'today': 'Today',
            'last7': 'Last 7 days',
            'month': 'This month',
            'lastMonth': 'Last month',
            'year': 'This year',
          }.entries)
            ActionChip(label: Text(p.value), visualDensity: VisualDensity.compact, onPressed: widget.busy ? null : () => _preset(p.key)),
          OutlinedButton.icon(
            key: const Key('filter-date-range'),
            onPressed: widget.busy ? null : _pickRange,
            icon: const Icon(Icons.date_range_outlined, size: 17),
            label: Text('${ymd(_from)} to ${ymd(_to)}'),
          ),
        ]),
        const SizedBox(height: 11),
        LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
          final double w = c.maxWidth < 620 ? c.maxWidth : (c.maxWidth - 18) / 3;
          final List<Map<String, dynamic>> cats = widget.categories;
          final List<Map<String, dynamic>> vens = widget.vendors;
          return Wrap(spacing: 9, runSpacing: 9, children: <Widget>[
            if (widget.showSearch)
              SizedBox(
                width: w,
                child: TextField(
                  controller: _search,
                  onSubmitted: (_) => _apply(),
                  decoration: expInput('Search', hint: 'Title, reference, beneficiary'),
                ),
              ),
            if (widget.showStatus)
              SizedBox(
                width: w,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _status,
                  decoration: expInput('Status'),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(value: '', child: Text('All statuses')),
                    for (final MapEntry<String, String> s in statusLabels.entries)
                      DropdownMenuItem<String>(value: s.key, child: Text(s.value)),
                  ],
                  onChanged: (String? v) => setState(() => _status = v ?? ''),
                ),
              ),
            SizedBox(
              width: w,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: cats.any((Map<String, dynamic> r) => text(r['id']) == _category) ? _category : '',
                decoration: expInput('Category'),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(value: '', child: Text('All categories')),
                  ...cats.map(_registryItem),
                ],
                onChanged: (String? v) => setState(() => _category = v ?? ''),
              ),
            ),
            SizedBox(
              width: w,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: vens.any((Map<String, dynamic> r) => text(r['id']) == _vendor) ? _vendor : '',
                decoration: expInput('Vendor'),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(value: '', child: Text('All vendors')),
                  ...vens.map(_registryItem),
                ],
                onChanged: (String? v) => setState(() => _vendor = v ?? ''),
              ),
            ),
            SizedBox(width: w, child: TextField(controller: _dept, onSubmitted: (_) => _apply(), decoration: expInput('Department'))),
            SizedBox(width: w, child: TextField(controller: _branch, onSubmitted: (_) => _apply(), decoration: expInput('Branch'))),
          ]);
        }),
        const SizedBox(height: 9),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('filter-apply'),
            onPressed: widget.busy ? null : _apply,
            style: FilledButton.styleFrom(backgroundColor: expGreen),
            icon: const Icon(Icons.filter_alt_outlined, size: 17),
            label: const Text('Apply filters'),
          ),
        ),
      ]),
    );
  }
}
