import 'package:flutter/material.dart';

import 'expense_api.dart';
import 'expense_common.dart';
import 'expense_documents.dart';

/// Result of the Mark Paid / Reverse dialogs, ready for expenseAction.
class ExpenseSettlementInput {
  const ExpenseSettlementInput({required this.reason, required this.details, this.comments});
  final String reason;
  final String? comments;
  final Map<String, dynamic> details;
}

/// Mark Paid ([reverse] false) or Reverse paid ([reverse] true) dialog. Both
/// only RECORD an external event; ServicePay never moves money here.
Future<ExpenseSettlementInput?> showSettlementDialog(
  BuildContext context, {
  required bool reverse,
  required ExpenseManagementApi api,
  required List<Map<String, dynamic>> expenseDocuments,
  required int maxBytes,
  required int maxDocuments,
  required String amountLabel,
}) =>
    showDialog<ExpenseSettlementInput>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _SettlementDialog(
        reverse: reverse,
        api: api,
        expenseDocuments: expenseDocuments,
        maxBytes: maxBytes,
        maxDocuments: maxDocuments,
        amountLabel: amountLabel,
      ),
    );

class _SettlementDialog extends StatefulWidget {
  const _SettlementDialog({
    required this.reverse,
    required this.api,
    required this.expenseDocuments,
    required this.maxBytes,
    required this.maxDocuments,
    required this.amountLabel,
  });
  final bool reverse;
  final ExpenseManagementApi api;
  final List<Map<String, dynamic>> expenseDocuments;
  final int maxBytes;
  final int maxDocuments;
  final String amountLabel;
  @override
  State<_SettlementDialog> createState() => _SettlementDialogState();
}

class _SettlementDialogState extends State<_SettlementDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _date = TextEditingController(text: ymd(lagosToday()));
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _comments = TextEditingController();
  final Set<String> _selected = <String>{};
  List<Map<String, dynamic>> _uploaded = <Map<String, dynamic>>[];
  String _method = '';
  bool _confirmed = false;
  String? _error;

  @override
  void dispose() {
    _reference.dispose();
    _date.dispose();
    _reason.dispose();
    _comments.dispose();
    super.dispose();
  }

  void _submit() {
    final bool ok = _form.currentState!.validate();
    final List<String> evidence = <String>[..._selected, ..._uploaded.map((Map<String, dynamic> d) => text(d['id']))];
    String? error;
    if (widget.reverse && evidence.isEmpty) error = 'Attach or select evidence of the external return.';
    if (!_confirmed) error = 'Tick the confirmation to continue.';
    setState(() => _error = error);
    if (!ok || error != null) return;
    Navigator.pop(
      context,
      ExpenseSettlementInput(
        reason: _reason.text.trim(),
        comments: _comments.text.trim(),
        details: widget.reverse
            ? <String, dynamic>{'reference': _reference.text.trim(), 'date': _date.text.trim(), 'evidenceDocumentIds': evidence}
            : <String, dynamic>{'method': _method, 'reference': _reference.text.trim(), 'date': _date.text.trim(), 'evidenceDocumentIds': evidence},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool rev = widget.reverse;
    return AlertDialog(
      title: Text(rev ? 'Record reversal of paid expense' : 'Mark as paid (manual record)'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              ExpenseNotice(
                rev
                    ? 'This records that ${widget.amountLabel} was returned to the company outside ServicePay. No refund, wallet credit or bank instruction is created.'
                    : 'This records that ${widget.amountLabel} was paid by the company outside ServicePay. No wallet debit, payout or bank transfer is executed, and the payment is not verified with any provider.',
                tone: 'warn',
              ),
              const SizedBox(height: 12),
              if (!rev) ...<Widget>[
                DropdownButtonFormField<String>(
                  key: const Key('pay-method'),
                  isExpanded: true,
                  value: _method.isEmpty ? null : _method,
                  decoration: expInput('Payment method used *'),
                  items: paymentMethods.entries.map((MapEntry<String, String> m) => DropdownMenuItem<String>(value: m.key, child: Text(m.value))).toList(),
                  validator: (String? v) => (v ?? '').isEmpty ? 'Select the payment method.' : null,
                  onChanged: (String? v) => setState(() => _method = v ?? ''),
                ),
                const SizedBox(height: 12),
              ],
              ExpenseField(
                fieldKey: const Key('pay-reference'),
                controller: _reference,
                label: rev ? 'Return reference *' : 'Payment reference *',
                validator: (String? v) => requiredText(v, 'Reference', max: 180),
              ),
              const SizedBox(height: 12),
              ExpenseField(
                fieldKey: const Key('pay-date'),
                controller: _date,
                label: rev ? 'Return date (YYYY-MM-DD) *' : 'Payment date (YYYY-MM-DD) *',
                validator: (String? v) {
                  final DateTime? d = parseYmd((v ?? '').trim());
                  if (d == null) return 'Use a valid YYYY-MM-DD date.';
                  if (d.isAfter(lagosToday())) return 'The date cannot be in the future.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Text(rev ? 'Return evidence *' : 'Payment evidence (optional)', style: const TextStyle(fontWeight: FontWeight.w800, color: expInk)),
              for (final Map<String, dynamic> d in widget.expenseDocuments)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _selected.contains(text(d['id'])),
                  onChanged: (bool? v) => setState(() => v == true ? _selected.add(text(d['id'])) : _selected.remove(text(d['id']))),
                  title: Text(text(d['name'], fallback: 'Document'), overflow: TextOverflow.ellipsis),
                  subtitle: const Text('Existing expense document'),
                ),
              ExpenseDocumentPicker(
                api: widget.api,
                documents: _uploaded,
                maxBytes: widget.maxBytes,
                maxDocuments: widget.maxDocuments,
                onChanged: (List<Map<String, dynamic>> d) => setState(() => _uploaded = d),
              ),
              const SizedBox(height: 12),
              ExpenseField(
                fieldKey: const Key('pay-reason'),
                controller: _reason,
                label: 'Reason (audit) *',
                maxLines: 2,
                validator: (String? v) => requiredText(v, 'Reason', max: 2000, min: 10),
              ),
              const SizedBox(height: 12),
              ExpenseField(controller: _comments, label: 'Comments', maxLines: 2),
              CheckboxListTile(
                key: const Key('pay-confirm'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _confirmed,
                onChanged: (bool? v) => setState(() => _confirmed = v ?? false),
                title: Text(rev
                    ? 'I confirm the funds were returned externally and I am only recording it.'
                    : 'I confirm this payment was made externally and is recorded manually, not verified by ServicePay or any provider.'),
              ),
              if (_error != null) ExpenseNotice(_error!, tone: 'error'),
            ]),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Go back')),
        FilledButton(
          key: const Key('pay-submit'),
          style: FilledButton.styleFrom(backgroundColor: rev ? expDanger : expGreen),
          onPressed: _submit,
          child: Text(rev ? 'Record reversal' : 'Record payment'),
        ),
      ],
    );
  }
}
