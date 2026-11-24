part of 'expense_requests_section.dart';

// ---------------- Detail ----------------

class ExpenseRequestDetailView extends StatefulWidget {
  const ExpenseRequestDetailView(
      {super.key,
      required this.ctx,
      required this.requestId,
      required this.onClose});
  final ExpenseModuleContext ctx;
  final String requestId;
  final VoidCallback onClose;
  @override
  State<ExpenseRequestDetailView> createState() =>
      _ExpenseRequestDetailViewState();
}

class _ExpenseRequestDetailViewState extends State<ExpenseRequestDetailView> {
  Map<String, dynamic>? _item;
  List<Map<String, dynamic>> _audit = <Map<String, dynamic>>[];
  String? _error;
  String? _auditError;
  String? _actionError;
  bool _busy = false;
  bool _editing = false;
  final Map<String, String> _keys = <String, String>{};
  final Map<String, String> _keyBodies = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ExpenseRequestDetailView old) {
    super.didUpdateWidget(old);
    if (old.ctx.notificationsTick != widget.ctx.notificationsTick &&
        !_busy &&
        !_editing) {
      _load(quiet: true);
    }
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _error = null);
    try {
      final Map<String, dynamic> data =
          await widget.ctx.api.expenseRequest(widget.requestId);
      if (!mounted) return;
      setState(() => _item = asMap(data['item']));
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = errorText(e));
    }
    try {
      final Map<String, dynamic> a =
          await widget.ctx.api.requestAudit(widget.requestId);
      if (!mounted) return;
      setState(() {
        _audit = asList(a['items']).map(asMap).toList();
        _auditError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _auditError = errorText(e));
    }
  }

  Future<void> _act(String action) async {
    final Map<String, dynamic> item = _item!;
    if (action == 'EDIT') {
      setState(() => _editing = true);
      return;
    }
    String? reason;
    String? comments;
    Map<String, dynamic>? payment;
    if (action == 'PAY') {
      final RequestPaymentInput? input = await showDialog<RequestPaymentInput>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RequestPaymentDialog(ctx: widget.ctx, request: item),
      );
      if (input == null || !mounted) return;
      reason = input.reason;
      payment = input.payment;
    } else {
      final bool destructive = action == 'REJECT' || action == 'CANCEL';
      final String message = switch (action) {
        'APPROVE' =>
          'Approve this level. You cannot approve your own request or more than one level. Your reason is shown to the requester.',
        'REJECT' =>
          'The rejection reason is mandatory and shown to the requester.',
        'REQUEST_CHANGES' =>
          'Describe the additional information or changes needed. The requester can edit and resubmit.',
        'CANCEL' =>
          'Cancelling is final for this request and is recorded in the audit trail.',
        'SUBMIT' => 'Submit using the currently configured approval policy.',
        _ => 'This step is recorded in the immutable audit trail.',
      };
      reason = await askReason(context,
          title: requestActionLabels[action] ?? action,
          message: message,
          confirmLabel: requestActionLabels[action] ?? 'Confirm',
          destructive: destructive);
      if (reason == null || !mounted) return;
      if (action == 'APPROVE' ||
          action == 'REJECT' ||
          action == 'REQUEST_CHANGES') {
        comments = reason;
      }
    }
    final String body = jsonEncode(
        <String, dynamic>{'r': reason, 'p': payment, 'v': item['revision']});
    if (_keys[action] == null || _keyBodies[action] != body) {
      _keys[action] = ExpenseIdempotency.newKey('rqa');
      _keyBodies[action] = body;
    }
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final Map<String, dynamic> res = await widget.ctx.api.requestAction(
        text(item['id']),
        action: action,
        expectedVersion: asInt(item['revision']) ?? 0,
        reason: reason,
        comments: comments,
        payment: payment,
        idempotencyKey: _keys[action]!,
      );
      _keys.remove(action);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _item = asMap(res['item']);
      });
      showExpenseMessage(
          context,
          action == 'PAY'
              ? 'Payment recorded for bookkeeping.'
              : '${requestActionLabels[action] ?? action} recorded.');
      widget.ctx.refreshNotifications?.call();
      _load(quiet: true);
    } catch (e) {
      final ExpenseApiException? ex = e is ExpenseApiException ? e : null;
      if (ex == null || !ex.outcomeUnknown) _keys.remove(action);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _actionError = errorText(e);
      });
      if (ex != null && ex.isConflict) _load(quiet: true);
    }
  }

  Future<void> _download(Map<String, dynamic> d) async {
    try {
      final String name = await widget.ctx.api.downloadRequestDocument(
          widget.requestId, text(d['id']),
          fallbackName: text(d['name'], fallback: 'document'));
      if (mounted) showExpenseMessage(context, 'Downloaded $name');
    } catch (e) {
      if (mounted) showExpenseMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget back = TextButton.icon(
      key: const Key('request-back'),
      onPressed: widget.onClose,
      icon: const Icon(Icons.arrow_back, size: 18),
      label: const Text('Back to list'),
    );
    if (_item == null) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            back,
            _error != null
                ? ExpenseErrorState(message: _error!, onRetry: _load)
                : const ExpenseSkeleton(rows: 5),
          ]);
    }
    final Map<String, dynamic> item = _item!;
    if (_editing) {
      return ExpenseRequestForm(
        key: ValueKey<String>('edit-${item['id']}-${item['revision']}'),
        ctx: widget.ctx,
        existing: item,
        onCancel: () => setState(() => _editing = false),
        onSaved: (Map<String, dynamic> updated) {
          setState(() {
            _editing = false;
            _item = updated;
          });
          widget.ctx.refreshNotifications?.call();
          _load(quiet: true);
        },
      );
    }
    final List<String> actions =
        asList(item['actions']).map((dynamic v) => '$v').toList();
    // Server returns request attachments and payment proof together.
    final Set<String> evidenceIds =
        asList(asMap(item['payment'])['evidenceDocumentIds'])
            .map((dynamic v) => '$v')
            .toSet();
    final List<Map<String, dynamic>> allDocs =
        asList(item['documents']).map(asMap).toList();
    final List<Map<String, dynamic>> docs = allDocs
        .where((Map<String, dynamic> d) => !evidenceIds.contains(text(d['id'])))
        .toList();
    final List<Map<String, dynamic>> evidenceDocs = allDocs
        .where((Map<String, dynamic> d) => evidenceIds.contains(text(d['id'])))
        .toList();
    final String rejection = text(asMap(item['rejection'])['reason']);
    final String cancellation = text(asMap(item['cancellation'])['reason']);
    final Map<String, dynamic> snapshot = asMap(item['approvalSnapshot']);
    final List<Map<String, dynamic>> steps =
        asList(snapshot['steps']).map(asMap).toList();
    final List<Map<String, dynamic>> approvals =
        asList(item['approvals']).map(asMap).toList();
    final List<Map<String, dynamic>> history =
        asList(item['reviewHistory']).map(asMap).toList();
    final Map<String, dynamic> payment = asMap(item['payment']);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          back,
          ExpensePanel(
            title: text(item['title'], fallback: 'Untitled draft'),
            subtitle:
                'Revision ${text(item['revision'])} · updated ${timestamp(item['updatedAt'])}',
            trailing: RequestStatusChip(text(item['status'])),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                      item['amountMinor'] == null
                          ? 'Amount not set'
                          : money(item['amountMinor']),
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: expInk,
                          letterSpacing: -0.4)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 22, runSpacing: 10, children: <Widget>[
                    _fact('Department', text(item['department'])),
                    _fact('Category', text(item['categoryName'])),
                    _fact('Requested by', text(item['createdByName'])),
                    _fact('Required date', text(item['requiredDate'])),
                    _fact('Vendor', text(item['vendorName'])),
                    _fact('Beneficiary', text(item['beneficiary'])),
                    _fact(
                        'Submitted',
                        item['submittedAt'] == null
                            ? ''
                            : timestamp(item['submittedAt'])),
                  ]),
                  const SizedBox(height: 12),
                  _para(
                      'Business justification', text(item['businessPurpose'])),
                  _para('Detailed description', text(item['description'])),
                  if (rejection.isNotEmpty)
                    _para('Rejection reason', rejection),
                  if (cancellation.isNotEmpty)
                    _para('Cancellation reason', cancellation),
                  if (text(item['evidenceExceptionReason']).isNotEmpty)
                    _para('Evidence exception',
                        text(item['evidenceExceptionReason'])),
                  if (text(item['status']) == 'APPROVED' && payment.isEmpty)
                    const ExpenseNotice(
                        'Approved. Payment has not been recorded yet. Approval does not move money; Finance records an external payment manually.'),
                  if (actions.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                      for (final String a in actions)
                        a == 'APPROVE' ||
                                a == 'SUBMIT' ||
                                a == 'PAY' ||
                                a == 'SEND_FOR_APPROVAL'
                            ? FilledButton(
                                key: Key('request-action-$a'),
                                onPressed: _busy ? null : () => _act(a),
                                style: FilledButton.styleFrom(
                                    backgroundColor: expGreen),
                                child: Text(
                                    _keys[a] != null && _actionError != null
                                        ? 'Retry ${requestActionLabels[a] ?? a}'
                                        : requestActionLabels[a] ?? a),
                              )
                            : OutlinedButton(
                                key: Key('request-action-$a'),
                                onPressed: _busy ? null : () => _act(a),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor:
                                        a == 'REJECT' || a == 'CANCEL'
                                            ? expDanger
                                            : expGreen),
                                child: Text(requestActionLabels[a] ?? a),
                              ),
                    ]),
                  ],
                  if (_actionError != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: ExpenseNotice(_actionError!,
                            tone: 'error',
                            key: const Key('request-action-error'))),
                ]),
          ),
          const SizedBox(height: 12),
          ExpensePanel(
            title: 'Attachments',
            subtitle: 'Private documents. Downloads are authenticated.',
            child: docs.isEmpty
                ? const Text('No documents attached.',
                    style: TextStyle(color: expMuted))
                : Column(children: <Widget>[
                    for (final Map<String, dynamic> d in docs) _docTile(d)
                  ]),
          ),
          const SizedBox(height: 12),
          ExpensePanel(
            title: 'Approval route',
            subtitle: snapshot.isEmpty
                ? 'Assigned when submitted'
                : 'Policy snapshot, version ${text(snapshot['policyVersion'])}',
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (steps.isEmpty)
                    const Text(
                        'No approval route yet. It is fixed from the active policy at submission.',
                        style: TextStyle(color: expMuted)),
                  for (int i = 0; i < steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Level ${i + 1} · ${text(steps[i]['label'], fallback: 'Review')} — ${asList(steps[i]['userIds']).length} primary, ${asList(steps[i]['backupUserIds']).length} backup reviewer(s)',
                        style: const TextStyle(color: expInk, fontSize: 12.5),
                      ),
                    ),
                  if (steps.isNotEmpty)
                    const Text(
                        'A primary or backup reviewer may complete a level; the first valid decision wins.',
                        style: TextStyle(color: expMuted, fontSize: 11.5)),
                  for (final Map<String, dynamic> a in approvals)
                    _historyRow(a),
                ]),
          ),
          const SizedBox(height: 12),
          ExpensePanel(
            title: 'Review history',
            subtitle:
                'Approval comments, rejection reasons and requests for information',
            child: history.isEmpty
                ? const Text('No review activity yet.',
                    style: TextStyle(color: expMuted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                        for (final Map<String, dynamic> h in history)
                          _historyRow(h)
                      ]),
          ),
          const SizedBox(height: 12),
          ExpensePanel(
            title: 'Payment status',
            subtitle: 'Manual bookkeeping record only',
            child: payment.isEmpty
                ? Text(
                    text(item['status']) == 'PAID'
                        ? 'Payment recorded.'
                        : 'No payment recorded.',
                    style: const TextStyle(color: expMuted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                        Wrap(spacing: 22, runSpacing: 10, children: <Widget>[
                          _fact(
                              'Amount paid',
                              payment['amountMinor'] == null
                                  ? text(payment['amount'])
                                  : money(payment['amountMinor'])),
                          _fact(
                              'Method',
                              paymentMethods[text(payment['method'])] ??
                                  text(payment['method'])),
                          _fact(
                              'Payment date',
                              text(payment['paidDate'],
                                  fallback: text(payment['date']))),
                          _fact('Reference', text(payment['reference'])),
                          _fact('Recipient', text(payment['recipient'])),
                          _fact('Recorded', timestamp(payment['recordedAt'])),
                        ]),
                        if (text(payment['comments']).isNotEmpty) ...<Widget>[
                          const SizedBox(height: 8),
                          _para('Bookkeeping note', text(payment['comments']))
                        ],
                        const Text('Proof of payment',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: expMuted,
                                fontSize: 12)),
                        for (final Map<String, dynamic> d in evidenceDocs)
                          _docTile(d),
                        const SizedBox(height: 6),
                        const Text(
                            'ServicePay did not execute this transfer and no customer wallet was debited.',
                            style: TextStyle(color: expMuted, fontSize: 11.5)),
                      ]),
          ),
          const SizedBox(height: 12),
          ExpensePanel(
            title: 'Audit trail',
            subtitle: 'Immutable events for this request',
            trailing: IconButton(
                tooltip: 'Reload',
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18)),
            child: _auditError != null
                ? ExpenseErrorState(message: _auditError!, onRetry: _load)
                : _audit.isEmpty
                    ? const Text('No audit events returned.',
                        style: TextStyle(color: expMuted))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                            for (final Map<String, dynamic> a in _audit)
                              _historyRow(a)
                          ]),
          ),
        ]);
  }

  Widget _docTile(Map<String, dynamic> d) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
            text(d['mimeType']) == 'application/pdf'
                ? Icons.picture_as_pdf_outlined
                : Icons.image_outlined,
            color: expGreen),
        title: Text(text(d['name'], fallback: 'Document'),
            overflow: TextOverflow.ellipsis),
        subtitle: Text(fileSize(d['size'])),
        trailing: IconButton(
            tooltip: 'Download',
            onPressed: () => _download(d),
            icon: const Icon(Icons.download_outlined)),
      );

  Widget _fact(String label, String value) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 120, maxWidth: 260),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label.toUpperCase(),
                  style: const TextStyle(
                      color: expMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6)),
              const SizedBox(height: 2),
              Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(
                      color: expInk,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
      );

  Widget _para(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label.toUpperCase(),
                  style: const TextStyle(
                      color: expMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6)),
              const SizedBox(height: 2),
              Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(color: expInk, fontSize: 13)),
            ]),
      );

  Widget _historyRow(Map<String, dynamic> h) {
    final String action = text(h['action'],
        fallback:
            text(h['decision'], fallback: text(h['type'], fallback: 'Event')));
    final String who = text(h['actorName'],
        fallback: text(h['byName'], fallback: text(h['actorId'])));
    final String note = text(h['reason'], fallback: text(h['comments']));
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(left: 10),
      decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: expLine, width: 3))),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
                '${requestActionLabels[action] ?? requestStatusLabels[action] ?? action}${who.isEmpty ? '' : ' · $who'}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: expInk,
                    fontSize: 12.5)),
            if (note.isNotEmpty)
              Text(note, style: const TextStyle(color: expInk, fontSize: 12.5)),
            if (text(h['comments']).isNotEmpty && text(h['comments']) != note)
              Text(text(h['comments']),
                  style: const TextStyle(color: expInk, fontSize: 12.5)),
            Text(timestamp(h['at'] ?? h['createdAt'] ?? h['decidedAt']),
                style: const TextStyle(color: expMuted, fontSize: 11)),
          ]),
    );
  }
}
