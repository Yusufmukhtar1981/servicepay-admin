import 'package:flutter/material.dart';

import 'expense_action_dialogs.dart';
import 'expense_api.dart';
import 'expense_audit_section.dart';
import 'expense_common.dart';
import 'expense_documents.dart';
import 'expense_form_section.dart';
import 'expense_management_screen.dart';

const Map<String, String> _actionPermission = <String, String>{
  'EDIT': ExpensePermissions.update,
  'SUBMIT': ExpensePermissions.create,
  'APPROVE': ExpensePermissions.approve,
  'REJECT': ExpensePermissions.approve,
  'PAY': ExpensePermissions.pay,
  'CANCEL': ExpensePermissions.cancel,
  'REVERSE': ExpensePermissions.cancel,
};

class _PendingAction {
  _PendingAction(this.action, this.key, this.reason, {this.comments, this.payment, this.reversal});
  final String action;
  final String key;
  final String reason;
  final String? comments;
  final Map<String, dynamic>? payment;
  final Map<String, dynamic>? reversal;
}

class ExpenseDetailView extends StatefulWidget {
  const ExpenseDetailView({super.key, required this.ctx, required this.expenseId, required this.onClose});
  final ExpenseModuleContext ctx;
  final String expenseId;
  final VoidCallback onClose;
  @override
  State<ExpenseDetailView> createState() => _ExpenseDetailViewState();
}

class _ExpenseDetailViewState extends State<ExpenseDetailView> {
  Map<String, dynamic>? _item;
  String? _error;
  bool _loading = true;
  bool _editing = false;
  bool _acting = false;
  String? _actionError;
  _PendingAction? _pending; // retained until a definitive result
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final int request = ++_request;
    setState(() {
      _loading = _item == null;
      _error = null;
    });
    try {
      final Map<String, dynamic> data = await widget.ctx.api.expense(widget.expenseId);
      if (!mounted || request != _request) return;
      setState(() {
        _item = asMap(data['item']);
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

  bool get _isOwn {
    final String me = widget.ctx.access.actorId;
    return me.isNotEmpty && (text(_item?['createdBy']) == me || text(_item?['submittedBy']) == me);
  }

  bool get _alreadyApprovedByMe {
    final String me = widget.ctx.access.actorId;
    return me.isNotEmpty && asList(_item?['approvals']).any((dynamic a) => text(asMap(a)['actorId']) == me);
  }

  List<String> get _actions {
    final List<String> returned = asList(_item?['actions']).map((dynamic a) => '$a').toList();
    return returned.where((String a) {
      final String? p = _actionPermission[a];
      if (p == null || !widget.ctx.access.has(p)) return false;
      // Reversal of a paid record needs both cancel and pay authority.
      if (a == 'REVERSE' && !widget.ctx.access.has(ExpensePermissions.pay)) return false;
      if ((a == 'APPROVE' || a == 'REJECT') && (_isOwn || _alreadyApprovedByMe)) return false;
      return true;
    }).toList();
  }

  Future<void> _startAction(String action) async {
    final Map<String, dynamic> item = _item!;
    if (action == 'EDIT') {
      setState(() => _editing = true);
      return;
    }
    if (action == 'PAY' || action == 'REVERSE') {
      final ExpenseSettlementInput? input = await showSettlementDialog(
        context,
        reverse: action == 'REVERSE',
        api: widget.ctx.api,
        expenseDocuments: asList(item['documents']).map(asMap).toList(),
        maxBytes: widget.ctx.maxDocumentBytes,
        maxDocuments: widget.ctx.maxDocuments,
        amountLabel: money(item['amountMinor']),
      );
      if (input == null || !mounted) return;
      await _run(_PendingAction(action, ExpenseIdempotency.newKey('act'), input.reason,
          comments: input.comments,
          payment: action == 'PAY' ? input.details : null,
          reversal: action == 'REVERSE' ? input.details : null));
      return;
    }
    final (String title, String message, String label, bool danger) = switch (action) {
      'SUBMIT' => ('Submit for approval', 'The configured approval policy will be snapshotted for this expense.', 'Submit', false),
      'APPROVE' => ('Approve this step', 'Your approval, the time and your comments are recorded. You cannot approve your own request.', 'Approve', false),
      'REJECT' => ('Reject expense', 'The submitter will see this reason. The record is kept.', 'Reject', true),
      _ => ('Cancel expense', 'Cancellation is permanent and audited. The record is never deleted.', 'Cancel expense', true),
    };
    final String? reason = await askReason(context, title: title, message: message, confirmLabel: label, destructive: danger);
    if (reason == null || !mounted) return;
    await _run(_PendingAction(action, ExpenseIdempotency.newKey('act'), reason,
        comments: action == 'APPROVE' || action == 'REJECT' ? reason : null));
  }

  Future<void> _run(_PendingAction p) async {
    setState(() {
      _acting = true;
      _actionError = null;
      _pending = p;
    });
    try {
      final Map<String, dynamic> result = await widget.ctx.api.expenseAction(
        text(_item!['id']),
        action: p.action,
        expectedVersion: asInt(_item!['revision']) ?? 0,
        reason: p.reason,
        comments: p.comments,
        payment: p.payment,
        reversal: p.reversal,
        idempotencyKey: p.key,
      );
      if (!mounted) return;
      setState(() {
        _item = asMap(result['item']);
        _pending = null;
        _acting = false;
      });
      showExpenseMessage(context, p.action == 'PAY' ? 'Payment recorded manually. No funds were moved by ServicePay.' : 'Action recorded.');
    } catch (e) {
      if (!mounted) return;
      final ExpenseApiException? ex = e is ExpenseApiException ? e : null;
      setState(() {
        _acting = false;
        _actionError = errorText(e);
        if (ex == null || !ex.outcomeUnknown) _pending = null;
      });
      if (ex != null && ex.isConflict) await _load();
    }
  }

  Future<void> _download(Map<String, dynamic> d) async {
    try {
      final String name = await widget.ctx.api.downloadDocument(text(d['id']), fallbackName: text(d['name'], fallback: 'document'));
      if (mounted) showExpenseMessage(context, 'Downloaded $name.');
    } catch (e) {
      if (mounted) showExpenseMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget back = TextButton.icon(onPressed: widget.onClose, icon: const Icon(Icons.arrow_back, size: 18), label: const Text('Back to list'));
    if (_loading) return const ExpenseSkeleton(rows: 6);
    if (_item == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[back, ExpenseErrorState(message: _error ?? 'Expense not found.', onRetry: _load)]);
    }
    final Map<String, dynamic> e = _item!;
    if (_editing) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        ExpenseNotice('Editing ${text(e['title'])} (revision ${text(e['revision'])}). Status and approval data cannot be changed here.'),
        const SizedBox(height: 12),
        ExpenseFormSection(
          ctx: widget.ctx,
          existing: e,
          onCancel: () => setState(() => _editing = false),
          onConflict: _load,
          onSaved: (Map<String, dynamic> item) => setState(() {
            _item = item;
            _editing = false;
          }),
        ),
      ]);
    }
    final bool canDownload = widget.ctx.access.has(ExpensePermissions.documents);
    final List<String> actions = _actions;
    final Map<String, dynamic> exception = asMap(e['evidenceException']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
        back,
        OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 17), label: const Text('Reload record')),
      ]),
      const SizedBox(height: 8),
      ExpensePanel(
        title: text(e['title'], fallback: 'Untitled expense'),
        subtitle: '${money(e['amountMinor'], currency: text(e['currency'], fallback: 'NGN'))} · ${text(e['expenseDate'])} · revision ${text(e['revision'])}',
        trailing: ExpenseStatusChip(text(e['status'])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          _facts(<(String, String)>[
            ('Category', text(e['categoryName'], fallback: text(e['categoryId']))),
            ('Payment method', paymentMethods[text(e['paymentMethod'])] ?? text(e['paymentMethod'])),
            ('Vendor', text(e['vendorName'], fallback: '—')),
            ('Beneficiary', text(e['vendorName']).isNotEmpty ? text(e['vendorName']) : text(e['beneficiary'], fallback: '—')),
            ('Reference', text(e['reference'])),
            ('Department', text(e['department'], fallback: '—')),
            ('Branch', text(e['branch'], fallback: '—')),
            ('Created by', '${text(e['createdByName'], fallback: text(e['createdBy']))} · ${timestamp(e['createdAt'])}'),
            ('Submitted', text(e['submittedAt']).isEmpty ? 'Not yet submitted' : '${text(e['submittedBy'])} · ${timestamp(e['submittedAt'])}'),
            ('Last updated', timestamp(e['updatedAt'])),
          ]),
          const SizedBox(height: 10),
          _long('Description', text(e['description'])),
          _long('Business purpose', text(e['businessPurpose'])),
        ]),
      ),
      const SizedBox(height: 12),
      ExpensePanel(
        title: 'Actions',
        subtitle: 'Only actions allowed by the server and your explicit permissions are shown. The server re-checks every action.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          if (_isOwn && asList(e['actions']).contains('APPROVE'))
            const Padding(padding: EdgeInsets.only(bottom: 8), child: ExpenseNotice('You created or submitted this expense, so you cannot approve or reject it.')),
          if (_pending != null && !_acting) ...<Widget>[
            ExpenseNotice('The ${_pending!.action} request has an unknown outcome. Reload to check, or retry the identical operation; it cannot be applied twice.', tone: 'warn'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: <Widget>[
              FilledButton(onPressed: () => _run(_pending!), style: FilledButton.styleFrom(backgroundColor: expGreen), child: const Text('Retry same operation')),
              TextButton(onPressed: () {
                setState(() => _pending = null);
                _load();
              }, child: const Text('Discard and reload')),
            ]),
            const SizedBox(height: 8),
          ],
          if (_actionError != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: ExpenseNotice(_actionError!, tone: 'error')),
          if (actions.isEmpty)
            const Text('No actions are available to you for this record.', style: TextStyle(color: expMuted))
          else
            Wrap(spacing: 8, runSpacing: 8, children: actions.map((String a) {
              final bool danger = a == 'REJECT' || a == 'CANCEL' || a == 'REVERSE';
              final String label = switch (a) {
                'EDIT' => 'Edit',
                'SUBMIT' => 'Submit for approval',
                'APPROVE' => 'Approve',
                'REJECT' => 'Reject',
                'PAY' => 'Mark paid (manual record)',
                'CANCEL' => 'Cancel',
                _ => 'Record reversal',
              };
              return danger
                  ? OutlinedButton(key: Key('expense-action-$a'), onPressed: _acting || _pending != null ? null : () => _startAction(a), style: OutlinedButton.styleFrom(foregroundColor: expDanger), child: Text(label))
                  : FilledButton(key: Key('expense-action-$a'), onPressed: _acting || _pending != null ? null : () => _startAction(a), style: FilledButton.styleFrom(backgroundColor: expGreen), child: Text(label));
            }).toList()),
          if (_acting) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 3, color: expGreen)),
        ]),
      ),
      const SizedBox(height: 12),
      ExpensePanel(
        title: 'Supporting evidence',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          if (text(exception['reason']).isNotEmpty)
            ExpenseNotice('Evidence exception: ${text(exception['reason'])}\nAuthorized by ${text(exception['authorizedBy'])} at ${timestamp(exception['authorizedAt'])}', tone: 'warn'),
          if (asList(e['documents']).isEmpty && text(exception['reason']).isEmpty) const Text('No documents attached.', style: TextStyle(color: expMuted)),
          for (final Map<String, dynamic> d in asList(e['documents']).map(asMap))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined, color: expGreen),
              title: Text(text(d['name'], fallback: 'Document'), overflow: TextOverflow.ellipsis),
              subtitle: SelectableText('${text(d['mimeType'])} · ${fileSize(d['size'])} · SHA-256 ${text(d['sha256'])}', style: const TextStyle(fontSize: 11)),
              trailing: canDownload
                  ? IconButton(tooltip: 'Download (authenticated)', onPressed: () => _download(d), icon: const Icon(Icons.download_outlined))
                  : const Tooltip(message: 'Requires expenses.documents', child: Icon(Icons.lock_outline, size: 18)),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      _approvalPanel(e),
      if (asMap(e['payment']).isNotEmpty || asMap(e['reversal']).isNotEmpty || asMap(e['cancellation']).isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        ExpensePanel(
          title: 'Settlement records',
          subtitle: 'Manual company records only; not provider-verified.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            if (asMap(e['payment']).isNotEmpty) _record('Payment recorded', asMap(e['payment'])),
            if (asMap(e['reversal']).isNotEmpty) _record('Reversal recorded', asMap(e['reversal'])),
            if (asMap(e['cancellation']).isNotEmpty) _record('Cancellation', asMap(e['cancellation'])),
          ]),
        ),
      ],
      if (widget.ctx.access.has(ExpensePermissions.audit)) ...<Widget>[
        const SizedBox(height: 12),
        ExpensePanel(title: 'Audit history', child: ExpenseAuditList(ctx: widget.ctx, expenseId: text(e['id']))),
      ],
    ]);
  }

  Widget _approvalPanel(Map<String, dynamic> e) {
    final Map<String, dynamic> snap = asMap(e['approvalSnapshot']);
    final List<Map<String, dynamic>> steps = asList(snap['steps']).map(asMap).toList();
    final List<Map<String, dynamic>> approvals = asList(e['approvals']).map(asMap).toList();
    return ExpensePanel(
      title: 'Approval chain',
      subtitle: steps.isEmpty ? 'Policy is snapshotted when the expense is submitted.' : 'Policy revision ${text(snap['policyVersion'])}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        if (steps.isEmpty) const Text('Not yet submitted for approval.', style: TextStyle(color: expMuted)),
        for (int i = 0; i < steps.length; i++)
          Builder(builder: (BuildContext context) {
            final Map<String, dynamic>? done = approvals.length > i ? approvals[i] : null;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(done != null ? Icons.check_circle : Icons.radio_button_unchecked, color: done != null ? expGreen : expMuted),
              title: Text('Step ${i + 1}: ${text(steps[i]['label'])}'),
              subtitle: SelectableText(done == null
                  ? 'Awaiting a distinct authorized reviewer'
                  : '${text(done['actorName'], fallback: text(done['actorId']))} · ${timestamp(done['at'])}${text(done['comments']).isEmpty ? '' : '\n"${text(done['comments'])}"'}'),
            );
          }),
      ]),
    );
  }

  Widget _record(String title, Map<String, dynamic> r) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: expInk)),
          SelectableText(
            r.entries
                .where((MapEntry<String, dynamic> x) => x.value != null && '${x.value}'.isNotEmpty)
                .map((MapEntry<String, dynamic> x) => '${x.key}: ${x.key.endsWith('At') ? timestamp(x.value) : x.value}')
                .join('\n'),
            style: const TextStyle(fontSize: 12, color: expMuted, height: 1.4),
          ),
        ]),
      );

  Widget _facts(List<(String, String)> facts) => LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final double w = c.maxWidth < 560 ? c.maxWidth : (c.maxWidth - 16) / 2;
        return Wrap(spacing: 16, runSpacing: 10, children: <Widget>[
          for (final (String, String) f in facts)
            SizedBox(
              width: w,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(f.$1.toUpperCase(), style: const TextStyle(color: Color(0xff687b73), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                SelectableText(f.$2, style: const TextStyle(color: expInk, fontSize: 13)),
              ]),
            ),
        ]);
      });

  Widget _long(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(label.toUpperCase(), style: const TextStyle(color: Color(0xff687b73), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          SelectableText(value.isEmpty ? '—' : value, style: const TextStyle(color: expInk, fontSize: 13, height: 1.4)),
        ]),
      );
}
