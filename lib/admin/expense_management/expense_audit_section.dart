import 'dart:convert';

import 'package:flutter/material.dart';

import 'expense_common.dart';
import 'expense_management_screen.dart';

/// Global immutable audit log with date range and paging.
class ExpenseAuditSection extends StatefulWidget {
  const ExpenseAuditSection({super.key, required this.ctx});
  final ExpenseModuleContext ctx;
  @override
  State<ExpenseAuditSection> createState() => _ExpenseAuditSectionState();
}

class _ExpenseAuditSectionState extends State<ExpenseAuditSection> {
  late DateTime _from = DateTime(lagosToday().year, lagosToday().month);
  late DateTime _to = lagosToday();

  Future<void> _pick() async {
    final DateTimeRange? r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: lagosToday(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (r != null && mounted) {
      setState(() {
        _from = r.start;
        _to = r.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
          OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.date_range_outlined, size: 17), label: Text('${ymd(_from)} to ${ymd(_to)}')),
          const Text('Hash-chained, append-only records. Nothing here can be edited or deleted.', style: TextStyle(color: expMuted, fontSize: 12)),
        ]),
        const SizedBox(height: 12),
        ExpenseAuditList(key: ValueKey<String>('${ymd(_from)}-${ymd(_to)}'), ctx: widget.ctx, from: _from, to: _to),
      ]);
}

/// Audit rows for one expense ([expenseId]) or globally (date range).
class ExpenseAuditList extends StatefulWidget {
  const ExpenseAuditList({super.key, required this.ctx, this.expenseId, this.from, this.to});
  final ExpenseModuleContext ctx;
  final String? expenseId;
  final DateTime? from;
  final DateTime? to;
  @override
  State<ExpenseAuditList> createState() => _ExpenseAuditListState();
}

class _ExpenseAuditListState extends State<ExpenseAuditList> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  int _page = 1;
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
      final Map<String, dynamic> data = widget.expenseId != null
          ? await widget.ctx.api.expenseAudit(widget.expenseId!, page: _page)
          : await widget.ctx.api.audit(<String, String>{
              'page': '$_page',
              'pageSize': '50',
              if (widget.from != null) 'from': ymd(widget.from!),
              if (widget.to != null) 'to': ymd(widget.to!),
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

  Set<String> _documentIds(dynamic value) {
    final Set<String> out = <String>{};
    void walk(dynamic v, String key) {
      if (v is Map) {
        v.forEach((dynamic k, dynamic x) => walk(x, '$k'));
      } else if (v is List) {
        for (final dynamic x in v) {
          walk(x, key);
        }
      } else if (v is String && (key == 'documentIds' || key == 'evidenceDocumentIds') && RegExp(r'^[a-f\d]{24}$', caseSensitive: false).hasMatch(v)) {
        out.add(v);
      }
    }

    walk(value, '');
    return out;
  }

  Future<void> _download(String id) async {
    try {
      final String name = await widget.ctx.api.downloadDocument(id, fallbackName: 'expense-document-$id');
      if (mounted) showExpenseMessage(context, 'Downloaded $name.');
    } catch (e) {
      if (mounted) showExpenseMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const ExpenseSkeleton(rows: 3);
    if (_error != null) return ExpenseErrorState(message: _error!, onRetry: _load);
    final List<Map<String, dynamic>> rows = asList(_data?['items']).map(asMap).toList();
    final int total = asInt(_data?['total']) ?? rows.length;
    final int pageSize = asInt(_data?['pageSize']) ?? 50;
    if (rows.isEmpty) {
      return const ExpenseEmptyState(icon: Icons.history_edu_outlined, title: 'No audit events', message: 'No recorded events match this scope.');
    }
    final bool canDownload = widget.ctx.access.has(ExpensePermissions.documents);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text('${count(total)} event${total == 1 ? '' : 's'}', style: const TextStyle(color: expMuted, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      for (final Map<String, dynamic> r in rows)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: expCard, border: Border.all(color: expLine), borderRadius: BorderRadius.circular(8)),
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text('${text(r['action'])} · ${text(r['subjectType'])}', style: const TextStyle(fontWeight: FontWeight.w800, color: expInk, fontSize: 13)),
            subtitle: Text(
              '${timestamp(r['at'])} · ${text(r['actorName'], fallback: text(r['actorId']))} (${text(r['actorRole'], fallback: 'role unknown')})\nReason: ${text(r['reason'], fallback: '—')}',
              style: const TextStyle(fontSize: 12, color: expMuted),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SelectableText(
                'Subject ${text(r['subjectId'])} · version ${text(r['version'], fallback: '—')}\nEvent hash ${text(r['eventHash'])}\nPrevious hash ${text(r['previousHash'])}',
                style: const TextStyle(fontSize: 11, color: expMuted, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
                final bool side = c.maxWidth >= 720;
                final Widget before = _json('Previous values', r['before']);
                final Widget after = _json('New values', r['after']);
                return side
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Expanded(child: before), const SizedBox(width: 10), Expanded(child: after)])
                    : Column(children: <Widget>[before, const SizedBox(height: 8), after]);
              }),
              ...() {
                final Set<String> ids = <String>{..._documentIds(r['before']), ..._documentIds(r['after'])};
                if (ids.isEmpty) return <Widget>[];
                return <Widget>[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: ids
                      .map((String id) => canDownload
                          ? ActionChip(avatar: const Icon(Icons.download_outlined, size: 16), label: Text('Document ${id.substring(id.length - 6)}'), onPressed: () => _download(id))
                          : Chip(label: Text('Document ${id.substring(id.length - 6)} (requires expenses.documents)')))
                      .toList()),
                ];
              }(),
            ],
          ),
        ),
      if (total > pageSize)
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
          OutlinedButton(onPressed: _page <= 1 || _loading ? null : () {
            setState(() => _page--);
            _load();
          }, child: const Text('Previous')),
          Text('Page $_page of ${(total / pageSize).ceil()}'),
          OutlinedButton(onPressed: _page * pageSize >= total || _loading ? null : () {
            setState(() => _page++);
            _load();
          }, child: const Text('Next')),
        ]),
    ]);
  }

  Widget _json(String label, dynamic value) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 280),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: expSoft, borderRadius: BorderRadius.circular(6)),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xff687b73))),
            const SizedBox(height: 4),
            SelectableText(
              value == null ? 'None' : const JsonEncoder.withIndent('  ').convert(value),
              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', height: 1.35, color: expInk),
            ),
          ]),
        ),
      );
}
