import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'marketing_api.dart';

class MarketingPerformanceScreen extends StatefulWidget {
  const MarketingPerformanceScreen({super.key, required this.api});
  final MarketingApi api;

  @override
  State<MarketingPerformanceScreen> createState() =>
      _MarketingPerformanceScreenState();
}

class _MarketingPerformanceScreenState extends State<MarketingPerformanceScreen> {
  static const _green = Color(0xff173c35);
  static const _mint = Color(0xffe8f0e9);
  static const _periods = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'];
  static const _weights = [
    'achievement',
    'acquisitions',
    'firstTransactions',
    'tasks',
    'reportCompliance',
    'campaigns'
  ];
  String _period = 'DAILY';
  String _view = 'personal';
  String _archiveKind = '';
  String _archivePeriod = '';
  String _archiveStatus = '';
  String _search = '';
  DateTime? _from;
  DateTime? _to;
  int _page = 1;
  bool _busy = true;
  bool _showArchived = true;
  String? _error;
  Map<String, dynamic> _context = {};
  Map<String, dynamic> _dashboard = {};
  Map<String, dynamic> _department = {};
  Map<String, dynamic> _archive = {};
  Map<String, dynamic> _policy = {};
  List<Map<String, dynamic>> _notifications = [];

  bool get _manager => _context['manager'] == true;
  bool get _superAdmin => _context['superAdmin'] == true;
  bool get _headOffice => _context['headOffice'] == true;
  bool get _canViewDepartment => _manager || _headOffice;
  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
  String _text(dynamic value, [String fallback = '—']) =>
      value == null || '$value'.trim().isEmpty ? fallback : '$value';
  num? _number(dynamic value) => num.tryParse('$value');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _context = await widget.api.performanceContext();
      if (_headOffice && _view == 'personal') _view = 'department';
      switch (_view) {
        case 'department':
          if (!_canViewDepartment) throw Exception('Department performance is manager-only.');
          _department = await widget.api.performanceDepartment(
              period: _period,
              from: _from?.toUtc().toIso8601String(),
              to: _exclusiveTo?.toUtc().toIso8601String(),
              page: _page,
              search: _search);
          break;
        case 'archive':
          _archive = await widget.api.performanceArchive(
              kind: _archiveKind,
              period: _archivePeriod,
              status: _archiveStatus,
              search: _search,
              from: _from?.toUtc().toIso8601String(),
              to: _exclusiveTo?.toUtc().toIso8601String(),
              page: _page,
              archived: _showArchived);
          break;
        case 'notifications':
          _notifications =
              _maps((await widget.api.performanceNotifications())['items']);
          break;
        case 'methodology':
          if (!_superAdmin) throw Exception('Only Super Admin can configure ranking methodology.');
          _policy = await widget.api.rankingPolicy();
          break;
        default:
          _dashboard = await widget.api.performanceMe();
      }
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, String, IconData)>[
      if (!_headOffice) ('personal', 'My performance', Icons.person_outline),
      if (_canViewDepartment) ('department', 'Department', Icons.groups_outlined),
      ('archive', 'Archive', Icons.inventory_2_outlined),
      ('notifications', 'Notifications', Icons.notifications_none),
      if (_superAdmin) ('methodology', 'Ranking policy', Icons.tune),
    ];
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
          color: const Color(0xfff9fbf8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Performance & reporting',
                      style: TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w800,
                          fontSize: 20)),
                  SizedBox(height: 3),
                  Text('Private targets. Clear evidence. No financial authority.',
                      style: TextStyle(color: Color(0xff718178), fontSize: 12)),
                ]),
              ),
              IconButton(
                  tooltip: 'Refresh',
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh)),
            ]),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final tab in tabs)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      avatar: Icon(tab.$3, size: 16),
                      label: Text(tab.$2),
                      selected: _view == tab.$1,
                      onSelected: (_) {
                        setState(() {
                          _view = tab.$1;
                          _page = 1;
                        });
                        _load();
                      },
                    ),
                  ),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: _busy
              ? _loading()
              : _error != null
                  ? _errorPanel()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                        children: [
                          if (_view == 'personal') _personal(),
                          if (_view == 'department') _departmentView(),
                          if (_view == 'archive') _archiveView(),
                          if (_view == 'notifications') _notificationView(),
                          if (_view == 'methodology') _policyView(),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _loading() => ListView(
        padding: const EdgeInsets.all(18),
        children: List.generate(
            5,
            (i) => Container(
                  height: i == 0 ? 92 : 68,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: const Color(0xffe9efea),
                      borderRadius: BorderRadius.circular(12)),
                )),
      );

  Widget _errorPanel() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, color: _green, size: 34),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again')),
          ]),
        ),
      );

  Widget _personal() {
    final periods = _maps(_dashboard['periods']);
    final tasks = _maps(_dashboard['tasks']);
    final reports = _maps(_dashboard['reports']);
    final history = _maps(_dashboard['history']);
    final feedback = _maps(_dashboard['feedback']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _panel(
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _mint, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.insights_outlined, color: _green),
          ),
          const SizedBox(width: 13),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_text((_dashboard['staff'] is Map)
                ? (_dashboard['staff'] as Map)['name']
                : null,
                'Your private dashboard'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _green)),
            Text(_text((_dashboard['staff'] is Map)
                ? (_dashboard['staff'] as Map)['role']
                : null, 'Marketing staff'),
                style: const TextStyle(color: Color(0xff75847b), fontSize: 12)),
          ])),
        ]),
      ),
      const SizedBox(height: 12),
      _heading('Targets by period', 'Daily, weekly, monthly and yearly goals stay independent.'),
      if (periods.isEmpty)
        _empty('No period summaries are available.')
      else
        for (final period in periods) _periodSummary(period),
      const SizedBox(height: 16),
      _heading('Tasks', 'Assignments from your marketing workspace'),
      if (tasks.isEmpty)
        _empty('No tasks are assigned.')
      else
        for (final task in tasks.take(12))
          _simpleRow(
            title: _text(task['title'], 'Task'),
            subtitle:
                '${_text(task['status'])}${task['overdue'] == true ? ' · OVERDUE' : ''} · Due ${_text((task['data'] is Map) ? (task['data'] as Map)['dueAt'] : null)}',
            icon: task['overdue'] == true ? Icons.warning_amber_rounded : Icons.checklist_outlined,
          ),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        const Text('Export period'),
        _periodPicker(),
        _exportButton('PDF', 'pdf', officerId: _text(
            (_dashboard['staff'] is Map) ? (_dashboard['staff'] as Map)['id'] : null, '')),
        _exportButton('Excel', 'xlsx', officerId: _text(
            (_dashboard['staff'] is Map) ? (_dashboard['staff'] as Map)['id'] : null, '')),
      ]),
      const SizedBox(height: 12),
      _heading('Recent reports', 'Self-reported activity counts are never verified achievements.'),
      if (reports.isEmpty)
        _empty('Your reports will appear here.')
      else
        for (final report in reports.take(8))
          _simpleRow(title: _text(report['title'], 'Activity report'),
              subtitle: '${_text(report['status'])} · ${_text((report['data'] is Map) ? (report['data'] as Map)['startsAt'] : null)}',
              icon: Icons.description_outlined),
      const SizedBox(height: 16),
      _heading('Manager feedback', 'Review notes stay attached to the report history.'),
      if (feedback.isEmpty)
        _empty('No manager feedback yet.')
      else
        for (final item in feedback.take(10))
          _simpleRow(title: _text(item['reportTitle'], 'Report review'),
              subtitle: '${_text(item['status'], 'Feedback')} · ${_text(item['comment'] ?? item['reason'], 'No comment provided')}',
              icon: Icons.chat_bubble_outline),
      const SizedBox(height: 16),
      _heading('Performance history', 'Immutable captured observations.'),
      if (history.isEmpty)
        _empty('No historical snapshots have been captured.')
      else
        for (final item in history.take(10))
          _simpleRow(title: _text(item['title'], 'Performance snapshot'),
              subtitle: '${_text(item['status'])} · ${_text(item['createdAt'])}',
              icon: Icons.history),
      if (_manager)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: OutlinedButton.icon(
            onPressed: _captureSnapshot,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Capture verified snapshot'),
          ),
        ),
    ]);
  }

  Widget _periodSummary(Map<String, dynamic> period) {
    final periodTargets = _maps(period['targets']);
    final values = periodTargets
        .map((target) => _number(target['achievementPercent']))
        .whereType<num>()
        .toList();
    final ratio = values.isEmpty
        ? null
        : (values.fold<num>(
                    0, (total, value) => total + value.clamp(0, 100)) /
                values.length /
                100)
            .clamp(0.0, 1.0)
            .toDouble();
    return _panel(
      margin: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(_text(period['period'], 'Target period'),
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: _green)),
          ),
          _status(periodTargets.isEmpty ? 'NO TARGET' : '${periodTargets.length} TARGETS'),
        ]),
        const SizedBox(height: 4),
        Text('${_text(period['from'])} — ${_text(period['to'])} · UTC',
            style: const TextStyle(fontSize: 10, color: Color(0xff748279))),
        const SizedBox(height: 9),
        LinearProgressIndicator(
            value: ratio ?? 0,
            minHeight: 6,
            backgroundColor: _mint,
            color: const Color(0xff438466)),
        const SizedBox(height: 8),
        if (periodTargets.isEmpty)
          const Text('No assigned target overlaps this period.',
              style: TextStyle(fontSize: 11, color: Color(0xff748279)))
        else
          for (final target in periodTargets) _targetCard(target),
      ]),
    );
  }

  Widget _periodPicker() => DropdownButton<String>(
        value: _period,
        items: _periods
            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() => _period = value);
          if (_view == 'department') _load();
        },
      );

  Widget _targetCard(Map<String, dynamic> target) {
    final actual = _number(target['actual']);
    final goal = _number((target['data'] is Map) ? (target['data'] as Map)['value'] : null);
    final percent = _number(target['achievementPercent']);
    final progress = percent == null ? null : (percent / 100).clamp(0.0, 1.0).toDouble();
    final remaining = target['remaining'];
    final data = target['data'] is Map ? target['data'] as Map : const {};
    return _panel(
      margin: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(_text(target['title'], _pretty(_text(data['metric'], 'Target'))),
              style: const TextStyle(fontWeight: FontWeight.w800, color: _green))),
          _status(target['outcome'] ?? target['status']),
        ]),
        const SizedBox(height: 6),
        Text('${_pretty(_text(data['metric'], 'Metric'))} · ${_text(data['startsAt'])} — ${_text(data['endsAt'])}',
            style: const TextStyle(fontSize: 11, color: Color(0xff748279))),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: progress ?? 0, minHeight: 7, backgroundColor: _mint, color: const Color(0xff438466)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('Actual ${actual?.toString() ?? 'Unavailable'} / ${goal ?? 'Unavailable'}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: _green))),
          Text(percent == null ? 'Unavailable' : '${percent.toStringAsFixed(1)}%',
              style: const TextStyle(fontWeight: FontWeight.w800, color: _green)),
        ]),
        Text('Remaining ${_text(remaining, 'Unavailable')} · ${_text(data['objective'], 'No objective supplied')}',
            style: const TextStyle(fontSize: 11, color: Color(0xff748279))),
        const SizedBox(height: 6),
        const Text('Progress is based on verified records; custom and self-reported counts remain unavailable.',
            style: TextStyle(fontSize: 10, color: Color(0xff7d8b83))),
      ]),
    );
  }

  Widget _departmentView() {
    final rows = _maps(_department['items']);
    final method = _department['methodology'] is Map
        ? Map<String, dynamic>.from(_department['methodology'])
        : <String, dynamic>{};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _heading('Department ranking', 'Only permitted staff · verified measures only.')),
        _periodPicker(),
      ]),
      Align(alignment: Alignment.centerLeft, child: _dateFilter()),
      TextField(
        decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search), hintText: 'Search staff'),
        onSubmitted: (value) {
          setState(() {
            _search = value.trim();
            _page = 1;
          });
          _load();
        },
      ),
      const SizedBox(height: 10),
      _panel(
        child: Text(
            'Weights: ${method['weights'] is Map ? (method['weights'] as Map).entries.map((e) => '${_pretty('${e.key}')} ${e.value}%').join(' · ') : 'Methodology unavailable'}\n${_text(_department['comparisonNote'], 'Ranking does not add customers across periods.')}\n${_strings(method['methodology']).join(' ')}',
            style: const TextStyle(fontSize: 11, height: 1.5, color: Color(0xff65776d))),
      ),
      if (rows.isEmpty) _empty('No staff ranking data is available for this period.')
      else
        for (final row in rows) _rankCard(row),
      _pager(_int(_department['total'])),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _exportButton('PDF', 'pdf', department: true),
        _exportButton('Excel', 'xlsx', department: true),
      ]),
    ]);
  }

  Widget _rankCard(Map<String, dynamic> row) {
    final score = _number(row['score']);
    final rank = row['rank'];
    return _panel(
      margin: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36, alignment: Alignment.center,
              decoration: BoxDecoration(color: _mint, borderRadius: BorderRadius.circular(11)),
              child: Text(rank == null ? '—' : '#$rank', style: const TextStyle(fontWeight: FontWeight.w800, color: _green))),
          const SizedBox(width: 10),
          Expanded(child: Text(_text(row['name'], 'Marketing staff'),
              style: const TextStyle(fontWeight: FontWeight.w800, color: _green))),
          Text(score == null ? 'Not ranked' : '${score.toStringAsFixed(1)} score',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 7, runSpacing: 7, children: [
          _metricChip('Achievement', row['achievement']),
          _metricChip('Acquisitions', row['acquisitions']),
          _metricChip('First transactions', row['firstTransactions']),
          _metricChip('Verified tasks', row['tasks']),
          _metricChip('Campaigns', row['campaigns']),
          _metricChip('Report compliance', row['reportCompliance'], suffix: '%'),
          _metricChip('Reports outstanding', row['outstandingReports']),
          _metricChip('Submitted for review', row['submittedReports']),
        ]),
        if (_maps(row['targets']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_maps(row['targets']).map((t) =>
              '${_text(t['title'], 'Target')}: ${_text(t['outcome'])} (${_text(t['achievementPercent'], 'Unavailable')}%)').join(' · '),
              style: const TextStyle(fontSize: 11, color: Color(0xff697970))),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _openStaff(_text(row['id'], '')),
            icon: const Icon(Icons.open_in_new, size: 17),
            label: const Text('View performance'),
          ),
        ),
      ]),
    );
  }

  Future<void> _openStaff(String id) async {
    if (id.isEmpty) return;
    try {
      final detail = await widget.api.performanceStaff(id);
      if (!mounted) return;
      final periods = _maps(detail['periods']);
      final targets = _maps(detail['targets']);
      final tasks = _maps(detail['tasks']);
      final reports = _maps(detail['reports']);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_text((detail['staff'] is Map)
              ? (detail['staff'] as Map)['name']
              : null, 'Staff performance')),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final period in periods) ...[
                    _heading(_text(period['period'], 'Period'),
                        '${_text(period['from'])} — ${_text(period['to'])} · UTC'),
                    for (final target in _maps(period['targets']))
                      _targetCard(target),
                  ],
                  _heading('Targets', 'Complete target record list.'),
                  for (final target in targets.take(12)) _targetCard(target),
                  _heading('Tasks', 'Assignment state; completion requires manager review.'),
                  if (tasks.isEmpty)
                    _empty('No task records.')
                  else
                    for (final task in tasks.take(10))
                      _simpleRow(
                        title: _text(task['title'], 'Task'),
                        subtitle:
                            '${_text(task['status'])}${task['overdue'] == true ? ' · OVERDUE' : ''}',
                        icon: Icons.checklist_outlined,
                      ),
                  _heading('Reports', 'Self-reported counts are not verified.'),
                  if (reports.isEmpty)
                    _empty('No activity reports.')
                  else
                    for (final report in reports.take(10))
                      _simpleRow(
                        title: _text(report['title'], 'Report'),
                        subtitle: '${_text(report['status'])} · ${_text(report['createdAt'])}',
                        icon: Icons.description_outlined,
                      ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _captureSnapshot(officerId: id);
              },
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Capture snapshot'),
            ),
            TextButton.icon(
              onPressed: () => _export('pdf', false, id),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export PDF'),
            ),
            TextButton.icon(
              onPressed: () => _export('xlsx', false, id),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export Excel'),
            ),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close')),
          ],
        ),
      );
    } catch (error) {
      _message('$error');
    }
  }

  Widget _archiveView() {
    final rows = _maps(_archive['items']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Historical records', 'Archive and restore preserve the source record and audit trail.'),
      Align(alignment: Alignment.centerLeft, child: _dateFilter()),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Archived')),
          ButtonSegment(value: false, label: Text('All records')),
        ],
        selected: {_showArchived},
        onSelectionChanged: (selection) {
          setState(() {
            _showArchived = selection.first;
            _page = 1;
          });
          _load();
        },
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _filterMenu('Record type', _archiveKind,
            const ['', 'target', 'report', 'task', 'campaign', 'content', 'performance'],
            (value) => _archiveKind = value),
        _filterMenu('Period', _archivePeriod, const ['', ..._periods],
            (value) => _archivePeriod = value),
        _filterMenu('Status', _archiveStatus,
            const ['', 'DRAFT', 'SUBMITTED', 'APPROVED', 'REJECTED', 'CORRECTIONS_REQUESTED'],
            (value) => _archiveStatus = value),
      ]),
      const SizedBox(height: 9),
      TextField(
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search archived records'),
        onSubmitted: (value) {
          setState(() {
            _search = value.trim();
            _page = 1;
          });
          _load();
        },
      ),
      const SizedBox(height: 9),
      if (rows.isEmpty) _empty('No archived records match these filters.')
      else for (final record in rows) _archiveCard(record),
      _pager(_int(_archive['total'])),
    ]);
  }

  Widget _archiveCard(Map<String, dynamic> record) {
    final data = record['data'] is Map ? record['data'] as Map : const {};
    final isArchived = data['archivedAt'] != null;
    final kind = _text(record['kind'], 'report');
    return _panel(
      margin: const EdgeInsets.only(top: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.inventory_2_outlined, color: _green),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_text(record['title'], _pretty(kind)),
              style: const TextStyle(fontWeight: FontWeight.w800, color: _green)),
          Text('$kind · ${_text(record['status'])} · ${_text(record['createdAt'])}',
              style: const TextStyle(fontSize: 11, color: Color(0xff75847b))),
          Wrap(spacing: 3, children: [
            TextButton(onPressed: () => _showHistory(kind, _text(record['_id'])),
                child: const Text('History')),
            if (_manager || (kind == 'report' && _ownedByCurrentUser(record)))
              TextButton(onPressed: () => _archiveAction(record, !isArchived),
                  child: Text(isArchived ? 'Restore' : 'Archive')),
          ]),
        ])),
      ]),
    );
  }

  bool _ownedByCurrentUser(Map<String, dynamic> record) {
    final actor = _text(_context['actorId'], '');
    final owner = _text(record['officerId'] ?? record['createdBy'], '');
    return actor.isNotEmpty && actor == owner;
  }

  Widget _notificationView() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('Notifications', 'Assignments, deadlines, report decisions and period summaries.'),
          if (_notifications.isEmpty)
            _empty('You are up to date.')
          else
            for (final item in _notifications)
              _simpleRow(
                title: _text(item['title'], 'Marketing update'),
                subtitle: '${_text(item['status'])} · ${_text(item['createdAt'])}',
                icon: Icons.notifications_none,
                trailing: '${item['status']}'.toUpperCase() == 'UNREAD'
                    ? TextButton(
                        onPressed: () => _markRead(item),
                        child: const Text('Mark read'))
                    : null,
              ),
        ],
      );

  Widget _policyView() {
    final weights = _policy['weights'] is Map
        ? Map<String, dynamic>.from(_policy['weights'])
        : <String, dynamic>{};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Ranking methodology', 'Super Admin only · weights must total 100.'),
      _panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Revision ${_text(_policy['revision'], '0')}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: _green)),
          const SizedBox(height: 7),
          for (final item in _strings(_policy['methodology']))
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(item,
                  style: const TextStyle(fontSize: 12, height: 1.4)),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _editPolicy(weights),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Configure weights'),
          ),
        ]),
      ),
    ]);
  }

  Widget _heading(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: _green, fontSize: 17)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: Color(0xff748279), fontSize: 11)),
        ]),
      );

  Widget _panel({required Widget child, EdgeInsetsGeometry? margin}) => Container(
        margin: margin,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xfffbfdf9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xffdce7de)),
        ),
        child: child,
      );

  Widget _empty(String message) => _panel(
        margin: const EdgeInsets.only(top: 5),
        child: Row(children: [
          const Icon(Icons.inbox_outlined, color: Color(0xff668173)),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Color(0xff718178)))),
        ]),
      );

  Widget _simpleRow(
          {required String title,
          required String subtitle,
          required IconData icon,
          Widget? trailing}) =>
      _panel(
        margin: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          Icon(icon, color: const Color(0xff47745e), size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: _green)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xff738178))),
          ])),
          if (trailing != null) trailing,
        ]),
      );

  Widget _status(dynamic value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: _mint, borderRadius: BorderRadius.circular(20)),
        child: Text(_pretty(_text(value, 'UNAVAILABLE')),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _green)),
      );

  Widget _metricChip(String label, dynamic value, {String suffix = ''}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(color: _mint, borderRadius: BorderRadius.circular(9)),
        child: Text('$label · ${_text(value, 'Unavailable')}$suffix',
            style: const TextStyle(fontSize: 10, color: _green, fontWeight: FontWeight.w600)),
      );

  Widget _filterMenu(String label, String value, List<String> values,
          ValueChanged<String> change) =>
      DropdownButton<String>(
        hint: Text(label),
        value: value.isEmpty ? '' : value,
        items: [
          for (final item in values)
            DropdownMenuItem(value: item, child: Text(item.isEmpty ? 'Any $label' : _pretty(item)))
        ],
        onChanged: (next) {
          if (next == null) return;
          setState(() {
            change(next);
            _page = 1;
          });
          _load();
        },
      );

  Widget _pager(int total) => Row(children: [
        Text('$total records · Page $_page',
            style: const TextStyle(fontSize: 11, color: Color(0xff748279))),
        const Spacer(),
        IconButton(
            onPressed: _page <= 1
                ? null
                : () {
                    setState(() => _page--);
                    _load();
                  },
            icon: const Icon(Icons.chevron_left)),
        IconButton(
            onPressed: total <= _page * 20
                ? null
                : () {
                    setState(() => _page++);
                    _load();
                  },
            icon: const Icon(Icons.chevron_right)),
      ]);

  Widget _exportButton(String label, String format,
          {bool department = false, String? officerId}) =>
      OutlinedButton.icon(
        onPressed: () => _export(format, department, officerId),
        icon: const Icon(Icons.download_outlined),
        label: Text('Export $label'),
      );

  Future<void> _export(String format, bool department, String? officerId) async {
    try {
      final result = await widget.api.exportPerformance(
          format: format,
          period: _period,
          from: _from?.toUtc().toIso8601String(),
          to: _exclusiveTo?.toUtc().toIso8601String(),
          officerId: officerId?.isEmpty == true ? null : officerId,
          department: department);
      if (!mounted) return;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ServicePay marketing performance',
        fileName: 'servicepay-marketing-performance.$format',
        bytes: result.bodyBytes,
      );
      if (path != null) _message('Performance export saved.');
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _captureSnapshot({String? officerId}) async {
    final (start, next) = _periodBounds();
    try {
      await widget.api.capturePerformanceSnapshot({
        'period': _period,
        'from': start.toIso8601String(),
        'to': next.toIso8601String(),
        if (officerId != null)
          'officerId': officerId
        else if (_dashboard['staff'] is Map)
          'officerId': (_dashboard['staff'] as Map)['id'],
      });
      _message('Verified snapshot captured.');
      await _load();
    } catch (error) {
      _message('$error');
    }
  }

  DateTime? get _exclusiveTo =>
      _to == null ? null : DateTime.utc(_to!.year, _to!.month, _to!.day + 1);

  (DateTime, DateTime) _periodBounds() {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final start = switch (_period) {
      'WEEKLY' => today.subtract(Duration(days: today.weekday - 1)),
      'MONTHLY' => DateTime.utc(now.year, now.month),
      'YEARLY' => DateTime.utc(now.year),
      _ => today,
    };
    final end = switch (_period) {
      'WEEKLY' => start.add(const Duration(days: 7)),
      'MONTHLY' => DateTime.utc(start.year, start.month + 1),
      'YEARLY' => DateTime.utc(start.year + 1),
      _ => start.add(const Duration(days: 1)),
    };
    return (start, end);
  }

  Widget _dateFilter() => OutlinedButton.icon(
        onPressed: () async {
          final now = DateTime.now();
          final range = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2018),
            lastDate: now,
            initialDateRange: _from == null || _to == null
                ? null
                : DateTimeRange(start: _from!, end: _to!),
          );
          if (range == null) return;
          setState(() {
            _from = DateTime(range.start.year, range.start.month, range.start.day);
            _to = DateTime(range.end.year, range.end.month, range.end.day);
            _page = 1;
          });
          _load();
        },
        icon: const Icon(Icons.date_range_outlined),
        label: Text(_from == null
            ? 'Choose date range'
            : '${_from!.toIso8601String().substring(0, 10)} — ${_to!.toIso8601String().substring(0, 10)}'),
      );

  Future<void> _markRead(Map<String, dynamic> item) async {
    try {
      await widget.api.markPerformanceNotificationRead(_text(item['_id']));
      await _load();
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _archiveAction(Map<String, dynamic> record, bool archived) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(archived ? 'Archive record?' : 'Restore record?'),
        content: TextField(
          controller: reason,
          maxLines: 3,
          decoration: const InputDecoration(
              labelText: 'Reason *', helperText: 'This action is recorded in history.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, reason.text.trim().isNotEmpty),
            child: Text(archived ? 'Archive' : 'Restore'),
          )
        ],
      ),
    );
    if (confirmed != true) {
      reason.dispose();
      return;
    }
    try {
      await widget.api.archivePerformanceRecord(_text(record['kind']), _text(record['_id']), {
        'revision': _int(record['revision']),
        'archived': archived,
        'reason': reason.text.trim(),
      });
      _message(archived ? 'Record archived; source preserved.' : 'Record restored.');
      await _load();
    } catch (error) {
      _message('$error');
    } finally {
      reason.dispose();
    }
  }

  Future<void> _showHistory(String kind, String id) async {
    try {
      final result = await widget.api.performanceHistory(kind, id);
      if (!mounted) return;
      final rows = _maps(result['items']);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Record history'),
          content: SizedBox(
            width: 440,
            child: rows.isEmpty
                ? const Text('No audit events are available.')
                : ListView(shrinkWrap: true, children: [
                    for (final row in rows)
                      ListTile(
                        dense: true,
                        title: Text(_text(row['title'] ?? row['status'], 'Record event')),
                        subtitle: Text('${_text(row['createdAt'])} · ${_text(row['createdBy'])}'),
                      )
                  ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _editPolicy(Map<String, dynamic> initial) async {
    final controllers = <String, TextEditingController>{
      for (final key in _weights)
        key: TextEditingController(text: '${initial[key] ?? 0}')
    };
    final reason = TextEditingController();
    String? errorText;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Configure ranking weights'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (errorText != null) Text(errorText!, style: const TextStyle(color: Colors.red)),
                for (final key in _weights)
                  TextField(
                    controller: controllers[key],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: _pretty(key), suffixText: '%'),
                  ),
                TextField(
                  controller: reason,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Change reason *'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final values = <String, int>{};
                for (final key in _weights) {
                  final value = int.tryParse(controllers[key]!.text);
                  if (value == null || value < 0 || value > 100) {
                    setDialog(() => errorText = 'Each weight must be a whole number from 0 to 100.');
                    return;
                  }
                  values[key] = value;
                }
                if (values.values.fold<int>(0, (a, b) => a + b) != 100 ||
                    reason.text.trim().isEmpty) {
                  setDialog(() => errorText = 'Weights must total 100 and a reason is required.');
                  return;
                }
                Navigator.pop(ctx, {'weights': values, 'reason': reason.text.trim()});
              },
              child: const Text('Save policy'),
            )
          ],
        ),
      ),
    );
    if (result != null) {
      try {
        await widget.api.updateRankingPolicy({
          ...result,
          'revision': _int(_policy['revision']),
        });
        await _load();
        _message('Ranking policy updated.');
      } catch (error) {
        _message('$error');
      }
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
    reason.dispose();
  }

  int _int(dynamic value) => int.tryParse('$value') ?? 0;
  List<String> _strings(dynamic value) => value is List
      ? value.map((item) => '$item').toList()
      : <String>[];
  String _pretty(String value) => value
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .toLowerCase()
      .split(' ')
      .map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
