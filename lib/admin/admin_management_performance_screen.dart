import 'dart:async';

import 'package:flutter/material.dart';

import 'admin_management_performance_api.dart';
import 'admin_permissions.dart';
import 'admin_management_access.dart';
import 'hierarchy_management_screen.dart';
import 'management_performance_widgets.dart';
import 'management_performance_dates.dart';
import 'management_performance_export_panel.dart';

class AdminManagementPerformanceScreen extends StatefulWidget {
  const AdminManagementPerformanceScreen({
    super.key,
    required this.initialAccess,
    this.api,
  });

  final AdminAccess initialAccess;
  final AdminManagementPerformanceApi? api;

  @override
  State<AdminManagementPerformanceScreen> createState() =>
      _AdminManagementPerformanceScreenState();
}

class _AdminManagementPerformanceScreenState
    extends State<AdminManagementPerformanceScreen> {
  late final AdminManagementPerformanceApi _api =
      widget.api ?? AdminManagementPerformanceApi();
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _role = 'AGENT';
  String _period = 'THIS_MONTH';
  DateTimeRange? _customRange;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  String? _selectedId;
  List<Map<String, dynamic>> _managers = <Map<String, dynamic>>[];
  Map<String, dynamic>? _report;
  bool _loadingManagers = false;
  bool _loadingReport = false;
  String? _error;
  int _managerRequest = 0;
  int _reportRequest = 0;

  static const Map<String, String> _roles = <String, String>{
    'AGENT': 'Aggregator',
    'STATE_MANAGER': 'State Manager',
    'ZONAL_MANAGER': 'Zonal Manager',
  };
  static const Map<String, String> _periods = <String, String>{
    'TODAY': 'Today',
    'YESTERDAY': 'Yesterday',
    'THIS_WEEK': 'This week',
    'LAST_WEEK': 'Last week',
    'THIS_MONTH': 'This month',
    'LAST_MONTH': 'Last month',
    'LAST_30_DAYS': 'Last 30 days',
    'CUSTOM': 'Custom range',
  };
  bool get _authorized => canViewHeadOfficePerformance(widget.initialAccess);
  bool get _canAssign => canManageHeadOfficeHierarchy(widget.initialAccess);

  @override
  void initState() {
    super.initState();
    if (_authorized) _loadManagers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  String _id(Map<String, dynamic> item) =>
      '${item['_id'] ?? item['id'] ?? ''}'.trim();
  String _name(Map<String, dynamic> item) =>
      '${item['fullName'] ?? 'Unnamed manager'}'.trim();

  Future<void> _loadManagers() async {
    final int request = ++_managerRequest;
    _reportRequest++;
    setState(() {
      _loadingManagers = true;
      _loadingReport = false;
      _report = null;
      _error = null;
    });
    try {
      final Map<String, dynamic> response = await _api.managers(
        role: _role,
        search: _search.text,
        page: _page,
      );
      final dynamic rawData = response['data'];
      final Map<String, dynamic> data =
          rawData is Map ? Map<String, dynamic>.from(rawData) : response;
      final dynamic rawItems = data['items'];
      final List<Map<String, dynamic>> rows = rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((Map item) => Map<String, dynamic>.from(item))
              .where((Map<String, dynamic> item) => _id(item).isNotEmpty)
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted || request != _managerRequest) return;
      final String? selected =
          rows.any((Map<String, dynamic> row) => _id(row) == _selectedId)
              ? _selectedId
              : rows.isEmpty
                  ? null
                  : _id(rows.first);
      setState(() {
        _managers = rows;
        _selectedId = selected;
        _totalPages = _positive(data['totalPages'], 1);
        _total = _positive(data['total'], rows.length);
        _loadingManagers = false;
      });
      if (selected != null) {
        await _loadReport();
      } else if (mounted) {
        setState(() {
          _report = null;
          _loadingReport = false;
        });
      }
    } catch (error) {
      if (!mounted || request != _managerRequest) return;
      setState(() {
        _loadingManagers = false;
        _managers = <Map<String, dynamic>>[];
        _selectedId = null;
        _report = null;
        _error = error.toString();
      });
    }
  }

  int _positive(dynamic value, int fallback) {
    final int parsed = int.tryParse('$value') ?? fallback;
    return parsed > 0 ? parsed : fallback;
  }

  Future<void> _loadReport() async {
    final String? managerId = _selectedId;
    if (managerId == null || managerId.isEmpty) return;
    final int request = ++_reportRequest;
    final (String, String) dates = _dateParams();
    setState(() {
      _loadingReport = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> result = await _api.report(
        managerId: managerId,
        period: _period,
        from: dates.$1,
        to: dates.$2,
      );
      if (!mounted || request != _reportRequest || managerId != _selectedId) {
        return;
      }
      final dynamic data = result['data'];
      setState(() {
        _report = data is Map ? Map<String, dynamic>.from(data) : null;
        _loadingReport = false;
      });
    } catch (error) {
      if (!mounted || request != _reportRequest || managerId != _selectedId) {
        return;
      }
      setState(() {
        _report = null;
        _loadingReport = false;
        _error = error.toString();
      });
    }
  }

  (String, String) _dateParams() {
    return managementPerformanceDateParams(
      period: _period,
      lagosNow: managementPerformanceLagosNow(),
      customRange: _customRange,
    );
  }

  Future<void> _selectCustomRange() async {
    final DateTime lagosNow = managementPerformanceLagosNow();
    final DateTime today =
        DateTime(lagosNow.year, lagosNow.month, lagosNow.day);
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2018),
      lastDate: today,
      initialDateRange: _customRange ??
          DateTimeRange(
              start: DateTime(today.year, today.month, 1), end: today),
      helpText: 'Select report dates (Lagos inclusive)',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _period = 'CUSTOM';
    });
    await _loadReport();
  }

  String _safeSummary() {
    final Map<String, dynamic> overview = _report?['overview'] is Map
        ? Map<String, dynamic>.from(_report!['overview'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> kpis = overview['kpis'] is Map
        ? Map<String, dynamic>.from(overview['kpis'] as Map)
        : <String, dynamic>{};
    final String manager =
        '${(_report?['manager'] as Map?)?['fullName'] ?? 'Manager'}';
    final String period = _displayPeriod(overview);
    return 'ServicePay management report — $manager ($period). '
        'Customers: ${kpis['totalCustomers'] ?? '—'}; new: ${kpis['newCustomers'] ?? '—'}; '
        'transactions: ${kpis['totalTransactions'] ?? '—'}; successful: ${kpis['successfulTransactions'] ?? '—'}. '
        'Gross transaction value includes all statuses; commission is own recorded commission only. '
        'Legacy transaction attribution may be incomplete. No customer details are included.';
  }

  String _displayPeriod(Map<String, dynamic> overview) {
    final dynamic period = overview['period'];
    if (period is! Map) return _periods[_period] ?? _period;
    final String from = _displayDate(period['from']);
    final String rawTo = '${period['to'] ?? ''}';
    final String to = _displayDate(rawTo, subtractMillisecond: true);
    return from == to || to == '—' ? from : '$from – $to';
  }

  String _displayDate(dynamic raw, {bool subtractMillisecond = false}) {
    final String input = '$raw';
    final DateTime? parsed = DateTime.tryParse(input);
    if (parsed == null) return '—';
    final bool hasTimezone =
        input.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(input);
    DateTime date =
        hasTimezone ? parsed.toUtc().add(const Duration(hours: 1)) : parsed;
    if (subtractMillisecond) {
      date = date.subtract(const Duration(milliseconds: 1));
    }
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _value(dynamic value, {bool currency = false}) {
    if (value == null) return '—';
    if (currency) {
      final num? amount = num.tryParse('$value');
      return amount == null ? '$value' : '₦${amount.toStringAsFixed(2)}';
    }
    return '$value';
  }

  void _searchChanged(String value) {
    setState(() {
      _report = null;
    });
    _managerRequest++;
    _reportRequest++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _page = 1;
      _loadManagers();
    });
  }

  Widget _exportPanel() {
    final String managerId = _selectedId!;
    final (String, String) dates = _dateParams();
    return ManagementPerformanceExportPanel(
      key: ValueKey<String>(
          '$managerId|$_period|${dates.$1}|${dates.$2}|$_reportRequest'),
      api: _api,
      managerId: managerId,
      period: _period,
      from: dates.$1,
      to: dates.$2,
      whatsAppSummary: _safeSummary(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_authorized) {
      return const Center(
        child: Text(
            'Management Performance requires Head Office users.view access.'),
      );
    }
    final bool narrow = MediaQuery.sizeOf(context).width < 760;
    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Management Performance',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Read-only field network reporting. No financial controls.'),
      ],
    );
    final Widget assignmentsButton = _canAssign
        ? OutlinedButton.icon(
            onPressed: _openCustomerAssignments,
            icon: const Icon(Icons.assignment_ind_outlined),
            label: const Text('Customer assignments'),
          )
        : const SizedBox.shrink();
    return ListView(
      padding: EdgeInsets.fromLTRB(narrow ? 16 : 28, 24, narrow ? 16 : 28, 40),
      children: <Widget>[
        if (narrow) ...<Widget>[
          heading,
          if (_canAssign) ...<Widget>[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: assignmentsButton),
          ],
        ] else
          Row(children: <Widget>[
            Expanded(child: heading),
            if (_canAssign) assignmentsButton,
          ]),
        const SizedBox(height: 20),
        ManagementPerformanceFilterBar(
          narrow: narrow,
          role: _role,
          roles: _roles,
          period: _period,
          periods: _periods,
          search: _search,
          dateLabel: _customRange == null
              ? 'Choose dates'
              : '${_displayDate(_customRange!.start)} – ${_displayDate(_customRange!.end)}',
          onSearchChanged: _searchChanged,
          onClearSearch: () {
            _search.clear();
            _page = 1;
            _searchChanged('');
          },
          onRoleChanged: (String value) {
            setState(() {
              _role = value;
              _page = 1;
              _selectedId = null;
              _report = null;
            });
            _loadManagers();
          },
          onPeriodChanged: (String value) {
            if (value == 'CUSTOM') {
              _selectCustomRange();
              return;
            }
            setState(() {
              _period = value;
            });
            _loadReport();
          },
          onChooseDates: _selectCustomRange,
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          _errorPanel(),
        ],
        const SizedBox(height: 16),
        if (narrow)
          SizedBox(
            height: 285,
            child: ManagementManagersPanel(
              loading: _loadingManagers,
              managers: _managers,
              roleLabel: _roles[_role]!,
              total: _total,
              page: _page,
              totalPages: _totalPages,
              selectedId: _selectedId,
              idOf: _id,
              nameOf: _name,
              onPrevious: _page > 1
                  ? () {
                      setState(() => _page--);
                      _loadManagers();
                    }
                  : null,
              onNext: _page < _totalPages
                  ? () {
                      setState(() => _page++);
                      _loadManagers();
                    }
                  : null,
              onSelect: (Map<String, dynamic> manager) {
                setState(() {
                  _selectedId = _id(manager);
                  _report = null;
                });
                _loadReport();
              },
            ),
          )
        else
          SizedBox(
            height: 260,
            child: ManagementManagersPanel(
              loading: _loadingManagers,
              managers: _managers,
              roleLabel: _roles[_role]!,
              total: _total,
              page: _page,
              totalPages: _totalPages,
              selectedId: _selectedId,
              idOf: _id,
              nameOf: _name,
              onPrevious: _page > 1
                  ? () {
                      setState(() => _page--);
                      _loadManagers();
                    }
                  : null,
              onNext: _page < _totalPages
                  ? () {
                      setState(() => _page++);
                      _loadManagers();
                    }
                  : null,
              onSelect: (Map<String, dynamic> manager) {
                setState(() {
                  _selectedId = _id(manager);
                  _report = null;
                });
                _loadReport();
              },
            ),
          ),
        const SizedBox(height: 16),
        if (_loadingReport)
          const ManagementPerformanceReportSkeleton()
        else if (_report != null && _selectedId != null)
          ManagementPerformanceReportView(
            report: _report!,
            narrow: narrow,
            exportActions: _exportPanel(),
            displayPeriod: _displayPeriod,
            displayDate: _displayDate,
            displayValue: _value,
          )
        else if (!_loadingManagers && _managers.isEmpty && _error == null)
          _emptyState(),
      ],
    );
  }

  Widget _emptyState() => Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: <Widget>[
              const Icon(Icons.groups_2_outlined, size: 34),
              const SizedBox(height: 8),
              const Text('No managers match these filters.'),
              TextButton(
                  onPressed: _loadManagers, child: const Text('Try again')),
            ],
          ),
        ),
      );

  Widget _errorPanel() => Material(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: <Widget>[
            Expanded(child: Text(_error!)),
            TextButton(onPressed: _loadManagers, child: const Text('Retry')),
          ]),
        ),
      );

  Future<void> _openCustomerAssignments() async {
    if (!_canAssign) return;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Customer Assignments')),
        body: HierarchyManagementScreen(
          role: widget.initialAccess.role,
          permissions: widget.initialAccess.permissions,
          initialRole: 'CUSTOMER',
        ),
      ),
    ));
    if (mounted) await _loadManagers();
  }
}
