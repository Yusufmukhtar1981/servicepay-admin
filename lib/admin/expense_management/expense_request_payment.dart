part of 'expense_requests_section.dart';

// ---------------- Payment recording ----------------

class RequestPaymentInput {
  const RequestPaymentInput({required this.reason, required this.payment});
  final String reason;
  final Map<String, dynamic> payment;
}

class RequestPaymentDialog extends StatefulWidget {
  const RequestPaymentDialog(
      {super.key, required this.ctx, required this.request});
  final ExpenseModuleContext ctx;
  final Map<String, dynamic> request;
  @override
  State<RequestPaymentDialog> createState() => _RequestPaymentDialogState();
}

class _RequestPaymentDialogState extends State<RequestPaymentDialog> {
  late final String _expectedRecipient = text(widget.request['beneficiary'],
      fallback: text(widget.request['vendorName']));
  late final TextEditingController _amount = TextEditingController(
      text: minorToDecimal(widget.request['amountMinor']));
  final TextEditingController _date =
      TextEditingController(text: ymd(lagosToday()));
  final TextEditingController _reference = TextEditingController();
  late final TextEditingController _recipient =
      TextEditingController(text: _expectedRecipient);
  final TextEditingController _reason = TextEditingController();
  String _method = '';
  bool _confirmed = false;
  List<Map<String, dynamic>> _evidence = <Map<String, dynamic>>[];
  Map<String, String> _errs = <String, String>{};

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _amount,
      _date,
      _reference,
      _recipient,
      _reason
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final Map<String, String> e = <String, String>{};
    final int approved = asInt(widget.request['amountMinor']) ?? 0;
    final String? a = amountValidator(_amount.text);
    if (a != null) {
      e['amount'] = a;
    } else if ((decimalToMinor(_amount.text) ?? 0) > approved) {
      e['amount'] = 'Cannot exceed the approved ${money(approved)}.';
    }
    if (_method.isEmpty) e['method'] = 'Select the payment method used.';
    final DateTime? paid = parseYmd(_date.text.trim());
    if (paid == null) {
      e['date'] = 'Use the format YYYY-MM-DD.';
    } else if (paid.isAfter(lagosToday())) {
      e['date'] = 'A completed payment cannot have a future date.';
    }
    if (_reference.text.trim().length < 3) {
      e['reference'] = 'Enter the external payment reference.';
    }
    if (_recipient.text.trim().isEmpty) {
      e['recipient'] = 'Recipient is required.';
    } else if (_expectedRecipient.isNotEmpty &&
        _recipient.text.trim().toLowerCase() !=
            _expectedRecipient.trim().toLowerCase()) {
      e['recipient'] =
          'Recipient must match the approved payee: $_expectedRecipient.';
    }
    if (_evidence.isEmpty) e['evidence'] = 'Upload separate proof of payment.';
    if (_reason.text.trim().length < 10) {
      e['reason'] = 'Reason needs at least 10 characters.';
    }
    if (!_confirmed) {
      e['confirm'] = 'Confirm the payment was made outside ServicePay.';
    }
    setState(() => _errs = e);
    if (e.isNotEmpty) return;
    Navigator.of(context).pop(RequestPaymentInput(
        reason: _reason.text.trim(),
        payment: <String, dynamic>{
          'amount': _amount.text.trim().replaceAll(',', ''),
          'method': _method,
          'date': _date.text.trim(),
          'reference': _reference.text.trim(),
          'recipient': _recipient.text.trim(),
          'evidenceDocumentIds':
              _evidence.map((Map<String, dynamic> d) => text(d['id'])).toList(),
        }));
  }

  Widget _f(String k, TextEditingController c, String label,
          {TextInputType? kb, String? helper}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
            key: Key('pay-$k'),
            controller: c,
            keyboardType: kb,
            decoration:
                expInput(label, helper: helper).copyWith(errorText: _errs[k])),
      );

  @override
  Widget build(BuildContext context) {
    final ExpenseModuleContext ctx = widget.ctx;
    return AlertDialog(
      title: const Text('Record payment'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const ExpenseNotice(
                    'This records a payment already made outside ServicePay for bookkeeping. It does not send money, start a bank transfer or debit any customer wallet.',
                    tone: 'warn'),
                const SizedBox(height: 12),
                if (_errs.isNotEmpty) ...<Widget>[
                  ExpenseNotice(_errs.values.join('\n'),
                      tone: 'error', key: const Key('pay-errors')),
                  const SizedBox(height: 10),
                ],
                _f('amount', _amount, 'Actual amount paid (NGN) *',
                    kb: const TextInputType.numberWithOptions(decimal: true),
                    helper:
                        'Approved: ${money(widget.request['amountMinor'])}'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DropdownButtonFormField<String>(
                    key: const Key('pay-method'),
                    value: _method.isEmpty ? null : _method,
                    isExpanded: true,
                    decoration: expInput('Payment method *')
                        .copyWith(errorText: _errs['method']),
                    items: <DropdownMenuItem<String>>[
                      for (final MapEntry<String, String> m
                          in paymentMethods.entries)
                        DropdownMenuItem<String>(
                            value: m.key, child: Text(m.value)),
                    ],
                    onChanged: (String? v) => setState(() => _method = v ?? ''),
                  ),
                ),
                _f('date', _date, 'Payment date *'),
                _f('reference', _reference, 'Payment reference *'),
                _f('recipient', _recipient, 'Recipient *',
                    helper: _expectedRecipient.isEmpty
                        ? null
                        : 'Approved payee: $_expectedRecipient'),
                const Text('Proof of payment *',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: expInk,
                        fontSize: 13)),
                ExpenseDocumentPicker(
                  api: ctx.api,
                  documents: _evidence,
                  maxBytes: ctx.maxDocumentBytes,
                  maxDocuments: ctx.maxDocuments,
                  uploadLabel: 'Upload proof of payment',
                  buttonKey: const Key('pay-upload'),
                  uploader: (ExpenseDocumentUpload u, int max) =>
                      ctx.api.uploadRequestDocument(u, maxBytes: max),
                  onChanged: (List<Map<String, dynamic>> d) =>
                      setState(() => _evidence = d),
                ),
                if (_errs['evidence'] != null)
                  Text(_errs['evidence']!,
                      style: const TextStyle(color: expDanger, fontSize: 12)),
                const SizedBox(height: 10),
                _f('reason', _reason, 'Reason / bookkeeping note *'),
                CheckboxListTile(
                  key: const Key('pay-confirm'),
                  contentPadding: EdgeInsets.zero,
                  value: _confirmed,
                  onChanged: (bool? v) =>
                      setState(() => _confirmed = v ?? false),
                  title: const Text(
                      'I confirm this payment was made externally and I am only recording it.',
                      style: TextStyle(fontSize: 12.5)),
                  subtitle: _errs['confirm'] == null
                      ? null
                      : Text(_errs['confirm']!,
                          style: const TextStyle(
                              color: expDanger, fontSize: 11.5)),
                ),
              ]),
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            key: const Key('pay-submit'),
            onPressed: _submit,
            style: FilledButton.styleFrom(backgroundColor: expGreen),
            child: const Text('Record payment')),
      ],
    );
  }
}
