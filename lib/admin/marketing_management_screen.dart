import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'marketing_api.dart';
import 'marketing_department_screen.dart';
import 'marketing_performance_screen.dart';

@visibleForTesting
bool canUseMarketingManagement({required String role}) {
  final value = role.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_');
  return const {
    'HEAD_OFFICE',
    'ADMIN',
    'SUPER_ADMIN',
    'HEAD_OFFICE_ADMIN',
    'SERVICEPAY_SUPER_ADMIN',
  }.contains(value);
}

@visibleForTesting
(DateTime, DateTime) marketingTargetPeriodBounds(String period, DateTime at) {
  final now = at.toUtc();
  var from = DateTime.utc(now.year, now.month, now.day);
  if (period == 'WEEKLY') {
    from = from.subtract(Duration(days: from.weekday - 1));
  } else if (period == 'MONTHLY') {
    from = DateTime.utc(now.year, now.month);
  } else if (period == 'YEARLY') {
    from = DateTime.utc(now.year);
  }
  final to = switch (period) {
    'WEEKLY' => from.add(const Duration(days: 7)),
    'MONTHLY' => DateTime.utc(from.year, from.month + 1),
    'YEARLY' => DateTime.utc(from.year + 1),
    _ => from.add(const Duration(days: 1)),
  };
  return (from, to);
}

@visibleForTesting
bool isMarketingManagerRole(String? role) {
  final normalized = (role ?? '')
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  return normalized.contains('MANAGER') ||
      normalized.contains('HEAD OF MARKETING');
}

class MarketingManagementScreen extends StatefulWidget {
  const MarketingManagementScreen({super.key, this.api});
  final MarketingApi? api;

  @override
  State<MarketingManagementScreen> createState() =>
      _MarketingManagementScreenState();
}

class _MarketingManagementScreenState extends State<MarketingManagementScreen>
    with WidgetsBindingObserver {
  static const _ink = Color(0xff173c35);
  static const _mint = Color(0xffe8f0e9);
  static const _periods = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'];
  static const _metrics = <String, String>{
    'NEW_REGISTRATIONS': 'New registrations',
    'ACQUISITIONS': 'Customer acquisition',
    'FIRST_TRANSACTIONS': 'First transactions',
    'AGENT_ACQUISITIONS': 'Agent / aggregator acquisition',
    'MERCHANT_ACQUISITIONS': 'Merchant acquisition',
    'PARTNERSHIPS': 'Business partnerships',
    'TASKS': 'Tasks',
    'REPORTS': 'Reports',
    'CONTENT': 'Content',
    'ATTENDANCE': 'Attendance',
    'CAMPAIGNS': 'Campaigns',
    'ENGAGEMENT': 'Engagement',
    'CUSTOM': 'Other KPI',
  };
  static const _sections = <(String, IconData)>[
    ('Marketing Overview', Icons.space_dashboard_outlined),
    ('Marketing Manager', Icons.manage_accounts_outlined),
    ('Marketing Staff', Icons.groups_2_outlined),
    ('Target Management', Icons.flag_outlined),
    ('Performance Reports', Icons.assessment_outlined),
    ('Activity & Attendance', Icons.fact_check_outlined),
    ('Marketing Settings', Icons.tune_outlined),
  ];

  late final MarketingApi _api = widget.api ?? MarketingApi();
  final _searchController = TextEditingController();
  Timer? _refreshTimer;
  String _section = 'Marketing Overview';
  String _period = 'MONTHLY';
  String _performance = '';
  String _targetStatus = '';
  String _search = '';
  DateTime? _from;
  DateTime? _to;
  bool _loading = true;
  bool _requestInFlight = false;
  bool _refreshPending = false;
  bool _editorOpen = false;
  bool _exporting = false;
  bool _superAdmin = false;
  String? _error;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _team = [];
  List<Map<String, dynamic>> _activity = [];
  String? _activityError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_isVisible && !_editorOpen) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _searchController.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : <Map<String, dynamic>>[];
  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  String _text(dynamic value, [String fallback = '—']) =>
      value == null || '$value'.trim().isEmpty ? fallback : '$value';
  num? _num(dynamic value) => num.tryParse('$value');
  String _pretty(String value) => value
      .toLowerCase()
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
  Map<String, String> get _query => {
        'period': _period,
        if (_from != null) 'from': _from!.toUtc().toIso8601String(),
        if (_to != null)
          'to': _to!.add(const Duration(days: 1)).toUtc().toIso8601String(),
        if (_search.isNotEmpty) 'search': _search,
        if (_performance.isNotEmpty) 'performance': _performance,
      };

  Future<void> _load({bool quiet = false}) async {
    if (_requestInFlight) {
      _refreshPending = true;
      return;
    }
    _requestInFlight = true;
    if (mounted) {
      setState(() {
        if (!quiet) _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _api.management(_query),
        _api.team(),
        _api.performanceContext(),
      ]);
      if (!mounted) return;
      _data = results[0];
      _team = _maps(results[1]['items']);
      _superAdmin = results[2]['superAdmin'] == true;
      if (_section == 'Activity & Attendance') await _loadActivity();
    } catch (error) {
      _error = '$error'.replaceFirst('Exception: ', '');
    } finally {
      _requestInFlight = false;
      if (mounted) setState(() => _loading = false);
      if (_refreshPending && mounted) {
        _refreshPending = false;
        scheduleMicrotask(() => _load(quiet: true));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isVisible && !_editorOpen) {
      _load(quiet: true);
    }
  }

  bool get _isVisible =>
      mounted &&
      TickerMode.of(context) &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  Future<void> _loadActivity() async {
    try {
      final result = await _api.activity(limit: 50);
      if (!mounted) return;
      _activity = _maps(result['items']);
      _activityError = null;
    } catch (error) {
      _activityError = '$error'.replaceFirst('Exception: ', '');
    }
  }

  void _changeFilter(VoidCallback change) {
    setState(change);
    _load();
  }

  Future<void> _selectDates() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _from != null && _to != null
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
      helpText: 'Filter marketing performance dates',
    );
    if (selected == null) return;
    _changeFilter(() {
      _from = selected.start;
      _to = selected.end;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff2f6f2),
      body: SafeArea(
        child: Column(children: [
          _header,
          _filters,
          _navigation,
          Expanded(
            child: _loading
                ? _skeleton
                : _error != null
                    ? _errorView
                    : RefreshIndicator(
                        onRefresh: () => _load(),
                        child: ListView(
                          key: PageStorageKey<String>(_section),
                          padding: const EdgeInsets.fromLTRB(16, 15, 16, 28),
                          children: [_sectionBody],
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget get _header => Container(
        padding: const EdgeInsets.fromLTRB(18, 15, 14, 14),
        color: const Color(0xfffbfdf9),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: _mint, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.query_stats_rounded, color: _ink),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Marketing Management',
                  style: TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800, color: _ink)),
              Text('Head Office control center · shared department records',
                  style: TextStyle(fontSize: 11, color: Color(0xff6d7e74))),
            ]),
          ),
          IconButton(
            tooltip: 'Refresh marketing data',
            onPressed: _requestInFlight ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ]),
      );

  Widget get _filters => Container(
        color: const Color(0xfffbfdf9),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 135,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('marketing-period-filter'),
                  isExpanded: true,
                  value: _period,
                  decoration: const InputDecoration(
                      labelText: 'Target period', isDense: true),
                  items: _periods
                      .map((value) => DropdownMenuItem(
                          value: value, child: Text(_pretty(value))))
                      .toList(),
                  onChanged: (value) => value == null
                      ? null
                      : _changeFilter(() => _period = value),
                ),
              ),
              SizedBox(
                width: 155,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('marketing-performance-filter'),
                  isExpanded: true,
                  value: _performance,
                  decoration: const InputDecoration(
                      labelText: 'Performance', isDense: true),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All statuses')),
                    DropdownMenuItem(
                        value: 'MEETING', child: Text('Meeting targets')),
                    DropdownMenuItem(
                        value: 'BELOW', child: Text('Below targets')),
                    DropdownMenuItem(
                        value: 'UNAVAILABLE', child: Text('Unavailable')),
                  ],
                  onChanged: (value) =>
                      _changeFilter(() => _performance = value ?? ''),
                ),
              ),
              SizedBox(
                width: 210,
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Search staff',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 19),
                    suffixIcon: IconButton(
                      tooltip: 'Apply search',
                      onPressed: () => _changeFilter(
                          () => _search = _searchController.text.trim()),
                      icon: const Icon(Icons.arrow_forward, size: 18),
                    ),
                  ),
                  onSubmitted: (value) =>
                      _changeFilter(() => _search = value.trim()),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _selectDates,
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text(_from == null
                    ? 'Date range'
                    : '${_date(_from)} – ${_date(_to)}'),
              ),
              if (_from != null ||
                  _search.isNotEmpty ||
                  _performance.isNotEmpty)
                TextButton(
                  onPressed: () => _changeFilter(() {
                    _from = null;
                    _to = null;
                    _search = '';
                    _performance = '';
                    _searchController.clear();
                  }),
                  child: const Text('Clear filters'),
                ),
            ]),
      );

  Widget get _navigation => Container(
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          color: Color(0xfffbfdf9),
          border: Border(bottom: BorderSide(color: Color(0xffdce7de))),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final section in _sections)
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 8),
                child: ChoiceChip(
                  avatar: Icon(section.$2, size: 16),
                  label: Text(section.$1),
                  selected: _section == section.$1,
                  onSelected: (_) {
                    setState(() => _section = section.$1);
                    if (section.$1 == 'Activity & Attendance') _loadActivity();
                    if (section.$1 == 'Marketing Overview') _load(quiet: true);
                  },
                ),
              ),
          ]),
        ),
      );

  Widget get _sectionBody => switch (_section) {
        'Marketing Overview' => _overview,
        'Marketing Manager' => _people(managerOnly: true),
        'Marketing Staff' => _people(managerOnly: false),
        'Target Management' => _targetManagement,
        'Performance Reports' => _reportsView,
        'Activity & Attendance' => _activityView,
        'Marketing Settings' => _settings,
        _ => _overview,
      };

  Widget get _reportsView => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Performance reports',
              'Department, manager and individual views use the existing performance records.'),
          _panel(
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _exporting ? null : () => _export('csv'),
                icon: const Icon(Icons.table_view_outlined, size: 18),
                label: const Text('Export CSV'),
              ),
              OutlinedButton.icon(
                onPressed: _exporting ? null : () => _export('xlsx'),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Export Excel'),
              ),
              if (_exporting)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 760,
            child: MarketingPerformanceScreen(
              key: ValueKey(
                  'marketing-report-$_period-${_from?.millisecondsSinceEpoch}-${_to?.millisecondsSinceEpoch}'),
              api: _api,
              initialView: 'department',
              initialPeriod: _period,
              initialFrom: _from,
              initialTo: _to,
            ),
          ),
        ],
      );

  Widget get _overview {
    final summary = _map(_data['summary']);
    final periods = _maps(_data['periods']);
    final cards = <(String, dynamic, String, IconData)>[
      (
        'Team members',
        summary['teamMembers'],
        'All marketing staff',
        Icons.groups_outlined
      ),
      (
        'Assigned targets',
        summary['assignedTargets'],
        'Shared target records',
        Icons.flag_outlined
      ),
      (
        'Achieved targets',
        summary['verifiedAchievements'],
        'Count of measurable targets achieved',
        Icons.verified_outlined
      ),
      (
        'Staff meeting targets',
        summary['staffMeetingTargets'],
        'Current period',
        Icons.trending_up_outlined
      ),
      (
        'Staff below targets',
        summary['staffBelowTargets'],
        'Current period',
        Icons.trending_down_outlined
      ),
      (
        'Pending reports',
        summary['pendingReports'],
        'Awaiting review',
        Icons.pending_actions_outlined
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeading('Department pulse',
          'Verified results only · ${_text(_data['from'])} to ${_text(_data['to'])}'),
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth < 570
            ? constraints.maxWidth
            : (constraints.maxWidth - 16) / 3;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final card in cards)
            SizedBox(
                width: width, child: _kpi(card.$1, card.$2, card.$3, card.$4)),
        ]);
      }),
      const SizedBox(height: 12),
      _panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeading('Target vs achievement',
              'Period summaries returned by the marketing records service.'),
          if (periods.isEmpty)
            _emptyPanel('No period comparison data is available.')
          else
            for (final row in periods) _periodComparison(row),
          const SizedBox(height: 12),
          _labelValue('Overall department performance',
              _percent(summary['departmentPerformance'])),
          const SizedBox(height: 8),
          Text(
              _text(_data['note'],
                  'Comparisons use available verified evidence. Missing evidence is not treated as zero.'),
              style: const TextStyle(
                  fontSize: 11, color: Color(0xff64766c), height: 1.4)),
        ]),
      ),
      const SizedBox(height: 12),
      _panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeading('Staff snapshot',
              'Open an individual record without leaving the shared team data.'),
          for (final member in _maps(_data['staff']).take(6)) _staffRow(member),
          if (_maps(_data['staff']).isEmpty)
            _emptyPanel('No staff records match the current filters.'),
        ]),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => MarketingDepartmentScreen(
              permissions: const {'marketing.view'},
              isHeadOffice: true,
              api: _api,
            ),
          )),
          icon: const Icon(Icons.open_in_new, size: 17),
          label: const Text('Open marketing department workspace'),
        ),
      ),
    ]);
  }

  Widget _periodComparison(Map<String, dynamic> row) {
    final achievement = _num(row['achievementPercent']);
    final assigned = row['assignedTargets'];
    final target = _num(row['target'] ?? row['assignedValue']);
    final actual = _num(row['actual'] ?? row['verifiedAchievements']);
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(_pretty(_text(row['period'], 'Period')),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: _ink))),
          Text(
              achievement == null
                  ? 'Unavailable'
                  : '${achievement.toStringAsFixed(1)}%',
              style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: achievement == null
              ? Container(
                  height: 7,
                  decoration: BoxDecoration(
                    color: _mint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                )
              : LinearProgressIndicator(
                  value: (achievement / 100).clamp(0.0, 1.0).toDouble(),
                  minHeight: 7,
                  backgroundColor: _mint,
                  color: const Color(0xff438466),
                ),
        ),
        const SizedBox(height: 4),
        Text(
            target != null && actual != null
                ? 'Verified actual ${actual.toString()} of target ${target.toString()}'
                : 'Assigned targets ${_text(assigned, 'Unavailable')} · verified actual ${actual?.toString() ?? 'Unavailable'} · target value unavailable',
            style: const TextStyle(fontSize: 10, color: Color(0xff748279))),
      ]),
    );
  }

  Widget _people({required bool managerOnly}) {
    final people = _maps(_data['staff']);
    final filtered = people.where((person) {
      final isManager = isMarketingManagerRole(
          '${person['role'] ?? person['position'] ?? ''}');
      return managerOnly ? isManager : !isManager;
    }).toList();
    if (managerOnly && filtered.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeading('Marketing Manager',
            'Manager performance remains separate from department-wide totals.'),
        _emptyPanel(
            'No manager record was returned for this period. No profile has been inferred from department totals.'),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeading(
        managerOnly ? 'Marketing Manager' : 'Marketing Staff',
        managerOnly
            ? 'Independent profile, assigned goals and verified manager outcomes.'
            : 'Staff profiles, contact details, assignments and verified outcomes.',
      ),
      if (filtered.isEmpty)
        _emptyPanel(
            'No staff records match the current search and performance filters.')
      else
        for (final person in filtered) _personCard(person),
    ]);
  }

  Widget _personCard(Map<String, dynamic> person) {
    final id = _text(person['id'] ?? person['_id'], '');
    final teamRecord = _team.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item != null && _text(item['id'] ?? item['_id'], '') == id,
          orElse: () => null,
        );
    final contact = teamRecord ?? person;
    final targets = _maps(person['targets']);
    final name = _text(person['name'] ?? contact['name'] ?? contact['fullName'],
        'Marketing team member');
    return _panel(
      margin: const EdgeInsets.only(bottom: 9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
              backgroundColor: _mint,
              foregroundColor: _ink,
              child: Text(_initials(name))),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: _ink)),
                Text(
                    _text(
                        person['position'] ??
                            person['role'] ??
                            contact['position'],
                        'Position unavailable'),
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xff718178))),
                Text(
                    '${_text(contact['email'], 'Email unavailable')} · ${_text(contact['phone'], 'Phone unavailable')}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xff718178))),
              ])),
          _tag(_text(person['status'], 'STATUS UNAVAILABLE')),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 7, runSpacing: 7, children: [
          _metric('Achievement', person['achievement']),
          _metric('Score', person['score']),
          _metric('Rank', person['rank']),
          _metric('Acquisitions', person['acquisitions']),
          _metric('First transactions', person['firstTransactions']),
          _metric('Reports pending', person['outstandingReports']),
          _metric('Reports submitted', person['submittedReports']),
        ]),
        if (targets.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final target in targets) _targetProgress(target, compact: true),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: id.isEmpty
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => MarketingPerformanceScreen(
                        api: _api,
                        initialView: 'department',
                        initialStaffId: id,
                      ),
                    )),
            icon: const Icon(Icons.person_search_outlined, size: 17),
            label: const Text('Open performance detail'),
          ),
        ),
      ]),
    );
  }

  Widget get _targetManagement {
    final targets = _filterTargets(_data['targets'], scope: 'INDIVIDUAL');
    final departmentTargets =
        _filterTargets(_data['departmentTargets'], scope: 'DEPARTMENT');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: _sectionHeading('Target management',
                'One target record powers the manager, staff and Head Office views.')),
        FilledButton.icon(
            onPressed: () => _editTarget(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New target')),
      ]),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final status in const [
          '',
          'ACTIVE',
          'PAUSED',
          'INACTIVE',
          'COMPLETED'
        ])
          ChoiceChip(
            label: Text(status.isEmpty ? 'All' : _pretty(status)),
            selected: _targetStatus == status,
            onSelected: (_) => setState(() => _targetStatus = status),
          ),
      ]),
      const SizedBox(height: 8),
      if (targets.isEmpty && departmentTargets.isEmpty)
        _emptyPanel('No target records match these filters.')
      else ...[
        for (final target in targets) _targetCard(target),
      ],
      if (departmentTargets.isNotEmpty) ...[
        const SizedBox(height: 12),
        _sectionHeading('Department-wide targets',
            'Department scope has no individual officer assignment.'),
        for (final target in departmentTargets) _targetCard(target),
      ],
    ]);
  }

  List<Map<String, dynamic>> _filterTargets(
    dynamic records, {
    required String scope,
  }) {
    return _maps(records).where((target) {
      final data = _map(target['data']);
      if (_text(data['scope'], 'INDIVIDUAL').toUpperCase() != scope) {
        return false;
      }
      if (_targetStatus.isNotEmpty &&
          '${target['status'] ?? ''}'.toUpperCase() != _targetStatus) {
        return false;
      }
      if ('${data['period'] ?? ''}'.toUpperCase() != _period) return false;
      if (_from != null || _to != null) {
        final startsAt = DateTime.tryParse('${data['startsAt'] ?? ''}');
        final endsAt = DateTime.tryParse('${data['endsAt'] ?? ''}');
        if (startsAt == null || endsAt == null) return false;
        if (_from != null && endsAt.isBefore(_from!)) return false;
        if (_to != null &&
            startsAt.isAfter(_to!.add(const Duration(days: 1)))) {
          return false;
        }
      }
      if (_search.isNotEmpty) {
        final officerId = _text(target['officerId'], '');
        final staff = _maps(_data['staff'])
                .where(
                  (person) =>
                      _text(person['id'] ?? person['_id'], '') == officerId,
                )
                .firstOrNull ??
            _team
                .where((person) =>
                    _text(person['id'] ?? person['_id'], '') == officerId)
                .firstOrNull;
        final searchable = [
          target['title'],
          data['objective'],
          data['customMetric'],
          staff?['name'],
          staff?['position'],
          staff?['role'],
        ].whereType<Object>().join(' ').toLowerCase();
        if (!searchable.contains(_search.toLowerCase())) return false;
      }
      if (_performance.isNotEmpty) {
        final percent = _num(target['achievementPercent']);
        final outcome = '${target['outcome'] ?? ''}'.toUpperCase();
        final isUnavailable = percent == null;
        final meets =
            {'MEETING', 'MET', 'ACHIEVED', 'COMPLETE'}.contains(outcome) ||
                (percent != null && percent >= 100);
        final isBelow = {'BELOW', 'NOT_MET', 'IN_PROGRESS'}.contains(outcome) ||
            (percent != null && percent < 100);
        if (_performance == 'UNAVAILABLE' && !isUnavailable) return false;
        if (_performance == 'MEETING' && !meets) return false;
        if (_performance == 'BELOW' && !isBelow) return false;
      }
      return true;
    }).toList();
  }

  Widget _targetCard(Map<String, dynamic> target) {
    final data = _map(target['data']);
    final scope = _text(data['scope'], 'INDIVIDUAL').toUpperCase();
    final officerId = _text(target['officerId'], '');
    final officer = _maps(_data['staff'])
        .where((item) => _text(item['id'] ?? item['_id'], '') == officerId)
        .firstOrNull;
    final metric = _text(data['metric'], 'Metric');
    final title = _text(target['title'], _metrics[metric] ?? _pretty(metric));
    final status = _text(target['status'], 'UNAVAILABLE').toUpperCase();
    final adminAssigned = _text(data['authority'], '').toUpperCase() == 'ADMIN';
    return _panel(
      margin: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: _ink)),
                Text(
                    '${_metrics[metric] ?? _pretty(metric)} · ${_pretty(_text(data['period'], 'Period'))}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xff718178))),
              ])),
          _tag(status),
          PopupMenuButton<String>(
            tooltip: 'Target actions',
            onSelected: (action) {
              if (action == 'edit') {
                _editTarget(target);
              }
              if (action.startsWith('status:')) {
                _transitionTarget(target, action.substring(7));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit target')),
              if (status == 'ACTIVE')
                const PopupMenuItem(
                    value: 'status:PAUSED', child: Text('Pause target')),
              if (status == 'PAUSED')
                const PopupMenuItem(
                    value: 'status:ACTIVE', child: Text('Resume target')),
              if (status == 'ACTIVE' || status == 'PAUSED')
                const PopupMenuItem(
                    value: 'status:INACTIVE', child: Text('Deactivate target')),
            ],
          ),
        ]),
        const SizedBox(height: 7),
        Text(
            '${scope == 'DEPARTMENT' ? 'Entire department' : _text(officer?['name'], 'Assigned staff unavailable')} · goal ${_text(data['value'], 'Unavailable')}',
            style: const TextStyle(
                fontSize: 12, color: _ink, fontWeight: FontWeight.w600)),
        Text(
            '${_text(data['startsAt'])} — ${_text(data['endsAt'])} · ${_text(data['objective'], 'No objective supplied')}',
            style: const TextStyle(fontSize: 10, color: Color(0xff718178))),
        if (adminAssigned)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Admin-assigned · shared record · changes are audited.',
                style: TextStyle(fontSize: 10, color: Color(0xff526d60))),
          ),
        _targetProgress(target),
      ]),
    );
  }

  Widget _targetProgress(Map<String, dynamic> target, {bool compact = false}) {
    final data = _map(target['data']);
    final actual = _num(target['actual']);
    final goal = _num(data['value']);
    final percent = _num(target['achievementPercent']);
    final progress =
        percent == null ? null : (percent / 100).clamp(0.0, 1.0).toDouble();
    final unavailableMetric = const {
          'AGENT_ACQUISITIONS',
          'MERCHANT_ACQUISITIONS'
        }.contains('${data['metric']}'.toUpperCase()) &&
        actual == null;
    return Padding(
      padding: EdgeInsets.only(top: compact ? 5 : 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        progress == null
            ? Container(
                height: 6,
                decoration: BoxDecoration(
                  color: _mint,
                  borderRadius: BorderRadius.circular(8),
                ),
              )
            : LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: _mint,
                color: const Color(0xff438466)),
        const SizedBox(height: 4),
        Text(
          '${actual?.toString() ?? (unavailableMetric ? 'Unavailable · trusted evidence source pending' : 'Unavailable')} / ${goal?.toString() ?? 'Unavailable'}'
          ' · ${percent == null ? 'Achievement unavailable' : '${percent.toStringAsFixed(1)}%'}'
          '${target['remaining'] == null ? '' : ' · ${target['remaining']} remaining'}',
          style: const TextStyle(fontSize: 10, color: Color(0xff67786e)),
        ),
      ]),
    );
  }

  Future<void> _editTarget([Map<String, dynamic>? existing]) async {
    final data = _map(existing?['data']);
    final titleController =
        TextEditingController(text: _text(existing?['title'], ''));
    final objectiveController =
        TextEditingController(text: _text(data['objective'], ''));
    final customController =
        TextEditingController(text: _text(data['customMetric'], ''));
    final valueController =
        TextEditingController(text: _text(data['value'], ''));
    final managerId = _team
        .where((person) {
          return isMarketingManagerRole(
              '${person['role'] ?? person['position'] ?? ''}');
        })
        .map((person) => _text(person['id'] ?? person['_id'], ''))
        .firstWhere((id) => id.isNotEmpty, orElse: () => '');
    var scope = _text(data['scope'], 'INDIVIDUAL').toUpperCase();
    var metric = _text(data['metric'], 'ACQUISITIONS').toUpperCase();
    var period = _text(data['period'], _period).toUpperCase();
    var officerId = _text(existing?['officerId'], managerId);
    DateTime? startsAt = DateTime.tryParse('${data['startsAt'] ?? ''}');
    DateTime? endsAt = DateTime.tryParse('${data['endsAt'] ?? ''}');
    final defaultBounds = marketingTargetPeriodBounds(period, DateTime.now());
    startsAt ??= defaultBounds.$1;
    endsAt ??= defaultBounds.$2;
    final formKey = GlobalKey<FormState>();
    _editorOpen = true;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) =>
          StatefulBuilder(builder: (context, setDialogState) {
        final selectable = _team;
        return AlertDialog(
          title: Text(existing == null
              ? 'Create marketing target'
              : 'Edit marketing target'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                    key: const ValueKey('target-assignment-scope'),
                    value: scope,
                    decoration:
                        const InputDecoration(labelText: 'Assignment scope'),
                    items: const [
                      DropdownMenuItem(
                          value: 'INDIVIDUAL',
                          child: Text('Individual / manager')),
                      DropdownMenuItem(
                          value: 'DEPARTMENT',
                          child: Text('Entire department')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => scope = value ?? scope),
                  ),
                  if (scope == 'INDIVIDUAL')
                    DropdownButtonFormField<String>(
                      key: const ValueKey('target-assignee'),
                      value: selectable.any((person) =>
                              _text(person['id'] ?? person['_id'], '') ==
                              officerId)
                          ? officerId
                          : null,
                      decoration: const InputDecoration(
                          labelText: 'Assign to staff member'),
                      items: selectable.map((person) {
                        final id = _text(person['id'] ?? person['_id'], '');
                        return DropdownMenuItem(
                            value: id,
                            child: Text(
                                '${_text(person['name'], 'Staff')} · ${_text(person['role'] ?? person['position'], 'Marketing')}'));
                      }).toList(),
                      validator: (value) => scope == 'INDIVIDUAL' &&
                              (value == null || value.isEmpty)
                          ? 'Select an assignee.'
                          : null,
                      onChanged: (value) =>
                          setDialogState(() => officerId = value ?? ''),
                    ),
                  TextFormField(
                    controller: titleController,
                    decoration:
                        const InputDecoration(labelText: 'Target title'),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Enter a target title.'
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('target-metric'),
                    value: _metrics.containsKey(metric) ? metric : 'CUSTOM',
                    decoration: const InputDecoration(labelText: 'KPI'),
                    items: _metrics.entries
                        .map((entry) => DropdownMenuItem(
                            value: entry.key, child: Text(entry.value)))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => metric = value ?? metric),
                  ),
                  if (metric == 'CUSTOM')
                    TextFormField(
                        controller: customController,
                        decoration: const InputDecoration(
                          labelText: 'Custom KPI name',
                          hintText: 'For example, new active customers',
                          helperText:
                              'Use service-returned evidence status; custom counts are not inferred.',
                        )),
                  TextFormField(
                    controller: valueController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Target value',
                        helperText:
                            'Positive whole number; achievement is calculated from existing evidence.'),
                    validator: (value) {
                      final number = int.tryParse((value ?? '').trim());
                      return number == null || number <= 0
                          ? 'Enter a positive whole number.'
                          : null;
                    },
                  ),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('target-period'),
                    value: period,
                    decoration:
                        const InputDecoration(labelText: 'Target period'),
                    items: _periods
                        .map((item) => DropdownMenuItem(
                            value: item, child: Text(_pretty(item))))
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      period = value ?? period;
                      final bounds =
                          marketingTargetPeriodBounds(period, DateTime.now());
                      startsAt = bounds.$1;
                      endsAt = bounds.$2;
                    }),
                  ),
                  TextFormField(
                    controller: objectiveController,
                    decoration: const InputDecoration(labelText: 'Objective'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text('Starts ${_date(startsAt)}'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                            context: context,
                            initialDate: startsAt!,
                            firstDate: DateTime(2020),
                            lastDate:
                                DateTime.now().add(const Duration(days: 3650)));
                        if (picked != null) {
                          setDialogState(() => startsAt = DateTime.utc(
                              picked.year, picked.month, picked.day));
                        }
                      },
                    )),
                    const SizedBox(width: 8),
                    Expanded(
                        child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_outlined, size: 16),
                      label: Text('Ends ${_date(endsAt)}'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                            context: context,
                            initialDate: endsAt!,
                            firstDate: DateTime(2020),
                            lastDate:
                                DateTime.now().add(const Duration(days: 3650)));
                        if (picked != null) {
                          setDialogState(() => endsAt = DateTime.utc(
                              picked.year, picked.month, picked.day));
                        }
                      },
                    )),
                  ]),
                  if (metric == 'NEW_REGISTRATIONS')
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                          'Only confirmed attribution records count toward this KPI.',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xff718178))),
                    ),
                  if (const {'AGENT_ACQUISITIONS', 'MERCHANT_ACQUISITIONS'}
                      .contains(metric))
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                          'Achievement remains unavailable until a trusted evidence source is supplied.',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xff718178))),
                    ),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                if (endsAt!.isBefore(startsAt!)) return;
                Navigator.pop(dialogContext, {
                  'scope': scope,
                  'metric': metric,
                  'period': period,
                  'officerId': officerId,
                  'title': titleController.text.trim(),
                  'objective': objectiveController.text.trim(),
                  'customMetric': customController.text.trim(),
                  'value': int.parse(valueController.text.trim()),
                  'startsAt': startsAt!.toUtc().toIso8601String(),
                  'endsAt': endsAt!.toUtc().toIso8601String(),
                });
              },
              child: Text(existing == null ? 'Create target' : 'Save changes'),
            ),
          ],
        );
      }),
    );
    _editorOpen = false;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      titleController.dispose();
      objectiveController.dispose();
      customController.dispose();
      valueController.dispose();
    });
    if (result == null) return;
    if (endsAt!.isBefore(startsAt!)) {
      _message('End date must be on or after the start date.');
      return;
    }
    final scopeValue = '${result['scope']}';
    final metricValue = '${result['metric']}';
    final payload = <String, dynamic>{
      'title': result['title'],
      'description': result['objective'],
      if (scopeValue == 'INDIVIDUAL') 'officerId': result['officerId'],
      if (existing != null && scopeValue == 'DEPARTMENT') 'officerId': null,
      'data': {
        'scope': scopeValue,
        'metric': metricValue,
        'value': result['value'],
        'period': result['period'],
        'startsAt': result['startsAt'],
        'endsAt': result['endsAt'],
        'objective': result['objective'],
        if (metricValue == 'CUSTOM' &&
            '${result['customMetric']}'.trim().isNotEmpty)
          'customMetric': '${result['customMetric']}'.trim(),
      },
      if (existing != null) 'revision': existing['revision'],
    };
    try {
      if (existing == null) {
        await _api.createRecord('target', payload,
            idempotencyKey:
                'marketing_target_${DateTime.now().microsecondsSinceEpoch}');
      } else {
        await _api.updateRecord(
            'target', _text(existing['_id'] ?? existing['id']), payload);
      }
      if (!mounted) return;
      _message(existing == null ? 'Target created.' : 'Target updated.');
      await _load(quiet: true);
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _transitionTarget(
      Map<String, dynamic> target, String status) async {
    final reasonController = TextEditingController();
    _editorOpen = true;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${_pretty(status)} target'),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          decoration:
              const InputDecoration(labelText: 'Reason for audit history'),
          maxLines: 2,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, reasonController.text.trim());
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    _editorOpen = false;
    reasonController.dispose();
    if (reason == null || reason.isEmpty) return;
    try {
      await _api.transition('target', _text(target['_id'] ?? target['id']), {
        'revision': target['revision'],
        'status': status,
        'reason': reason,
      });
      if (!mounted) return;
      _message('Target ${status.toLowerCase()}.');
      await _load(quiet: true);
    } catch (error) {
      _message('$error');
    }
  }

  Widget get _activityView =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeading('Activity & attendance',
            'Existing activity records only. Attendance is not inferred from dashboard visits.'),
        if (_activityError != null)
          _inlineError(_activityError!, _loadActivity)
        else if (_activity.isEmpty)
          _emptyPanel(
              'No activity records are available for this view. No attendance value has been fabricated.')
        else
          for (final item in _activity)
            _panel(
              margin: const EdgeInsets.only(bottom: 8),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.history, color: _ink, size: 19),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          _text(item['title'] ?? item['action'],
                              'Marketing activity'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, color: _ink)),
                      Text(
                          '${_text(item['actorName'] ?? item['actor'])} · ${_text(item['createdAt'])}',
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xff718178))),
                    ])),
                _tag(_text(item['status'], 'RECORDED')),
              ]),
            ),
        const Padding(
          padding: EdgeInsets.only(top: 5),
          child: Text(
              'Attendance KPI values are displayed only when the existing target response contains verifiable actuals. Reported activity is self-reported.',
              style: TextStyle(fontSize: 11, color: Color(0xff718178))),
        ),
      ]);

  Widget get _settings =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeading('Marketing settings',
            'Ranking methodology remains governed by Super Admin permissions.'),
        _panel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ranking policy',
                style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 5),
            Text(
                _superAdmin
                    ? 'Super Admin access confirmed. The existing performance policy editor is available below.'
                    : 'Read-only for this account. Only Super Admin can modify ranking methodology.',
                style: const TextStyle(fontSize: 12, color: Color(0xff6d7e74))),
            if (_superAdmin) ...[
              const SizedBox(height: 10),
              SizedBox(
                  height: 620,
                  child: MarketingPerformanceScreen(
                      api: _api, initialView: 'methodology')),
            ],
          ]),
        ),
      ]);

  Future<void> _export(String format) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final response = await _api.exportPerformance(
        format: format,
        period: _period,
        from: _from?.toUtc().toIso8601String(),
        to: _to?.add(const Duration(days: 1)).toUtc().toIso8601String(),
        department: true,
      );
      if (!mounted) return;
      await FilePicker.platform.saveFile(
        dialogTitle: 'Save ServicePay marketing report',
        fileName: 'servicepay-marketing-${_period.toLowerCase()}.$format',
        bytes: response.bodyBytes,
      );
      if (mounted) _message('Marketing report export prepared.');
    } catch (error) {
      if (mounted) _message('$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _kpi(String title, dynamic value, String note, IconData icon) =>
      _panel(
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: _mint, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 19, color: _ink),
          ),
          const SizedBox(width: 9),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(_text(value, 'Unavailable'),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _ink)),
                Text(title,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _ink)),
                Text(note,
                    style:
                        const TextStyle(fontSize: 9, color: Color(0xff77877e))),
              ])),
        ]),
      );

  Widget _metric(String label, dynamic value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
            color: const Color(0xfff1f6f1),
            borderRadius: BorderRadius.circular(9)),
        child: Text('$label · ${_text(value, 'Unavailable')}',
            style: const TextStyle(
                fontSize: 10, color: _ink, fontWeight: FontWeight.w600)),
      );

  Widget _staffRow(Map<String, dynamic> person) => Padding(
        padding: const EdgeInsets.only(top: 9),
        child: Row(children: [
          Expanded(
              child: Text(_text(person['name'], 'Marketing staff'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: _ink))),
          Text(_text(person['achievement'], 'Achievement unavailable'),
              style: const TextStyle(fontSize: 11, color: Color(0xff6d7e74))),
        ]),
      );

  Widget _labelValue(String label, String value) => Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: _ink))),
        Text(value,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: _ink)),
      ]);

  Widget _sectionHeading(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 3),
          Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xff718178))),
        ]),
      );

  Widget _panel({required Widget child, EdgeInsetsGeometry? margin}) =>
      Container(
        margin: margin,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xfffbfdf9),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xffdce7de)),
        ),
        child: child,
      );

  Widget _tag(String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
            color: _mint, borderRadius: BorderRadius.circular(20)),
        child: Text(value,
            style: const TextStyle(
                fontSize: 9, color: _ink, fontWeight: FontWeight.w800)),
      );

  Widget get _skeleton => ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(
            5,
            (index) => Container(
                  height: index == 0 ? 96 : 72,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                      color: const Color(0xffe6eee7),
                      borderRadius: BorderRadius.circular(13)),
                )),
      );

  Widget get _errorView => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, color: _ink, size: 34),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: () => _load(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry')),
          ]),
        ),
      );

  Widget _inlineError(String message, VoidCallback retry) => _panel(
        child: Row(children: [
          const Icon(Icons.cloud_off_outlined, color: _ink),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          TextButton(onPressed: retry, child: const Text('Retry')),
        ]),
      );

  Widget _emptyPanel(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: const Color(0xfff8fbf7),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xffdce7de))),
        child: Text(message,
            style: const TextStyle(fontSize: 12, color: Color(0xff718178))),
      );

  String _percent(dynamic value) {
    final parsed = _num(value);
    return parsed == null ? 'Unavailable' : '${parsed.toStringAsFixed(1)}%';
  }

  String _date(DateTime? value) => value == null
      ? '—'
      : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

extension _MarketingFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
