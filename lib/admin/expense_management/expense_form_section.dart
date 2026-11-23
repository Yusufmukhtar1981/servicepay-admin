import 'package:flutter/material.dart';

import 'expense_api.dart';
import 'expense_common.dart';
import 'expense_documents.dart';
import 'expense_management_screen.dart';

/// Create (when [existing] is null) or edit an expense. Status, submitter,
/// approvals and timestamps are never editable here.
class ExpenseFormSection extends StatefulWidget {
  const ExpenseFormSection({super.key, required this.ctx, this.existing, this.onSaved, this.onConflict, this.onCancel});
  final ExpenseModuleContext ctx;
  final Map<String, dynamic>? existing;
  final ValueChanged<Map<String, dynamic>>? onSaved;
  final VoidCallback? onConflict;
  final VoidCallback? onCancel;

  @override
  State<ExpenseFormSection> createState() => _ExpenseFormSectionState();
}

class _ExpenseFormSectionState extends State<ExpenseFormSection> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final Map<String, dynamic> _e = widget.existing ?? <String, dynamic>{};
  late final TextEditingController _title = TextEditingController(text: text(_e['title']));
  late final TextEditingController _description = TextEditingController(text: text(_e['description']));
  late final TextEditingController _purpose = TextEditingController(text: text(_e['businessPurpose']));
  late final TextEditingController _amount = TextEditingController(text: minorToDecimal(_e['amountMinor']));
  late final TextEditingController _date = TextEditingController(text: text(_e['expenseDate'], fallback: ymd(lagosToday())));
  late final TextEditingController _beneficiary = TextEditingController(text: text(_e['beneficiary']));
  late final TextEditingController _reference = TextEditingController(text: text(_e['reference']));
  late final TextEditingController _department = TextEditingController(text: text(_e['department']));
  late final TextEditingController _branch = TextEditingController(text: text(_e['branch']));
  late final TextEditingController _exception = TextEditingController(text: text(asMap(_e['evidenceException'])['reason']));
  late String _categoryId = text(_e['categoryId']);
  late String _vendorId = text(_e['vendorId']);
  late String _method = text(_e['paymentMethod']);
  late List<Map<String, dynamic>> _documents = asList(_e['documents']).map(asMap).toList();
  late bool _useException = text(asMap(_e['evidenceException'])['reason']).isNotEmpty;

  String _key = ExpenseIdempotency.newKey('exp');
  bool _saving = false;
  String? _error;
  bool _outcomeUnknown = false;
  List<String> _summaryErrors = <String>[];

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _title, _description, _purpose, _amount, _date, _beneficiary, _reference, _department, _branch, _exception,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // Inactive entries are only listed when already referenced by this record.
  List<DropdownMenuItem<String>> _registryItems(List<Map<String, dynamic>> rows, String selected, String snapshotName) {
    final List<DropdownMenuItem<String>> items = <DropdownMenuItem<String>>[];
    bool found = false;
    for (final Map<String, dynamic> r in rows) {
      final String id = text(r['id']);
      final bool active = r['active'] != false;
      if (id == selected) found = true;
      if (!active && id != selected) continue;
      items.add(DropdownMenuItem<String>(
        value: id,
        child: Text('${text(r['name'], fallback: id)}${active ? '' : ' (inactive)'}', overflow: TextOverflow.ellipsis),
      ));
    }
    if (selected.isNotEmpty && !found) {
      items.add(DropdownMenuItem<String>(
        value: selected,
        child: Text('${snapshotName.isEmpty ? selected : snapshotName} (no longer listed)', overflow: TextOverflow.ellipsis),
      ));
    }
    return items;
  }

  List<String> _collectErrors() {
    final List<String> errors = <String>[];
    void add(String? e) {
      if (e != null) errors.add(e);
    }

    add(requiredText(_title.text, 'Expense title', max: 180));
    if (_categoryId.isEmpty) errors.add('Select an expense category.');
    add(requiredText(_description.text, 'Description', max: 4000));
    add(requiredText(_purpose.text, 'Business purpose', max: 2000));
    add(amountValidator(_amount.text));
    if (parseYmd(_date.text.trim()) == null) errors.add('Expense date must be a valid YYYY-MM-DD date.');
    if (_method.isEmpty) errors.add('Select a payment method.');
    if (_vendorId.isEmpty && _beneficiary.text.trim().isEmpty) errors.add('Select a vendor or enter a beneficiary.');
    add(requiredText(_reference.text, 'Reference number', max: 180));
    if (_department.text.trim().isEmpty && _branch.text.trim().isEmpty) errors.add('Enter a department or branch.');
    if (_documents.isEmpty) {
      if (!_useException) {
        errors.add('Attach a receipt or invoice, or record an authorized evidence exception.');
      } else if (_exception.text.trim().length < 10) {
        errors.add('Evidence exception reason needs at least 10 characters.');
      }
    }
    return errors;
  }

  Map<String, dynamic> _payload() => <String, dynamic>{
        'title': _title.text.trim(),
        'categoryId': _categoryId,
        'description': _description.text.trim(),
        'businessPurpose': _purpose.text.trim(),
        'amount': _amount.text.trim().replaceAll(',', ''),
        'expenseDate': _date.text.trim(),
        'paymentMethod': _method,
        if (_vendorId.isNotEmpty) 'vendorId': _vendorId,
        if (_vendorId.isEmpty) 'beneficiary': _beneficiary.text.trim(),
        'reference': _reference.text.trim(),
        if (_department.text.trim().isNotEmpty) 'department': _department.text.trim(),
        if (_branch.text.trim().isNotEmpty) 'branch': _branch.text.trim(),
        'documentIds': _documents.map((Map<String, dynamic> d) => text(d['id'])).toList(),
        if (_documents.isEmpty && _useException) 'evidenceExceptionReason': _exception.text.trim(),
      };

  Future<void> _save() async {
    final bool fieldsOk = _form.currentState?.validate() ?? false;
    final List<String> errors = _collectErrors();
    setState(() => _summaryErrors = errors);
    if (!fieldsOk || errors.isNotEmpty) return;
    String reason = '';
    if (_isEdit) {
      final String? r = await askReason(context,
          title: 'Reason for edit', message: 'Edits are recorded with previous and new values in the audit log.', confirmLabel: 'Save changes');
      if (r == null || !mounted) return;
      reason = r;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> result = _isEdit
          ? await widget.ctx.api.updateExpense(
              text(_e['id']),
              expense: _payload(),
              expectedVersion: asInt(_e['revision']) ?? 0,
              reason: reason,
              idempotencyKey: _key,
            )
          : await widget.ctx.api.createExpense(_payload(), _key);
      if (!mounted) return;
      final Map<String, dynamic> item = asMap(result['item']);
      _key = ExpenseIdempotency.newKey('exp');
      setState(() {
        _saving = false;
        _outcomeUnknown = false;
      });
      showExpenseMessage(
          context,
          result['idempotent'] == true
              ? 'This expense was already recorded by an earlier attempt. Showing the stored record.'
              : _isEdit
                  ? 'Expense updated.'
                  : 'Expense recorded with status Submitted. Submit it for approval from the record.');
      if (widget.onSaved != null) {
        widget.onSaved!(item);
      } else if (text(item['id']).isNotEmpty) {
        widget.ctx.openExpense(text(item['id']));
      }
    } catch (e) {
      if (!mounted) return;
      final ExpenseApiException? ex = e is ExpenseApiException ? e : null;
      if (ex != null && ex.isDefinitiveRejection) _key = ExpenseIdempotency.newKey('exp');
      setState(() {
        _saving = false;
        _outcomeUnknown = ex?.outcomeUnknown ?? false;
        _error = errorText(e);
      });
      if (ex != null && ex.isConflict && _isEdit) widget.onConflict?.call();
    }
  }

  Future<void> _pickDate() async {
    final DateTime t = lagosToday();
    final DateTime? d = await showDatePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: t,
      initialDate: parseYmd(_date.text.trim()) ?? t,
    );
    if (d != null && mounted) setState(() => _date.text = ymd(d));
  }

  Widget _grid(List<Widget> children) => LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final double w = c.maxWidth < 640 ? c.maxWidth : (c.maxWidth - 12) / 2;
        return Wrap(spacing: 12, runSpacing: 14, children: children.map((Widget x) => SizedBox(width: w, child: x)).toList());
      });

  @override
  Widget build(BuildContext context) {
    final ExpenseModuleContext ctx = widget.ctx;
    final bool canException = ctx.access.has(ExpensePermissions.exception);
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        if (!_isEdit)
          const ExpenseNotice(
              'Submitter, timestamps and approvers are assigned by the server. A new expense starts as Submitted; it enters the approval workflow only when you choose Submit for approval.'),
        if (ctx.categories.isEmpty) ...<Widget>[
          const SizedBox(height: 10),
          ExpenseNotice(
            'No expense categories exist yet. A user with ${ExpensePermissions.categories} must create one in Expense Categories before expenses can be recorded.',
            tone: 'warn',
          ),
        ],
        const SizedBox(height: 14),
        ExpensePanel(
          title: 'Expense details',
          child: _grid(<Widget>[
            ExpenseField(fieldKey: const Key('expense-title'), controller: _title, label: 'Expense title *', maxLength: 180,
                validator: (String? v) => requiredText(v, 'Expense title', max: 180)),
            DropdownButtonFormField<String>(
              key: const Key('expense-category'),
              isExpanded: true,
              value: _categoryId.isEmpty ? null : _categoryId,
              decoration: expInput('Category *'),
              items: _registryItems(ctx.categories, _categoryId, text(_e['categoryName'])),
              validator: (String? v) => (v ?? '').isEmpty ? 'Select an expense category.' : null,
              onChanged: _saving ? null : (String? v) => setState(() => _categoryId = v ?? ''),
            ),
            ExpenseField(fieldKey: const Key('expense-amount'), controller: _amount, label: 'Amount (NGN) *', hint: 'e.g. 125000.50',
                keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: amountValidator,
                helper: 'Exact naira and kobo; no currency symbol.'),
            TextFormField(
              key: const Key('expense-date'),
              controller: _date,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (String? v) => parseYmd((v ?? '').trim()) == null ? 'Use a valid date in YYYY-MM-DD format.' : null,
              decoration: expInput('Expense date *', hint: 'YYYY-MM-DD').copyWith(
                suffixIcon: IconButton(tooltip: 'Choose date', onPressed: _pickDate, icon: const Icon(Icons.calendar_today_outlined, size: 18)),
              ),
            ),
            DropdownButtonFormField<String>(
              key: const Key('expense-method'),
              isExpanded: true,
              value: _method.isEmpty ? null : _method,
              decoration: expInput('Payment method *'),
              items: paymentMethods.entries.map((MapEntry<String, String> m) => DropdownMenuItem<String>(value: m.key, child: Text(m.value))).toList(),
              validator: (String? v) => (v ?? '').isEmpty ? 'Select a payment method.' : null,
              onChanged: _saving ? null : (String? v) => setState(() => _method = v ?? ''),
            ),
            ExpenseField(fieldKey: const Key('expense-reference'), controller: _reference, label: 'Reference / invoice number *', maxLength: 180,
                helper: 'Must be unique. Duplicate invoice references are rejected.', validator: (String? v) => requiredText(v, 'Reference number', max: 180)),
          ]),
        ),
        const SizedBox(height: 12),
        ExpensePanel(
          title: 'Purpose',
          child: Column(children: <Widget>[
            ExpenseField(fieldKey: const Key('expense-description'), controller: _description, label: 'Description *', maxLines: 4, maxLength: 4000,
                validator: (String? v) => requiredText(v, 'Description', max: 4000)),
            const SizedBox(height: 12),
            ExpenseField(fieldKey: const Key('expense-purpose'), controller: _purpose, label: 'Business purpose *', maxLines: 3, maxLength: 2000,
                validator: (String? v) => requiredText(v, 'Business purpose', max: 2000)),
          ]),
        ),
        const SizedBox(height: 12),
        ExpensePanel(
          title: 'Payee and cost centre',
          subtitle: 'Choose a vendor or enter a beneficiary; enter a department or branch.',
          child: _grid(<Widget>[
            DropdownButtonFormField<String>(
              key: const Key('expense-vendor'),
              isExpanded: true,
              value: _vendorId,
              decoration: expInput('Vendor / supplier'),
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem<String>(value: '', child: Text('No vendor (enter beneficiary)')),
                ..._registryItems(ctx.vendors, _vendorId, text(_e['vendorName'])),
              ],
              onChanged: _saving ? null : (String? v) => setState(() => _vendorId = v ?? ''),
            ),
            ExpenseField(
              fieldKey: const Key('expense-beneficiary'),
              controller: _beneficiary,
              enabled: _vendorId.isEmpty,
              label: _vendorId.isEmpty ? 'Beneficiary *' : 'Beneficiary (vendor selected)',
              maxLength: 180,
              validator: (String? v) => _vendorId.isEmpty && (v ?? '').trim().isEmpty ? 'Enter a beneficiary or select a vendor.' : null,
            ),
            ExpenseField(fieldKey: const Key('expense-department'), controller: _department, label: 'Department', maxLength: 120,
                validator: (String? v) => (v ?? '').trim().isEmpty && _branch.text.trim().isEmpty ? 'Enter a department or branch.' : null),
            ExpenseField(fieldKey: const Key('expense-branch'), controller: _branch, label: 'Branch', maxLength: 120),
          ]),
        ),
        const SizedBox(height: 12),
        ExpensePanel(
          title: 'Supporting evidence *',
          subtitle: 'Every expense needs a receipt/invoice or an authorized documented exception.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            ExpenseDocumentPicker(
              api: ctx.api,
              documents: _documents,
              enabled: !_saving,
              maxBytes: ctx.maxDocumentBytes,
              maxDocuments: ctx.maxDocuments,
              onChanged: (List<Map<String, dynamic>> d) => setState(() => _documents = d),
            ),
            if (_documents.isEmpty) ...<Widget>[
              const SizedBox(height: 10),
              if (canException) ...<Widget>[
                CheckboxListTile(
                  key: const Key('expense-exception-toggle'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _useException,
                  onChanged: _saving ? null : (bool? v) => setState(() => _useException = v ?? false),
                  title: const Text('Record an authorized evidence exception'),
                  subtitle: const Text('The server stamps you as the authorizing officer. Use only when no document can exist.'),
                ),
                if (_useException)
                  ExpenseField(
                    fieldKey: const Key('expense-exception-reason'),
                    controller: _exception,
                    label: 'Exception reason *',
                    maxLines: 3,
                    maxLength: 2000,
                    validator: (String? v) => _useException ? requiredText(v, 'Exception reason', max: 2000, min: 10) : null,
                  ),
              ] else
                ExpenseNotice(
                  'Evidence exceptions require the explicit permission ${ExpensePermissions.exception}. Upload a receipt or invoice instead.',
                ),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        if (_summaryErrors.isNotEmpty) ...<Widget>[
          ExpenseNotice(
            key: const Key('expense-form-errors'),
            'Please correct ${_summaryErrors.length} item${_summaryErrors.length == 1 ? '' : 's'}:\n- ${_summaryErrors.join('\n- ')}',
            tone: 'error',
          ),
          const SizedBox(height: 10),
        ],
        if (_error != null) ...<Widget>[
          ExpenseNotice(_error!, tone: _outcomeUnknown ? 'warn' : 'error'),
          const SizedBox(height: 10),
        ],
        Wrap(spacing: 10, runSpacing: 8, children: <Widget>[
          FilledButton.icon(
            key: const Key('expense-save'),
            style: FilledButton.styleFrom(backgroundColor: expGreen),
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(_saving
                ? 'Saving...'
                : _outcomeUnknown
                    ? 'Retry safely (same operation)'
                    : _isEdit
                        ? 'Save changes'
                        : 'Record expense'),
          ),
          if (widget.onCancel != null)
            TextButton(onPressed: _saving ? null : widget.onCancel, child: const Text('Cancel editing')),
        ]),
      ]),
    );
  }
}
