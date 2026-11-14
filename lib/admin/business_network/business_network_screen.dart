import 'package:flutter/material.dart';

import 'business_network_admin_api.dart';
import 'business_network_export.dart';

part 'business_network_profile_review.dart';
part 'business_network_settings_editor.dart';

class BusinessNetworkScreen extends StatefulWidget {
  const BusinessNetworkScreen({super.key, this.api, this.initialSection});
  final BusinessNetworkAdminApi? api;
  final int? initialSection;
  @override
  State<BusinessNetworkScreen> createState() => _BusinessNetworkScreenState();
}

class _BusinessNetworkScreenState extends State<BusinessNetworkScreen> {
  late final BusinessNetworkAdminApi _api =
      widget.api ?? BusinessNetworkAdminApi();
  static const _sections = [
    'Network Overview',
    'Agent Applications',
    'Active Agents',
    'Suspended Agents',
    'Merchant Applications',
    'Active Merchants',
    'Suspended Merchants',
    'Agent Transactions',
    'Merchant Transactions',
    'Commission Management',
    'Commission Payments/Statements',
    'Business Network Reports',
    'Network Settings',
    'Audit Logs',
  ];
  int _index = 0;
  bool _loading = true;
  bool _exporting = false;
  bool _printing = false;
  String? _error;
  Map<String, dynamic>? _overview;
  List<dynamic> _rows = [];
  List<dynamic> _rules = [];
  List<dynamic> _audit = [];
  int _auditTotal = 0;
  Map<String, dynamic> _commissionTotals = {};
  static const int _commissionLimit = 50;
  int _commissionPage = 1;
  int _commissionTotal = 0;
  final _search = TextEditingController();
  final _state = TextEditingController();
  final _lga = TextEditingController();
  final _profileId = TextEditingController();
  final _commissionProfileId = TextEditingController();
  String _status = 'ALL';
  String _profileStatus = 'SUBMITTED';
  int _page = 1;
  Map<String, dynamic>? _settings;

  @override
  void initState() {
    super.initState();
    _index = widget.initialSection ?? 0;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _state.dispose();
    _lga.dispose();
    _profileId.dispose();
    _commissionProfileId.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  String get _section => _sections[_index];
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_index == 0) {
        _overview =
            Map<String, dynamic>.from(await _api.get('overview') as Map);
      } else if (_index >= 1 && _index <= 6) {
        final kind = _index <= 3 ? 'AGENT' : 'MERCHANT';
        final status = _index == 1 || _index == 4
            ? _profileStatus
            : _index == 3 || _index == 6
                ? 'SUSPENDED'
                : 'APPROVED';
        final data = await _api.get('profiles', query: {
          'kind': kind,
          'status': status,
          'search': _search.text.trim(),
          'state': _state.text.trim(),
          'lga': _lga.text.trim(),
          'page': '$_page'
        });
        _rows = (data as Map)['items'] as List? ?? [];
      } else if (_index == 7 || _index == 8) {
        final data = await _api.get('transactions', query: {
          'kind': _index == 7 ? 'AGENT' : 'MERCHANT',
          'profileId': _profileId.text.trim(),
          'status': _status == 'ALL' ? '' : _status,
          'page': '$_page'
        });
        _rows = (data as Map)['items'] as List? ?? [];
      } else if (_index == 9) {
        _rules = ((await _api.get('rules') as Map)['items'] as List? ?? []);
        final data = await _api.get('commissions', query: {
          if (_commissionProfileId.text.trim().isNotEmpty)
            'profileId': _commissionProfileId.text.trim(),
          'page': '$_commissionPage',
          'limit': '$_commissionLimit',
        });
        _rows = (data as Map)['items'] as List? ?? [];
        _commissionTotal =
            data['total'] is num ? (data['total'] as num).toInt() : 0;
        _commissionTotals = data['totals'] is Map
            ? Map<String, dynamic>.from(data['totals'] as Map)
            : {};
      } else if (_index == 10) {
        final data = await _api.get('commissions', query: {
          if (_commissionProfileId.text.trim().isNotEmpty)
            'profileId': _commissionProfileId.text.trim(),
          'page': '$_commissionPage',
          'limit': '$_commissionLimit',
        });
        _rows = (data as Map)['items'] as List? ?? [];
        _commissionTotal =
            data['total'] is num ? (data['total'] as num).toInt() : 0;
        _commissionTotals = data['totals'] is Map
            ? Map<String, dynamic>.from(data['totals'] as Map)
            : {};
      } else if (_index == 12) {
        _settings =
            Map<String, dynamic>.from(await _api.get('settings') as Map);
      } else if (_index == 13) {
        final data = await _api.get('audit', query: {'page': '$_page'});
        _audit = (data as Map)['items'] as List? ?? [];
        _auditTotal =
            data['total'] is num ? (data['total'] as num).toInt() : _auditTotal;
      } else {
        _rows = [];
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _select(int index) {
    setState(() {
      _index = index;
      _page = 1;
      if (index == 9 || index == 10) {
        _commissionPage = 1;
      }
    });
    _load();
  }

  Widget _commissionPagination() {
    if (_commissionPage == 1 && _commissionTotal <= _commissionLimit) {
      return const SizedBox.shrink();
    }
    final pageCount =
        (_commissionTotal + _commissionLimit - 1) ~/ _commissionLimit;
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        TextButton(
          onPressed: _commissionPage > 1
              ? () {
                  setState(() => _commissionPage--);
                  _load();
                }
              : null,
          child: const Text('Previous'),
        ),
        Text('Page $_commissionPage of $pageCount'),
        TextButton(
          onPressed: _commissionPage < pageCount
              ? () {
                  setState(() => _commissionPage++);
                  _load();
                }
              : null,
          child: const Text('Next'),
        ),
      ],
    );
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final csv = await _api.csv('reports', query: const {'format': 'csv'});
      final downloaded = await downloadBusinessNetworkCsv(
        csv,
        'servicepay-business-network-${DateTime.now().toIso8601String().substring(0, 10)}.csv',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          downloaded
              ? 'Business Network CSV downloaded.'
              : 'Download cancelled.',
        )));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _printAgentReport() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      final csv = await _api.csv(
        'reports',
        query: const {'format': 'csv', 'kind': 'AGENT'},
      );
      final opened = await printBusinessNetworkReport(
        csv,
        title: 'ServicePay Agent Report',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              opened
                  ? 'Agent report opened in the browser print dialog.'
                  : 'Direct printing is unavailable on this platform. Use Download Business Network CSV instead.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      appBar: AppBar(
          title: const Text('BUSINESS NETWORK',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8)),
          backgroundColor: const Color(0xFFF4F7F5),
          foregroundColor: const Color(0xFF18372A),
          actions: [
            IconButton(
                onPressed: _load,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh))
          ]),
      body: wide
          ? Row(children: [_sideNav(), Expanded(child: _content())])
          : Column(children: [
              SizedBox(
                height: 64,
                child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: List.generate(
                        _sections.length,
                        (i) => Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 3, vertical: 9),
                            child: ChoiceChip(
                                label: Text(_sections[i]),
                                selected: i == _index,
                                onSelected: (_) => _select(i))))),
              ),
              Expanded(child: _content())
            ]),
    );
  }

  Widget _sideNav() => Container(
      width: 242,
      color: Colors.white,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        const Padding(
            padding: EdgeInsets.fromLTRB(10, 8, 10, 16),
            child: Text('BUSINESS NETWORK',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: Color(0xFF08783E)))),
        ...List.generate(
            _sections.length,
            (i) => ListTile(
                selected: i == _index,
                selectedTileColor: const Color(0xFFE8F3EC),
                leading: Icon(_icons[i]),
                title: Text(_sections[i],
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                onTap: () => _select(i)))
      ]));
  static const _icons = [
    Icons.hub_outlined,
    Icons.assignment_outlined,
    Icons.storefront_outlined,
    Icons.pause_circle_outline,
    Icons.business_outlined,
    Icons.business_center_outlined,
    Icons.pause_circle_outline,
    Icons.receipt_long_outlined,
    Icons.receipt_outlined,
    Icons.tune,
    Icons.payments_outlined,
    Icons.download_outlined,
    Icons.settings_outlined,
    Icons.fact_check_outlined
  ];
  Widget _content() {
    if (_loading) return _skeleton();
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                FilledButton(onPressed: _load, child: const Text('Retry'))
              ])));
    }
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(18), children: [
          Row(children: [
            Expanded(
                child: Text(_section,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800))),
            if (_index == 11)
              IconButton(
                  onPressed: _exporting ? null : _export,
                  tooltip: 'Download CSV',
                  icon: _exporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined))
          ]),
          const SizedBox(height: 12),
          if (_index == 0)
            _overviewContent()
          else if (_index >= 1 && _index <= 8)
            _records()
          else if (_index == 9)
            _commissionManagement()
          else if (_index == 10)
            _settlement()
          else if (_index == 11)
            _reports()
          else if (_index == 12)
            _settingsView()
          else
            _auditView(),
        ]));
  }

  Widget _overviewContent() {
    final agents = _overview?['agents'] is Map
        ? Map<String, dynamic>.from(_overview!['agents'] as Map)
        : <String, dynamic>{};
    final merchants = _overview?['merchants'] is Map
        ? Map<String, dynamic>.from(_overview!['merchants'] as Map)
        : <String, dynamic>{};
    final transactions = _overview?['transactions'] is Map
        ? Map<String, dynamic>.from(_overview!['transactions'] as Map)
        : <String, dynamic>{};
    final commissions = _overview?['commissions'] is Map
        ? Map<String, dynamic>.from(_overview!['commissions'] as Map)
        : <String, dynamic>{};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('The operating picture',
          style: TextStyle(color: Color(0xFF53645B))),
      const SizedBox(height: 14),
      _metricGroup('RETAIL AGENTS', agents,
          ['registered', 'approved', 'pending', 'active', 'suspended']),
      _metricGroup('SME MERCHANTS', merchants,
          ['registered', 'approved', 'pending', 'active', 'suspended']),
      _metricGroup('NETWORK ACTIVITY', transactions,
          ['total', 'successful', 'pending', 'failed', 'volumeKobo']),
      _metricGroup('COMMISSIONS', commissions,
          commissions.keys.map((e) => e.toString()).toList()),
      if ((_overview?['locations'] as List? ?? []).isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('Verified network locations',
            style: TextStyle(fontWeight: FontWeight.w800)),
        ...(_overview!['locations'] as List).map((x) {
          final location = Map<String, dynamic>.from(x as Map);
          return ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(location['state']?.toString() ?? 'Location'),
            subtitle:
                Text('${location['lga'] ?? ''} · ${location['count'] ?? ''}'),
          );
        }),
      ],
    ]);
  }

  Widget _metricGroup(
          String title, Map<String, dynamic> data, List<String> keys) =>
      Card(
          color: Colors.white,
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 11,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF66756D))),
                    const SizedBox(height: 8),
                    Wrap(
                        spacing: 18,
                        runSpacing: 12,
                        children: keys
                            .map((key) => SizedBox(
                                width: 110,
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(_human(key),
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF66756D))),
                                      Text(_moneyIfKobo(key, data[key]),
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800))
                                    ])))
                            .toList())
                  ])));
  Widget _records() {
    return Column(children: [
      if (_index <= 6)
        Row(children: [
          Expanded(
              child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                      labelText: 'Search name, phone or network ID',
                      prefixIcon: Icon(Icons.search)),
                  onSubmitted: (_) => _load())),
          const SizedBox(width: 8),
          SizedBox(
              width: 130,
              child: TextField(
                  controller: _state,
                  decoration: const InputDecoration(labelText: 'State'),
                  onSubmitted: (_) => _load()))
        ]),
      if (_index <= 6)
        TextField(
            controller: _lga,
            decoration: const InputDecoration(labelText: 'LGA'),
            onSubmitted: (_) => _load()),
      if (_index == 7 || _index == 8)
        TextField(
            controller: _profileId,
            decoration: const InputDecoration(
                labelText: 'Business profile ID (optional)'),
            onSubmitted: (_) => _load()),
      if (_index <= 6)
        Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Apply filters'))),
      if (_index == 1 || _index == 4)
        DropdownButtonFormField<String>(
          value: _profileStatus,
          decoration: const InputDecoration(labelText: 'Application status'),
          items: const ['SUBMITTED', 'UNDER_REVIEW', 'REJECTED']
              .map(
                (status) => DropdownMenuItem(
                    value: status, child: Text(status.replaceAll('_', ' '))),
              )
              .toList(),
          onChanged: (status) {
            _profileStatus = status ?? 'SUBMITTED';
            _load();
          },
        ),
      if (_index == 7 || _index == 8)
        DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(labelText: 'Transaction status'),
            items: const ['ALL', 'SUCCESSFUL', 'PENDING', 'FAILED']
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (s) {
              _status = s ?? 'ALL';
              _load();
            }),
      if (_rows.isEmpty) _empty('No records match these filters.'),
      ..._rows.map((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        return _index <= 6 ? _profileRow(item) : _transactionRow(item);
      }),
      if (_rows.isNotEmpty)
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
              onPressed: _page > 1
                  ? () {
                      setState(() => _page--);
                      _load();
                    }
                  : null,
              child: const Text('Previous')),
          Text('Page $_page'),
          TextButton(
              onPressed: () {
                setState(() => _page++);
                _load();
              },
              child: const Text('Next'))
        ]),
    ]);
  }

  Widget _profileRow(Map<String, dynamic> item) {
    final details = item['details'] is Map
        ? Map<String, dynamic>.from(item['details'] as Map)
        : <String, dynamic>{};
    return Card(
        color: Colors.white,
        elevation: 0,
        child: ListTile(
            onTap: () => _profileDetail(item),
            leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F3EC),
                child: Icon(Icons.business_outlined, color: Color(0xFF08783E))),
            title: Text(
                details['businessName']?.toString() ??
                    details['ownerName']?.toString() ??
                    'Business profile',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${item['networkId'] ?? item['_id'] ?? ''} · ${details['phone'] ?? ''}\\n${details['state'] ?? ''} ${details['lga'] ?? ''}'),
            isThreeLine: true,
            trailing:
                Text((item['status'] ?? '').toString().replaceAll('_', ' '))));
  }

  Widget _transactionRow(Map<String, dynamic> item) => Card(
        color: Colors.white,
        elevation: 0,
        child: ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(item['reference']?.toString() ??
              item['_id']?.toString() ??
              'Transaction'),
          subtitle:
              Text('${item['serviceType'] ?? ''} · ${item['createdAt'] ?? ''}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_moneyIfKobo('amountKobo', item['amountKobo'])),
              Text(item['status']?.toString() ?? ''),
            ],
          ),
        ),
      );
  Future<void> _profileDetail(Map<String, dynamic> item) async {
    try {
      final detail = Map<String, dynamic>.from(
          await _api.get('profiles/${item['_id']}') as Map);
      final profile = detail['profile'] is Map
          ? Map<String, dynamic>.from(detail['profile'] as Map)
          : detail;
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (context) =>
              _ReviewDialog(api: _api, profile: profile, onDone: _load));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Widget _commissionManagement() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _commissionProfileId,
          decoration:
              const InputDecoration(labelText: 'Filter by business profile ID'),
          onSubmitted: (_) {
            setState(() => _commissionPage = 1);
            _load();
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              setState(() => _commissionPage = 1);
              _load();
            },
            icon: const Icon(Icons.filter_alt_outlined),
            label: const Text('Apply profile filter'),
          ),
        ),
        _metricGroup('COMMISSION TOTALS', _commissionTotals,
            _commissionTotals.keys.toList()),
        FilledButton.icon(
            onPressed: _newRule,
            icon: const Icon(Icons.add),
            label: const Text('Create commission rule')),
        const SizedBox(height: 10),
        const Text(
            'Rules are evaluated by the backend. Percent values use basis points; money bounds use integer kobo.',
            style: TextStyle(color: Color(0xFF53645B))),
        if (_rules.isEmpty) _empty('No commission rules returned.'),
        ..._rules.map((raw) {
          final rule = Map<String, dynamic>.from(raw as Map);
          final id = rule['_id']?.toString() ?? '';
          final enabled = rule['enabled'] == true;
          return Card(
            color: Colors.white,
            elevation: 0,
            child: ListTile(
              title: Text(
                  '${rule['service'] ?? 'Service'} · ${rule['mode'] ?? ''} ${rule['value'] ?? ''}'),
              subtitle: Text(
                  '${rule['group'] ?? 'All groups'} · ${rule['state'] ?? 'All states'} ${rule['lga'] ?? ''}\\n${rule['minAmountKobo'] ?? 0}–${rule['maxAmountKobo'] ?? '∞'} kobo'),
              isThreeLine: true,
              trailing: enabled
                  ? TextButton(
                      onPressed: () async {
                        try {
                          await _api.patch('rules/$id', {'enabled': false});
                          _load();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                        }
                      },
                      child: const Text('Disable'),
                    )
                  : const Text('Disabled'),
            ),
          );
        }),
        const SizedBox(height: 16),
        const Text('Commission ledger',
            style: TextStyle(fontWeight: FontWeight.w800)),
        ..._rows.map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          final reference =
              (row['reference'] ?? row['publicReference'] ?? '').toString();
          return ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(
                  '${row['event'] ?? 'Commission'} · ${_moneyIfKobo('amountKobo', row['amountKobo'])}'),
              subtitle: Text(
                  '${reference.isEmpty ? 'Reference unavailable' : reference} · '
                  '${row['serviceType'] ?? ''} · ${row['transactionStatus'] ?? ''}'));
        }),
        _commissionPagination(),
      ]);
  Future<void> _newRule() async {
    final service = TextEditingController();
    final group = TextEditingController();
    final state = TextEditingController();
    final lga = TextEditingController();
    final value = TextEditingController();
    final min = TextEditingController(text: '0');
    final max = TextEditingController();
    String mode = 'FIXED';
    bool enabled = true;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Commission rule'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _input(service, 'Service type'),
              _input(group, 'Commission group'),
              _input(state, 'State (optional)'),
              _input(lga, 'LGA (optional)'),
              DropdownButtonFormField<String>(
                value: mode,
                items: const [
                  DropdownMenuItem(value: 'FIXED', child: Text('Fixed kobo')),
                  DropdownMenuItem(
                      value: 'PERCENT', child: Text('Percent · basis points')),
                ],
                onChanged: (v) => setDialog(() => mode = v ?? 'FIXED'),
              ),
              _input(value,
                  mode == 'FIXED' ? 'Value (kobo)' : 'Value (basis points)',
                  numeric: true),
              _input(min, 'Minimum amount (kobo)', numeric: true),
              _input(max, 'Maximum amount (kobo)', numeric: true),
              SwitchListTile(
                value: enabled,
                onChanged: (v) => setDialog(() => enabled = v),
                title: const Text('Enabled'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await _api.post('rules', {
                    'service': service.text.trim(),
                    'group': group.text.trim(),
                    'state': state.text.trim(),
                    'lga': lga.text.trim(),
                    'mode': mode,
                    'value': int.parse(value.text),
                    'minAmountKobo': int.parse(min.text),
                    'maxAmountKobo':
                        max.text.trim().isEmpty ? null : int.parse(max.text),
                    'enabled': enabled,
                  });
                  if (context.mounted) Navigator.pop(context);
                  _load();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(this.context)
                        .showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
              child: const Text('Save rule'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settlement() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _commissionProfileId,
          decoration:
              const InputDecoration(labelText: 'Filter by business profile ID'),
          onSubmitted: (_) {
            setState(() => _commissionPage = 1);
            _load();
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              setState(() => _commissionPage = 1);
              _load();
            },
            icon: const Icon(Icons.filter_alt_outlined),
            label: const Text('Apply profile filter'),
          ),
        ),
        const Text(
            'Record a manual company-bank settlement. This records evidence only; it does not verify a provider or initiate a bank payment.',
            style: TextStyle(height: 1.45)),
        const SizedBox(height: 12),
        _metricGroup('COMMISSION TOTALS', _commissionTotals,
            _commissionTotals.keys.toList()),
        FilledButton.icon(
            onPressed: _settle,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Record settlement')),
        if (_rows.isEmpty) _empty('No commission statement rows returned.'),
        ..._rows.map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          final reference =
              (row['reference'] ?? row['publicReference'] ?? '').toString();
          return ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(
                  '${row['event'] ?? 'Commission'} · ${_moneyIfKobo('amountKobo', row['amountKobo'])}'),
              subtitle: Text(
                  '${reference.isEmpty ? 'Reference unavailable' : reference} · '
                  '${row['serviceType'] ?? ''} · ${row['transactionStatus'] ?? ''}'));
        }),
        _commissionPagination(),
      ]);
  Future<void> _settle() async {
    final profile = TextEditingController();
    final ids = TextEditingController();
    final reference = TextEditingController();
    final reason = TextEditingController();
    final date = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    final confirmation = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Manual settlement evidence'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _input(profile, 'Business profile ID'),
                _input(ids, 'Commission IDs (comma separated)'),
                _input(reference, 'Bank transfer reference'),
                _input(date, 'Paid date (YYYY-MM-DD)'),
                _input(reason, 'Settlement reason'),
                _input(confirmation, 'Type CONFIRM to acknowledge'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (confirmation.text.trim() != 'CONFIRM') {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Type CONFIRM to proceed.')),
                  );
                  return;
                }
                try {
                  await _api.post('commissions/settle', {
                    'profileId': profile.text.trim(),
                    'commissionIds': ids.text
                        .split(',')
                        .map((value) => value.trim())
                        .where((value) => value.isNotEmpty)
                        .toList(),
                    'reference': reference.text.trim(),
                    'paidAt': date.text.trim(),
                    'reason': reason.text.trim(),
                    'confirmation': true,
                  });
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  _load();
                } catch (error) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error.toString())),
                    );
                  }
                }
              },
              child: const Text('Record evidence'),
            ),
          ],
        ),
      );
    } finally {
      profile.dispose();
      ids.dispose();
      reference.dispose();
      reason.dispose();
      date.dispose();
      confirmation.dispose();
    }
  }

  Widget _reports() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
            'Download the actual CSV returned by the Business Network API. Web downloads use ServicePay’s existing browser export helper; Android and iOS save through the existing file picker.',
            style: TextStyle(height: 1.5)),
        const SizedBox(height: 14),
        FilledButton.icon(
            onPressed: _exporting ? null : _export,
            icon: const Icon(Icons.download_outlined),
            label: Text(_exporting
                ? 'Preparing report'
                : 'Download Business Network CSV')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _printing ? null : _printAgentReport,
          icon: const Icon(Icons.print_outlined),
          label:
              Text(_printing ? 'Preparing Agent report' : 'Print Agent report'),
        ),
        const SizedBox(height: 14),
        const Text(
            'Printing uses the API-provided Agent CSV in a browser print window. Native platforms report direct printing as unavailable; download the CSV there. No generated totals or client-side data are substituted.')
      ]);
  Widget _settingsView() {
    final categories = (_settings?['categories'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    return _SettingsEditor(
        api: _api,
        categories: categories,
        features: _settings?['features'] is Map
            ? Map<String, dynamic>.from(_settings!['features'] as Map)
            : const {});
  }

  Widget _auditView() => _audit.isEmpty
      ? _empty('No audit records returned.')
      : Column(children: [
          ..._audit.map((raw) {
            final row = Map<String, dynamic>.from(raw as Map);
            return Card(
                color: Colors.white,
                elevation: 0,
                child: ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: Text(row['action']?.toString() ??
                        row['event']?.toString() ??
                        'Network event'),
                    subtitle: Text(
                        '${row['actor'] ?? ''} · ${row['createdAt'] ?? ''}\\n${row['target'] ?? ''}'),
                    isThreeLine: true));
          }),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
                onPressed: _page > 1
                    ? () {
                        setState(() => _page--);
                        _load();
                      }
                    : null,
                child: const Text('Previous')),
            Text('Page $_page'),
            TextButton(
                onPressed: _auditTotal > _page * _audit.length
                    ? () {
                        setState(() => _page++);
                        _load();
                      }
                    : null,
                child: const Text('Next')),
          ]),
        ]);
  Widget _empty(String text) => Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Text(text, style: const TextStyle(color: Color(0xFF53645B))));
  Widget _skeleton() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            height: 95,
            decoration: BoxDecoration(
              color: const Color(0xFFE4ECE7),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(
            4,
            (_) => Container(
              height: 60,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE4ECE7),
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
        ],
      );
}
