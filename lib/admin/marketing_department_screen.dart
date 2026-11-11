import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'marketing_api.dart';

class MarketingDepartmentScreen extends StatefulWidget {
  const MarketingDepartmentScreen({
    super.key,
    required this.permissions,
    required this.isHeadOffice,
    this.api,
  });
  final Set<String> permissions;
  final bool isHeadOffice;
  final MarketingApi? api;

  @override
  State<MarketingDepartmentScreen> createState() =>
      _MarketingDepartmentScreenState();
}

class _InteractiveTrendChart extends StatefulWidget {
  const _InteractiveTrendChart({required this.points});
  final List<Map<String, dynamic>> points;

  @override
  State<_InteractiveTrendChart> createState() => _InteractiveTrendChartState();
}

class _InteractiveTrendChartState extends State<_InteractiveTrendChart> {
  String _metric = 'acquired';
  int? _selected;
  static const _metrics = <String, String>{
    'acquired': 'Acquired customers',
    'firstTransactions': 'First transactions',
  };

  @override
  Widget build(BuildContext context) {
    final rows = widget.points;
    final values =
        rows.map((row) => num.tryParse('${row[_metric]}')?.toDouble()).toList();
    final selected = _selected != null &&
            _selected! < rows.length &&
            values[_selected!] != null
        ? rows[_selected!]
        : null;
    return _chartPanel(
      title: 'Acquisition trend',
      subtitle: 'Daily series from the overview response · UTC dates',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          label: 'Choose trend metric',
          child: DropdownButton<String>(
            key: const ValueKey('trend-metric-selector'),
            isExpanded: true,
            value: _metric,
            items: _metrics.entries
                .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (value) => setState(() {
              _metric = value ?? _metric;
              _selected = null;
            }),
          ),
        ),
        if (rows.isEmpty)
          const _ChartEmpty('No dated series returned for this period.')
        else
          Semantics(
            label:
                'Interactive line chart of ${_metrics[_metric]} over UTC dates. Select a point to view its value.',
            child: LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                height: 176,
                width: double.infinity,
                child: GestureDetector(
                  key: const ValueKey('trend-chart-canvas'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (event) {
                    final index = ((event.localPosition.dx /
                                max(1.0, constraints.maxWidth)) *
                            max(1, rows.length - 1))
                        .round()
                        .clamp(0, rows.length - 1);
                    setState(() => _selected = index);
                  },
                  child: CustomPaint(
                    painter: _SeriesPainter(values, _selected),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        if (rows.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Semantics(
                    button: true,
                    label:
                        '${rows[i]['date'] ?? 'Date unavailable'}, ${_metrics[_metric]}: ${values[i] ?? 'Unavailable'}',
                    child: ChoiceChip(
                      label: Text('${rows[i]['date'] ?? 'Date unavailable'}'),
                      selected: _selected == i,
                      onSelected: (_) => setState(() => _selected = i),
                    ),
                  ),
                ),
            ]),
          ),
        if (selected != null)
          Semantics(
            liveRegion: true,
            label:
                '${_metrics[_metric]} on ${selected['date']}: ${values[_selected!]}',
            child: Text(
                '${selected['date'] ?? 'Date unavailable'} · ${_metrics[_metric]}: ${values[_selected!] ?? 'Unavailable'}',
                style: const TextStyle(
                    color: Color(0xff284d40),
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
      ]),
    );
  }
}

class _CampaignComparison extends StatefulWidget {
  const _CampaignComparison({required this.campaigns});
  final List<Map<String, dynamic>> campaigns;

  @override
  State<_CampaignComparison> createState() => _CampaignComparisonState();
}

class _CampaignComparisonState extends State<_CampaignComparison> {
  String _metric = 'acquired';
  String? _selected;
  static const _metrics = <String, String>{
    'acquired': 'Acquired',
    'firstTransactions': 'First transactions',
  };

  @override
  Widget build(BuildContext context) {
    final rows = widget.campaigns;
    final maximum = rows
        .map((row) => num.tryParse('${row[_metric]}')?.toDouble())
        .whereType<double>()
        .fold<double>(0, max);
    return _chartPanel(
      title: 'Campaign comparison',
      subtitle: 'Compare only reported campaign outcomes.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          label: 'Choose campaign comparison metric',
          child: DropdownButton<String>(
            key: const ValueKey('campaign-metric-selector'),
            isExpanded: true,
            value: _metric,
            items: _metrics.entries
                .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (value) => setState(() {
              _metric = value ?? _metric;
              _selected = null;
            }),
          ),
        ),
        if (rows.isEmpty)
          const _ChartEmpty('No campaign comparison data is available.')
        else
          for (final row in rows)
            Semantics(
              button: true,
              label:
                  '${row['title'] ?? 'Campaign'}, ${_metrics[_metric]}, ${row[_metric] ?? 'Unavailable'}',
              child: InkWell(
                onTap: () => setState(
                    () => _selected = '${row['id'] ?? row['title'] ?? ''}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(
                      width: 120,
                      child: Text('${row['title'] ?? 'Campaign'}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      child: _ComparisonBar(
                          value: num.tryParse('${row[_metric]}')?.toDouble(),
                          maximum: maximum),
                    ),
                    const SizedBox(width: 9),
                    Text(row[_metric] == null
                        ? 'Unavailable'
                        : '${row[_metric]}'),
                  ]),
                ),
              ),
            ),
        if (_selected != null)
          Text(
            () {
              final selected = rows.firstWhere(
                (r) => '${r['id'] ?? r['title'] ?? ''}' == _selected,
                orElse: () => <String, dynamic>{},
              );
              return '${selected['title'] ?? 'Selected campaign'} · ${_metrics[_metric]}: ${selected[_metric] ?? 'Unavailable'}';
            }(),
            style: const TextStyle(
                color: Color(0xff284d40), fontWeight: FontWeight.w700),
          ),
      ]),
    );
  }
}

Widget _chartPanel(
        {required String title,
        required String subtitle,
        required Widget child}) =>
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xfffbfdf9),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xffdce7de)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xff21473c),
                fontSize: 15)),
        const SizedBox(height: 3),
        Text(subtitle,
            style: const TextStyle(fontSize: 11, color: Color(0xff75877d))),
        const SizedBox(height: 10),
        child,
      ]),
    );

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        height: 112,
        alignment: Alignment.center,
        child: Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xff75877d))),
      );
}

class _ComparisonBar extends StatelessWidget {
  const _ComparisonBar({required this.value, required this.maximum});
  final double? value;
  final double maximum;
  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return const Text('Unavailable',
          style: TextStyle(fontSize: 11, color: Color(0xff75877d)));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final ratio = maximum == 0 ? 0.0 : (value!.abs() / maximum.abs());
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          height: 10,
          width: constraints.maxWidth * ratio.clamp(0.0, 1.0),
          decoration: BoxDecoration(
              color: const Color(0xff579477),
              borderRadius: BorderRadius.circular(8)),
        ),
      );
    });
  }
}

class _SeriesPainter extends CustomPainter {
  _SeriesPainter(this.values, this.selected);
  final List<double?> values;
  final int? selected;
  @override
  void paint(Canvas canvas, Size size) {
    final valid = values.whereType<double>().toList();
    if (valid.isEmpty) return;
    const inset = 12.0;
    final maxY = valid.reduce(max).clamp(1, double.infinity);
    final minY = min(0.0, valid.reduce(min));
    final span = max(1.0, maxY - minY);
    final grid = Paint()
      ..color = const Color(0xffe5ece6)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = inset + (size.height - inset * 2) * i / 3;
      canvas.drawLine(Offset(inset, y), Offset(size.width - inset, y), grid);
    }
    final line = Paint()
      ..color = const Color(0xff347a5a)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    var started = false;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        started = false;
        continue;
      }
      final x = values.length == 1
          ? size.width / 2
          : inset + (size.width - inset * 2) * i / (values.length - 1);
      final y =
          size.height - inset - (size.height - inset * 2) * (v - minY) / span;
      if (started) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
        started = true;
      }
      canvas.drawCircle(Offset(x, y), selected == i ? 5 : 3,
          Paint()..color = const Color(0xff347a5a));
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _SeriesPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.selected != selected;
}

class _MarketingDepartmentScreenState extends State<MarketingDepartmentScreen> {
  late final MarketingApi _api = widget.api ?? MarketingApi();
  static const _groups = <String, List<String>>{
    'Acquisition': ['campaign', 'attribution', 'partnership', 'contribution'],
    'Team & delivery': ['task', 'report', 'attendance'],
    'Finance': ['budget', 'expense'],
    'Creative': ['content', 'social', 'material'],
    'Planning': ['strategy', 'proposal', 'announcement', 'target'],
    'Governance': ['audit'],
  };
  static const _titles = <String, String>{
    'campaign': 'Campaigns',
    'attribution': 'Attribution',
    'partnership': 'Partnerships',
    'contribution': 'Verified contributions',
    'task': 'Tasks',
    'report': 'Reports',
    'attendance': 'Attendance',
    'budget': 'Budgets',
    'expense': 'Expenses',
    'content': 'Content calendar',
    'social': 'Social reports',
    'material': 'Materials',
    'strategy': 'Strategy',
    'proposal': 'Proposals',
    'announcement': 'Announcements',
    'target': 'Targets',
    'audit': 'Audit trail',
  };
  String _section = 'overview';
  String _preset = '7days';
  String _search = '';
  String _status = '';
  DateTime? _from;
  DateTime? _to;
  int _page = 1;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _schema = {};
  Set<String> _schemaPermissions = <String>{};
  bool _schemaLoaded = false;
  String _currentUserId = '';
  String? _recordCreateIdempotencyKey;
  final Map<String, String> _assetIdempotencyKeys = <String, String>{};
  Map<String, dynamic> _overview = {};
  List<Map<String, dynamic>> _records = [];
  final List<Map<String, dynamic>> _recentAssets = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _roles = [];
  int _total = 0;
  final _searchController = TextEditingController();

  bool _can(String permission) {
    if (_schemaLoaded) return _schemaPermissions.contains(permission);
    return widget.isHeadOffice || widget.permissions.contains(permission);
  }

  String _assetIdempotencyKey(String filename, List<int> bytes) {
    final fingerprint = '$filename:${bytes.length}:${Object.hashAll(bytes)}';
    return _assetIdempotencyKeys.putIfAbsent(
      fingerprint,
      () =>
          'asset_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(0x7fffffff)}',
    );
  }

  void _completeAssetUpload(String filename, List<int> bytes) {
    _assetIdempotencyKeys.remove(
      '$filename:${bytes.length}:${Object.hashAll(bytes)}',
    );
  }

  bool _writeAllowed(String kind) {
    if (kind == 'material') return false;
    final permission = switch (kind) {
      'campaign' => 'marketing.campaigns.manage',
      'task' => 'marketing.team.manage',
      'report' => 'marketing.reports.manage',
      'budget' || 'expense' => 'marketing.budgets.submit',
      'partnership' || 'contribution' => 'marketing.reports.manage',
      'content' ||
      'social' ||
      'material' ||
      'strategy' ||
      'proposal' ||
      'announcement' =>
        'marketing.content.manage',
      'attribution' => 'marketing.attribution.manage',
      'target' => 'marketing.targets.manage',
      'attendance' => 'marketing.team.manage',
      _ => 'marketing.audit',
    };
    return _can(permission) && (kind != 'target' || widget.isHeadOffice);
  }

  bool _canApprove(Map<String, dynamic> record) {
    if (['content', 'report'].contains(_section) &&
        !_can('marketing.content.approve')) {
      return false;
    }
    if (['strategy', 'proposal', 'partnership', 'contribution', 'campaign']
            .contains(_section) &&
        !widget.isHeadOffice) return false;
    if (['budget', 'expense'].contains(_section) &&
        !(widget.isHeadOffice && _can('marketing.budgets.approve'))) {
      return false;
    }
    final creator = record['createdBy'] is Map
        ? (record['createdBy'] as Map)['_id'] ??
            (record['createdBy'] as Map)['id']
        : record['createdBy'];
    if (_currentUserId.isNotEmpty && '$creator' == _currentUserId) {
      return false;
    }
    return _writeAllowed(_section);
  }

  List<String> _nextStatuses(String status) {
    final List<String> candidates;
    switch (_section) {
      case 'campaign':
        candidates = switch (status) {
          'DRAFT' => ['SUBMITTED', if (widget.isHeadOffice) 'ACTIVE'],
          'SUBMITTED' => ['APPROVED', 'REJECTED'],
          'APPROVED' => ['ACTIVE'],
          'ACTIVE' => ['PAUSED', 'COMPLETED'],
          'PAUSED' => ['ACTIVE', 'COMPLETED'],
          _ => [],
        };
      case 'partnership':
        candidates = switch (status) {
          'SUBMITTED' => ['APPROVED', 'REJECTED'],
          'APPROVED' => ['COMPLETED'],
          _ => [],
        };
      case 'contribution':
        candidates = switch (status) {
          'SUBMITTED' => ['APPROVED', 'REJECTED'],
          _ => [],
        };
      case 'task':
        candidates = switch (status) {
          'TODO' => ['IN_PROGRESS'],
          'IN_PROGRESS' => ['SUBMITTED'],
          'SUBMITTED' => ['COMPLETED'],
          _ => [],
        };
      case 'content':
        candidates = switch (status) {
          'DRAFT' => ['SUBMITTED'],
          'SUBMITTED' => ['APPROVED', 'REJECTED'],
          'APPROVED' => ['PUBLISHED'],
          'REJECTED' => ['DRAFT'],
          _ => [],
        };
      case 'report':
      case 'budget':
      case 'expense':
      case 'proposal':
      case 'strategy':
        candidates = switch (status) {
          'DRAFT' => ['SUBMITTED'],
          'SUBMITTED' => ['APPROVED', 'REJECTED'],
          'APPROVED' when _section == 'expense' && widget.isHeadOffice => [
              'PAID'
            ],
          _ => [],
        };
      default:
        return const [];
    }
    final rawStatuses = _schema['statuses'];
    final kindStatuses =
        rawStatuses is Map ? rawStatuses[_section] : rawStatuses;
    if (kindStatuses is List) {
      final allowed =
          kindStatuses.map((value) => '$value'.toUpperCase()).toSet();
      return candidates.where(allowed.contains).toList();
    }
    return candidates;
  }

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() => _currentUserId = prefs.getString('user_id') ??
            prefs.getString('admin_user_id') ??
            '');
      }
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      if (!refresh) _loading = true;
      _error = null;
    });
    try {
      final schema = await _api.schema();
      if (!mounted) return;
      _schema = schema;
      _schemaPermissions = schema['permissions'] is List
          ? (schema['permissions'] as List)
              .map((value) => '$value'.trim().toLowerCase())
              .toSet()
          : <String>{};
      _schemaLoaded = true;
      if (_section == 'overview') {
        _overview = await _api.overview(_dateQuery);
      } else if (_section == 'team') {
        final data = await _api.team();
        _staff = _maps(data['items']);
        _roles = _maps(data['roles']);
      } else if (_section == 'audit') {
        final data = await _api.activity(page: _page);
        _records = _maps(data['items']);
        _total = _int(data['total']);
      } else if (_section == 'material') {
        final data = await _api.records('asset', page: _page, search: _search);
        _records = _maps(data['items'])
            .map((record) => <String, dynamic>{
                  ...record,
                  'assetId': record['_id'],
                  'filename': (record['data'] is Map)
                      ? record['data']['filename']
                      : record['title'],
                })
            .toList();
        _total = _int(data['total']);
      } else {
        final data = await _api.records(_section,
            page: _page, search: _search, status: _status, filters: _dateQuery);
        _records = _maps(data['items']);
        _total = _int(data['total']);
      }
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
  int _int(dynamic value) => int.tryParse('$value') ?? 0;
  Map<String, String> get _dateQuery => _preset == 'custom'
      ? {
          'preset': 'custom',
          if (_from != null) 'from': _from!.toUtc().toIso8601String(),
          if (_to != null) 'to': _to!.toUtc().toIso8601String(),
        }
      : {'preset': _preset};
  String _str(dynamic v, [String fallback = '—']) =>
      v == null || '$v'.isEmpty ? fallback : '$v';
  String _percent(dynamic value) => value == null ? 'Unavailable' : '$value%';

  void _disposeAfterDialog(Iterable<TextEditingController> controllers) {
    final owned = controllers.toList();
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      for (final controller in owned) {
        controller.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      backgroundColor: const Color(0xfff3f6f3),
      body: SafeArea(
        child: Row(children: [
          if (isWide) _rail(),
          Expanded(
              child: Column(children: [
            _header(isWide),
            if (!isWide) _mobileNav(),
            Expanded(
                child: _loading
                    ? _skeleton()
                    : _error != null
                        ? _errorPanel()
                        : _section == 'overview'
                            ? _overviewView()
                            : _section == 'team'
                                ? _teamView()
                                : _recordsView()),
          ])),
        ]),
      ),
    );
  }

  Widget _rail() => Container(
        width: 248,
        color: const Color(0xff173c35),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
              padding: EdgeInsets.fromLTRB(22, 25, 16, 25),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SERVICEPAY',
                        style: TextStyle(
                            color: Color(0xffbbd5b4),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                    SizedBox(height: 8),
                    Text('Marketing',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w700)),
                  ])),
          Expanded(
              child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                _navItem('overview', 'Overview', Icons.grid_view_rounded),
                if (_can('marketing.team.manage'))
                  _navItem('team', 'Team', Icons.groups_2_outlined),
                for (final entry in _groups.entries) ...[
                  Padding(
                      padding: const EdgeInsets.fromLTRB(13, 20, 8, 7),
                      child: Text(entry.key.toUpperCase(),
                          style: const TextStyle(
                              color: Color(0xff91b3a9),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2))),
                  for (final kind in entry.value)
                    if (kind == 'audit'
                        ? _can('marketing.audit')
                        : _canForView(kind))
                      _navItem(kind, _titles[kind]!, _icon(kind)),
                ],
              ])),
          const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                  'ACQUISITION INTELLIGENCE\nEvidence-led · Read-only money access',
                  style: TextStyle(
                      color: Color(0xffa6c0b6), fontSize: 11, height: 1.5))),
        ]),
      );

  bool _canForView(String kind) =>
      _can('marketing.view') || _writeAllowed(kind);
  IconData _icon(String kind) => switch (kind) {
        'campaign' => Icons.campaign_outlined,
        'attribution' => Icons.link_outlined,
        'task' => Icons.checklist_outlined,
        'report' => Icons.summarize_outlined,
        'attendance' => Icons.schedule_outlined,
        'budget' || 'expense' => Icons.account_balance_wallet_outlined,
        'content' || 'material' => Icons.perm_media_outlined,
        'social' => Icons.forum_outlined,
        'strategy' => Icons.lightbulb_outline,
        'proposal' => Icons.description_outlined,
        'announcement' => Icons.announcement_outlined,
        'target' => Icons.flag_outlined,
        _ => Icons.history_outlined,
      };
  Widget _navItem(String key, String label, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: ListTile(
          dense: true,
          selected: _section == key,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          selectedTileColor: const Color(0xff28574c),
          textColor: const Color(0xffd0e1d9),
          iconColor: const Color(0xffadc8be),
          title: Text(label,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          leading: Icon(icon, size: 19),
          onTap: () => _changeSection(key),
        ),
      );
  Widget _mobileNav() => SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final key in [
            'overview',
            ..._titles.keys.where((k) => _canForView(k)),
            if (_can('marketing.team.manage')) 'team'
          ])
            Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  label: Text(key == 'overview'
                      ? 'Overview'
                      : key == 'team'
                          ? 'Team'
                          : _titles[key]!),
                  selected: key == _section,
                  onSelected: (_) => _changeSection(key),
                ))
        ],
      ));
  void _changeSection(String key) {
    setState(() {
      _section = key;
      _page = 1;
    });
    _load();
  }

  Widget _header(bool wide) => Container(
        padding: EdgeInsets.fromLTRB(wide ? 30 : 18, 17, 20, 17),
        decoration: const BoxDecoration(
            color: Color(0xfff9fbf8),
            border: Border(bottom: BorderSide(color: Color(0xffdce6df)))),
        child: Row(children: [
          if (!wide)
            const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(Icons.insights, color: Color(0xff1a6554))),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    _section == 'overview'
                        ? 'Acquisition, with receipts.'
                        : _section == 'team'
                            ? 'Marketing team'
                            : _titles[_section] ?? _section,
                    style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: Color(0xff183d35))),
                const SizedBox(height: 3),
                Text(
                    _section == 'overview'
                        ? 'Evidence-based growth reporting · No customer money access'
                        : 'ServicePay · Nigerian acquisition operations',
                    style: const TextStyle(
                        color: Color(0xff61756b), fontSize: 12)),
              ])),
          if (_section != 'team' &&
              _section != 'material' &&
              _can('marketing.export'))
            PopupMenuButton<String>(
                tooltip: _section == 'overview'
                    ? 'Export overview'
                    : 'Export records',
                icon: const Icon(Icons.download_outlined),
                onSelected: _export,
                itemBuilder: (_) => const [
                      PopupMenuItem(value: 'xlsx', child: Text('Export Excel')),
                      PopupMenuItem(value: 'pdf', child: Text('Export PDF'))
                    ]),
          IconButton(
              tooltip: 'Refresh',
              onPressed: () => _load(refresh: true),
              icon: const Icon(Icons.refresh_rounded)),
        ]),
      );

  Widget _overviewView() {
    final metrics = (_overview['metrics'] is Map)
        ? Map<String, dynamic>.from(_overview['metrics'])
        : <String, dynamic>{};
    final campaigns = _maps(_overview['campaigns']);
    final geography = _maps(_overview['geography']);
    final officers = _maps(_overview['officers']);
    return RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: ListView(
            key: const ValueKey('marketing-overview-scroll'),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [
              Row(children: [
                const Expanded(
                    child: Text('The acquisition pulse',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Color(0xff21473c)))),
                DropdownButton<String>(
                    value: _preset,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'today', child: Text('Today')),
                      DropdownMenuItem(
                          value: 'yesterday', child: Text('Yesterday')),
                      DropdownMenuItem(
                          value: '7days', child: Text('Last 7 days')),
                      DropdownMenuItem(
                          value: '30days', child: Text('Last 30 days')),
                      DropdownMenuItem(
                          value: 'month', child: Text('This month')),
                      DropdownMenuItem(
                          value: 'lastMonth', child: Text('Last month')),
                      DropdownMenuItem(
                          value: 'custom', child: Text('Custom range')),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      if (value == 'custom') {
                        final now = DateTime.now();
                        final start = await showDatePicker(
                            context: context,
                            initialDate:
                                _from ?? now.subtract(const Duration(days: 6)),
                            firstDate: DateTime(2018),
                            lastDate: now);
                        if (start == null || !mounted) return;
                        final end = await showDatePicker(
                            context: context,
                            initialDate: _to ?? now,
                            firstDate: start,
                            lastDate: now);
                        if (end == null) return;
                        setState(() {
                          _preset = 'custom';
                          _from = DateTime(start.year, start.month, start.day);
                          _to = DateTime(
                              end.year, end.month, end.day, 23, 59, 59);
                        });
                      } else {
                        setState(() => _preset = value);
                      }
                      _load();
                    }),
              ]),
              if (_overview['period'] is Map)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'Reporting window: ${_str((_overview['period'] as Map)['from'], 'Unavailable')} — ${_str((_overview['period'] as Map)['to'], 'Unavailable')} · UTC',
                    style:
                        const TextStyle(color: Color(0xff75877d), fontSize: 11),
                  ),
                ),
              const SizedBox(height: 15),
              LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth < 650 ? 2 : 4;
                final metricsList = [
                  (
                    'Customers acquired',
                    metrics['totalCustomersAcquired'],
                    Icons.person_add_alt_1_outlined,
                    'Growth'
                  ),
                  (
                    'New today',
                    metrics['newCustomersToday'],
                    Icons.today_outlined,
                    'Daily'
                  ),
                  (
                    'First transactions',
                    metrics['firstTimeTransactingCustomers'],
                    Icons.swap_horiz_rounded,
                    'Quality'
                  ),
                  (
                    'Active customers',
                    metrics['activeCustomers'],
                    Icons.people_outline,
                    'Engagement'
                  ),
                  (
                    'Active campaigns',
                    metrics['activeCampaigns'],
                    Icons.campaign_outlined,
                    'Live'
                  ),
                  (
                    'Conversion rate',
                    metrics['conversionRate'] == null
                        ? null
                        : '${metrics['conversionRate']}%',
                    Icons.trending_up,
                    'Funnel'
                  ),
                  (
                    'Expenditure (legacy)',
                    metrics['expenditureNaira'] == null
                        ? null
                        : '₦${metrics['expenditureNaira']}',
                    Icons.payments_outlined,
                    'Reported'
                  ),
                  (
                    'Approved budget',
                    metrics['approvedBudgetNaira'] == null
                        ? null
                        : '₦${metrics['approvedBudgetNaira']}',
                    Icons.account_balance_outlined,
                    'Naira'
                  ),
                  (
                    'New registrations',
                    metrics['newRegistrations'],
                    Icons.person_add_alt,
                    'Global'
                  ),
                  (
                    'Retention rate',
                    metrics['retentionRate'] == null
                        ? null
                        : '${metrics['retentionRate']}%',
                    Icons.replay_outlined,
                    'Cohort'
                  ),
                  (
                    'CAC',
                    metrics['cacNaira'] == null
                        ? null
                        : '₦${metrics['cacNaira']}',
                    Icons.price_check_outlined,
                    'Attributed'
                  ),
                  (
                    'Verified contribution',
                    metrics['verifiedContributionNaira'] == null
                        ? null
                        : '₦${metrics['verifiedContributionNaira']}',
                    Icons.verified_outlined,
                    'Observed'
                  ),
                  (
                    'Verified paid spend',
                    metrics['verifiedSpendNaira'] == null
                        ? null
                        : '₦${metrics['verifiedSpendNaira']}',
                    Icons.receipt_long_outlined,
                    'Evidence'
                  ),
                  (
                    'ROI',
                    metrics['roi'] == null ? null : '${metrics['roi']}%',
                    Icons.show_chart,
                    'Evidence'
                  ),
                ];
                return GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent:
                          148 * MediaQuery.textScalerOf(context).scale(1),
                      crossAxisSpacing: 11,
                      mainAxisSpacing: 11,
                    ),
                    children: [
                      for (final item in metricsList)
                        _metric(item.$1, item.$2, item.$3, item.$4)
                    ]);
              }),
              const SizedBox(height: 18),
              _notice('Registration and expenditure definitions',
                  'New registrations are global registrations in the selected period; first transactions are attributed-cohort outcomes. Approved allocations are not actual spend. Only verified paid evidence is shown as expenditure. All reporting dates are UTC.'),
              const SizedBox(height: 18),
              _trendChart(_maps(_overview['series'])),
              const SizedBox(height: 18),
              _campaignComparison(campaigns),
              const SizedBox(height: 18),
              _referralSection(_overview['referrals']),
              const SizedBox(height: 18),
              _socialSection(_maps(_overview['social'])),
              const SizedBox(height: 25),
              _dataSection(
                  'Campaign performance',
                  'Evidence-confirmed campaign attribution; approved allocation is not paid spend.',
                  campaigns, [
                'title',
                'channel',
                'status',
                'acquired',
                'firstTransactions',
                'verifiedContributionNaira',
                'verifiedSpendNaira',
                'roi'
              ]),
              const SizedBox(height: 18),
              _dataSection(
                  'Partnerships',
                  'Lifecycle and outcomes linked to partnership campaigns.',
                  _maps(_overview['partnerships']), [
                'title',
                'status',
                'campaignId',
                'acquired',
                'firstTransactions'
              ]),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, c) => c.maxWidth < 680
                    ? Column(children: [
                        _dataSection(
                            'Where growth lands',
                            'State and LGA attribution · current profile geography',
                            geography,
                            ['state', 'lga', 'acquired']),
                        const SizedBox(height: 18),
                        _officerScorecard(officers),
                      ])
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _dataSection(
                                'Where growth lands',
                                'State and LGA attribution · current profile geography',
                                geography,
                                ['state', 'lga', 'acquired']),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _officerScorecard(officers),
                          ),
                        ],
                      ),
              ),
              if (_maps(_overview['limitations']).isNotEmpty)
                const SizedBox(height: 12),
              if (_overview['limitations'] is List &&
                  (_overview['limitations'] as List).isNotEmpty)
                _notice('How to read this',
                    (_overview['limitations'] as List).join('  •  ')),
              const SizedBox(height: 12),
              _notice('Measurement boundary',
                  'Referral attribution uses existing referredBy records. Campaign attribution is evidence-confirmed and does not rewrite registrations. Social results are manually evidenced; no publishing credentials are verified and nothing is auto-published.'),
            ]));
  }

  Widget _trendChart(List<Map<String, dynamic>> points) =>
      _InteractiveTrendChart(points: points);

  Widget _campaignComparison(List<Map<String, dynamic>> campaigns) =>
      _CampaignComparison(campaigns: campaigns);

  Widget _referralSection(dynamic referral) {
    final data = referral is Map
        ? Map<String, dynamic>.from(referral)
        : <String, dynamic>{};
    return _dataSection(
      'Referral outcomes',
      'Reliable referral attribution from existing referredBy records.',
      [data],
      ['registrations', 'firstTransactions', 'conversionRate'],
    );
  }

  Widget _socialSection(List<Map<String, dynamic>> social) => _dataSection(
      'Manually evidenced social results',
      'Reported metrics only; no publishing credentials are verified.',
      social,
      ['channel', 'reach', 'impressions', 'engagements', 'reportCount']);

  Widget _officerScorecard(List<Map<String, dynamic>> officers) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xfffbfdf9),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xffdce7de))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Officer scorecard',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xff21473c),
                  fontSize: 15)),
          const SizedBox(height: 3),
          const Text(
              'Multiple measured outcomes; missing evidence stays unavailable.',
              style: TextStyle(fontSize: 11, color: Color(0xff75877d))),
          if (officers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('No officer outcomes in this period.'),
            )
          else
            for (final officer in officers)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(_str(officer['name'], 'Officer'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    'Score ${_percent(officer['scorePercent'])} · Acquired ${_str(officer['acquired'], 'Unavailable')} · First transactions ${_str(officer['firstTransactions'], 'Unavailable')}'),
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final item in [
                      'completedTasks',
                      'submittedReports',
                      'publishedContent',
                      'attendance',
                      'targetValue',
                      'achievementPercent'
                    ])
                      _badge(
                          '${_pretty(item)}: ${_str(officer[item], 'Unavailable')}'),
                  ]),
                  if (officer['scorecard'] is List)
                    for (final score in _maps(officer['scorecard']))
                      ListTile(
                        dense: true,
                        title: Text(_str(score['metric'], 'Metric')),
                        trailing: Text(
                            '${_str(score['actual'], 'Unavailable')} / ${_str(score['target'], 'Unavailable')} · ${_percent(score['achievementPercent'])}'),
                      ),
                ],
              ),
        ]),
      );

  Widget _metric(String title, dynamic value, IconData icon, String tag) =>
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: const Color(0xfffbfdf9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xffdce7de))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 17, color: const Color(0xff34725c)),
            const Spacer(),
            Text(tag.toUpperCase(),
                style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xff85978c),
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6))
          ]),
          const Spacer(),
          Text(value == null ? 'Unavailable' : '$value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: Color(0xff193f35))),
          const SizedBox(height: 3),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xff6b7f74))),
        ]),
      );

  Widget _dataSection(String title, String subtitle,
          List<Map<String, dynamic>> rows, List<String> fields) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xfffbfdf9),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xffdce7de))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xff21473c),
                  fontSize: 15)),
          const SizedBox(height: 3),
          Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xff75877d))),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Text('No evidence in this period yet.',
                style: TextStyle(color: Color(0xff73877c), fontSize: 12))
          else
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  horizontalMargin: 0,
                  columnSpacing: 22,
                  headingRowHeight: 34,
                  dataRowMinHeight: 38,
                  dataRowMaxHeight: 48,
                  columns: [
                    for (final field in fields)
                      DataColumn(
                          label: Text(field == 'lga' ? 'LGA' : _pretty(field),
                              style: const TextStyle(
                                  fontSize: 10, color: Color(0xff778a7f))))
                  ],
                  rows: [
                    for (final row in rows.take(8))
                      DataRow(cells: [
                        for (final field in fields)
                          DataCell(Text(
                              _str(
                                  field == 'lga'
                                      ? row['lga'] ?? row['city']
                                      : row[field],
                                  'Unavailable'),
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xff26463b))))
                      ])
                  ],
                )),
        ]),
      );
  String _pretty(String value) => value
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}')
      .replaceFirstMapped(RegExp(r'^[a-z]'), (m) => m[0]!.toUpperCase());

  String _singularTitle(String kind) => switch (kind) {
        'partnership' => 'Partnership',
        'contribution' => 'Contribution',
        'campaign' => 'Campaign',
        'attribution' => 'Attribution',
        'attendance' => 'Attendance',
        'content' => 'Content item',
        'social' => 'Social report',
        'material' => 'Material',
        'strategy' => 'Strategy',
        'proposal' => 'Proposal',
        'announcement' => 'Announcement',
        'audit' => 'Audit entry',
        'task' => 'Task',
        'report' => 'Report',
        'budget' => 'Budget',
        'expense' => 'Expense',
        'target' => 'Target',
        _ => 'Record',
      };
  Widget _notice(String title, String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xffeaf1e9),
            borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: Color(0xff43735c), size: 19),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xff315843))),
                const SizedBox(height: 3),
                Text(text,
                    style: const TextStyle(
                        fontSize: 11, height: 1.4, color: Color(0xff546d5d)))
              ]))
        ]),
      );

  Widget _recordsView() => Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Wrap(
                spacing: 9,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                      width: min(340, MediaQuery.sizeOf(context).width * .72),
                      height: 42,
                      child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search, size: 19),
                              hintText:
                                  'Search ${_titles[_section]?.toLowerCase() ?? 'records'}',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 9)),
                          onSubmitted: (value) {
                            _search = value.trim();
                            _page = 1;
                            _load();
                          })),
                  if (_section != 'audit') _recordDateFilter(),
                  DropdownButton<String>(
                      value: _status,
                      hint: const Text('Any status'),
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('Any status')),
                        for (final status in _availableStatuses)
                          DropdownMenuItem(
                              value: status, child: Text(_pretty(status))),
                      ],
                      onChanged: (v) {
                        setState(() => _status = v ?? '');
                        _load();
                      }),
                  if (_writeAllowed(_section))
                    FilledButton.icon(
                        onPressed: () => _editRecord(),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('New ${_singularTitle(_section)}')),
                  if (_section == 'material' &&
                      _can('marketing.content.manage'))
                    OutlinedButton.icon(
                        onPressed: _uploadAsset,
                        icon: const Icon(Icons.upload_file_outlined, size: 18),
                        label: const Text('Upload material')),
                ])),
        Expanded(
            child: _records.isEmpty
                ? _emptyRecords()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
                    itemCount: _records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _recordTile(_records[index]))),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(children: [
              Text('$_total records · Page $_page',
                  style:
                      const TextStyle(color: Color(0xff708176), fontSize: 12)),
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
                  onPressed: _records.length < 20
                      ? null
                      : () {
                          setState(() => _page++);
                          _load();
                        },
                  icon: const Icon(Icons.chevron_right)),
            ])),
      ]);

  List<String> get _availableStatuses {
    final statuses = _schema['statuses'];
    final values = statuses is Map ? statuses[_section] : statuses;
    if (values is List) {
      return values.map((value) => '$value'.toUpperCase()).toSet().toList()
        ..sort();
    }
    return const [
      'DRAFT',
      'TODO',
      'IN_PROGRESS',
      'SUBMITTED',
      'PENDING',
      'ACTIVE',
      'PAUSED',
      'APPROVED',
      'REJECTED',
      'COMPLETED'
    ];
  }

  Widget _recordDateFilter() => DropdownButton<String>(
        value: _preset,
        underline: const SizedBox(),
        items: const [
          DropdownMenuItem(value: 'today', child: Text('Today')),
          DropdownMenuItem(value: 'yesterday', child: Text('Yesterday')),
          DropdownMenuItem(value: '7days', child: Text('7 days')),
          DropdownMenuItem(value: '30days', child: Text('30 days')),
          DropdownMenuItem(value: 'month', child: Text('This month')),
          DropdownMenuItem(value: 'lastMonth', child: Text('Last month')),
          DropdownMenuItem(value: 'custom', child: Text('Custom range')),
        ],
        onChanged: (value) async {
          if (value == null) return;
          if (value == 'custom') {
            final now = DateTime.now();
            final start = await showDatePicker(
              context: context,
              initialDate: _from ?? now.subtract(const Duration(days: 6)),
              firstDate: DateTime(2018),
              lastDate: now,
            );
            if (start == null || !mounted) return;
            final end = await showDatePicker(
              context: context,
              initialDate: _to ?? now,
              firstDate: start,
              lastDate: now,
            );
            if (end == null) return;
            setState(() {
              _preset = 'custom';
              _from = DateTime(start.year, start.month, start.day);
              _to = DateTime(end.year, end.month, end.day, 23, 59, 59);
            });
          } else {
            setState(() => _preset = value);
          }
          _page = 1;
          _load();
        },
      );

  Widget _recordTile(Map<String, dynamic> record) {
    final data = record['data'] is Map
        ? Map<String, dynamic>.from(record['data'])
        : <String, dynamic>{};
    final status = _str(record['status'], 'DRAFT').toUpperCase();
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 10, 13),
      decoration: BoxDecoration(
          color: const Color(0xfffbfdf9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xffdce7de))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
                color: const Color(0xffe5efe7),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(_icon(_section),
                size: 18, color: const Color(0xff3d755e))),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_str(record['title'] ?? record['filename']),
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Color(0xff20443a))),
          if (_str(record['description'] ?? record['mime'], '').isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(_str(record['description'] ?? record['mime']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xff74847a)))),
          if (_section == 'content')
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'Scheduled: ${_str(data['scheduledAt'], 'Unavailable')} · ${data['scheduledAt'] != null && DateTime.tryParse('${data['scheduledAt']}')?.isBefore(DateTime.now().toUtc()) == true && status != 'PUBLISHED' ? 'OVERDUE' : 'Due tracking'} · Published URL: ${_str(data['publishedUrl'], 'Unavailable')}',
                style: const TextStyle(fontSize: 11, color: Color(0xff65776c)),
              ),
            ),
          if (_section == 'social')
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'Manual evidence: ${_str(data['evidence'], 'Unavailable')} · Reported ${_str(data['reportedAt'], 'Unavailable')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xff65776c)),
              ),
            ),
          if (_section == 'partnership')
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'Organization: ${_str(data['organization'], 'Unavailable')} · Campaign: ${_str(record['campaignId'] ?? data['campaignId'], 'Unavailable')} · ${_str(data['startsAt'], 'Unavailable')} to ${_str(data['endsAt'], 'Unavailable')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xff65776c)),
              ),
            ),
          if (_section == 'contribution')
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'Transaction: ${_str(data['transactionId'], 'Unavailable')} · Observed contribution: ${_str(record['verifiedContributionNaira'] ?? record['observedContributionNaira'] ?? data['verifiedContributionNaira'] ?? data['observedContributionNaira'], 'Unavailable')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xff65776c)),
              ),
            ),
          const SizedBox(height: 7),
          Wrap(spacing: 7, children: [
            _badge(status),
            for (final entry in data.entries.take(3))
              Text('${_pretty(entry.key)}: ${entry.value}',
                  style:
                      const TextStyle(fontSize: 10, color: Color(0xff65776c))),
          ]),
        ])),
        PopupMenuButton<String>(
            tooltip: 'Record actions',
            onSelected: (action) => _recordAction(action, record),
            itemBuilder: (_) => [
                  if (_writeAllowed(_section))
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  for (final next in _nextStatuses(status))
                    if (next == 'APPROVED' || next == 'REJECTED'
                        ? _canApprove(record)
                        : (next == 'PUBLISHED'
                            ? _writeAllowed(_section)
                            : _writeAllowed(_section)))
                      PopupMenuItem(
                        value: 'status:$next',
                        child: Text(_pretty(next)),
                      ),
                  if (_section == 'material' ||
                      record['assetId'] != null ||
                      data['assetId'] != null)
                    const PopupMenuItem(
                        value: 'download',
                        child: Text('Download private asset')),
                ]),
      ]),
    );
  }

  Widget _badge(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: const Color(0xffeaf0e9),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: const TextStyle(
              fontSize: 9,
              letterSpacing: .4,
              fontWeight: FontWeight.w800,
              color: Color(0xff41634f))));
  Widget _emptyRecords() => Center(
      child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.inventory_2_outlined,
                size: 42, color: Color(0xff9aafa0)),
            const SizedBox(height: 12),
            Text(
                'No ${_titles[_section]?.toLowerCase() ?? 'records'} match yet',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xff355247))),
            const SizedBox(height: 5),
            const Text('Add a record when you have evidence to support it.',
                style: TextStyle(color: Color(0xff7b8d81), fontSize: 12)),
            if (_writeAllowed(_section))
              Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: OutlinedButton.icon(
                      onPressed: () => _editRecord(),
                      icon: const Icon(Icons.add),
                      label: const Text('Create first record'))),
          ])));

  Widget _teamView() => ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          const Expanded(
              child: Text('People accountable for growth',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xff21473c)))),
          if (widget.isHeadOffice)
            FilledButton.icon(
                onPressed: _createStaff,
                icon: const Icon(Icons.person_add_alt_1, size: 17),
                label: const Text('Add staff'))
        ]),
        const SizedBox(height: 12),
        if (_staff.isEmpty)
          _notice('No marketing staff listed',
              'Head Office can add a staff account and choose an existing Marketing role. Role assignment and permission changes remain in Staff Management.')
        else
          for (final member in _staff) _staffCard(member),
        if (_staff.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _notice('Role permissions',
                  'Head Office manages role assignment and grants in the existing Staff Management workflow.')),
      ]);
  Widget _staffCard(Map<String, dynamic> staff) {
    final role = staff['staffRoleId'] ?? staff['role'] ?? {};
    final roleMap =
        role is Map ? Map<String, dynamic>.from(role) : <String, dynamic>{};
    final name = _str(staff['fullName'] ?? staff['name'], 'Marketing staff');
    final id = _str(staff['_id'] ?? staff['id'], '');
    final status = _str(staff['status'], 'ACTIVE').toUpperCase();
    return Card(
        color: const Color(0xfffbfdf9),
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: const BorderSide(color: Color(0xffdce7de))),
        child: ListTile(
          leading: CircleAvatar(
              backgroundColor: const Color(0xffe2eee5),
              foregroundColor: const Color(0xff315b47),
              child: Text(name.isEmpty ? 'S' : name[0].toUpperCase())),
          title:
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
              '${_str(staff['email'])} · ${_str(roleMap['displayName'] ?? roleMap['name'], 'Marketing role')} · $status'),
          trailing: PopupMenuButton<String>(
              onSelected: (v) => _staffAction(v, id, staff),
              itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit contact')),
                    PopupMenuItem(
                        value: 'toggle', child: Text('Change account status'))
                  ]),
        ));
  }

  Future<void> _recordAction(String action, Map<String, dynamic> record) async {
    if (action == 'edit') {
      await _editRecord(record);
      return;
    }
    if (action == 'download') {
      try {
        final assetId = _str(
            record['assetId'] ??
                (record['data'] is Map ? record['data']['assetId'] : null),
            '');
        final response = await _api.downloadAsset(assetId);
        final saved = await FilePicker.platform.saveFile(
          dialogTitle: 'Save private marketing asset',
          fileName: _str(
              record['filename'] ??
                  (record['data'] is Map ? record['data']['filename'] : null),
              'servicepay-marketing-asset'),
          bytes: response.bodyBytes,
        );
        if (saved != null) _message('Private asset saved.');
      } catch (e) {
        _message('$e', failure: true);
      }
      return;
    }
    final nextStatus =
        action.startsWith('status:') ? action.substring('status:'.length) : '';
    if (nextStatus.isEmpty) return;
    if (nextStatus == 'PUBLISHED' && _section == 'content') {
      final data = record['data'] is Map
          ? Map<String, dynamic>.from(record['data'])
          : <String, dynamic>{};
      if (_str(data['publishedUrl'], '').isEmpty ||
          _str(data['publishedAt'], '').isEmpty) {
        _message(
            'Add the actual publication URL and date before marking content published.',
            failure: true);
        return;
      }
    }
    final reason = TextEditingController();
    final paymentEvidence = TextEditingController();
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('${_pretty(nextStatus)} record?'),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nextStatus == 'REJECTED'
                    ? 'A reason is required. The submitter cannot approve this record.'
                    : 'Move ${_str(record['title'])} to ${_pretty(nextStatus)}?'),
                if (nextStatus == 'REJECTED')
                  TextField(
                      controller: reason,
                      onChanged: (_) => setDialog(() {}),
                      decoration: const InputDecoration(labelText: 'Reason'),
                      maxLines: 3),
                if (nextStatus == 'PAID')
                  TextField(
                    controller: paymentEvidence,
                    onChanged: (_) => setDialog(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Payment evidence reference *',
                      helperText:
                          'Bookkeeping evidence only. This does not initiate or confirm a bank transfer.',
                    ),
                    maxLines: 2,
                  ),
              ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () =>
                    ((nextStatus == 'REJECTED' && reason.text.trim().isEmpty) ||
                            (nextStatus == 'PAID' &&
                                paymentEvidence.text.trim().isEmpty))
                        ? null
                        : Navigator.pop(ctx, nextStatus),
                child: Text(_pretty(nextStatus)))
          ],
        ),
      ),
    );
    if (selected == null) {
      _disposeAfterDialog([reason, paymentEvidence]);
      return;
    }
    try {
      if (['budget', 'expense'].contains(_section) &&
          !(widget.isHeadOffice && _can('marketing.budgets.approve'))) {
        throw Exception(
            'Only Head Office may approve budget or expense records.');
      }
      if (['content', 'report', 'strategy', 'proposal'].contains(_section) &&
          !_can('marketing.content.approve')) {
        throw Exception('Content approval permission is required.');
      }
      if (['strategy', 'proposal', 'partnership', 'contribution']
              .contains(_section) &&
          !widget.isHeadOffice) {
        throw Exception('Only Head Office may approve this record.');
      }
      if (_section == 'campaign' &&
          nextStatus == 'APPROVED' &&
          !widget.isHeadOffice) {
        throw Exception(
            'Only an independent Head Office reviewer may approve campaigns.');
      }
      if (nextStatus == 'PAID' &&
          !(widget.isHeadOffice && paymentEvidence.text.trim().isNotEmpty)) {
        throw Exception(
            'Head Office payment evidence is required for bookkeeping.');
      }
      if (nextStatus == 'APPROVED' && !_canApprove(record)) {
        throw Exception(
            'You cannot approve your own record or lack approval permission.');
      }
      await _api.transition(_section, _str(record['_id']), {
        'status': nextStatus,
        'reason': reason.text.trim(),
        'revision': _int(record['revision']),
        if (nextStatus == 'PAID')
          'paymentEvidence': paymentEvidence.text.trim(),
      });
      await _load(refresh: true);
      _message('Record moved to ${_pretty(nextStatus)}.');
    } catch (e) {
      _message('$e', failure: true);
    }
    _disposeAfterDialog([reason, paymentEvidence]);
  }

  Future<void> _editRecord([Map<String, dynamic>? existing]) async {
    if (!_writeAllowed(_section)) return;
    final recordData = existing?['data'] is Map
        ? Map<String, dynamic>.from(existing!['data'])
        : <String, dynamic>{};
    final title = TextEditingController(text: _str(existing?['title'], ''));
    final description =
        TextEditingController(text: _str(existing?['description'], ''));
    final fields = _fieldNames(_section);
    final attributionFields = _section == 'attribution';
    final customerId =
        TextEditingController(text: _str(existing?['customerId'], ''));
    final campaignId =
        TextEditingController(text: _str(existing?['campaignId'], ''));
    final officerId =
        TextEditingController(text: _str(existing?['officerId'], ''));
    String? selectedReceiptAsset;
    final controllers = <String, TextEditingController>{
      for (final f in fields)
        f: TextEditingController(text: _str(recordData[f], ''))
    };
    String? validationError;
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialog) => AlertDialog(
                  title: Text(existing == null
                      ? 'New ${_singularTitle(_section)}'
                      : 'Edit record'),
                  content: SizedBox(
                      width: 520,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        if (validationError != null)
                          _notice('Check this record', validationError!),
                        TextField(
                            controller: title,
                            decoration:
                                const InputDecoration(labelText: 'Title *')),
                        TextField(
                            controller: description,
                            maxLines: 2,
                            decoration: const InputDecoration(
                                labelText: 'Description')),
                        if (attributionFields) ...[
                          TextField(
                              controller: customerId,
                              decoration: const InputDecoration(
                                  labelText: 'Customer ID *',
                                  helperText:
                                      'Attribution reference only; no financial or account data.')),
                          TextField(
                              controller: campaignId,
                              decoration: const InputDecoration(
                                  labelText:
                                      'Campaign ID (required for campaign source)')),
                        ],
                        if (_section == 'task' || _section == 'report')
                          TextField(
                              controller: officerId,
                              decoration: const InputDecoration(
                                  labelText: 'Officer ID (optional)')),
                        for (final field in fields)
                          _recordFieldInput(field, controllers[field]!),
                        if (_section == 'attribution')
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _notice(
                                  'Evidence-confirmed manual attribution',
                                  'This is not automated tracking and does not represent every registration. Use a customer reference only for acquisition attribution; never enter account or payment details.')),
                        if (_section == 'social')
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _notice('Manual reporting only',
                                  'Enter evidence-sourced results. This workspace does not publish posts or automate social metrics.')),
                        if (_section == 'expense')
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _notice('Receipt required',
                                  'Expenses require an approved budget and uploaded receipt before submission.')),
                        if (_section == 'expense')
                          Row(children: [
                            Expanded(
                                child: Text(
                                    selectedReceiptAsset == null
                                        ? 'Receipt: not attached'
                                        : 'Receipt asset: $selectedReceiptAsset',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xff66796c)))),
                            TextButton.icon(
                                onPressed: () async {
                                  try {
                                    final result = await FilePicker.platform
                                        .pickFiles(
                                            withData: true,
                                            type: FileType.custom,
                                            allowedExtensions: const [
                                          'png',
                                          'jpg',
                                          'jpeg',
                                          'webp',
                                          'pdf'
                                        ]);
                                    if (result == null) return;
                                    final file = result.files.single;
                                    if (file.bytes == null ||
                                        file.bytes!.length > 8 * 1024 * 1024) {
                                      throw Exception(
                                          'Receipt must be an image or PDF under 8 MiB.');
                                    }
                                    final mime = _mime(file.extension ?? '');
                                    if (![
                                          'image/png',
                                          'image/jpeg',
                                          'image/webp',
                                          'application/pdf'
                                        ].contains(mime) ||
                                        !_magicMatches(file.bytes!, mime)) {
                                      throw Exception(
                                          'Receipt type does not match its contents.');
                                    }
                                    final uploaded = await _api.uploadAsset(
                                        file.name, mime, file.bytes!,
                                        idempotencyKey: _assetIdempotencyKey(
                                            file.name, file.bytes!));
                                    _completeAssetUpload(
                                        file.name, file.bytes!);
                                    final asset = uploaded['asset'] is Map
                                        ? uploaded['asset']
                                        : uploaded;
                                    setDialog(() => selectedReceiptAsset =
                                        _str(asset['_id'], ''));
                                  } catch (e) {
                                    setDialog(() => validationError = '$e');
                                  }
                                },
                                icon: const Icon(Icons.attach_file),
                                label: const Text('Attach receipt')),
                          ]),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () async {
                          final missing = _requiredFields(_section)
                              .where((f) => controllers[f]!.text.trim().isEmpty)
                              .toList();
                          if (title.text.trim().isEmpty) {
                            missing.insert(0, 'title');
                          }
                          if (missing.isNotEmpty) {
                            setDialog(() => validationError =
                                'Required: ${missing.map(_pretty).join(', ')}.');
                            return;
                          }
                          final data = <String, dynamic>{};
                          for (final f in fields) {
                            final v = controllers[f]!.text.trim();
                            if (v.isEmpty) continue;
                            if (_dateFields.contains(f)) {
                              final parsed = DateTime.tryParse(v);
                              if (parsed == null) {
                                setDialog(() => validationError =
                                    '${_pretty(f)} must be a valid ISO date.');
                                return;
                              }
                              data[f] = parsed.toUtc().toIso8601String();
                            } else {
                              data[f] = _numericFields.contains(f)
                                  ? num.tryParse(v) ?? v
                                  : v;
                            }
                          }
                          if (_section == 'campaign' ||
                              _section == 'partnership') {
                            final start =
                                DateTime.tryParse('${data['startsAt']}');
                            final end = DateTime.tryParse('${data['endsAt']}');
                            if (start == null ||
                                end == null ||
                                !end.isAfter(start)) {
                              setDialog(() => validationError =
                                  'Use valid ISO dates; the end must be after the start.');
                              return;
                            }
                          }
                          if (['budget', 'expense'].contains(_section) &&
                              (num.tryParse('${data['amountNaira']}') ?? 0) <=
                                  0) {
                            setDialog(() => validationError =
                                'Amount must be greater than zero.');
                            return;
                          }
                          if (attributionFields) {
                            if (customerId.text.trim().isEmpty) {
                              setDialog(() => validationError =
                                  'Customer ID is required for manual attribution.');
                              return;
                            }
                            final source =
                                '${data['source'] ?? ''}'.toUpperCase();
                            if (!const {'CAMPAIGN', 'REFERRAL'}
                                .contains(source)) {
                              setDialog(() => validationError =
                                  'Choose CAMPAIGN or REFERRAL as the attribution source.');
                              return;
                            }
                            if (source == 'CAMPAIGN' &&
                                campaignId.text.trim().isEmpty) {
                              setDialog(() => validationError =
                                  'Select or enter a campaign for campaign attribution.');
                              return;
                            }
                          }
                          if (_section == 'expense') {
                            if (selectedReceiptAsset == null &&
                                (recordData['assetId'] == null)) {
                              setDialog(() => validationError =
                                  'Upload and attach the receipt before submitting.');
                              return;
                            }
                            data['assetId'] =
                                selectedReceiptAsset ?? recordData['assetId'];
                          }
                          final payload = <String, dynamic>{
                            'title': title.text.trim(),
                            'description': description.text.trim(),
                            'data': data
                          };
                          if (attributionFields) {
                            payload['customerId'] = customerId.text.trim();
                            if (campaignId.text.trim().isNotEmpty) {
                              payload['campaignId'] = campaignId.text.trim();
                            }
                          }
                          if (officerId.text.trim().isNotEmpty) {
                            payload['officerId'] = officerId.text.trim();
                          }
                          Navigator.pop(ctx, payload);
                        },
                        child: Text(existing == null
                            ? 'Create record'
                            : 'Save changes'))
                  ],
                )));
    if (result == null) {
      _disposeAfterDialog([
        title,
        description,
        customerId,
        campaignId,
        officerId,
        ...controllers.values,
      ]);
      return;
    }
    try {
      if (existing == null) {
        _recordCreateIdempotencyKey ??=
            'mk_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(0x7fffffff)}';
        await _api.createRecord(_section, result,
            idempotencyKey: _recordCreateIdempotencyKey!);
        _recordCreateIdempotencyKey = null;
      } else {
        final payload = <String, dynamic>{
          'revision': _int(existing['revision'])
        };
        if (result['title'] != existing['title']) {
          payload['title'] = result['title'];
        }
        if (result['description'] != existing['description']) {
          payload['description'] = result['description'];
        }
        final oldData = existing['data'] is Map
            ? Map<String, dynamic>.from(existing['data'])
            : <String, dynamic>{};
        final changedData = Map<String, dynamic>.from(result['data'] as Map)
          ..removeWhere((k, v) => oldData[k] == v);
        if (changedData.isNotEmpty) {
          payload['data'] = changedData;
        }
        if (attributionFields &&
            customerId.text.trim() != _str(existing['customerId'], '')) {
          payload['customerId'] = customerId.text.trim();
        }
        if (attributionFields &&
            campaignId.text.trim() != _str(existing['campaignId'], '')) {
          payload['campaignId'] = campaignId.text.trim();
        }
        if (officerId.text.trim().isNotEmpty &&
            officerId.text.trim() != _str(existing['officerId'], '')) {
          payload['officerId'] = officerId.text.trim();
        }
        await _api.updateRecord(_section, _str(existing['_id']), payload);
      }
      await _load(refresh: true);
      _message(existing == null ? 'Record created.' : 'Record updated.');
    } catch (e) {
      _message('$e', failure: true);
    }
    _disposeAfterDialog([
      title,
      description,
      customerId,
      campaignId,
      officerId,
      ...controllers.values,
    ]);
  }

  Widget _recordFieldInput(String field, TextEditingController controller) {
    final List<String> options = switch (field) {
      'source' => const ['CAMPAIGN', 'REFERRAL'],
      'period' => const ['DAILY', 'WEEKLY', 'MONTHLY'],
      'channel' when _schema['channels'] is List =>
        (_schema['channels'] as List).map((value) => '$value').toList(),
      _ => const <String>[],
    };
    final label =
        '${_pretty(field)}${_requiredFields(_section).contains(field) ? ' *' : ''}';
    if (options.isNotEmpty) {
      return DropdownButtonFormField<String>(
        value: options.contains(controller.text) ? controller.text : null,
        decoration: InputDecoration(labelText: label),
        items: options
            .map((value) =>
                DropdownMenuItem(value: value, child: Text(_pretty(value))))
            .toList(),
        onChanged: (value) => controller.text = value ?? '',
      );
    }
    return TextField(
      controller: controller,
      keyboardType: _numericFields.contains(field)
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: _dateFields.contains(field)
            ? 'ISO date/time, e.g. 2025-06-04T12:00:00Z'
            : null,
      ),
    );
  }

  static const _numericFields = {
    'budgetNaira',
    'amountNaira',
    'acquired',
    'completedTasks',
    'reach',
    'impressions',
    'engagements',
    'targetValue',
    'value'
  };
  static const _dateFields = {
    'startsAt',
    'endsAt',
    'dueAt',
    'scheduledAt',
    'publishedAt',
    'incurredAt',
    'occurredAt',
    'reportedAt'
  };
  List<String> _fieldNames(String kind) {
    final dynamic kinds = _schema['kinds'];
    final dynamic schemaKind = kinds is Map ? kinds[kind] : null;
    final dynamic fields = _schema['fields'];
    final dynamic schemaFields = fields is Map ? fields[kind] : null;
    if (schemaFields is List) {
      return schemaFields.map((e) => '$e').toList();
    }
    if (schemaKind is Map && schemaKind['fields'] is List) {
      return (schemaKind['fields'] as List).map((e) => '$e').toList();
    }
    return switch (kind) {
      'campaign' => [
          'objective',
          'channel',
          'audience',
          'startsAt',
          'endsAt',
          'budgetNaira'
        ],
      'task' => ['dueAt', 'responsibility'],
      'report' => [
          'period',
          'startsAt',
          'endsAt',
          'acquired',
          'completedTasks',
          'evidence'
        ],
      'budget' => ['amountNaira', 'category', 'evidence'],
      'expense' => [
          'amountNaira',
          'category',
          'budgetId',
          'assetId',
          'incurredAt'
        ],
      'attribution' => [
          'source',
          'referralCode',
          'utmSource',
          'utmMedium',
          'utmCampaign',
          'evidence'
        ],
      'content' => [
          'scheduledAt',
          'channel',
          'assetId',
          'publishedUrl',
          'publishedAt'
        ],
      'partnership' => ['organization', 'evidence', 'startsAt', 'endsAt'],
      'contribution' => ['transactionId', 'evidence'],
      'social' => [
          'channel',
          'reach',
          'impressions',
          'engagements',
          'evidence',
          'reportedAt'
        ],
      'strategy' || 'proposal' => ['evidence'],
      'target' => ['metric', 'value', 'period', 'startsAt', 'endsAt'],
      'attendance' => ['occurredAt', 'evidence'],
      _ => [],
    };
  }

  Set<String> _requiredFields(String kind) => switch (kind) {
        'campaign' => {'objective', 'channel', 'startsAt', 'endsAt'},
        'budget' => {'amountNaira', 'category'},
        'expense' => {
            'amountNaira',
            'category',
            'budgetId',
            'incurredAt',
          },
        'attribution' => {'source', 'evidence'},
        'report' => {'period', 'startsAt', 'endsAt', 'acquired', 'evidence'},
        'strategy' || 'proposal' => {'evidence'},
        'social' => {'channel', 'evidence', 'reportedAt'},
        'attendance' => {'occurredAt', 'evidence'},
        'partnership' => {'organization', 'evidence', 'startsAt', 'endsAt'},
        'contribution' => {'transactionId', 'evidence'},
        'target' => {'metric', 'value', 'period', 'startsAt', 'endsAt'},
        _ => <String>{},
      };

  Future<void> _uploadAsset() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
          withData: true,
          type: FileType.custom,
          allowedExtensions: const [
            'png',
            'jpg',
            'jpeg',
            'webp',
            'mp4',
            'pdf'
          ]);
      if (picked == null || picked.files.isEmpty) return;
      final f = picked.files.single;
      final bytes = f.bytes;
      if (bytes == null) {
        throw Exception('Could not read the selected file.');
      }
      if (bytes.length > 8 * 1024 * 1024) {
        throw Exception('File exceeds the 8 MiB limit.');
      }
      final mime = _mime(f.extension ?? '');
      if (mime.isEmpty || !_magicMatches(bytes, mime)) {
        throw Exception(
            'File type does not match its contents. Use PNG, JPEG, WEBP, MP4 or PDF.');
      }
      final uploaded = await _api.uploadAsset(f.name, mime, bytes,
          idempotencyKey: _assetIdempotencyKey(f.name, bytes));
      _completeAssetUpload(f.name, bytes);
      _recentAssets.add({
        ...uploaded,
        'filename': uploaded['filename'] ?? f.name,
        'assetId': uploaded['_id'],
        'title': uploaded['filename'] ?? f.name,
        'status': 'PRIVATE',
      });
      _message('Private material uploaded.');
      await _load(refresh: true);
    } catch (e) {
      _message('$e', failure: true);
    }
  }

  String _mime(String extension) => switch (extension.toLowerCase()) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'mp4' => 'video/mp4',
        'pdf' => 'application/pdf',
        _ => '',
      };
  bool _magicMatches(List<int> b, String mime) {
    bool starts(List<int> signature) =>
        b.length >= signature.length &&
        List.generate(signature.length, (i) => b[i] == signature[i])
            .every((e) => e);
    return switch (mime) {
      'image/png' => starts([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      'image/jpeg' => starts([0xff, 0xd8, 0xff]),
      'image/webp' => b.length >= 12 &&
          String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(b.sublist(8, 12)) == 'WEBP',
      'application/pdf' => starts([0x25, 0x50, 0x44, 0x46, 0x2d]),
      'video/mp4' =>
        b.length >= 12 && String.fromCharCodes(b.sublist(4, 8)) == 'ftyp',
      _ => false,
    };
  }

  Future<void> _export(String format) async {
    try {
      final filters = <String, String>{
        ..._dateQuery,
        if (_section != 'overview' && _search.isNotEmpty) 'search': _search,
        if (_section != 'overview' && _status.isNotEmpty) 'status': _status,
      };
      final response = await _api.export(_section, format, query: filters);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Marketing export',
        fileName:
            'servicepay-$_section-${DateTime.now().toIso8601String().substring(0, 10)}.$format',
        bytes: Uint8List.fromList(response.bodyBytes),
      );
      if (path != null) _message('Export saved.');
    } catch (e) {
      _message('$e', failure: true);
    }
  }

  Future<void> _createStaff() async {
    final fields = {
      for (final key in ['fullName', 'email', 'phone', 'password'])
        key: TextEditingController()
    };
    String? roleId;
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: const Text('Add marketing staff'),
                  content: SizedBox(
                      width: 440,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        for (final entry in fields.entries)
                          TextField(
                              controller: entry.value,
                              obscureText: entry.key == 'password',
                              keyboardType: entry.key == 'email'
                                  ? TextInputType.emailAddress
                                  : TextInputType.text,
                              decoration: InputDecoration(
                                  labelText: _pretty(entry.key))),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                            value: roleId,
                            decoration: const InputDecoration(
                                labelText: 'Marketing role *'),
                            items: _roles
                                .where((r) =>
                                    '${r['department']}'.toUpperCase() ==
                                    'MARKETING')
                                .map((r) {
                              final id = _str(r['_id'] ?? r['id'], '');
                              return DropdownMenuItem(
                                  value: id,
                                  child: Text(
                                      _str(r['displayName'] ?? r['name'])));
                            }).toList(),
                            onChanged: (value) => update(() => roleId = value)),
                        if (_roles
                            .where((r) =>
                                '${r['department']}'.toUpperCase() ==
                                'MARKETING')
                            .isEmpty)
                          const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                  'Create a MARKETING role in Staff Management first.',
                                  style: TextStyle(color: Colors.red))),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () {
                          if (fields.values.any((c) => c.text.trim().isEmpty) ||
                              roleId == null) {
                            return;
                          }
                          Navigator.pop(ctx, {
                            'fullName': fields['fullName']!.text.trim(),
                            'email': fields['email']!.text.trim(),
                            'phone': fields['phone']!.text.trim(),
                            'password': fields['password']!.text,
                            'roleId': roleId
                          });
                        },
                        child: const Text('Create staff'))
                  ],
                )));
    for (final c in fields.values) {
      c.clear();
      c.dispose();
    }
    if (result == null) return;
    try {
      await _api.createStaff(result);
      _message('Marketing staff created.');
      await _load(refresh: true);
    } catch (e) {
      _message('$e', failure: true);
    }
  }

  Future<void> _staffAction(
      String action, String id, Map<String, dynamic> staff) async {
    if (action == 'edit') {
      final values = <String, TextEditingController>{
        'fullName': TextEditingController(
            text: _str(staff['fullName'] ?? staff['name'], '')),
        'email': TextEditingController(text: _str(staff['email'], '')),
        'phone': TextEditingController(text: _str(staff['phone'], '')),
      };
      final result = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Edit staff contact'),
                  content: SizedBox(
                      width: 420,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        for (final e in values.entries)
                          TextField(
                              controller: e.value,
                              decoration:
                                  InputDecoration(labelText: _pretty(e.key)))
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, {
                              for (final e in values.entries)
                                e.key: e.value.text.trim()
                            }),
                        child: const Text('Save'))
                  ]));
      for (final c in values.values) {
        c.dispose();
      }
      if (result == null) return;
      try {
        await _api.updateStaff(id, result);
        await _load(refresh: true);
        _message('Staff details updated.');
      } catch (e) {
        _message('$e', failure: true);
      }
      return;
    }
    final next = _str(staff['status'], 'ACTIVE').toUpperCase() == 'ACTIVE'
        ? 'SUSPENDED'
        : 'ACTIVE';
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text('$next account?'),
                content:
                    Text('This changes the staff account status to $next.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(next))
                ]));
    if (ok != true) return;
    try {
      await _api.staffStatus(id, next);
      await _load(refresh: true);
      _message('Staff status updated.');
    } catch (e) {
      _message('$e', failure: true);
    }
  }

  Widget _skeleton() => ListView(padding: const EdgeInsets.all(22), children: [
        for (int i = 0; i < 4; i++)
          Container(
              height: i == 0 ? 110 : 72,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: const Color(0xffe5ece6),
                  borderRadius: BorderRadius.circular(13)))
      ]);
  Widget _errorPanel() => Center(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_outlined,
                    size: 42, color: Color(0xff9a6d48)),
                const SizedBox(height: 12),
                Text(
                    _error?.contains('503') == true
                        ? 'Marketing storage is not provisioned yet'
                        : 'Marketing data is unavailable',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xff345247))),
                const SizedBox(height: 7),
                Text(
                    _error?.contains('503') == true
                        ? 'The readiness check returns HTTP 503 until separately approved storage provisioning is completed. No production resources were changed.'
                        : (_error ?? 'Try again in a moment.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xff718278))),
                const SizedBox(height: 14),
                FilledButton.icon(
                    onPressed: () => _load(refresh: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry')),
              ]))));
  void _message(String text, {bool failure = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor:
            failure ? const Color(0xff9c4937) : const Color(0xff315d49),
        behavior: SnackBarBehavior.floating));
  }
}
