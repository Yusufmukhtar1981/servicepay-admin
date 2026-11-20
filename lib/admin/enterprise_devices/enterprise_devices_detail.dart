part of 'enterprise_devices_screen.dart';

// ---------------------------------------------------------------- details

Future<String?> askReason(
  BuildContext context,
  String title, {
  String action = 'Confirm',
}) {
  final TextEditingController r = TextEditingController();
  final GlobalKey<FormState> k = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: k,
        child: TextFormField(
          controller: r,
          autofocus: true,
          maxLines: 3,
          validator: (String? v) => (v ?? '').trim().length < 5
              ? 'Give a reason (min 5 characters)'
              : null,
          decoration: const InputDecoration(
            labelText: 'Reason (audited)',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: EdColors.forest),
          onPressed: () {
            if (k.currentState!.validate()) Navigator.pop(ctx, r.text.trim());
          },
          child: Text(action),
        ),
      ],
    ),
  );
}

class _DetailsView extends StatefulWidget {
  const _DetailsView({
    super.key,
    required this.api,
    required this.id,
    required this.canManage,
    required this.canEnroll,
    required this.onChanged,
    required this.onHistory,
  });
  final EnterpriseDevicesApi api;
  final String id;
  final bool canManage;
  final bool canEnroll;
  final VoidCallback onChanged;
  final VoidCallback onHistory;
  @override
  State<_DetailsView> createState() => _DetailsViewState();
}

class _DetailsViewState extends State<_DetailsView> {
  bool busy = false;

  Future<void> run(Future<void> Function() op, String ok) async {
    setState(() => busy = true);
    try {
      await op();
      if (!mounted) return;
      _toast(context, ok);
      widget.onChanged();
    } catch (e) {
      if (mounted) _toast(context, _err(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> assign(Map<String, dynamic> d) async {
    final Map<String, dynamic>? p = await pickActiveStaff(context, widget.api);
    if (p == null || !mounted) return;
    final String? reason = await askReason(
      context,
      'Assign to ${_staffName(p)}',
      action: 'Assign',
    );
    if (reason == null) return;
    await run(
      () => widget.api.assign(
        widget.id,
        staffId: _s(p['_id']),
        expectedVersion: _i(d['version']),
        reason: reason,
      ),
      'Device assigned.',
    );
  }

  Future<void> status(Map<String, dynamic> d, String s) async {
    final String? reason = await askReason(
      context,
      'Mark ${s.replaceAll('_', ' / ')}',
    );
    if (reason == null) return;
    await run(
      () => widget.api.setStatus(
        widget.id,
        status: s,
        expectedVersion: _i(d['version']),
        reason: reason,
      ),
      'Status updated.',
    );
  }

  Future<void> revoke(Map<String, dynamic> d) async {
    final String? reason = await askReason(
      context,
      'Revoke companion app',
      action: 'Revoke',
    );
    if (reason == null) return;
    await run(
      () => widget.api.revoke(
        widget.id,
        expectedVersion: _i(d['version']),
        reason: reason,
      ),
      'Companion revoked.',
    );
  }

  Future<void> enroll(Map<String, dynamic> d) async {
    setState(() => busy = true);
    Map<String, dynamic>? res;
    try {
      res = await widget.api.enrollment(
        widget.id,
        expectedVersion: _i(d['version']),
      );
    } catch (e) {
      if (mounted) _toast(context, _err(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (res == null || !mounted) return;
    // Token lives only inside this dialog's local scope; never stored or logged.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EnrollmentTokenDialog(
        token: _s(res!['enrollmentToken']),
        expiresAt: _s(res['expiresAt']),
        deviceId: _s(res['deviceId']),
      ),
    );
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => _Loader<Map<String, dynamic>>(
        load: () => widget.api.device(widget.id),
        builder: (Map<String, dynamic> data, VoidCallback reload) {
          final Map<String, dynamic> d = _m(data['device']);
          final Map<String, dynamic> st = _m(d['assignedStaff']);
          final Map<String, dynamic> comp = _m(d['companion']);
          final String status = _s(d['status']);
          final bool terminal = status == 'RETIRED';
          List<Widget> kv(List<(String, String)> rows) => rows
              .map(
                ((String, String) r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 140,
                        child: Text(
                          r.$1,
                          style: const TextStyle(
                            color: EdColors.muted,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          r.$2.isEmpty ? '-' : r.$2,
                          style: const TextStyle(
                              fontSize: 13, color: EdColors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList();
          return ListView(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: EdColors.forest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      _s(d['deviceId']),
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    StatusPill(status),
                    Text(
                      '${_s(d['manufacturer'])} ${_s(d['model'])} · v${_i(d['version'])}',
                      style: const TextStyle(color: Color(0xFFC8E2D2)),
                    ),
                  ],
                ),
              ),
              if (widget.canManage || widget.canEnroll)
                _Panel(
                  title: 'Actions',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      if (widget.canManage)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: EdColors.forest,
                          ),
                          onPressed: busy || terminal || status == 'LOST_STOLEN'
                              ? null
                              : () => assign(d),
                          icon: const Icon(Icons.assignment_ind_outlined),
                          label: Text(st.isEmpty ? 'Assign' : 'Reassign'),
                        ),
                      for (final String s in <String>[
                        'AVAILABLE',
                        'INACTIVE',
                        'LOST_STOLEN',
                        'RETIRED',
                      ])
                        if (widget.canManage && s != status)
                          OutlinedButton(
                            onPressed:
                                busy || terminal ? null : () => status_(d, s),
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  s == 'LOST_STOLEN' || s == 'RETIRED'
                                      ? EdColors.red
                                      : EdColors.forest,
                            ),
                            child: Text(switch (s) {
                              'AVAILABLE' => 'Return to stock',
                              'INACTIVE' => 'Mark inactive',
                              'LOST_STOLEN' => 'Report lost / stolen',
                              _ => 'Retire',
                            }),
                          ),
                      if (widget.canEnroll)
                        OutlinedButton.icon(
                          key: const Key('ed-enroll'),
                          onPressed: busy || terminal ? null : () => enroll(d),
                          icon: const Icon(Icons.qr_code_2),
                          label: const Text('Issue enrollment token'),
                        ),
                      if (widget.canEnroll)
                        OutlinedButton.icon(
                          key: const Key('ed-revoke'),
                          onPressed: busy ||
                                  comp['enrolled'] != true ||
                                  comp['revoked'] == true
                              ? null
                              : () => revoke(d),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: EdColors.red,
                          ),
                          icon: const Icon(Icons.link_off),
                          label: const Text('Revoke companion'),
                        ),
                    ],
                  ),
                ),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints bc) {
                  final List<Widget> panels = <Widget>[
                    _Panel(
                      title: 'Identity',
                      child: Column(
                        children: kv(<(String, String)>[
                          ('IMEI 1', _s(d['imei1'])),
                          ('IMEI 2', _s(d['imei2'])),
                          ('Serial', _s(d['serialNumber'])),
                          ('Android', _s(d['androidVersion'])),
                          ('Registered', _date(d['registeredAt'])),
                        ]),
                      ),
                    ),
                    _Panel(
                      title: 'Assignment & purchase',
                      child: Column(
                        children: kv(<(String, String)>[
                          (
                            'Staff',
                            st.isEmpty
                                ? 'Unassigned'
                                : '${_s(st['name'])} (${_s(st['role'])})',
                          ),
                          ('Department', _s(d['department'])),
                          ('State', _s(d['state'])),
                          (
                            'Purchased',
                            '${_date(d['purchaseDate'])} · NGN ${_s(d['purchasePrice'])}',
                          ),
                          ('Warranty to', _date(d['warrantyExpiry'])),
                        ]),
                      ),
                    ),
                    _Panel(
                      title: 'Companion app',
                      child: Column(
                        children: kv(<(String, String)>[
                          ('Enrolled', comp['enrolled'] == true ? 'Yes' : 'No'),
                          ('Revoked', comp['revoked'] == true ? 'Yes' : 'No'),
                          ('Installation', _s(comp['installationId'])),
                          ('Last sync', _date(comp['lastSyncAt'])),
                          ('Last heartbeat', _date(comp['lastHeartbeatAt'])),
                        ]),
                      ),
                    ),
                  ];
                  if (bc.maxWidth < 900) return Column(children: panels);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: panels
                        .map(
                          (Widget p) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: p,
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              _Panel(
                title: 'Recent assignments',
                trailing: TextButton(
                  onPressed: widget.onHistory,
                  child: const Text('Full history'),
                ),
                child: _AssignmentList(rows: _l(data['assignments'])),
              ),
              _Panel(
                title: 'Audit',
                child: _AuditList(
                  rows: _l(data['audit']),
                  empty: 'No audit entries yet.',
                ),
              ),
            ],
          );
        },
      );

  // Named helper to avoid shadowing the `status` local inside build.
  Future<void> status_(Map<String, dynamic> d, String s) => status(d, s);
}

class EnrollmentTokenDialog extends StatefulWidget {
  const EnrollmentTokenDialog({
    super.key,
    required this.token,
    required this.expiresAt,
    required this.deviceId,
  });
  final String token;
  final String expiresAt;
  final String deviceId;
  @override
  State<EnrollmentTokenDialog> createState() => _EnrollmentTokenDialogState();
}

class _EnrollmentTokenDialogState extends State<EnrollmentTokenDialog> {
  bool copied = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Enrollment token'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Device ${widget.deviceId} · expires ${_date(widget.expiresAt)}',
                style: const TextStyle(color: EdColors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EdColors.greenSoft,
                  border: Border.all(color: EdColors.green),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  widget.token,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Shown once. Short-lived and single-use. It is not stored by this app; close this dialog once it has been entered on the device.',
                style: TextStyle(fontSize: 12.5, color: EdColors.ink),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.token));
              if (mounted) setState(() => copied = true);
            },
            icon: Icon(copied ? Icons.check : Icons.copy),
            label: Text(copied ? 'Copied' : 'Copy token'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: EdColors.forest),
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      );
}

/// Renders device events: {device, actor:string, action, reason, metadata, createdAt}.
class _AuditList extends StatelessWidget {
  const _AuditList({required this.rows, required this.empty});
  final List<Map<String, dynamic>> rows;
  final String empty;
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text(empty, style: const TextStyle(color: EdColors.muted));
    }
    return Column(
      children: rows.map((Map<String, dynamic> r) {
        final Map<String, dynamic> meta = _m(r['metadata']);
        final String metaText = meta.entries
            .where(
              (MapEntry<String, dynamic> e) =>
                  e.value is! Map && e.value is! List,
            )
            .map((MapEntry<String, dynamic> e) => '${e.key}: ${_s(e.value)}')
            .join(' · ');
        return _EventRow(
          at: r['createdAt'],
          title: _s(r['action']).isEmpty ? 'EVENT' : _s(r['action']),
          lines: <String>[
            if (_s(r['actor']).isNotEmpty) 'By ${_s(r['actor'])}',
            if (_s(r['reason']).isNotEmpty) 'Reason: ${_s(r['reason'])}',
            if (metaText.isNotEmpty) metaText,
          ],
        );
      }).toList(),
    );
  }
}

/// Renders assignments: {device, staff, assignedBy, reason, startedAt, endedAt, endedBy}.
class _AssignmentList extends StatelessWidget {
  const _AssignmentList({required this.rows});
  final List<Map<String, dynamic>> rows;
  static String _who(dynamic v) {
    if (v is Map) {
      final Map<String, dynamic> m = _m(v);
      final String n =
          _s(m['fullName']).isNotEmpty ? _s(m['fullName']) : _s(m['name']);
      return _s(m['role']).isEmpty ? n : '$n (${_s(m['role'])})';
    }
    return _s(v);
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Text(
        'No assignments recorded.',
        style: TextStyle(color: EdColors.muted),
      );
    }
    return Column(
      children: rows.map((Map<String, dynamic> r) {
        final bool open = _s(r['endedAt']).isEmpty;
        return _EventRow(
          at: r['startedAt'],
          title: '${_who(r['staff'])}${open ? '  ·  CURRENT' : ''}',
          lines: <String>[
            if (_who(r['assignedBy']).isNotEmpty)
              'Assigned by ${_who(r['assignedBy'])}',
            if (_s(r['reason']).isNotEmpty) 'Reason: ${_s(r['reason'])}',
            if (!open)
              'Ended ${_date(r['endedAt'])}${_who(r['endedBy']).isEmpty ? '' : ' by ${_who(r['endedBy'])}'}',
          ],
        );
      }).toList(),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.at, required this.title, required this.lines});
  final dynamic at;
  final String title;
  final List<String> lines;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: EdColors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 128,
              child: Text(
                _date(at),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  color: EdColors.muted,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  for (final String l in lines)
                    Text(
                      l,
                      style:
                          const TextStyle(fontSize: 12.5, color: EdColors.ink),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------- history

class _HistoryView extends StatefulWidget {
  const _HistoryView({super.key, required this.api, required this.id});
  final EnterpriseDevicesApi api;
  final String id;
  @override
  State<_HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<_HistoryView> {
  int page = 1;
  @override
  Widget build(BuildContext context) => _Loader<Map<String, dynamic>>(
        key: ValueKey<int>(page),
        load: () => widget.api.history(widget.id, page: page),
        isEmpty: (Map<String, dynamic> d) => _l(d['history']).isEmpty,
        empty: const _Empty(
          icon: Icons.history,
          title: 'No history yet',
          text: 'Assignment and status changes will appear here.',
        ),
        builder: (Map<String, dynamic> d, VoidCallback reload) {
          final int pages = _i(d['pages']) < 1 ? 1 : _i(d['pages']);
          return ListView(
            children: <Widget>[
              _Panel(
                title: 'History · ${_i(d['total'])} entries',
                trailing: pages > 1
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Previous page',
                            onPressed:
                                page > 1 ? () => setState(() => page--) : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Text('$page / $pages'),
                          IconButton(
                            tooltip: 'Next page',
                            onPressed: page < pages
                                ? () => setState(() => page++)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      )
                    : null,
                child: _AuditList(rows: _l(d['history']), empty: 'No history.'),
              ),
            ],
          );
        },
      );
}
