import 'package:flutter/material.dart';

import 'expense_api.dart';
import 'expense_common.dart';
import 'expense_management_screen.dart';

/// Categories or vendors registry. Records are deactivated, never deleted.
class ExpenseCatalogSection extends StatefulWidget {
  const ExpenseCatalogSection({super.key, required this.ctx, required this.kind});
  final ExpenseModuleContext ctx;
  final String kind; // categories | vendors
  @override
  State<ExpenseCatalogSection> createState() => _ExpenseCatalogSectionState();
}

class _ExpenseCatalogSectionState extends State<ExpenseCatalogSection> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  // Retained per operation until a definitive result.
  final Map<String, String> _keys = <String, String>{};
  int _request = 0;

  bool get _vendors => widget.kind == 'vendors';
  String get _noun => _vendors ? 'vendor' : 'category';
  bool get _canManage => widget.ctx.access.has(_vendors ? ExpensePermissions.vendors : ExpensePermissions.categories);

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
      final Map<String, dynamic> data = _vendors ? await widget.ctx.api.vendors() : await widget.ctx.api.categories();
      if (!mounted || request != _request) return;
      setState(() {
        _items = asList(data['items']).map(asMap).toList();
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

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final _CatalogResult? result = await showDialog<_CatalogResult>(
      context: context,
      builder: (BuildContext context) => _CatalogDialog(vendor: _vendors, item: item),
    );
    if (result == null || !mounted) return;
    final String opId = item == null ? 'create' : 'edit-${text(item['id'])}';
    await _write(opId, (String key) => item == null
        ? widget.ctx.api.createCatalogItem(widget.kind, <String, dynamic>{...result.fields, 'reason': result.reason}, key)
        : widget.ctx.api.updateCatalogItem(widget.kind, text(item['id']),
            expectedVersion: asInt(item['revision']) ?? 0, fields: result.fields, reason: result.reason, idempotencyKey: key));
  }

  Future<void> _toggle(Map<String, dynamic> item) async {
    final bool active = item['active'] != false;
    final String? reason = await askReason(context,
        title: active ? 'Deactivate $_noun' : 'Reactivate $_noun',
        message: active
            ? 'It will no longer be selectable for new expenses. Existing expenses keep their recorded name and history.'
            : 'It becomes selectable again for new expenses.',
        confirmLabel: active ? 'Deactivate' : 'Reactivate',
        destructive: active);
    if (reason == null || !mounted) return;
    await _write('toggle-${text(item['id'])}', (String key) => widget.ctx.api.updateCatalogItem(widget.kind, text(item['id']),
        expectedVersion: asInt(item['revision']) ?? 0, fields: <String, dynamic>{'active': !active}, reason: reason, idempotencyKey: key));
  }

  Future<void> _write(String opId, Future<Map<String, dynamic>> Function(String key) run) async {
    final String key = _keys[opId] ??= ExpenseIdempotency.newKey('reg');
    setState(() => _busy = true);
    try {
      await run(key);
      _keys.remove(opId);
      if (!mounted) return;
      showExpenseMessage(context, 'Saved. The change is recorded in the audit log.');
      await _load();
      await widget.ctx.reloadReferences();
    } catch (e) {
      final ExpenseApiException? ex = e is ExpenseApiException ? e : null;
      if (ex == null || !ex.outcomeUnknown) _keys.remove(opId);
      if (!mounted) return;
      showExpenseMessage(context, errorText(e), error: true);
      if (ex != null && ex.isConflict) await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> items = _items ?? <Map<String, dynamic>>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
        if (_canManage)
          FilledButton.icon(
            key: Key('catalog-add-${widget.kind}'),
            onPressed: _busy ? null : () => _edit(),
            style: FilledButton.styleFrom(backgroundColor: expGreen),
            icon: const Icon(Icons.add, size: 18),
            label: Text('Add $_noun'),
          ),
        OutlinedButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 17), label: const Text('Reload')),
      ]),
      if (!_canManage)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ExpenseNotice('Read-only. Changes require ${_vendors ? ExpensePermissions.vendors : ExpensePermissions.categories}.'),
        ),
      if (_keys.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: ExpenseNotice('A previous change has an unknown outcome. Reload to check before trying again; repeating the same change reuses its operation key.', tone: 'warn'),
        ),
      const SizedBox(height: 12),
      if (_loading && _items == null)
        const ExpenseSkeleton()
      else if (_error != null)
        ExpenseErrorState(message: _error!, onRetry: _load)
      else if (items.isEmpty)
        ExpenseEmptyState(
          icon: _vendors ? Icons.storefront_outlined : Icons.category_outlined,
          title: 'No ${_vendors ? 'vendors' : 'categories'} yet',
          message: _canManage ? 'Add the first $_noun used by your finance team.' : 'A finance manager has not created any yet.',
        )
      else
        ...items.map((Map<String, dynamic> r) {
          final bool active = r['active'] != false;
          final List<String> contact = <String>[
            text(r['contactName']),
            text(r['email']),
            text(r['phone']),
            text(r['address']),
          ].where((String s) => s.isNotEmpty).toList();
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: active ? expCard : const Color(0xfff1f3f2), border: Border.all(color: expLine), borderRadius: BorderRadius.circular(8)),
            child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 8, children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
                    Text(text(r['name']), style: const TextStyle(fontWeight: FontWeight.w800, color: expInk)),
                    Text(active ? 'Active' : 'Inactive', style: TextStyle(color: active ? expGreen : expMuted, fontSize: 11, fontWeight: FontWeight.w800)),
                    Text('rev ${text(r['revision'], fallback: '0')}', style: const TextStyle(color: expMuted, fontSize: 11)),
                  ]),
                  if (text(r['description']).isNotEmpty) Text(text(r['description']), style: const TextStyle(color: expMuted, fontSize: 12)),
                  if (contact.isNotEmpty) SelectableText(contact.join(' · '), style: const TextStyle(color: expMuted, fontSize: 12)),
                ]),
              ),
              if (_canManage)
                Wrap(spacing: 6, children: <Widget>[
                  OutlinedButton(onPressed: _busy ? null : () => _edit(r), child: const Text('Edit')),
                  TextButton(onPressed: _busy ? null : () => _toggle(r), child: Text(active ? 'Deactivate' : 'Reactivate')),
                ]),
            ]),
          );
        }),
    ]);
  }
}

class _CatalogResult {
  const _CatalogResult(this.fields, this.reason);
  final Map<String, dynamic> fields;
  final String reason;
}

class _CatalogDialog extends StatefulWidget {
  const _CatalogDialog({required this.vendor, this.item});
  final bool vendor;
  final Map<String, dynamic>? item;
  @override
  State<_CatalogDialog> createState() => _CatalogDialogState();
}

class _CatalogDialogState extends State<_CatalogDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c = <String, TextEditingController>{
    for (final String f in <String>['name', 'description', 'contactName', 'email', 'phone', 'address'])
      f: TextEditingController(text: text(widget.item?[f])),
  };
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    for (final TextEditingController c in _c.values) {
      c.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.item != null;
    final String noun = widget.vendor ? 'vendor' : 'category';
    return AlertDialog(
      title: Text(editing ? 'Edit $noun' : 'Add $noun'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              ExpenseField(fieldKey: const Key('catalog-name'), controller: _c['name']!, label: 'Name *', maxLength: 120, validator: (String? v) => requiredText(v, 'Name', max: 120)),
              const SizedBox(height: 8),
              ExpenseField(controller: _c['description']!, label: 'Description', maxLines: 2, maxLength: 1000),
              if (widget.vendor) ...<Widget>[
                const SizedBox(height: 8),
                ExpenseField(controller: _c['contactName']!, label: 'Contact name', maxLength: 120),
                const SizedBox(height: 8),
                ExpenseField(
                  controller: _c['email']!,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  validator: (String? v) => (v ?? '').trim().isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v!.trim()) ? null : 'Enter a valid email address.',
                ),
                const SizedBox(height: 8),
                ExpenseField(controller: _c['phone']!, label: 'Phone', keyboardType: TextInputType.phone, maxLength: 30),
                const SizedBox(height: 8),
                ExpenseField(controller: _c['address']!, label: 'Address', maxLines: 2, maxLength: 300),
              ],
              const SizedBox(height: 8),
              ExpenseField(fieldKey: const Key('catalog-reason'), controller: _reason,
                  label: editing ? 'Reason for change (audit) *' : 'Reason for adding (audit) *', maxLines: 2,
                  validator: (String? v) => requiredText(v, 'Reason', max: 2000, min: 10)),
            ]),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Go back')),
        FilledButton(
          key: const Key('catalog-save'),
          style: FilledButton.styleFrom(backgroundColor: expGreen),
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final Map<String, dynamic> fields = <String, dynamic>{
              'name': _c['name']!.text.trim(),
              'description': _c['description']!.text.trim(),
              if (widget.vendor) ...<String, dynamic>{
                'contactName': _c['contactName']!.text.trim(),
                'email': _c['email']!.text.trim(),
                'phone': _c['phone']!.text.trim(),
                'address': _c['address']!.text.trim(),
              },
            };
            Navigator.pop(context, _CatalogResult(fields, _reason.text.trim()));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
