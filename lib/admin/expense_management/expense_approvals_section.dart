import 'package:flutter/material.dart';

import 'expense_api.dart';
import 'expense_common.dart';
import 'expense_list_section.dart';
import 'expense_management_screen.dart';
import 'expense_requests_section.dart';

class ExpenseApprovalsSection extends StatelessWidget {
  const ExpenseApprovalsSection({super.key, required this.ctx});
  final ExpenseModuleContext ctx;

  @override
  Widget build(BuildContext context) {
    final ExpenseAccess a = ctx.access;
    if (!ctx.financeAccess) {
      // Request reviewers without finance-wide access see only assigned requests.
      return RequestScopeSection(ctx: ctx, scope: 'assigned');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      if (ctx.canReviewRequests) ...<Widget>[
        const Text('Assigned department requests', style: TextStyle(fontWeight: FontWeight.w800, color: expInk, fontSize: 15)),
        const SizedBox(height: 8),
        RequestScopeSection(ctx: ctx, scope: 'assigned'),
        const SizedBox(height: 18),
        const Text('Legacy expense approvals', style: TextStyle(fontWeight: FontWeight.w800, color: expInk, fontSize: 15)),
        const SizedBox(height: 8),
      ],
      if (ctx.canConfigurePolicies) ...<Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => ctx.goTo('policies'),
            icon: const Icon(Icons.rule_outlined, size: 17),
            label: const Text('Department request policies are configured in Approval Policy Configuration'),
          ),
        ),
        const SizedBox(height: 6),
      ],
      if (a.has(ExpensePermissions.approve)) ...<Widget>[
        const ExpenseNotice('Expenses awaiting review. You only see Approve or Reject on records where you are the authorized reviewer for the current step and are not the submitter.'),
        const SizedBox(height: 12),
        ExpenseListSection(ctx: ctx, fixedStatus: 'PENDING_APPROVAL', showFilters: false),
      ] else
        const ExpenseNotice('Reviewing expenses requires the explicit permission expenses.approve.'),
      const SizedBox(height: 18),
      if (a.canManagePolicy)
        ExpensePolicyEditor(ctx: ctx)
      else if (a.has(ExpensePermissions.policy))
        const ExpenseNotice('Approval policy configuration is restricted to the HEAD_OFFICE role together with expenses.manage_policy.', tone: 'warn')
      else
        ExpenseNotice(ctx.workflowConfigured
            ? 'An approval policy is configured. Changing it requires expenses.manage_policy and the HEAD_OFFICE role.'
            : 'No approval policy is configured, so expenses cannot be submitted. A HEAD_OFFICE user with expenses.manage_policy must configure reviewers.'),
    ]);
  }
}

class _StepDraft {
  _StepDraft({String label = '', Set<String>? users, Set<String>? roles})
      : label = TextEditingController(text: label),
        users = users ?? <String>{},
        roles = roles ?? <String>{};
  final TextEditingController label;
  final Set<String> users;
  final Set<String> roles;
}

class ExpensePolicyEditor extends StatefulWidget {
  const ExpensePolicyEditor({super.key, required this.ctx});
  final ExpenseModuleContext ctx;
  @override
  State<ExpensePolicyEditor> createState() => _ExpensePolicyEditorState();
}

class _ExpensePolicyEditorState extends State<ExpensePolicyEditor> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  Map<String, dynamic>? _policy;
  bool _loaded = false;
  String? _error;
  bool _saving = false;
  String? _saveError;
  String? _key; // retained until definitive result
  List<_StepDraft> _steps = <_StepDraft>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final _StepDraft s in _steps) {
      s.label.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _loaded = false;
    });
    try {
      final Map<String, dynamic> data = await widget.ctx.api.policy();
      if (!mounted) return;
      final Map<String, dynamic>? p = data['policy'] is Map ? asMap(data['policy']) : null;
      for (final _StepDraft s in _steps) {
        s.label.dispose();
      }
      setState(() {
        _policy = p;
        _steps = asList(p?['approvalSteps']).map(asMap).map((Map<String, dynamic> s) => _StepDraft(
              label: text(s['label']),
              users: asList(s['userIds']).map((dynamic v) => '$v').toSet(),
              roles: asList(s['roleIds']).map((dynamic v) => '$v').toSet(),
            )).toList();
        _loaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _save() async {
    String? problem;
    if (_steps.isEmpty || _steps.length > 8) problem = 'Configure between one and eight approval steps.';
    for (int i = 0; i < _steps.length && problem == null; i++) {
      if (_steps[i].users.isEmpty && _steps[i].roles.isEmpty) problem = 'Step ${i + 1} needs at least one approver user or role.';
    }
    final bool ok = _form.currentState?.validate() ?? false;
    setState(() => _saveError = problem);
    if (!ok || problem != null) return;
    final String? reason = await askReason(context,
        title: 'Save approval policy', message: 'Only expenses submitted after saving use the new policy. Existing submissions keep their snapshot.', confirmLabel: 'Save policy');
    if (reason == null || !mounted) return;
    _key ??= ExpenseIdempotency.newKey('pol');
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> result = await widget.ctx.api.savePolicy(
        expectedVersion: _policy == null ? -1 : (asInt(_policy!['revision']) ?? 0),
        approvalSteps: _steps
            .map((_StepDraft s) => <String, dynamic>{'label': s.label.text.trim(), 'userIds': s.users.toList(), 'roleIds': s.roles.toList()})
            .toList(),
        reason: reason,
        idempotencyKey: _key!,
      );
      _key = null;
      if (!mounted) return;
      setState(() {
        _saving = false;
        _policy = asMap(result['policy']);
      });
      showExpenseMessage(context, 'Approval policy saved.');
    } catch (e) {
      final ExpenseApiException? ex = e is ExpenseApiException ? e : null;
      if (ex == null || !ex.outcomeUnknown) _key = null;
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = errorText(e);
      });
      if (ex != null && ex.isConflict) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> approvers = asMap(widget.ctx.references['approvers']);
    final List<Map<String, dynamic>> users = asList(approvers['users']).map(asMap).toList();
    final List<Map<String, dynamic>> roles = asList(approvers['roles']).map(asMap).toList();
    return ExpensePanel(
      title: 'Approval policy',
      subtitle: _policy == null ? 'Not configured' : 'Revision ${text(_policy!['revision'])}',
      trailing: OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 17), label: const Text('Reload policy')),
      child: !_loaded
          ? (_error != null ? ExpenseErrorState(message: _error!, onRetry: _load) : const ExpenseSkeleton(rows: 2))
          : Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                const ExpenseNotice('Each step needs a distinct reviewer. Submitters can never approve their own expense, and one person cannot approve two steps.'),
                if (_policy == null) ...<Widget>[
                  const SizedBox(height: 8),
                  const ExpenseNotice('No policy is configured. Expenses cannot enter approval until you save one.', tone: 'warn'),
                ],
                if (users.isEmpty && roles.isEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  const ExpenseNotice('The server returned no eligible approver users or roles. Assign expenses.approve to staff first.', tone: 'warn'),
                ],
                const SizedBox(height: 12),
                for (int i = 0; i < _steps.length; i++) _stepCard(i, users, roles),
                Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _steps.length >= 8 || _saving ? null : () => setState(() => _steps.add(_StepDraft())),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('Add step (${_steps.length}/8)'),
                  ),
                  FilledButton.icon(
                    key: const Key('policy-save'),
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(backgroundColor: expGreen),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(_saving ? 'Saving...' : _key != null ? 'Retry save (same operation)' : 'Save policy'),
                  ),
                ]),
                if (_saveError != null) Padding(padding: const EdgeInsets.only(top: 8), child: ExpenseNotice(_saveError!, tone: 'error')),
              ]),
            ),
    );
  }

  Widget _stepCard(int i, List<Map<String, dynamic>> users, List<Map<String, dynamic>> roles) {
    final _StepDraft s = _steps[i];
    // Keep previously assigned IDs visible even if no longer returned.
    final Set<String> knownUsers = users.map((Map<String, dynamic> u) => text(u['id'])).toSet();
    final Set<String> knownRoles = roles.map((Map<String, dynamic> r) => text(r['id'])).toSet();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: expSoft, borderRadius: BorderRadius.circular(8), border: Border.all(color: expLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Text('Step ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: expInk)),
          const Spacer(),
          IconButton(
            tooltip: 'Remove step',
            onPressed: _saving
                ? null
                : () => setState(() {
                      final _StepDraft removed = _steps.removeAt(i);
                      WidgetsBinding.instance.addPostFrameCallback((_) => removed.label.dispose());
                    }),
            icon: const Icon(Icons.delete_outline),
          ),
        ]),
        ExpenseField(controller: s.label, label: 'Step label *', hint: 'e.g. Finance review', maxLength: 100,
            validator: (String? v) => requiredText(v, 'Step label', max: 100)),
        const SizedBox(height: 6),
        const Text('Approver users', style: TextStyle(fontWeight: FontWeight.w700, color: expMuted, fontSize: 12)),
        Wrap(spacing: 6, runSpacing: 4, children: <Widget>[
          for (final Map<String, dynamic> u in users)
            FilterChip(
              label: Text('${text(u['fullName'], fallback: text(u['id']))} · ${text(u['role'])}'),
              selected: s.users.contains(text(u['id'])),
              onSelected: (bool v) => setState(() => v ? s.users.add(text(u['id'])) : s.users.remove(text(u['id']))),
            ),
          for (final String id in s.users.where((String id) => !knownUsers.contains(id)))
            InputChip(label: Text('Unlisted user $id'), onDeleted: () => setState(() => s.users.remove(id))),
        ]),
        const SizedBox(height: 6),
        const Text('Approver roles', style: TextStyle(fontWeight: FontWeight.w700, color: expMuted, fontSize: 12)),
        Wrap(spacing: 6, runSpacing: 4, children: <Widget>[
          for (final Map<String, dynamic> r in roles)
            FilterChip(
              label: Text(text(r['name'], fallback: text(r['id']))),
              selected: s.roles.contains(text(r['id'])),
              onSelected: (bool v) => setState(() => v ? s.roles.add(text(r['id'])) : s.roles.remove(text(r['id']))),
            ),
          for (final String id in s.roles.where((String id) => !knownRoles.contains(id)))
            InputChip(label: Text('Unlisted role $id'), onDeleted: () => setState(() => s.roles.remove(id))),
        ]),
      ]),
    );
  }
}
