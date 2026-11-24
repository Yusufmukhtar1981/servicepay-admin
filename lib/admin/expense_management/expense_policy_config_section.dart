import 'package:flutter/material.dart';

import 'expense_api.dart';
import 'expense_common.dart';
import 'expense_management_screen.dart';

/// Dedicated Head Office page for department approval policies and
/// request capability assignments. Nothing is configured or granted
/// automatically: every change needs an explicit save with a reason.
class ApprovalPolicyConfigSection extends StatefulWidget {
  const ApprovalPolicyConfigSection({super.key, required this.ctx});
  final ExpenseModuleContext ctx;
  @override
  State<ApprovalPolicyConfigSection> createState() => _ApprovalPolicyConfigSectionState();
}

class _ApprovalPolicyConfigSectionState extends State<ApprovalPolicyConfigSection> {
  List<Map<String, dynamic>> _policies = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _people = <Map<String, dynamic>>[];
  List<String> _departments = <String>[];
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _editing; // empty map = new policy
  int _editorVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> data = await widget.ctx.api.approvalPolicies();
      if (!mounted) return;
      setState(() {
        _policies = asList(data['items']).map(asMap).toList();
        _people = asList(data['people']).map(asMap).toList();
        _departments = asList(data['departments']).map((dynamic v) => '$v').toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  String _name(String id) {
    final Map<String, dynamic> p = _people.firstWhere((Map<String, dynamic> x) => text(x['id']) == id, orElse: () => <String, dynamic>{});
    return text(p['fullName'], fallback: 'Unlisted user $id');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.ctx.canConfigurePolicies) {
      return const ExpenseEmptyState(
        icon: Icons.lock_outline,
        title: 'Access not granted',
        message: 'Approval Policy Configuration requires the HEAD_OFFICE role together with expenses.manage_policy.',
      );
    }
    if (_loading && _policies.isEmpty && _people.isEmpty) return const ExpenseSkeleton(rows: 5);
    if (_error != null && _policies.isEmpty && _people.isEmpty) return ExpenseErrorState(message: _error!, onRetry: _load);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      const ExpenseNotice(
        'Policies route department requests by department and amount range. A primary OR an assigned backup reviewer may complete a level; '
        'the first valid decision wins. Nobody can approve their own request or more than one level. Policy changes apply to NEW submissions only; existing submissions keep their reviewer snapshot. Both named primary and backup reviewers may act.',
      ),
      const SizedBox(height: 12),
      if (_editing != null)
        _PolicyEditor(
          key: ValueKey<String>('policy-editor-$_editorVersion'),
          ctx: widget.ctx,
          policy: _editing!,
          people: _people,
          departments: _departments,
          onCancel: () => setState(() => _editing = null),
          onSaved: () {
            setState(() => _editing = null);
            _load();
          },
          onConflict: _load,
        )
      else
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          FilledButton.icon(
            key: const Key('policy-new'),
            onPressed: () => setState(() {
              _editing = <String, dynamic>{};
              _editorVersion++;
            }),
            style: FilledButton.styleFrom(backgroundColor: expGreen),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New approval policy'),
          ),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 17), label: const Text('Reload')),
        ]),
      const SizedBox(height: 14),
      ExpensePanel(
        title: 'Approval policies',
        subtitle: '${_policies.where((Map<String, dynamic> p) => p['active'] == true).length} active of ${_policies.length}',
        child: _policies.isEmpty
            ? const Text('No approval policies are configured. Department requests cannot be submitted until an active policy covers the department and amount.',
                style: TextStyle(color: expMuted))
            : Column(children: <Widget>[for (final Map<String, dynamic> p in _policies) _policyCard(p)]),
      ),
      const SizedBox(height: 14),
      _AssignmentsPanel(ctx: widget.ctx, people: _people, onAssigned: _load),
    ]);
  }

  Widget _policyCard(Map<String, dynamic> p) {
    final List<Map<String, dynamic>> steps = asList(p['approvalSteps']).map(asMap).toList();
    final bool active = p['active'] == true;
    String limit(dynamic v) => v == null ? 'not set' : money(v);
    return Container(
      key: Key('policy-card-${text(p['id'])}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: expSoft, borderRadius: BorderRadius.circular(8), border: Border.all(color: expLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(text(p['name'], fallback: 'Unnamed policy'), style: const TextStyle(fontWeight: FontWeight.w800, color: expInk))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: active ? const Color(0xffdcefe5) : const Color(0xffeceeed), borderRadius: BorderRadius.circular(5)),
            child: Text(active ? 'Active' : 'Inactive', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: active ? expGreen : expMuted)),
          ),
          IconButton(
            key: Key('policy-edit-${text(p['id'])}'),
            tooltip: 'Edit policy',
            onPressed: () => setState(() {
              _editing = p;
              _editorVersion++;
            }),
            icon: const Icon(Icons.edit_outlined, size: 19),
          ),
        ]),
        if (text(p['description']).isNotEmpty) Text(text(p['description']), style: const TextStyle(color: expMuted, fontSize: 12)),
        const SizedBox(height: 4),
        Text('Departments: ${asList(p['departments']).join(', ')}', style: const TextStyle(fontSize: 12.5, color: expInk)),
        Text('Amount range: ${limit(p['minimumAmountMinor'])} to ${limit(p['maximumAmountMinor'])} · revision ${text(p['revision'])}',
            style: const TextStyle(fontSize: 12.5, color: expInk)),
        for (int i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Level ${i + 1} · ${text(steps[i]['label'])}: primary ${asList(steps[i]['userIds']).map((dynamic v) => _name('$v')).join(', ')}'
              '${asList(steps[i]['backupUserIds']).isEmpty ? '' : '; backup ${asList(steps[i]['backupUserIds']).map((dynamic v) => _name('$v')).join(', ')}'}',
              style: const TextStyle(fontSize: 12, color: expMuted),
            ),
          ),
      ]),
    );
  }
}

class _LevelDraft {
  _LevelDraft({String label = '', Set<String>? primary, Set<String>? backup})
      : label = TextEditingController(text: label),
        primary = primary ?? <String>{},
        backup = backup ?? <String>{};
  final TextEditingController label;
  final Set<String> primary;
  final Set<String> backup;
}

class _PolicyEditor extends StatefulWidget {
  const _PolicyEditor({
    super.key,
    required this.ctx,
    required this.policy,
    required this.people,
    required this.departments,
    required this.onCancel,
    required this.onSaved,
    required this.onConflict,
  });
  final ExpenseModuleContext ctx;
  final Map<String, dynamic> policy;
  final List<Map<String, dynamic>> people;
  final List<String> departments;
  final VoidCallback onCancel;
  final VoidCallback onSaved;
  final Future<void> Function() onConflict;
  @override
  State<_PolicyEditor> createState() => _PolicyEditorState();
}

class _PolicyEditorState extends State<_PolicyEditor> {
  late final Map<String, dynamic> _p = widget.policy;
  late final bool _isNew = text(_p['id']).isEmpty;
  late final TextEditingController _name = TextEditingController(text: text(_p['name']));
  late final TextEditingController _description = TextEditingController(text: text(_p['description']));
  late final TextEditingController _min =
      TextEditingController(text: _p['minimumAmountMinor'] == null ? '' : minorToDecimal(_p['minimumAmountMinor']));
  late final TextEditingController _max =
      TextEditingController(text: _p['maximumAmountMinor'] == null ? '' : minorToDecimal(_p['maximumAmountMinor']));
  late final Set<String> _depts = asList(_p['departments']).map((dynamic v) => '$v').toSet();
  late bool _active = _p['active'] == true;
  late final List<_LevelDraft> _levels = asList(_p['approvalSteps'])
      .map(asMap)
      .map((Map<String, dynamic> s) => _LevelDraft(
            label: text(s['label']),
            primary: asList(s['userIds']).map((dynamic v) => '$v').toSet(),
            backup: asList(s['backupUserIds']).map((dynamic v) => '$v').toSet(),
          ))
      .toList();
  List<String> _problems = <String>[];
  String? _error;
  bool _saving = false;
  String? _key;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_name, _description, _min, _max]) {
      c.dispose();
    }
    for (final _LevelDraft l in _levels) {
      l.label.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _approvers =>
      widget.people.where((Map<String, dynamic> p) => asMap(p['capabilities'])['approver'] == true).toList();

  int? _minor(String s) {
    final String v = s.trim().replaceAll(',', '');
    if (v.isEmpty || !amountPattern.hasMatch(v)) return null;
    final List<String> parts = v.split('.');
    return int.parse(parts[0]) * 100 + int.parse(parts.length > 1 ? parts[1].padRight(2, '0') : '0');
  }

  List<String> _validate() {
    final List<String> e = <String>[];
    if (_name.text.trim().isEmpty) e.add('Policy name is required.');
    if (_depts.isEmpty) e.add('Select at least one department.');
    final String minRaw = _min.text.trim(), maxRaw = _max.text.trim();
    if (minRaw.isNotEmpty && _minor(minRaw) == null) e.add('Minimum amount must be a NGN amount with at most two decimals.');
    if (maxRaw.isNotEmpty && _minor(maxRaw) == null) e.add('Maximum amount must be a NGN amount with at most two decimals.');
    final int? mn = _minor(minRaw), mx = _minor(maxRaw);
    if (mn != null && mx != null && mx < mn) e.add('Maximum amount must be at least the minimum amount.');
    final Set<String> approverIds = _approvers.map((Map<String, dynamic> p) => text(p['id'])).toSet();
    final Map<String, int> seen = <String, int>{};
    for (int i = 0; i < _levels.length; i++) {
      final _LevelDraft l = _levels[i];
      if (l.label.text.trim().isEmpty) e.add('Level ${i + 1} needs a label.');
      for (final String id in <String>{...l.primary, ...l.backup}) {
        if (seen.containsKey(id)) {
          e.add('A reviewer appears on level ${seen[id]! + 1} and level ${i + 1}. One person cannot approve multiple levels.');
        }
        seen[id] = i;
      }
      if (l.primary.intersection(l.backup).isNotEmpty) e.add('Level ${i + 1} lists the same person as primary and backup.');
    }
    if (_active) {
      if (mn == null || mx == null) e.add('Activation requires explicit minimum and maximum amounts.');
      if (_levels.isEmpty) e.add('Activation requires at least one approval level.');
      for (int i = 0; i < _levels.length; i++) {
        if (_levels[i].primary.isEmpty) e.add('Activation requires a primary reviewer on level ${i + 1}.');
        if (_levels[i].primary.any((String id) => !approverIds.contains(id))) {
          e.add('Level ${i + 1} has a primary reviewer without active approver capability.');
        }
      }
    }
    return e;
  }

  Future<void> _save() async {
    final List<String> problems = _validate();
    setState(() {
      _problems = problems;
      _error = null;
    });
    if (problems.isNotEmpty) return;
    final String? reason = await askReason(context,
        title: _isNew ? 'Create approval policy' : 'Save approval policy',
        message: _active
            ? 'This policy will route new submissions for the selected departments and amount range. Existing submissions keep their snapshot.'
            : 'The policy is saved inactive and will not route requests until activated.',
        confirmLabel: 'Save policy');
    if (reason == null || !mounted) return;
    _key ??= ExpenseIdempotency.newKey('pol');
    setState(() => _saving = true);
    try {
      await widget.ctx.api.saveApprovalPolicy(
        id: _isNew ? null : text(_p['id']),
        expectedVersion: asInt(_p['revision']) ?? 0,
        reason: reason,
        idempotencyKey: _key!,
        fields: <String, dynamic>{
          'name': _name.text.trim(),
          if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
          'departments': _depts.toList(),
          'minimumAmount': _min.text.trim().isEmpty ? null : _min.text.trim().replaceAll(',', ''),
          'maximumAmount': _max.text.trim().isEmpty ? null : _max.text.trim().replaceAll(',', ''),
          'approvalSteps': _levels
              .map((_LevelDraft l) => <String, dynamic>{
                    'label': l.label.text.trim(),
                    'userIds': l.primary.toList(),
                    'backupUserIds': l.backup.toList(),
                    'roleIds': <String>[],
                  })
              .toList(),
          'active': _active,
        },
      );
      _key = null;
      if (!mounted) return;
      setState(() => _saving = false);
      showExpenseMessage(context, 'Approval policy saved.');
      widget.onSaved();
    } catch (e) {
      final ExpenseApiException? ex = e is ExpenseApiException ? e : null;
      if (ex == null || !ex.outcomeUnknown) _key = null;
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '${errorText(e)} Your policy edits are preserved.';
      });
      if (ex != null && ex.isConflict) await widget.onConflict();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> depts = <String>{...widget.departments, ..._depts}.toList();
    return ExpensePanel(
      title: _isNew ? 'New approval policy' : 'Edit ${text(_p['name'])}',
      subtitle: _isNew ? 'Nothing is pre-filled; set every limit and reviewer explicitly.' : 'Revision ${text(_p['revision'])}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        if (_problems.isNotEmpty) ...<Widget>[
          ExpenseNotice(_problems.map((String s) => '- $s').join('\n'), tone: 'error', key: const Key('policy-errors')),
          const SizedBox(height: 10),
        ],
        TextField(key: const Key('policy-name'), controller: _name, enabled: !_saving, decoration: expInput('Policy name *')),
        const SizedBox(height: 10),
        TextField(controller: _description, enabled: !_saving, maxLines: 2, decoration: expInput('Description')),
        const SizedBox(height: 12),
        const Text('Departments covered *', style: TextStyle(fontWeight: FontWeight.w800, color: expInk, fontSize: 13)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: <Widget>[
          for (final String d in depts)
            FilterChip(
              key: Key('policy-dept-$d'),
              label: Text(d),
              selected: _depts.contains(d),
              onSelected: _saving ? null : (bool v) => setState(() => v ? _depts.add(d) : _depts.remove(d)),
            ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
          SizedBox(
            width: 220,
            child: TextField(
              key: const Key('policy-min'),
              controller: _min,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: expInput('Minimum amount (NGN)', helper: 'Required to activate'),
            ),
          ),
          SizedBox(
            width: 220,
            child: TextField(
              key: const Key('policy-max'),
              controller: _max,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: expInput('Maximum amount (NGN)', helper: 'Required to activate'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (_approvers.isEmpty)
          const ExpenseNotice('No staff currently hold approver capability. Add it under Approval assignments below before naming reviewers.', tone: 'warn'),
        for (int i = 0; i < _levels.length; i++) _levelCard(i),
        OutlinedButton.icon(
          key: const Key('policy-add-level'),
          onPressed: _saving || _levels.length >= 8 ? null : () => setState(() => _levels.add(_LevelDraft())),
          icon: const Icon(Icons.add, size: 18),
          label: Text('Add approval level (${_levels.length}/8)'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const Key('policy-active'),
          contentPadding: EdgeInsets.zero,
          value: _active,
          onChanged: _saving ? null : (bool v) => setState(() => _active = v),
          title: const Text('Active', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Overlapping active coverage for the same department and amount is rejected by the server.', style: TextStyle(fontSize: 12)),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: ExpenseNotice(_error!, tone: 'error', key: const Key('policy-save-error'))),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          FilledButton.icon(
            key: const Key('policy-save'),
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: expGreen),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(_saving ? 'Saving...' : _key != null ? 'Retry save (same operation)' : 'Save policy'),
          ),
          TextButton(onPressed: _saving ? null : widget.onCancel, child: const Text('Cancel')),
        ]),
      ]),
    );
  }

  Widget _levelCard(int i) {
    final _LevelDraft l = _levels[i];
    final Set<String> known = _approvers.map((Map<String, dynamic> p) => text(p['id'])).toSet();
    Widget picker(String label, Set<String> set, String kind) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: expMuted, fontSize: 12)),
          Wrap(spacing: 6, runSpacing: 4, children: <Widget>[
            for (final Map<String, dynamic> p in _approvers)
              FilterChip(
                key: Key('level-$i-$kind-${text(p['id'])}'),
                label: Text('${text(p['fullName'], fallback: text(p['id']))} · ${text(p['department'])}'),
                selected: set.contains(text(p['id'])),
                onSelected: _saving ? null : (bool v) => setState(() => v ? set.add(text(p['id'])) : set.remove(text(p['id']))),
              ),
            for (final String id in set.where((String id) => !known.contains(id)))
              InputChip(label: Text('Unlisted user $id'), onDeleted: () => setState(() => set.remove(id))),
          ]),
        ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: expSoft, borderRadius: BorderRadius.circular(8), border: Border.all(color: expLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Text('Level ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: expInk)),
          const Spacer(),
          IconButton(
            tooltip: 'Remove level',
            onPressed: _saving
                ? null
                : () => setState(() {
                      final _LevelDraft removed = _levels.removeAt(i);
                      WidgetsBinding.instance.addPostFrameCallback((_) => removed.label.dispose());
                    }),
            icon: const Icon(Icons.delete_outline),
          ),
        ]),
        TextField(key: Key('level-$i-label'), controller: l.label, enabled: !_saving, decoration: expInput('Level label *', hint: 'e.g. Finance Manager review')),
        const SizedBox(height: 8),
        picker('Primary reviewers *', l.primary, 'primary'),
        const SizedBox(height: 6),
        picker('Backup reviewers (may act when a primary is unavailable)', l.backup, 'backup'),
      ]),
    );
  }
}

// ---------------- Assignments ----------------

const Map<String, String> _capabilityLabels = <String, String>{
  'requester': 'Requester',
  'departmentManager': 'Department manager',
  'approver': 'Approver',
  'finance': 'Finance',
};

class _AssignmentsPanel extends StatelessWidget {
  const _AssignmentsPanel({required this.ctx, required this.people, required this.onAssigned});
  final ExpenseModuleContext ctx;
  final List<Map<String, dynamic>> people;
  final Future<void> Function() onAssigned;

  @override
  Widget build(BuildContext context) {
    return ExpensePanel(
      title: 'Approval assignments',
      subtitle: 'Current request capabilities by staff member',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const ExpenseNotice(
          'Adding a capability never removes existing permissions. To revoke a capability use Staff Management. Department manager, Approver and Finance require an active GLOBAL staff role. '
          'Finance includes protected finance viewing, payment recording and documents.',
        ),
        const SizedBox(height: 10),
        if (people.isEmpty) const Text('No eligible staff returned by the server.', style: TextStyle(color: expMuted)),
        for (final Map<String, dynamic> p in people)
          Container(
            key: Key('person-${text(p['id'])}'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: expLine))),
            child: Row(children: <Widget>[
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(text(p['fullName'], fallback: text(p['id'])), style: const TextStyle(fontWeight: FontWeight.w700, color: expInk)),
                  Text('${text(p['department'], fallback: 'No department')} · ${text(p['scope'], fallback: 'scope unknown')}',
                      style: const TextStyle(color: expMuted, fontSize: 12)),
                  Wrap(spacing: 4, runSpacing: 4, children: <Widget>[
                    for (final MapEntry<String, String> c in _capabilityLabels.entries)
                      if (asMap(p['capabilities'])[c.key] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xffdcefe5), borderRadius: BorderRadius.circular(4)),
                          child: Text(c.value, style: const TextStyle(fontSize: 10.5, color: expGreen, fontWeight: FontWeight.w800)),
                        ),
                  ]),
                ]),
              ),
              TextButton(
                key: Key('assign-${text(p['id'])}'),
                onPressed: () async {
                  final bool? done = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => CapabilityAssignDialog(ctx: ctx, person: p),
                  );
                  if (done == true) await onAssigned();
                },
                child: const Text('Add capability'),
              ),
            ]),
          ),
      ]),
    );
  }
}

class CapabilityAssignDialog extends StatefulWidget {
  const CapabilityAssignDialog({super.key, required this.ctx, required this.person});
  final ExpenseModuleContext ctx;
  final Map<String, dynamic> person;
  @override
  State<CapabilityAssignDialog> createState() => _CapabilityAssignDialogState();
}

class _CapabilityAssignDialogState extends State<CapabilityAssignDialog> {
  late final Map<String, dynamic> _existing = asMap(widget.person['capabilities']);
  final Set<String> _add = <String>{};
  final TextEditingController _reason = TextEditingController();
  bool _confirmed = false;
  bool _busy = false;
  String? _error;
  String? _key;

  bool get _global => text(widget.person['scope']).toUpperCase() == 'GLOBAL';

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    String? problem;
    if (_add.isEmpty) {
      problem = 'Select at least one new capability.';
    } else if (_reason.text.trim().length < 10) {
      problem = 'Reason needs at least 10 characters.';
    } else if (!_confirmed) {
      problem = 'Confirm the grant explicitly.';
    }
    setState(() => _error = problem);
    if (problem != null) return;
    _key ??= ExpenseIdempotency.newKey('asg');
    setState(() => _busy = true);
    try {
      await widget.ctx.api.assignRequestCapabilities(
        userId: text(widget.person['id']),
        capabilities: <String, bool>{for (final String c in _add) c: true},
        expectedRoleId: text(widget.person['roleId']),
        reason: _reason.text.trim(),
        idempotencyKey: _key!,
      );
      _key = null;
      if (!mounted) return;
      showExpenseMessage(context, 'Expense access added for ${text(widget.person['fullName'], fallback: 'the staff member')}. Their staff role and permissions are unchanged; they refresh navigation to see the new access.');
      Navigator.of(context).pop(true);
    } catch (e) {
      final ExpenseApiException? ex = e is ExpenseApiException ? e : null;
      if (ex == null || !ex.outcomeUnknown) _key = null;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add capability: ${text(widget.person['fullName'])}'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const Text('Existing capabilities stay checked and cannot be removed here. Revocation is done in Staff Management. '
                'Grants are expense-only and apply to this person alone. Their existing staff role and permissions stay unchanged, colleagues are unaffected, and they refresh navigation to see the new access.',
                style: TextStyle(color: expMuted, fontSize: 12)),
            for (final MapEntry<String, String> c in _capabilityLabels.entries)
              Builder(builder: (BuildContext context) {
                final bool has = _existing[c.key] == true;
                final bool needsGlobal = c.key != 'requester';
                final bool blocked = needsGlobal && !_global;
                return CheckboxListTile(
                  key: Key('cap-${c.key}'),
                  contentPadding: EdgeInsets.zero,
                  value: has || _add.contains(c.key),
                  onChanged: has || blocked || _busy ? null : (bool? v) => setState(() => v == true ? _add.add(c.key) : _add.remove(c.key)),
                  title: Text(c.value),
                  subtitle: Text(
                    has
                        ? 'Already granted'
                        : blocked
                            ? 'Requires an active GLOBAL staff role'
                            : switch (c.key) {
                                'requester' => 'Submit own expense requests only',
                                'departmentManager' => 'Department request history, not global finance',
                                'approver' => 'Can be named as a reviewer in policies',
                                _ => 'Protected finance viewing, payment recording and documents',
                              },
                    style: const TextStyle(fontSize: 11.5),
                  ),
                );
              }),
            const SizedBox(height: 8),
            TextField(key: const Key('cap-reason'), controller: _reason, enabled: !_busy, maxLines: 2, decoration: expInput('Reason *')),
            CheckboxListTile(
              key: const Key('cap-confirm'),
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: _busy ? null : (bool? v) => setState(() => _confirmed = v ?? false),
              title: const Text('I confirm granting the selected capabilities to this staff member.', style: TextStyle(fontSize: 12.5)),
            ),
            if (_error != null) ExpenseNotice(_error!, tone: 'error'),
          ]),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          key: const Key('cap-submit'),
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: expGreen),
          child: Text(_busy ? 'Granting...' : 'Grant selected'),
        ),
      ],
    );
  }
}
