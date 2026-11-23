import 'package:flutter/material.dart';

import 'expense_common.dart';
import 'expense_documents.dart';
import 'expense_management_screen.dart';

/// Formats an original NGN numeric amount (legacy records are not in kobo).
String legacyNaira(dynamic amount) {
  if (amount is! num || !amount.isFinite) return 'Unavailable';
  final int minor = (amount * 100).round();
  return money(minor);
}

/// Read-only view of immutable Financial Control expense records. These are
/// shown as LEGACY_RECORDED only; no approval or payment status is implied.
class ExpenseLegacySection extends StatefulWidget {
  const ExpenseLegacySection({super.key, required this.ctx, required this.from, required this.to});
  final ExpenseModuleContext ctx;
  final DateTime from;
  final DateTime to;
  @override
  State<ExpenseLegacySection> createState() => _ExpenseLegacySectionState();
}

class _ExpenseLegacySectionState extends State<ExpenseLegacySection> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ExpenseLegacySection old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to) _load();
  }

  Future<void> _load() async {
    final int request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> data = await widget.ctx.api.legacyExpenses(from: ymd(widget.from), to: ymd(widget.to));
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _data = null;
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _download(Map<String, dynamic> r) async {
    try {
      final String name = await widget.ctx.api.downloadLegacyDocument(text(r['id']),
          fallbackName: text(asMap(r['supportingDocument'])['name'], fallback: 'legacy-receipt'));
      if (mounted) showExpenseMessage(context, 'Downloaded $name.');
    } catch (e) {
      if (mounted) showExpenseMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canDownload = widget.ctx.access.has(ExpensePermissions.documents);
    final List<Map<String, dynamic>> items = asList(_data?['items']).map(asMap).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      const ExpenseNotice(
        'Historical records from the Financial Control Center. They are immutable, were recorded before approval workflow existed, '
        'and carry no approval or payment status. Their totals are kept separate from new expense totals.',
        tone: 'warn',
      ),
      const SizedBox(height: 10),
      if (_loading && _data == null)
        const ExpenseSkeleton()
      else if (_error != null)
        ExpenseErrorState(message: _error!, onRetry: _load)
      else ...<Widget>[
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
          Text('Legacy total recorded: ${legacyNaira(_data?['totalRecorded'])}',
              key: const Key('legacy-total'), style: const TextStyle(color: expInk, fontWeight: FontWeight.w800)),
          if (text(_data?['status']).isNotEmpty) Text('Source status: ${text(_data?['status'])}', style: const TextStyle(color: expMuted, fontSize: 12)),
          OutlinedButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 17), label: const Text('Reload')),
        ]),
        if (_data?['coverage'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SelectableText('Coverage: ${_data!['coverage'] is Map ? asMap(_data!['coverage']).entries.map((MapEntry<String, dynamic> e) => '${e.key}: ${e.value}').join(', ') : text(_data!['coverage'])}',
                style: const TextStyle(color: expMuted, fontSize: 12)),
          ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          const ExpenseEmptyState(icon: Icons.inventory_2_outlined, title: 'No historical records', message: 'No legacy expenses were recorded in this date range.')
        else
          for (final Map<String, dynamic> r in items) _row(r, canDownload),
      ],
    ]);
  }

  Widget _row(Map<String, dynamic> r, bool canDownload) {
    final Map<String, dynamic> doc = asMap(r['supportingDocument']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: expCard, border: Border.all(color: expLine), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
          Text(legacyNaira(r['amount']), style: const TextStyle(color: expInk, fontWeight: FontWeight.w800, fontSize: 15)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xffeceeed), borderRadius: BorderRadius.circular(5)),
            child: const Text('LEGACY_RECORDED', style: TextStyle(color: Color(0xff56625d), fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 4),
        SelectableText(
          '${text(r['date'], fallback: '—')} · ${text(r['category'], fallback: 'Uncategorised')} · Ref ${text(r['reference'], fallback: '—')}\n'
          'Recorded by ${text(r['recordedBy'], fallback: 'unknown')}'
          '${text(r['description']).isEmpty ? '' : '\n${text(r['description'])}'}',
          style: const TextStyle(color: expMuted, fontSize: 12, height: 1.4),
        ),
        if (doc.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: canDownload
                ? OutlinedButton.icon(
                    key: Key('legacy-download-${text(r['id'])}'),
                    onPressed: () => _download(r),
                    icon: const Icon(Icons.download_outlined, size: 17),
                    label: Text('Download ${text(doc['name'], fallback: 'receipt')} (${fileSize(doc['size'])})', overflow: TextOverflow.ellipsis),
                  )
                : Text('Receipt on file: ${text(doc['name'])}. Download requires expenses.documents.',
                    style: const TextStyle(color: expMuted, fontSize: 12)),
          ),
      ]),
    );
  }
}
