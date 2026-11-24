import 'dart:convert';

import 'package:flutter/material.dart';

import 'expense_api.dart';
import 'expense_common.dart';
import 'expense_documents.dart';
import 'expense_management_screen.dart';

part 'expense_request_detail.dart';
part 'expense_request_form.dart';
part 'expense_request_payment.dart';

/// Department expense request portal: own requests, department history,
/// assigned reviews, approved queue and manual payment records.

const Map<String, String> requestStatusLabels = <String, String>{
  'DRAFT': 'Draft',
  'SUBMITTED': 'Submitted',
  'UNDER_REVIEW': 'Under review',
  'PENDING_APPROVAL': 'Pending approval',
  'APPROVED': 'Approved',
  'REJECTED': 'Rejected',
  'CHANGES_REQUESTED': 'Changes requested',
  'PAID': 'Payment recorded',
  'CANCELLED': 'Cancelled',
};

const Map<String, String> requestActionLabels = <String, String>{
  'EDIT': 'Edit request',
  'SUBMIT': 'Submit for approval',
  'BEGIN_REVIEW': 'Begin review',
  'SEND_FOR_APPROVAL': 'Send for approval',
  'APPROVE': 'Approve',
  'REJECT': 'Reject',
  'REQUEST_CHANGES': 'Request more information',
  'CANCEL': 'Cancel request',
  'PAY': 'Record payment',
};

/// Converts a validated decimal NGN string to integer kobo.
int? decimalToMinor(String raw) {
  final String s = raw.trim().replaceAll(',', '');
  if (!amountPattern.hasMatch(s)) return null;
  final List<String> parts = s.split('.');
  final String frac = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  return int.parse(parts[0]) * 100 + int.parse(frac);
}

class RequestStatusChip extends StatelessWidget {
  const RequestStatusChip(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      'APPROVED' => (const Color(0xffdcefe5), expGreen),
      'PAID' => (const Color(0xffcfe6dc), expInk),
      'REJECTED' => (const Color(0xfff6e1df), expDanger),
      'CANCELLED' => (const Color(0xffeceeed), const Color(0xff56625d)),
      'PENDING_APPROVAL' || 'UNDER_REVIEW' || 'CHANGES_REQUESTED' => (
          const Color(0xfffff4de),
          expAmber
        ),
      _ => (expSoft, const Color(0xff466158)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(requestStatusLabels[status] ?? status,
          style:
              TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

// ---------------- Notifications ----------------

class RequestNotificationsPanel extends StatelessWidget {
  const RequestNotificationsPanel({super.key, required this.ctx});
  final ExpenseModuleContext ctx;
  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> n = ctx.notifications;
    if (n.isEmpty) return const SizedBox.shrink();
    final int pending = asInt(n['pendingCount']) ?? 0;
    final List<Map<String, dynamic>> items =
        asList(n['items']).map(asMap).take(5).toList();
    return Container(
      key: const Key('request-notifications'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: expCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: expLine)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              const Icon(Icons.notifications_none_rounded,
                  size: 18, color: expGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pending == 0
                      ? 'No requests need your action'
                      : '$pending request${pending == 1 ? '' : 's'} need${pending == 1 ? 's' : ''} your action',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: expInk),
                ),
              ),
              if (ctx.refreshNotifications != null)
                IconButton(
                  tooltip: 'Refresh notifications',
                  onPressed: () => ctx.refreshNotifications!(),
                  icon: const Icon(Icons.refresh, size: 18),
                ),
            ]),
            for (final Map<String, dynamic> i in items)
              InkWell(
                onTap: text(i['requestId']).isEmpty
                    ? null
                    : () => ctx.openRequest(text(i['requestId'])),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: <Widget>[
                    Expanded(
                      child: Text(
                          '${text(i['title'], fallback: 'Expense request')} · ${timestamp(i['updatedAt'])}',
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontSize: 12.5, color: expInk)),
                    ),
                    const SizedBox(width: 8),
                    RequestStatusChip(text(i['status'])),
                  ]),
                ),
              ),
          ]),
    );
  }
}

// ---------------- Lists ----------------

class ExpenseRequestList extends StatefulWidget {
  const ExpenseRequestList(
      {super.key,
      required this.ctx,
      required this.scope,
      this.emptyTitle = 'No requests',
      this.emptyMessage = ''});
  final ExpenseModuleContext ctx;
  final String scope;
  final String emptyTitle;
  final String emptyMessage;
  @override
  State<ExpenseRequestList> createState() => _ExpenseRequestListState();
}

class _ExpenseRequestListState extends State<ExpenseRequestList> {
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _hasMore = false;
  int _page = 1;
  int _total = 0;
  String? _error;
  String _status = '';
  String _department = '';
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void didUpdateWidget(ExpenseRequestList old) {
    super.didUpdateWidget(old);
    if (old.ctx.notificationsTick != widget.ctx.notificationsTick ||
        old.scope != widget.scope) {
      _load(reset: true, quiet: true);
    }
  }

  Future<void> _load({bool reset = false, bool quiet = false}) async {
    final int r = ++_req;
    final int page = reset ? 1 : _page + 1;
    setState(() {
      if (!quiet) _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> data = await widget.ctx.api.listRequests(
        scope: widget.scope,
        page: page,
        status: _status,
        department: _department,
      );
      if (!mounted || r != _req) return;
      final List<Map<String, dynamic>> rows =
          asList(data['items']).map(asMap).toList();
      setState(() {
        _items = reset ? rows : <Map<String, dynamic>>[..._items, ...rows];
        _page = page;
        _hasMore = data['hasMore'] == true;
        _total = asInt(data['total']) ?? _items.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || r != _req) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> departments = widget.ctx.requestDepartments;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    key: Key('request-status-filter-${widget.scope}'),
                    value: _status,
                    isExpanded: true,
                    decoration: expInput('Status'),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                          value: '', child: Text('All statuses')),
                      for (final MapEntry<String, String> e
                          in requestStatusLabels.entries)
                        DropdownMenuItem<String>(
                            value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (String? v) {
                      _status = v ?? '';
                      _load(reset: true);
                    },
                  ),
                ),
                if (widget.scope != 'my' && departments.length > 1)
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      value: _department,
                      isExpanded: true,
                      decoration: expInput('Department'),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem<String>(
                            value: '', child: Text('All departments')),
                        for (final String d in departments)
                          DropdownMenuItem<String>(value: d, child: Text(d)),
                      ],
                      onChanged: (String? v) {
                        _department = v ?? '';
                        _load(reset: true);
                      },
                    ),
                  ),
                OutlinedButton.icon(
                    onPressed: () => _load(reset: true),
                    icon: const Icon(Icons.refresh, size: 17),
                    label: const Text('Refresh')),
                if (!_loading && _error == null)
                  Text('$_total record${_total == 1 ? '' : 's'}',
                      style: const TextStyle(color: expMuted, fontSize: 12)),
              ]),
          const SizedBox(height: 12),
          if (_loading && _items.isEmpty)
            const ExpenseSkeleton(rows: 4)
          else if (_error != null && _items.isEmpty)
            ExpenseErrorState(
                message: _error!, onRetry: () => _load(reset: true))
          else if (_items.isEmpty)
            ExpenseEmptyState(
                icon: Icons.inbox_outlined,
                title: widget.emptyTitle,
                message: widget.emptyMessage)
          else ...<Widget>[
            for (final Map<String, dynamic> item in _items)
              _RequestCard(
                  item: item,
                  onTap: () => widget.ctx.openRequest(text(item['id']))),
            if (_error != null) ExpenseNotice(_error!, tone: 'error'),
            if (_hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                    onPressed: _loading ? null : () => _load(),
                    child: Text(_loading ? 'Loading...' : 'Load more')),
              ),
          ],
        ]);
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final List<String> actions =
        asList(item['actions']).map((dynamic v) => '$v').toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: expCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: expLine)),
        child: InkWell(
          key: Key('request-row-${text(item['id'])}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                              text(item['title'], fallback: 'Untitled draft'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: expInk,
                                  fontSize: 14)),
                        ),
                        const SizedBox(width: 8),
                        RequestStatusChip(text(item['status'])),
                      ]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 14, runSpacing: 4, children: <Widget>[
                    Text(
                        item['amountMinor'] == null
                            ? 'Amount not set'
                            : money(item['amountMinor']),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: expGreen,
                            fontSize: 13)),
                    if (text(item['department']).isNotEmpty)
                      _meta(Icons.apartment_outlined, text(item['department'])),
                    if (text(item['createdByName']).isNotEmpty)
                      _meta(Icons.person_outline, text(item['createdByName'])),
                    if (text(item['requiredDate']).isNotEmpty)
                      _meta(Icons.event_outlined,
                          'Needed ${text(item['requiredDate'])}'),
                    _meta(Icons.update, timestamp(item['updatedAt'])),
                  ]),
                  if (actions.any((String a) => a != 'EDIT')) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                        'Awaiting you: ${actions.where((String a) => a != 'EDIT').map((String a) => requestActionLabels[a] ?? a).join(', ')}',
                        style: const TextStyle(
                            color: expAmber,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                  ],
                ]),
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(icon, size: 14, color: expMuted),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: expMuted, fontSize: 12)),
      ]);
}

// ---------------- Sections ----------------

class MyExpenseRequestsSection extends StatefulWidget {
  const MyExpenseRequestsSection({super.key, required this.ctx});
  final ExpenseModuleContext ctx;
  @override
  State<MyExpenseRequestsSection> createState() =>
      _MyExpenseRequestsSectionState();
}

class _MyExpenseRequestsSectionState extends State<MyExpenseRequestsSection> {
  bool _composing = false;
  int _listVersion = 0;

  @override
  Widget build(BuildContext context) {
    final ExpenseModuleContext ctx = widget.ctx;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          RequestNotificationsPanel(ctx: ctx),
          if (!ctx.canCreateRequests)
            const ExpenseNotice(
                'You can view your request history, but submitting new requests requires expenses.requests.create.',
                tone: 'warn')
          else if (_composing)
            ExpenseRequestForm(
              key: const ValueKey<String>('new-request'),
              ctx: ctx,
              onCancel: () => setState(() => _composing = false),
              onSaved: (Map<String, dynamic> item) {
                setState(() {
                  _composing = false;
                  _listVersion++;
                });
                ctx.refreshNotifications?.call();
                ctx.openRequest(text(item['id']));
              },
            )
          else
            Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  FilledButton.icon(
                    key: const Key('request-new'),
                    onPressed: () => setState(() => _composing = true),
                    style: FilledButton.styleFrom(backgroundColor: expGreen),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New expense request'),
                  ),
                  const Text(
                      'Request operational funds. Finance records any payment separately after approval.',
                      style: TextStyle(color: expMuted, fontSize: 12)),
                ]),
          const SizedBox(height: 16),
          ExpenseRequestList(
            key: ValueKey<String>('my-$_listVersion'),
            ctx: ctx,
            scope: 'my',
            emptyTitle: 'No expense requests yet',
            emptyMessage:
                'Drafts and submitted requests you create appear here with their approval comments and payment status.',
          ),
        ]);
  }
}

class RequestScopeSection extends StatelessWidget {
  const RequestScopeSection(
      {super.key, required this.ctx, required this.scope});
  final ExpenseModuleContext ctx;
  final String scope;
  @override
  Widget build(BuildContext context) {
    final (String note, String empty, String emptyMsg) = switch (scope) {
      'department' => (
          'Request history for ${ctx.department.isEmpty ? 'your department' : ctx.department}. Viewing department requests does not grant finance totals, vendors or reports.',
          'No department requests',
          'Requests raised by your department appear here once created.'
        ),
      'approved' => (
          'Approved requests awaiting manual payment recording, and their approval trail.',
          'No approved requests',
          'Requests appear here after every approval level is complete.'
        ),
      'payments' => (
          'Payment records are manual bookkeeping entries. ServicePay did not execute any transfer and no customer wallet was debited.',
          'No payment records',
          'Recorded payments with proof of payment appear here.'
        ),
      _ => (
          'Department requests assigned to you as a primary or backup reviewer. The first valid decision at a level completes it.',
          'Nothing assigned to you',
          'When a request reaches a level you are assigned to, it appears here.'
        ),
    };
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (scope == 'assigned' || scope == 'department')
            RequestNotificationsPanel(ctx: ctx),
          ExpenseNotice(note),
          const SizedBox(height: 12),
          ExpenseRequestList(
              key: ValueKey<String>('scope-$scope'),
              ctx: ctx,
              scope: scope,
              emptyTitle: empty,
              emptyMessage: emptyMsg),
        ]);
  }
}
