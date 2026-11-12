import 'package:flutter/material.dart';

import 'admin_permissions.dart';
import 'customer_export_platform.dart' as export_platform;
import 'customer_intelligence_api.dart';

class CustomerIntelligenceScreen extends StatefulWidget {
  const CustomerIntelligenceScreen({super.key, this.api, this.access});
  final CustomerIntelligenceApi? api;
  final AdminAccess? access;

  @override
  State<CustomerIntelligenceScreen> createState() =>
      _CustomerIntelligenceScreenState();
}

class _CustomerIntelligenceScreenState
    extends State<CustomerIntelligenceScreen> {
  static const _ink = Color(0xff173b40);
  static const _teal = Color(0xff087f78);
  static const _mint = Color(0xffe7f4ef);
  static const _canvas = Color(0xfff3f7f5);
  static const _line = Color(0xffdbe9e4);
  static const _ranges = <String, String>{
    '30d': 'Last 30 days',
    'today': 'Today',
    '7d': 'Last 7 days',
    '90d': 'Last 90 days',
    'thisMonth': 'This month',
    'lastMonth': 'Last month',
    'custom': 'Custom dates',
  };
  static const _segments = [
    ('', 'All'),
    ('FREQUENT', 'Frequent'),
    ('REGULAR', 'Regular'),
    ('OCCASIONAL', 'Occasional'),
    ('DECLINING', 'Declining'),
    ('INACTIVE', 'Inactive'),
    ('NEVER', 'Never'),
  ];

  late final CustomerIntelligenceApi _api =
      widget.api ?? CustomerIntelligenceApi();
  final _search = TextEditingController();
  final _state = TextEditingController();
  final _lga = TextEditingController();
  final _agent = TextEditingController();
  final _stateManager = TextEditingController();
  final _zonalManager = TextEditingController();
  final _minCount = TextEditingController();
  final _maxCount = TextEditingController();
  final _minValue = TextEditingController();
  final _maxValue = TextEditingController();
  final _registeredFrom = TextEditingController();
  final _registeredTo = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _lastFrom = TextEditingController();
  final _lastTo = TextEditingController();
  final _controllers = <TextEditingController>[];
  Map<String, dynamic> _response = {};
  Map<String, dynamic> _performance = {};
  final Map<String, dynamic> _filters = {
    'range': '30d',
    'page': 1,
    'limit': 20
  };
  Map<String, dynamic> _appliedFilters = {};
  String _category = '';
  String _sort = 'registered';
  String _range = '30d';
  String _service = '';
  String _status = '';
  String _view = 'customers';
  String _dimension = 'agent';
  bool _newOnly = false;
  bool _showFilters = true;
  bool _loading = false;
  bool _workforceLoading = false;
  String? _error;
  String? _workforceError;
  final Set<String> _selected = {};
  AdminAccess? _access;
  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _definitions = {};

  @override
  void initState() {
    super.initState();
    _controllers.addAll([
      _search,
      _state,
      _lga,
      _agent,
      _stateManager,
      _zonalManager,
      _minCount,
      _maxCount,
      _minValue,
      _maxValue,
      _registeredFrom,
      _registeredTo,
      _from,
      _to,
      _lastFrom,
      _lastTo,
    ]);
    _loadAccess();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _loadAccess() async {
    try {
      final access = widget.access ?? await AdminSessionStore.loadAccess();
      if (mounted) setState(() => _access = access);
    } catch (_) {
      if (mounted) setState(() => _access = null);
    }
  }

  bool get _canSettings =>
      _access != null &&
      AdminAccess.normalizeRole(_access!.role) == 'HEAD_OFFICE' &&
      (_access!.permissions.any((p) => p.toLowerCase() == 'settings.update') ||
          _access!.permissions.contains('*')) &&
      _map(_response['capabilities'])['canConfigure'] == true;

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  List<Map<String, dynamic>> _list(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
  String _text(dynamic v, [String fallback = '—']) {
    final value = v?.toString().trim() ?? '';
    return value.isEmpty || value == 'null' ? fallback : value;
  }

  int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  double _double(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  Map<String, dynamic> _currentFilters({bool includePage = true}) => {
        'q': _search.text.trim(),
        'category': _category,
        if (_newOnly) 'newOnly': true,
        'state': _state.text.trim(),
        'lga': _lga.text.trim(),
        'agentId': _agent.text.trim(),
        'stateManagerId': _stateManager.text.trim(),
        'zonalManagerId': _zonalManager.text.trim(),
        'registeredFrom': _registeredFrom.text.trim(),
        'registeredTo': _registeredTo.text.trim(),
        'lastFrom': _lastFrom.text.trim(),
        'lastTo': _lastTo.text.trim(),
        'minCount': _minCount.text.trim(),
        'maxCount': _maxCount.text.trim(),
        'minValue': _minValue.text.trim(),
        'maxValue': _maxValue.text.trim(),
        'serviceType': _service,
        'status': _status,
        'range': _range,
        if (_range == 'custom') 'from': _from.text.trim(),
        if (_range == 'custom') 'to': _to.text.trim(),
        'sort': _sort,
        if (includePage) 'page': _int(_filters['page']).clamp(1, 100000),
        'limit': _int(_filters['limit']) == 0 ? 20 : _filters['limit'],
      };

  bool get _hasUnappliedFilters {
    final current = _currentFilters(includePage: false);
    if (current.length != _appliedFilters.length) return true;
    return current.entries
        .any((entry) => _appliedFilters[entry.key] != entry.value);
  }

  Map<String, dynamic> _exportFilters() =>
      Map<String, dynamic>.from(_appliedFilters);

  Future<void> _load({bool resetPage = false}) async {
    if (resetPage) {
      _filters['page'] = 1;
      _selected.clear();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final requestFilters = _currentFilters();
    try {
      final result = await _api.customers(requestFilters);
      if (!mounted) return;
      setState(() {
        _response = result;
        _settings = _map(result['settings']);
        _definitions = _map(result['definitions']);
        _appliedFilters = Map<String, dynamic>.from(requestFilters)
          ..remove('page');
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPerformance({int page = 1}) async {
    setState(() {
      _workforceLoading = true;
      _workforceError = null;
    });
    try {
      final result = await _api.performance(_exportFilters(),
          dimension: _dimension,
          page: page,
          limit: _int(_filters['limit']) == 0 ? 20 : _int(_filters['limit']));
      if (mounted) setState(() => _performance = result);
    } catch (e) {
      if (mounted) setState(() => _workforceError = e.toString());
    } finally {
      if (mounted) setState(() => _workforceLoading = false);
    }
  }

  void _clearFilters() {
    for (final controller in _controllers) {
      controller.clear();
    }
    setState(() {
      _category = '';
      _newOnly = false;
      _service = '';
      _status = '';
      _range = '30d';
      _sort = 'registered';
      _selected.clear();
    });
    _load(resetPage: true);
  }

  Future<void> _openProfile(Map<String, dynamic> row) async {
    final id = _text(row['_id'], '');
    if (id.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _CustomerProfileDialog(api: _api, id: id),
    );
  }

  Future<void> _export(String action, String format) async {
    final can = _map(_response['capabilities'])['canExport'] == true;
    if (!can) {
      _notice('Contact export is not available for this access.');
      return;
    }
    final selectedCount = _selected.isEmpty
        ? _int(_map(_response['pagination'])['total'])
        : _selected.length;
    if (selectedCount == 0) {
      _notice('Select at least one customer to prepare a contact export.');
      return;
    }
    Object? printTarget;
    if (action == 'print' && export_platform.supportsPrintPopup) {
      printTarget = export_platform.openPrintTarget();
    }
    try {
      final file = await _api.export(
        filters: _exportFilters(),
        ids: List<String>.unmodifiable(_selected),
        allFiltered: _selected.isEmpty,
        format: format,
        action: action,
      );
      if (action == 'share' && export_platform.supportsFileShare) {
        final shared = await export_platform.shareFile(file);
        if (!shared) await export_platform.downloadFile(file);
      } else if (action == 'print') {
        await export_platform.deliverToPrintTarget(printTarget, file);
      } else {
        await export_platform.downloadFile(file);
      }
      if (mounted) {
        _notice('Contact file prepared for $selectedCount customers.');
      }
    } catch (e) {
      export_platform.closePrintTarget(printTarget);
      if (mounted) _notice(e.toString());
    }
  }

  Future<void> _prepareCampaign() async {
    final can = _map(_response['capabilities'])['canPrepareCampaign'] == true;
    if (!can) {
      _notice('Campaign preparation is not available for this access.');
      return;
    }
    final draft = await showDialog<_CampaignDraft>(
      context: context,
      builder: (_) => const _CampaignDraftDialog(),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await _api.campaignPreview(
        filters: _exportFilters(),
        ids: List<String>.unmodifiable(_selected),
        allFiltered: _selected.isEmpty,
        purpose: draft.purpose,
        message: draft.message,
      );
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => _PreviewDialog(data: preview),
        );
      }
    } catch (e) {
      if (mounted) _notice(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: _canvas,
          foregroundColor: _ink,
          elevation: 0,
          title: const Text('Customer intelligence',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                  color: _mint, borderRadius: BorderRadius.circular(20)),
              child: const Row(children: [
                Icon(Icons.visibility_outlined, size: 14, color: _teal),
                SizedBox(width: 6),
                Text('NO FINANCIAL AUTHORITY',
                    style: TextStyle(
                        color: _teal,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ]),
            )
          ],
        ),
        body: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return RefreshIndicator(
            onRefresh: () => _view == 'workforce'
                ? _loadPerformance()
                : _load(resetPage: false),
            child: ListView(
              padding:
                  EdgeInsets.fromLTRB(wide ? 28 : 16, 8, wide ? 28 : 16, 36),
              children: [
                _intro(wide),
                const SizedBox(height: 18),
                _navigation(),
                const SizedBox(height: 16),
                _summary(),
                const SizedBox(height: 16),
                if (_view == 'workforce')
                  _workforceView()
                else if (_view == 'settings')
                  _settingsView()
                else if (_view == 'definitions')
                  _definitionsView()
                else
                  _customerView(wide),
              ],
            ),
          );
        }),
      );

  Widget _intro(bool wide) => Container(
        padding: EdgeInsets.all(wide ? 24 : 19),
        decoration:
            BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(20)),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 18,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: wide ? 600 : 310,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SERVICEPAY  /  HEAD OFFICE',
                      style: TextStyle(
                          color: Color(0xff8fd2c5),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5)),
                  SizedBox(height: 10),
                  Text('Understand engagement. Prepare responsibly.',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          height: 1.12,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Text(
                      'A permission-aware view of customer activity, retention and service use.',
                      style: TextStyle(color: Color(0xffc0d8d3), height: 1.45)),
                ],
              ),
            ),
            Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                  color: const Color(0xff255257),
                  borderRadius: BorderRadius.circular(13)),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, color: Color(0xff8fd2c5), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        'Analytics and contact-file preparation only. No balances, financial controls, consent records or message delivery.',
                        style: TextStyle(
                            color: Color(0xffe4f0ec),
                            height: 1.4,
                            fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _navigation() => Wrap(spacing: 8, runSpacing: 8, children: [
        _navButton('customers', 'Customers', Icons.people_outline),
        _navButton('workforce', 'Workforce', Icons.account_tree_outlined),
        _navButton('definitions', 'Metric definitions', Icons.info_outline),
        if (_canSettings)
          _navButton('settings', 'Settings', Icons.tune_outlined),
      ]);

  Widget _navButton(String id, String label, IconData icon) {
    final active = _view == id;
    return OutlinedButton.icon(
      onPressed: () {
        setState(() => _view = id);
        if (id == 'workforce') _loadPerformance();
      },
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? _ink : Colors.white,
        foregroundColor: active ? Colors.white : _ink,
        side: BorderSide(color: active ? _ink : _line),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _summary() {
    final s = _map(_response['summary']);
    final items = [
      ('Customers', s['customers'], Icons.groups_outlined, _ink),
      ('Active', s['active'], Icons.bolt_outlined, _teal),
      (
        'Retained',
        '${_text(s['retentionRate'], '—')}${s['retentionRate'] is num ? '%' : ''}',
        Icons.repeat_rounded,
        _teal
      ),
      (
        'Reactivated',
        s['reactivated'],
        Icons.refresh_rounded,
        const Color(0xffa36a2f)
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, c) {
        final count = c.maxWidth < 520 ? 2 : 4;
        final width = (c.maxWidth - (count - 1) * 10) / count;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items
              .map((item) => SizedBox(
                    width: width,
                    child: _Surface(
                      padding: const EdgeInsets.all(15),
                      child: Row(children: [
                        Container(
                          width: 37,
                          height: 37,
                          decoration: BoxDecoration(
                              color: item.$4.withValues(alpha: .09),
                              borderRadius: BorderRadius.circular(11)),
                          child: Icon(item.$3, color: item.$4, size: 19),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.$1,
                                    style: const TextStyle(
                                        color: Color(0xff718782),
                                        fontSize: 11)),
                                const SizedBox(height: 3),
                                Text(_text(item.$2),
                                    style: const TextStyle(
                                        color: _ink,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18)),
                              ]),
                        ),
                      ]),
                    ),
                  ))
              .toList(),
        );
      }),
      const SizedBox(height: 10),
      _Surface(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Wrap(spacing: 18, runSpacing: 8, children: [
          for (final entry in <String, dynamic>{
            'Frequent': s['frequent'],
            'Regular': s['regular'],
            'Occasional': s['occasional'],
            'Declining': s['declining'],
            'Inactive': s['inactive'],
            'Never': s['never'],
            'New registrations (period)': s['newRegistrations'],
            'New customers (rolling overlay)': s['newCustomers'],
            'Previous active': s['previousActive'],
            'Retained': s['retained'],
          }.entries)
            _summaryValue(entry.key, entry.value),
        ]),
      ),
    ]);
  }

  Widget _summaryValue(String label, dynamic value) => Semantics(
        label: '$label: ${_text(value)}',
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 12, color: Color(0xff718782)),
            children: [
              TextSpan(text: '$label  '),
              TextSpan(
                text: _text(value),
                style:
                    const TextStyle(color: _ink, fontWeight: FontWeight.w800),
              )
            ],
          ),
        ),
      );

  Widget _customerView(bool wide) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _filterPanel(wide),
          const SizedBox(height: 14),
          _trendPanel(),
          const SizedBox(height: 14),
          _rankingPanel(),
          const SizedBox(height: 14),
          _customerList(),
        ],
      );

  Widget _filterPanel(bool wide) => _Surface(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (context, constraints) {
            final actions = Wrap(
              spacing: 2,
              runSpacing: 0,
              children: [
                TextButton.icon(
                    onPressed: () =>
                        setState(() => _showFilters = !_showFilters),
                    icon: Icon(
                        _showFilters ? Icons.expand_less : Icons.expand_more),
                    label:
                        Text(_showFilters ? 'Hide filters' : 'Show filters')),
                TextButton(
                    onPressed: _clearFilters, child: const Text('Clear all')),
              ],
            );
            const title = Text('Find a customer cohort',
                style: TextStyle(
                    color: _ink, fontWeight: FontWeight.w800, fontSize: 16));
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, actions],
              );
            }
            return Row(children: [const Expanded(child: title), actions]);
          }),
          const SizedBox(height: 11),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ..._segments.map((segment) => _segment(segment.$1, segment.$2)),
            _segment('TOP_COUNT', 'Top count'),
            _segment('TOP_VOLUME', 'Top volume'),
            _segment('NEW', 'New customers'),
          ]),
          if (_showFilters) ...[
            const SizedBox(height: 15),
            LayoutBuilder(builder: (context, c) {
              final n = c.maxWidth < 600
                  ? 1
                  : c.maxWidth < 1000
                      ? 2
                      : 4;
              final w = (c.maxWidth - (n - 1) * 10) / n;
              Widget field(TextEditingController controller, String label,
                      {String? hint, TextInputType? keyboard}) =>
                  SizedBox(
                    width: w,
                    child: TextField(
                      controller: controller,
                      onSubmitted: (_) => _load(resetPage: true),
                      keyboardType: keyboard,
                      decoration: _decoration(label, hint: hint),
                    ),
                  );
              return Wrap(spacing: 10, runSpacing: 10, children: [
                field(_search, 'Name, phone or email',
                    hint: 'Search customers'),
                _dropField<String>(
                    'Activity period',
                    _range,
                    _ranges.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(), (v) {
                  setState(() => _range = v ?? '30d');
                  _load(resetPage: true);
                }, width: w),
                _dropField<String>('Service type', _service, [
                  const DropdownMenuItem(
                      value: '', child: Text('All services')),
                  ...const [
                    'AIRTIME',
                    'DATA',
                    'BILLS',
                    'TV',
                    'ELECTRICITY'
                  ].map(
                      (v) => DropdownMenuItem(value: v, child: Text(_title(v))))
                ], (v) {
                  setState(() => _service = v ?? '');
                  _load(resetPage: true);
                }, width: w),
                _dropField<String>('Transaction status', _status, [
                  const DropdownMenuItem(
                      value: '', child: Text('All statuses')),
                  ...const [
                    'SUCCESSFUL',
                    'FAILED',
                    'PENDING',
                    'REFUNDED',
                    'OTHER'
                  ].map(
                      (v) => DropdownMenuItem(value: v, child: Text(_title(v))))
                ], (v) {
                  setState(() => _status = v ?? '');
                  _load(resetPage: true);
                }, width: w),
                field(_state, 'State'),
                field(_lga, 'LGA'),
                field(_agent, 'Agent ID'),
                field(_stateManager, 'State manager ID'),
                field(_zonalManager, 'Zonal manager ID'),
                field(_registeredFrom, 'Registered from', hint: 'YYYY-MM-DD'),
                field(_registeredTo, 'Registered to', hint: 'YYYY-MM-DD'),
                if (_range == 'custom') ...[
                  field(_from, 'Activity range from', hint: 'YYYY-MM-DD'),
                  field(_to, 'Activity range to', hint: 'YYYY-MM-DD'),
                ],
                field(_lastFrom, 'Last successful from', hint: 'YYYY-MM-DD'),
                field(_lastTo, 'Last successful to', hint: 'YYYY-MM-DD'),
                field(_minCount, 'Min successful (30d)',
                    keyboard: TextInputType.number),
                field(_maxCount, 'Max successful (30d)',
                    keyboard: TextInputType.number),
                field(_minValue, 'Min lifetime value',
                    keyboard: TextInputType.number),
                field(_maxValue, 'Max lifetime value',
                    keyboard: TextInputType.number),
                _dropField<String>('Sort by', _sort, const [
                  DropdownMenuItem(
                      value: 'registered', child: Text('Registration date')),
                  DropdownMenuItem(
                      value: 'count', child: Text('Successful count')),
                  DropdownMenuItem(
                      value: 'value', child: Text('Successful value')),
                ], (v) {
                  setState(() => _sort = v ?? 'registered');
                  _load(resetPage: true);
                }, width: w),
                SizedBox(
                  width: w,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilterChip(
                      selected: _newOnly,
                      label: const Text('New customers only'),
                      onSelected: (v) {
                        setState(() => _newOnly = v);
                        _load(resetPage: true);
                      },
                    ),
                  ),
                ),
              ]);
            }),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _loading ? null : () => _load(resetPage: true),
                style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 13)),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Apply filters'),
              ),
            ),
          ],
        ]),
      );

  Widget _segment(String key, String label) {
    final selected = key == 'NEW'
        ? _newOnly
        : key == 'TOP_COUNT'
            ? _sort == 'count'
            : key == 'TOP_VOLUME'
                ? _sort == 'value'
                : _category == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          if (key == 'NEW') {
            _newOnly = !_newOnly;
          } else if (key == 'TOP_COUNT') {
            _sort = 'count';
            _category = '';
            _newOnly = false;
          } else if (key == 'TOP_VOLUME') {
            _sort = 'value';
            _category = '';
            _newOnly = false;
          } else {
            _category = key;
            _sort = 'registered';
            _newOnly = false;
          }
          _selected.clear();
        });
        _load(resetPage: true);
      },
      selectedColor: _mint,
      labelStyle: TextStyle(
          color: selected ? _teal : const Color(0xff526c67),
          fontWeight: FontWeight.w700,
          fontSize: 12),
      side: BorderSide(color: selected ? _teal : _line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: const Color(0xfff8faf9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _line)),
      );

  Widget _dropField<T>(String label, T value, List<DropdownMenuItem<T>> items,
          ValueChanged<T?> changed,
          {required double width}) =>
      SizedBox(
        width: width,
        child: DropdownButtonFormField<T>(
          value: items.any((e) => e.value == value) ? value : items.first.value,
          isExpanded: true,
          decoration: _decoration(label),
          items: items,
          onChanged: changed,
        ),
      );

  Widget _trendPanel() {
    final trend = _list(_response['trend']);
    return _Surface(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Activity trend',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(
            'Successful transactions · ${_ranges[_range] ?? 'Selected period'}',
            style: const TextStyle(color: Color(0xff718782), fontSize: 12)),
        const SizedBox(height: 16),
        if (trend.isEmpty)
          const _EmptyInline(
              message: 'No trend observations for this selection.')
        else
          SizedBox(
            height: 126,
            child: Semantics(
              label:
                  'Customer transaction count trend; ${trend.length} dated values',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: trend.map((point) {
                  final count = _double(point['count']);
                  final max = trend
                      .map((e) => _double(e['count']))
                      .fold<double>(1, (a, b) => a > b ? a : b);
                  final barHeight = (count / max * 72).clamp(4.0, 72.0);
                  return Expanded(
                    child: Tooltip(
                      message:
                          '${_text(point['date'])}: ${_text(point['count'])} transactions · ${_money(point['value'])}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(_text(point['count']),
                                style:
                                    const TextStyle(fontSize: 10, color: _ink)),
                            const SizedBox(height: 5),
                            Container(
                              height: barHeight,
                              decoration: BoxDecoration(
                                  color: _teal,
                                  borderRadius: BorderRadius.circular(5)),
                            ),
                            const SizedBox(height: 6),
                            Text(_shortDate(point['date']),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 9, color: Color(0xff718782))),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _rankingPanel() {
    final count = _list(_response['topCount']);
    final volume = _list(_response['topVolume']);
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth < 700 ? 1 : 2;
      final w = (c.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(width: w, child: _ranking('Highest activity', count, 'count')),
        SizedBox(
            width: w,
            child: _ranking('Highest lifetime value', volume, 'value')),
      ]);
    });
  }

  Widget _ranking(
          String title, List<Map<String, dynamic>> rows, String metric) =>
      _Surface(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: _ink, fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const _EmptyInline(message: 'No ranked customers in this response.')
          else
            ...rows.take(5).toList().asMap().entries.map((entry) {
              final r = entry.value;
              return InkWell(
                onTap: () => _openProfile(r),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(children: [
                    SizedBox(
                        width: 24,
                        child: Text('${entry.key + 1}'.padLeft(2, '0'),
                            style: const TextStyle(
                                color: _teal,
                                fontWeight: FontWeight.w800,
                                fontSize: 11))),
                    Expanded(
                        child: Text(_text(r['fullName']),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _ink, fontWeight: FontWeight.w700))),
                    Text(
                        metric == 'count'
                            ? '${_text(_map(r['successful'])['count'], _text(r['recentCount']))} tx'
                            : _money(_map(r['successful'])['value']),
                        style: const TextStyle(
                            color: Color(0xff526c67),
                            fontWeight: FontWeight.w700,
                            fontSize: 12))
                  ]),
                ),
              );
            }),
        ]),
      );

  Widget _customerList() {
    final rows = _list(_response['items']);
    final pagination = _map(_response['pagination']);
    final cap = _map(_response['capabilities']);
    final canExport = cap['canExport'] == true;
    final allCount = _int(pagination['total']);
    return _Surface(
      padding: const EdgeInsets.all(0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 10,
            children: [
              Text('Customer list  ·  $allCount matched',
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w800, fontSize: 15)),
              Wrap(spacing: 7, runSpacing: 7, children: [
                OutlinedButton.icon(
                    onPressed:
                        canExport ? () => _export('download', 'csv') : null,
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('CSV contacts')),
                OutlinedButton.icon(
                    onPressed:
                        canExport ? () => _export('download', 'xlsx') : null,
                    icon: const Icon(Icons.table_view_outlined, size: 16),
                    label: const Text('Excel')),
                OutlinedButton.icon(
                    onPressed: canExport ? () => _export('share', 'csv') : null,
                    icon: const Icon(Icons.ios_share_outlined, size: 16),
                    label: const Text('Share')),
                OutlinedButton.icon(
                    onPressed: canExport ? () => _export('print', 'pdf') : null,
                    icon: const Icon(Icons.print_outlined, size: 16),
                    label: const Text('Print PDF')),
                FilledButton.tonalIcon(
                    onPressed: cap['canPrepareCampaign'] == true
                        ? _prepareCampaign
                        : null,
                    icon: const Icon(Icons.edit_note_outlined, size: 17),
                    label: const Text('Prepare campaign')),
              ]),
            ],
          ),
        ),
        if (canExport)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
                _selected.isEmpty
                    ? 'No rows selected · contact export will include all $allCount matching customers.'
                    : '${_selected.length} selected · contact details only',
                style: const TextStyle(color: Color(0xff718782), fontSize: 11)),
          ),
        if (_loading)
          const _SkeletonList()
        else if (_error != null)
          _errorPanel(_error!, _load)
        else if (rows.isEmpty)
          const Padding(
              padding: EdgeInsets.all(25),
              child: _EmptyInline(message: 'No customers match these filters.'))
        else ...[
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                TextButton(
                    onPressed: () => setState(() => _selected.clear()),
                    child: const Text('Clear selection')),
                TextButton(
                    onPressed: () => setState(() => _selected
                      ..clear()
                      ..addAll(rows
                          .map((r) => _text(r['_id'], ''))
                          .where((v) => v.isNotEmpty))),
                    child: const Text('Select this page')),
              ]),
            ),
          ...rows.map(_customerRow),
          _pager(pagination, (page) {
            setState(() => _filters['page'] = page);
            _load();
          }),
        ],
      ]),
    );
  }

  Widget _customerRow(Map<String, dynamic> customer) {
    final id = _text(customer['_id'], '');
    final successful = _map(customer['successful']);
    final category = _text(customer['category'], 'Unclassified');
    return InkWell(
      onTap: () => _openProfile(customer),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xffedf2ef)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_map(_response['capabilities'])['canExport'] == true)
            SizedBox(
              width: 35,
              child: Checkbox(
                value: id.isNotEmpty && _selected.contains(id),
                activeColor: _teal,
                onChanged: (v) => setState(() {
                  if (id.isNotEmpty && v == true) {
                    _selected.add(id);
                  } else {
                    _selected.remove(id);
                  }
                }),
              ),
            ),
          if (_hasUnappliedFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _noticeBox(
                  'Filters have unapplied edits. Exports and previews remain scoped to the filters used for this displayed list until you apply changes.'),
            ),
          CircleAvatar(
            backgroundColor: _mint,
            foregroundColor: _teal,
            radius: 20,
            child: Text(_text(customer['fullName'], '?')
                .characters
                .first
                .toUpperCase()),
          ),
          const SizedBox(width: 11),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                  spacing: 7,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_text(customer['fullName']),
                        style: const TextStyle(
                            color: _ink, fontWeight: FontWeight.w800)),
                    _tag(category.toUpperCase()),
                    if (customer['isNew'] == true) _tag('NEW'),
                  ]),
              const SizedBox(height: 4),
              Text(
                  '${_text(customer['phone'])}  ·  ${_text(customer['email'])}',
                  style:
                      const TextStyle(color: Color(0xff607773), fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                  '${_text(customer['state'])} / ${_text(customer['lga'])}  ·  Last success ${_date(customer['lastSuccess'])}',
                  style:
                      const TextStyle(color: Color(0xff718782), fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 8),
          if (MediaQuery.sizeOf(context).width > 560)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                    '${_text(successful['count'], _text(customer['recentCount'], '0'))} tx · 30d',
                    style: const TextStyle(
                        color: _ink, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(_money(successful['value']),
                    style: const TextStyle(
                        color: _teal,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                Text('lifetime successful',
                    style: const TextStyle(
                        color: Color(0xff718782), fontSize: 10)),
              ],
            ),
          const SizedBox(width: 7),
          const Icon(Icons.chevron_right, color: Color(0xff8ba29c)),
        ]),
      ),
    );
  }

  Widget _tag(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration:
            BoxDecoration(color: _mint, borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: const TextStyle(
                color: _teal,
                fontSize: 9,
                letterSpacing: .3,
                fontWeight: FontWeight.w800)),
      );

  Widget _pager(Map<String, dynamic> page, ValueChanged<int> onPage) {
    final current = _int(page['page'] ?? page['currentPage']);
    final totalPages = _int(page['totalPages']);
    final total = _int(page['total']);
    if (totalPages <= 1 && total <= 20) return const SizedBox(height: 5);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text(
            'Page $current of ${totalPages == 0 ? 1 : totalPages} · $total records',
            style: const TextStyle(color: Color(0xff718782), fontSize: 12)),
        IconButton(
          tooltip: 'Previous page',
          onPressed: current > 1 ? () => onPage(current - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Next page',
          onPressed: current < totalPages ? () => onPage(current + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
    );
  }

  Widget _workforceView() {
    final items = _list(_performance['items']);
    final p = _map(_performance['pagination']);
    final unavailable = (_performance['unavailableDimensions'] as List?)
            ?.map((e) => '$e')
            .toList() ??
        [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Surface(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text('Engagement by workforce dimension',
                    style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 16))),
            DropdownButton<String>(
              value: _dimension,
              items: const [
                DropdownMenuItem(value: 'agent', child: Text('Agent')),
                DropdownMenuItem(
                    value: 'stateManager', child: Text('State manager')),
                DropdownMenuItem(
                    value: 'zonalManager', child: Text('Zonal manager')),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => _dimension = v);
                  _loadPerformance();
                }
              },
            )
          ]),
          const SizedBox(height: 4),
          const Text(
              'Registration, activation, retention and successful value for the selected period.',
              style: TextStyle(color: Color(0xff718782), fontSize: 12)),
          if (unavailable.isNotEmpty) ...[
            const SizedBox(height: 12),
            _noticeBox(
                'Dimensions not available: ${unavailable.join(', ')}. They are shown by their source codes and are not relabelled.'),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      if (_workforceLoading)
        const _SkeletonList()
      else if (_workforceError != null)
        _errorPanel(_workforceError!, _loadPerformance)
      else if (items.isEmpty)
        const _Surface(
            padding: EdgeInsets.all(20),
            child: _EmptyInline(
                message: 'No workforce rows are available for these filters.'))
      else
        _Surface(
          padding: const EdgeInsets.all(0),
          child: Column(children: [
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_text(item['name']),
                            style: const TextStyle(
                                color: _ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                        const SizedBox(height: 10),
                        Wrap(spacing: 9, runSpacing: 9, children: [
                          _smallMetric('Registered', item['registered']),
                          _smallMetric('Transacted', item['transacted']),
                          _smallMetric('Never', item['never']),
                          _smallMetric('Active', item['active']),
                          _smallMetric('Inactive', item['inactive']),
                          _smallMetric(
                              'Previous active', item['previousActive']),
                          _smallMetric('Retained', item['retained']),
                          _smallMetric(
                              'Retention', '${_text(item['retentionRate'])}%'),
                          _smallMetric(
                              'Successful value', _money(item['value'])),
                        ]),
                      ]),
                )),
            _pager(p, (page) => _loadPerformance(page: page)),
          ]),
        ),
    ]);
  }

  Widget _smallMetric(String label, dynamic value) => Container(
        constraints: const BoxConstraints(minWidth: 100),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0xfff4f8f6),
            borderRadius: BorderRadius.circular(9)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(color: Color(0xff718782), fontSize: 10)),
          const SizedBox(height: 3),
          Text(_text(value),
              style: const TextStyle(
                  color: _ink, fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _settingsView() {
    if (_settings.isEmpty) {
      return _Surface(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Segment thresholds',
              style: TextStyle(
                  color: _ink, fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 7),
          const Text(
              'Settings are unavailable until the customer intelligence snapshot returns thresholds.',
              style: TextStyle(color: Color(0xff718782))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry')),
        ]),
      );
    }
    final values = {
      'frequentMin': '${_settings['frequentMin'] ?? 10}',
      'regularMin': '${_settings['regularMin'] ?? 4}',
      'activityDays': '${_settings['activityDays'] ?? 30}',
      'inactiveDays': '${_settings['inactiveDays'] ?? 60}',
      'newDays': '${_settings['newDays'] ?? 30}',
    };
    return _Surface(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Segment thresholds',
            style: TextStyle(
                color: _ink, fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 6),
        const Text(
            'Classification changes affect the rolling engagement segments. Frequent and regular thresholds must remain exclusive.',
            style: TextStyle(color: Color(0xff718782), height: 1.4)),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth < 650 ? 1 : 2;
          final width = (c.maxWidth - (cols - 1) * 12) / cols;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            ...values.entries.map((entry) => SizedBox(
                  width: width,
                  child: TextFormField(
                    key: ValueKey('settings-${entry.key}'),
                    initialValue: entry.value,
                    keyboardType: TextInputType.number,
                    decoration: _decoration(_settingLabel(entry.key)),
                    onChanged: (v) => values[entry.key] = v,
                  ),
                )),
            SizedBox(
              width: width,
              child: FilledButton.icon(
                onPressed: _canSettings ? () => _saveSettings(values) : null,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save thresholds'),
                style: FilledButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white),
              ),
            ),
          ]);
        }),
        if (!_canSettings) ...[
          const SizedBox(height: 12),
          _noticeBox(
              'Read only. Changes require Head Office identity and settings.update.'),
        ],
      ]),
    );
  }

  Future<void> _saveSettings(Map<String, String> values) async {
    if (!_canSettings) return;
    final frequent = int.tryParse(values['frequentMin'] ?? '');
    final regular = int.tryParse(values['regularMin'] ?? '');
    final days = [
      int.tryParse(values['activityDays'] ?? ''),
      int.tryParse(values['inactiveDays'] ?? ''),
      int.tryParse(values['newDays'] ?? ''),
    ];
    if (frequent == null ||
        regular == null ||
        frequent <= regular ||
        regular < 1 ||
        days.any((v) => v == null || v < 1)) {
      _notice(
          'Use positive whole days/counts. Frequent minimum must exceed regular minimum.');
      return;
    }
    final form = GlobalKey<FormState>();
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm segment settings'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: reason,
            decoration: const InputDecoration(
                labelText: 'Reason for change',
                hintText: 'Required for the audit record'),
            validator: (v) => (v?.trim().length ?? 0) < 5
                ? 'Enter a reason (at least 5 characters).'
                : null,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Continue')),
        ],
      ),
    );
    if (accepted != true) {
      reason.dispose();
      return;
    }
    final payload = <String, dynamic>{
      for (final entry in values.entries) entry.key: int.tryParse(entry.value),
      'reason': reason.text.trim(),
    };
    reason.dispose();
    try {
      final response = await _api.updateSettings(payload);
      if (mounted) {
        setState(() => _settings = _map(response['settings']).isNotEmpty
            ? _map(response['settings'])
            : _settings);
        _notice('Segment settings saved.');
        await _load();
      }
    } catch (e) {
      if (mounted) _notice(e.toString());
    }
  }

  Widget _definitionsView() {
    final metrics = <String, String>{
      'Active':
          'Customers with a successful transaction in the selected activity window.',
      'Retained':
          'Previously active customers who are active again in the selected period.',
      'Retention rate':
          'Retained customers divided by the previous active cohort.',
      'Frequent / regular / occasional':
          'Exclusive rolling 30-day successful transaction-count segments, using the configured thresholds.',
      'Declining':
          'A prior active customer whose current engagement has declined.',
      'Inactive': 'Previously active customers outside the inactivity window.',
      'Never': 'No successful transaction on record.',
      'New':
          'Registration within the configured new-customer window. This overlay does not replace a segment.',
      'Successful count':
          'Successful transaction count; separate from failed, pending, refunded and other statuses.',
      'Successful value':
          'Successful amount; separate from transaction count and other statuses.',
    };
    return _Surface(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('How to read this page',
            style: TextStyle(
                color: _ink, fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 5),
        const Text(
            'Definitions returned by the service are shown alongside the operational guide below.',
            style: TextStyle(color: Color(0xff718782))),
        const SizedBox(height: 10),
        ...metrics.entries.map((entry) => _definition(
            entry.key,
            _text(_definitions[entry.key] ??
                _definitions[_camel(entry.key)] ??
                entry.value))),
        if (_definitions.isNotEmpty) ...[
          const Divider(height: 26),
          ..._definitions.entries
              .map((e) => _definition(_title(e.key), '${e.value}')),
        ],
        const Divider(height: 26),
        _noticeBox(
            'This view reports engagement, not financial authority. Customer contact details are exposed only through the authorized contact-file workflow.'),
      ]),
    );
  }

  Widget _definition(String title, String description) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              margin: const EdgeInsets.only(top: 5),
              width: 7,
              height: 7,
              decoration:
                  const BoxDecoration(color: _teal, shape: BoxShape.circle)),
          const SizedBox(width: 11),
          Expanded(
              child: RichText(
            text: TextSpan(
              style: const TextStyle(
                  color: Color(0xff526c67), height: 1.45, fontSize: 13),
              children: [
                TextSpan(
                    text: '$title. ',
                    style: const TextStyle(
                        color: _ink, fontWeight: FontWeight.w800)),
                TextSpan(text: description),
              ],
            ),
          )),
        ]),
      );

  Widget _errorPanel(String error, Future<void> Function() retry) => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Color(0xffa34b3f)),
          const SizedBox(width: 9),
          Expanded(child: Text(error, style: const TextStyle(color: _ink))),
          TextButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry')),
        ]),
      );

  Widget _noticeBox(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xfffff7e9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xffefdfbd))),
        child: Text(message,
            style: const TextStyle(
                color: Color(0xff74592f), fontSize: 12, height: 1.4)),
      );

  String _money(dynamic value) => value == null
      ? '—'
      : '₦${_double(value).toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';

  String _date(dynamic value) {
    final parsed = DateTime.tryParse('$value');
    if (parsed == null) return 'Unavailable';
    final d = parsed.toLocal();
    return '${d.day.toString().padLeft(2, '0')} ${_month(d.month)} ${d.year}';
  }

  String _shortDate(dynamic value) {
    final date = DateTime.tryParse('$value');
    return date == null ? _text(value) : '${date.day}/${date.month}';
  }

  String _month(int month) => const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][month - 1];

  String _title(String value) => value
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String _camel(String value) {
    final words = value.toLowerCase().split(RegExp(r'[\s_]+'));
    return words.first +
        words
            .skip(1)
            .map((w) =>
                w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
            .join();
  }

  String _settingLabel(String key) => switch (key) {
        'frequentMin' => 'Frequent minimum · 30d successes',
        'regularMin' => 'Regular minimum · 30d successes',
        'activityDays' => 'Activity window · days',
        'inactiveDays' => 'Inactive after · days',
        'newDays' => 'New customer window · days',
        _ => key,
      };
}

class _CustomerProfileDialog extends StatefulWidget {
  const _CustomerProfileDialog({required this.api, required this.id});
  final CustomerIntelligenceApi api;
  final String id;
  @override
  State<_CustomerProfileDialog> createState() => _CustomerProfileDialogState();
}

class _CustomerProfileDialogState extends State<_CustomerProfileDialog> {
  static const _ink = Color(0xff173b40);
  static const _teal = Color(0xff087f78);
  Map<String, dynamic> _data = {};
  String? _error;
  bool _loading = true;
  int _page = 1;
  @override
  void initState() {
    super.initState();
    _load(1);
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.customer(widget.id, page: page);
      if (mounted) {
        setState(() {
          _data = result;
          _page = page;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> m(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : {};
  List<Map<String, dynamic>> l(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : [];
  String t(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty || s == 'null' ? 'Unavailable' : s;
  }

  @override
  Widget build(BuildContext context) {
    final customer = m(_data['customer']);
    final transactions = l(_data['transactions']);
    final pagination = m(_data['pagination']);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 850),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 17, 10, 12),
            child: Row(children: [
              const Icon(Icons.person_search_outlined, color: _teal),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      t(customer['fullName']) == 'Unavailable'
                          ? 'Customer profile'
                          : t(customer['fullName']),
                      style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 18))),
              IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const _SkeletonList()
                : _error != null
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!),
                        TextButton.icon(
                            onPressed: () => _load(_page),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'))
                      ]))
                    : ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          _profileSection('Contact', [
                            _profileValue('Phone', customer['phone']),
                            _profileValue('Email', customer['email']),
                            _profileValue('Registered', customer['createdAt']),
                            _profileValue('State', customer['state']),
                            _profileValue('LGA', customer['lga']),
                            _profileValue('Category', customer['category']),
                            _profileValue('Last login', _data['lastLogin']),
                            _profileValue('Registration source',
                                _data['registrationSource']),
                          ]),
                          _profileSection('Engagement', [
                            _profileValue('Recent successful count',
                                customer['recentCount']),
                            _profileValue('Period successful count',
                                customer['periodCount']),
                            _profileValue('Period successful value',
                                customer['periodValue']),
                            _profileValue(
                                'Last success', customer['lastSuccess']),
                            _profileValue('Days since last success',
                                customer['daysSinceLastSuccess']),
                            _profileValue('Most used service',
                                customer['mostUsedService']),
                          ]),
                          _profileSection('Assigned workforce', [
                            _profileValue(
                                'Agent', m(customer['agent'])['name']),
                            _profileValue('State manager',
                                m(customer['stateManager'])['name']),
                            _profileValue('Zonal manager',
                                m(customer['zonalManager'])['name']),
                          ]),
                          _statusCounts(customer),
                          const SizedBox(height: 12),
                          _simpleRows(
                              'Service breakdown',
                              l(_data['services']),
                              (e) =>
                                  '${t(e['serviceType'])} · ${t(e['count'])} · ₦${t(e['value'])}'),
                          _simpleRows(
                              'Engagement frequency',
                              l(_data['frequency']),
                              (e) =>
                                  '${t(e['date'])} · ${t(e['count'])} successful · ₦${t(e['value'])}'),
                          _simpleRows('Customer timeline', l(_data['timeline']),
                              (e) => '${t(e['date'])} · ${t(e['event'])}'),
                          const SizedBox(height: 8),
                          const Text('Transaction history',
                              style: TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                          const SizedBox(height: 7),
                          if (transactions.isEmpty)
                            const _EmptyInline(
                                message:
                                    'No transactions in this history page.')
                          else
                            ...transactions.map((tx) => ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                      Icons.receipt_long_outlined,
                                      color: _teal,
                                      size: 19),
                                  title: Text(
                                      '${t(tx['reference'])} · ${t(tx['serviceType'])}',
                                      style: const TextStyle(
                                          color: _ink,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                  subtitle: Text(
                                      '${t(tx['status'])} · ${t(tx['createdAt'])}'),
                                  trailing: Text('₦${t(tx['amount'])}',
                                      style: const TextStyle(
                                          color: _ink,
                                          fontWeight: FontWeight.w700)),
                                )),
                          _pager(pagination, (next) => _load(next)),
                          const Text(
                              'Amounts and transaction records are read-only engagement context; no financial controls are available here.',
                              style: TextStyle(
                                  color: Color(0xff718782),
                                  fontSize: 11,
                                  height: 1.4)),
                        ],
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _profileSection(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: _ink, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ]),
      );

  Widget _profileValue(String label, dynamic value) => Container(
        constraints: const BoxConstraints(minWidth: 165, maxWidth: 370),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xfff4f8f6),
            borderRadius: BorderRadius.circular(9)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(color: Color(0xff718782), fontSize: 10)),
          const SizedBox(height: 4),
          Text(t(value),
              style: const TextStyle(
                  color: _ink, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _statusCounts(Map<String, dynamic> customer) => _profileSection(
        'Transaction outcomes · counts and values stay separate',
        [
          for (final status in const [
            'successful',
            'failed',
            'pending',
            'refunded',
            'other'
          ])
            _profileValue(_title(status),
                '${t(m(customer[status])['count'])} transactions · ₦${t(m(customer[status])['value'])}'),
        ],
      );

  Widget _simpleRows(String title, List<Map<String, dynamic>> rows,
          String Function(Map<String, dynamic>) label) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: _ink, fontWeight: FontWeight.w800, fontSize: 15)),
          if (rows.isEmpty)
            const Padding(
                padding: EdgeInsets.only(top: 6),
                child: _EmptyInline(message: 'No records available.'))
          else
            ...rows.map((row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(label(row),
                      style: const TextStyle(
                          color: Color(0xff526c67), fontSize: 12)),
                )),
        ]),
      );

  Widget _pager(Map<String, dynamic> pagination, ValueChanged<int> onPage) {
    final current = int.tryParse('${pagination['page'] ?? _page}') ?? _page;
    final total = int.tryParse('${pagination['totalPages'] ?? 1}') ?? 1;
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      Text('Page $current of $total',
          style: const TextStyle(color: Color(0xff718782), fontSize: 12)),
      IconButton(
          tooltip: 'Previous page',
          onPressed: current > 1 ? () => onPage(current - 1) : null,
          icon: const Icon(Icons.chevron_left)),
      IconButton(
          tooltip: 'Next page',
          onPressed: current < total ? () => onPage(current + 1) : null,
          icon: const Icon(Icons.chevron_right)),
    ]);
  }

  String _title(String text) => text[0].toUpperCase() + text.substring(1);
}

class _CampaignDraft {
  const _CampaignDraft(this.purpose, this.message);
  final String purpose;
  final String message;
}

class _CampaignDraftDialog extends StatefulWidget {
  const _CampaignDraftDialog();
  @override
  State<_CampaignDraftDialog> createState() => _CampaignDraftDialogState();
}

class _CampaignDraftDialogState extends State<_CampaignDraftDialog> {
  final _message = TextEditingController();
  String _purpose = 'WELCOME';
  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Prepare campaign preview'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'This prepares an audited draft preview only. It cannot send messages.',
                style: TextStyle(color: Color(0xff607773), height: 1.4)),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _purpose,
              decoration: const InputDecoration(labelText: 'Purpose'),
              items: const [
                DropdownMenuItem(value: 'WELCOME', child: Text('Welcome')),
                DropdownMenuItem(
                    value: 'FIRST_TRANSACTION',
                    child: Text('First transaction')),
                DropdownMenuItem(
                    value: 'REACTIVATE', child: Text('Reactivation')),
                DropdownMenuItem(value: 'REWARD', child: Text('Reward')),
                DropdownMenuItem(
                    value: 'DECLINING', child: Text('Declining engagement')),
              ],
              onChanged: (v) => setState(() => _purpose = v ?? 'WELCOME'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _message,
              maxLines: 5,
              maxLength: 1000,
              decoration: const InputDecoration(
                  labelText: 'Draft message',
                  hintText: 'Write a draft for review',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            const _SafetyCopy(),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _message.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                      context, _CampaignDraft(_purpose, _message.text.trim())),
              child: const Text('Preview draft')),
        ],
      );
}

class _PreviewDialog extends StatelessWidget {
  const _PreviewDialog({required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    String value(String key, [String fallback = 'Not provided']) {
      final v = data[key]?.toString().trim() ?? '';
      return v.isEmpty || v == 'null' ? fallback : v;
    }

    return AlertDialog(
      title: const Text('Campaign preparation preview'),
      content: SizedBox(
        width: 500,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Purpose: ${value('purpose')}'),
              const SizedBox(height: 5),
              Text('Selected customers: ${value('selectedCount')}'),
              const SizedBox(height: 12),
              const Text('Draft',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              SelectableText(value('message')),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xfffff7e9),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(
                    '${value('warning', 'Preview only; dispatch is disabled.')}\n\nConsent records are not available here. No message was delivered.',
                    style: const TextStyle(
                        color: Color(0xff74592f), height: 1.4, fontSize: 12)),
              ),
              const SizedBox(height: 9),
              Text('Dispatch enabled: ${value('dispatchEnabled', 'false')}',
                  style: const TextStyle(
                      color: _CustomerIntelligenceScreenState._teal,
                      fontWeight: FontWeight.w800)),
            ]),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}

class _SafetyCopy extends StatelessWidget {
  const _SafetyCopy();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xfffff7e9),
            borderRadius: BorderRadius.circular(9)),
        child: const Text(
            'No consent records are available. This is draft preparation only: no dispatch or delivery. Contact details can only be prepared using the contact export.',
            style:
                TextStyle(color: Color(0xff74592f), fontSize: 11, height: 1.4)),
      );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, required this.padding});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xffe2ece8)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x080f403d), blurRadius: 14, offset: Offset(0, 4))
          ],
        ),
        child: child,
      );
}

class _EmptyInline extends StatelessWidget {
  const _EmptyInline({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          const Icon(Icons.inbox_outlined, size: 17, color: Color(0xff829791)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style:
                      const TextStyle(color: Color(0xff718782), fontSize: 12))),
        ]),
      );
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();
  @override
  Widget build(BuildContext context) => Column(
        children: List.generate(
          4,
          (index) => Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            height: 50,
            decoration: BoxDecoration(
                color: const Color(0xffedf3f0),
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
}
