part of 'expense_requests_section.dart';

// ---------------- Form ----------------

class ExpenseRequestForm extends StatefulWidget {
  const ExpenseRequestForm(
      {super.key,
      required this.ctx,
      this.existing,
      required this.onSaved,
      required this.onCancel});
  final ExpenseModuleContext ctx;
  final Map<String, dynamic>? existing;
  final ValueChanged<Map<String, dynamic>> onSaved;
  final VoidCallback onCancel;
  @override
  State<ExpenseRequestForm> createState() => _ExpenseRequestFormState();
}

class _ExpenseRequestFormState extends State<ExpenseRequestForm> {
  late final Map<String, dynamic> _e = widget.existing ?? <String, dynamic>{};
  late final TextEditingController _title =
      TextEditingController(text: text(_e['title']));
  late final TextEditingController _amount = TextEditingController(
      text: _e['amountMinor'] == null ? '' : minorToDecimal(_e['amountMinor']));
  late final TextEditingController _purpose =
      TextEditingController(text: text(_e['businessPurpose']));
  late final TextEditingController _description =
      TextEditingController(text: text(_e['description']));
  late final TextEditingController _date =
      TextEditingController(text: text(_e['requiredDate']));
  late final TextEditingController _beneficiary =
      TextEditingController(text: text(_e['beneficiary']));
  late final TextEditingController _exception =
      TextEditingController(text: text(_e['evidenceExceptionReason']));
  late String? _department = text(_e['department']).isNotEmpty
      ? text(_e['department'])
      : (widget.ctx.department.isNotEmpty ? widget.ctx.department : null);
  late String? _categoryId =
      text(_e['categoryId']).isEmpty ? null : text(_e['categoryId']);
  late String? _vendorId =
      text(_e['vendorId']).isEmpty ? null : text(_e['vendorId']);
  late List<Map<String, dynamic>> _docs =
      asList(_e['documents']).map(asMap).toList();
  Map<String, String> _errs = <String, String>{};
  String? _error;
  bool _busy = false;
  String? _key;
  String? _submitKey;
  Map<String, dynamic>? _savedItem; // edit saved but submit pending

  bool get _editing => widget.existing != null;

  /// Only Head Office finance users may raise requests for other departments.
  bool get _canChooseDepartment =>
      (widget.ctx.access.role == 'HEAD_OFFICE' && widget.ctx.financeAccess) ||
      widget.ctx.department.isEmpty;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _title,
      _amount,
      _purpose,
      _description,
      _date,
      _beneficiary,
      _exception
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Validates every value from state, independent of which widgets are
  /// mounted or scrolled into view.
  Map<String, String> _validate(bool submit) {
    final Map<String, String> e = <String, String>{};
    final String amount = _amount.text.trim();
    if (amount.isNotEmpty || submit) {
      final String? a = amountValidator(amount);
      if (a != null) e['amount'] = a;
    }
    if (_title.text.trim().length > 200) {
      e['title'] = 'Title must be 200 characters or fewer.';
    }
    if (_date.text.trim().isNotEmpty && parseYmd(_date.text.trim()) == null) {
      e['requiredDate'] = 'Use the format YYYY-MM-DD.';
    }
    if (!submit) return e;
    if (_title.text.trim().isEmpty) e['title'] = 'Request title is required.';
    if (_department == null || _department!.isEmpty) {
      e['department'] = 'Select a department.';
    }
    if (_categoryId == null) e['category'] = 'Select an expense category.';
    if (_purpose.text.trim().length < 10) {
      e['purpose'] = 'Business justification needs at least 10 characters.';
    }
    if (_description.text.trim().length < 10) {
      e['description'] = 'Detailed description needs at least 10 characters.';
    }
    if (_date.text.trim().isEmpty) {
      e['requiredDate'] = 'Required date is required.';
    }
    if (_vendorId == null && _beneficiary.text.trim().isEmpty) {
      e['payee'] = 'Select a vendor or enter a beneficiary.';
    }
    if (_docs.isEmpty && _exception.text.trim().length < 10) {
      e['documents'] = widget.ctx.access.has(ExpensePermissions.exception)
          ? 'Attach a supporting document or quotation, or give an evidence exception reason (10+ characters).'
          : 'Attach a supporting document or quotation.';
    }
    return e;
  }

  Map<String, dynamic> _fields() {
    String? v(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    return <String, dynamic>{
      if (v(_title) != null) 'title': v(_title),
      if (_department != null) 'department': _department,
      if (v(_amount) != null) 'amount': _amount.text.trim().replaceAll(',', ''),
      if (_categoryId != null) 'categoryId': _categoryId,
      if (v(_purpose) != null) 'businessPurpose': v(_purpose),
      if (v(_description) != null) 'description': v(_description),
      if (v(_date) != null) 'requiredDate': v(_date),
      if (_vendorId != null) 'vendorId': _vendorId,
      if (v(_beneficiary) != null) 'beneficiary': v(_beneficiary),
      'documentIds':
          _docs.map((Map<String, dynamic> d) => text(d['id'])).toList(),
      if (v(_exception) != null) 'evidenceExceptionReason': v(_exception),
    };
  }

  Future<void> _save(bool submit) async {
    final Map<String, String> errs = _validate(submit);
    setState(() {
      _errs = errs;
      _error = null;
    });
    if (errs.isNotEmpty) return;
    String reason = '';
    if (_editing && _savedItem == null) {
      final String? r = await askReason(context,
          title: submit ? 'Save and resubmit' : 'Save changes',
          message:
              'Explain what changed. This is recorded in the request history.',
          confirmLabel: submit ? 'Save and submit' : 'Save changes');
      if (r == null || !mounted) return;
      reason = r;
    } else if (submit && _editing) {
      final String? r = await askReason(context,
          title: 'Submit request',
          message: 'Confirm submission for approval.',
          confirmLabel: 'Submit');
      if (r == null || !mounted) return;
      reason = r;
    }
    setState(() => _busy = true);
    try {
      Map<String, dynamic> item;
      if (!_editing) {
        _key ??= ExpenseIdempotency.newKey('req');
        final Map<String, dynamic> res = await widget.ctx.api
            .createRequest(_fields(), submit: submit, idempotencyKey: _key!);
        _key = null;
        item = asMap(res['item']);
      } else {
        if (_savedItem == null) {
          _key ??= ExpenseIdempotency.newKey('req');
          final Map<String, dynamic> res = await widget.ctx.api.updateRequest(
            text(_e['id']),
            request: _fields(),
            expectedVersion: asInt(_e['revision']) ?? 0,
            reason: reason,
            idempotencyKey: _key!,
          );
          _key = null;
          _savedItem = asMap(res['item']);
        }
        item = _savedItem!;
        if (submit) {
          _submitKey ??= ExpenseIdempotency.newKey('rsb');
          final Map<String, dynamic> res = await widget.ctx.api.requestAction(
            text(item['id']),
            action: 'SUBMIT',
            expectedVersion: asInt(item['revision']) ?? 0,
            reason: reason,
            idempotencyKey: _submitKey!,
          );
          _submitKey = null;
          item = asMap(res['item']);
        }
      }
      if (!mounted) return;
      setState(() => _busy = false);
      showExpenseMessage(
          context, submit ? 'Request submitted for approval.' : 'Draft saved.');
      widget.onSaved(item);
    } catch (e) {
      final ExpenseApiException? ex = e is ExpenseApiException ? e : null;
      if (ex == null || !ex.outcomeUnknown) {
        _key = null;
        _submitKey = null;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            '${errorText(e)}${_savedItem != null ? ' Your changes were saved; submission did not complete.' : ''} Your entries are preserved.';
      });
    }
  }

  Future<void> _pickDate() async {
    final DateTime today = lagosToday();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: parseYmd(_date.text.trim()) ?? today,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 730)),
    );
    if (d != null) setState(() => _date.text = ymd(d));
  }

  Widget _text(String key, TextEditingController c, String label,
          {String? hint,
          int maxLines = 1,
          TextInputType? keyboard,
          String? helper,
          Widget? suffix}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          key: Key('request-$key'),
          controller: c,
          enabled: !_busy,
          maxLines: maxLines,
          minLines: maxLines > 1 ? 2 : 1,
          keyboardType: keyboard,
          onChanged: (_) {
            if (_errs.containsKey(key)) {
              setState(
                  () => _errs = Map<String, String>.from(_errs)..remove(key));
            }
          },
          decoration: expInput(label, hint: hint, helper: helper)
              .copyWith(errorText: _errs[key], suffixIcon: suffix),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ExpenseModuleContext ctx = widget.ctx;
    final List<Map<String, dynamic>> cats = ctx.requestCategories
        .where((Map<String, dynamic> c) =>
            c['active'] != false || text(c['id']) == _categoryId)
        .toList();
    final List<Map<String, dynamic>> vendors = ctx.requestVendors
        .where((Map<String, dynamic> v) =>
            v['active'] != false || text(v['id']) == _vendorId)
        .toList();
    final List<String> depts = <String>{
      ...ctx.requestDepartments,
      if (_department != null) _department!
    }.toList();
    final bool canException = ctx.access.has(ExpensePermissions.exception);
    final Map<String, dynamic> actor = asMap(ctx.readiness['actor']);
    final String requester = _editing
        ? text(_e['createdByName'], fallback: 'Original requester')
        : text(actor['fullName'],
            fallback: text(actor['name'], fallback: 'Your signed-in account'));
    return ExpensePanel(
      title: _editing ? 'Edit expense request' : 'New expense request',
      subtitle: _editing
          ? 'Revision ${text(_e['revision'])}'
          : 'Save a draft at any time; submitting checks every required field.',
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_errs.isNotEmpty) ...<Widget>[
              ExpenseNotice(
                  'Fix the following before continuing:\n${_errs.values.map((String s) => '- $s').join('\n')}',
                  tone: 'error',
                  key: const Key('request-form-errors')),
              const SizedBox(height: 12),
            ],
            InputDecorator(
              decoration: expInput('Requesting staff member',
                  helper:
                      'Set by the server from your signed-in account. It cannot be changed.'),
              child: Text(requester,
                  style: const TextStyle(
                      color: expInk, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            _text('title', _title, 'Request title *',
                hint: 'e.g. Generator diesel for Ikeja hub'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                key: const Key('request-department'),
                value: _department,
                isExpanded: true,
                decoration: expInput('Department *',
                        helper: _canChooseDepartment
                            ? null
                            : 'Requests are raised for your assigned department.')
                    .copyWith(errorText: _errs['department']),
                items: <DropdownMenuItem<String>>[
                  for (final String d in depts)
                    DropdownMenuItem<String>(value: d, child: Text(d))
                ],
                onChanged: _busy || !_canChooseDepartment
                    ? null
                    : (String? v) => setState(() => _department = v),
              ),
            ),
            _text('amount', _amount, 'Amount requested (NGN) *',
                hint: '125000.00',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                helper: 'Naira, up to two decimals.'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                key: const Key('request-category'),
                value: _categoryId,
                isExpanded: true,
                decoration: expInput('Expense category *')
                    .copyWith(errorText: _errs['category']),
                items: <DropdownMenuItem<String>>[
                  for (final Map<String, dynamic> c in cats)
                    DropdownMenuItem<String>(
                        value: text(c['id']),
                        child: Text(text(c['name'], fallback: text(c['id'])))),
                ],
                onChanged: _busy
                    ? null
                    : (String? v) => setState(() => _categoryId = v),
              ),
            ),
            _text('purpose', _purpose, 'Business justification *',
                maxLines: 3, hint: 'Why the company needs this spend'),
            _text('description', _description, 'Detailed description *',
                maxLines: 4, hint: 'Items, quantities, quotation details'),
            _text('requiredDate', _date, 'Required date *',
                hint: 'YYYY-MM-DD',
                suffix: IconButton(
                    tooltip: 'Pick date',
                    onPressed: _busy ? null : _pickDate,
                    icon: const Icon(Icons.event_outlined))),
            const Text('Vendor or beneficiary *',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: expInk, fontSize: 13)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                key: const Key('request-vendor'),
                value: _vendorId,
                isExpanded: true,
                decoration: expInput('Registered vendor (optional)'),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                      value: null, child: Text('No vendor')),
                  for (final Map<String, dynamic> v in vendors)
                    DropdownMenuItem<String>(
                        value: text(v['id']),
                        child: Text(text(v['name'], fallback: text(v['id'])))),
                ],
                onChanged: _busy
                    ? null
                    : (String? v) => setState(() {
                          _vendorId = v;
                          _errs = Map<String, String>.from(_errs)
                            ..remove('payee');
                        }),
              ),
            ),
            _text('payee', _beneficiary, 'Beneficiary name',
                hint:
                    'Person or business to be paid if not a registered vendor'),
            const Text('Supporting documents or quotation *',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: expInk, fontSize: 13)),
            const SizedBox(height: 6),
            ExpenseDocumentPicker(
              api: ctx.api,
              documents: _docs,
              enabled: !_busy,
              maxBytes: ctx.maxDocumentBytes,
              maxDocuments: ctx.maxDocuments,
              uploadLabel: 'Upload document or quotation',
              buttonKey: const Key('request-upload-document'),
              uploader: (ExpenseDocumentUpload u, int max) =>
                  ctx.api.uploadRequestDocument(u, maxBytes: max),
              onPreview: (Map<String, dynamic> d) => _preview(d),
              onChanged: (List<Map<String, dynamic>> d) => setState(() {
                _docs = d;
                _errs = Map<String, String>.from(_errs)..remove('documents');
              }),
            ),
            if (_errs['documents'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_errs['documents']!,
                    style: const TextStyle(color: expDanger, fontSize: 12)),
              ),
            if (canException) ...<Widget>[
              const SizedBox(height: 10),
              _text('exception', _exception, 'Evidence exception reason',
                  maxLines: 2,
                  helper:
                      'Only when no document exists. Your account is authorized to record evidence exceptions.'),
            ],
            const SizedBox(height: 8),
            if (_error != null) ...<Widget>[
              ExpenseNotice(_error!,
                  tone: 'error', key: const Key('request-save-error')),
              const SizedBox(height: 10),
            ],
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              OutlinedButton.icon(
                key: const Key('request-save-draft'),
                onPressed:
                    _busy || _savedItem != null ? null : () => _save(false),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(_key != null && _error != null
                    ? 'Retry save (same operation)'
                    : (_editing ? 'Save changes' : 'Save draft')),
              ),
              FilledButton.icon(
                key: const Key('request-submit'),
                onPressed: _busy ? null : () => _save(true),
                style: FilledButton.styleFrom(backgroundColor: expGreen),
                icon: const Icon(Icons.send_outlined, size: 18),
                label: Text(_busy ? 'Working...' : 'Submit for approval'),
              ),
              TextButton(
                  onPressed: _busy ? null : widget.onCancel,
                  child: const Text('Cancel')),
            ]),
          ]),
    );
  }

  Future<void> _preview(Map<String, dynamic> d) async {
    try {
      final String? requestId = _editing ? text(_e['id']) : null;
      final bool attached = requestId != null &&
          asList(_e['documentIds'])
              .map((dynamic v) => '$v')
              .contains(text(d['id']));
      final String name = attached
          ? await widget.ctx.api.downloadRequestDocument(
              requestId, text(d['id']),
              fallbackName: text(d['name'], fallback: 'document'))
          : await widget.ctx.api.downloadUnattachedRequestDocument(
              text(d['id']),
              fallbackName: text(d['name'], fallback: 'document'));
      if (mounted) showExpenseMessage(context, 'Downloaded $name');
    } catch (e) {
      if (mounted) showExpenseMessage(context, errorText(e), error: true);
    }
  }
}
