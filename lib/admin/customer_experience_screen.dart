import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'customer_experience_api.dart';
import 'private_asset_download.dart';

class AdminCustomerExperienceScreen extends StatefulWidget {
  const AdminCustomerExperienceScreen({super.key, this.api});
  final CustomerExperienceApi? api;
  @override
  State<AdminCustomerExperienceScreen> createState() =>
      _AdminCustomerExperienceScreenState();
}

class _AdminCustomerExperienceScreenState
    extends State<AdminCustomerExperienceScreen>
    with SingleTickerProviderStateMixin {
  late final CustomerExperienceApi _api = widget.api ?? CustomerExperienceApi();
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final TextEditingController _search = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _min = TextEditingController();
  final TextEditingController _max = TextEditingController();
  final TextEditingController _releaseTitle = TextEditingController();
  final TextEditingController _releaseNotes = TextEditingController();
  final TextEditingController _latestVersion = TextEditingController();
  final TextEditingController _latestCode = TextEditingController();
  final TextEditingController _minimumCode = TextEditingController();
  final TextEditingController _storeUrl = TextEditingController();
  Map<String, dynamic>? _customer;
  Map<String, dynamic>? _customerSummary;
  Map<String, dynamic>? _reportData;
  DateTimeRange? _reportRange;
  DateTimeRange? _statementRange;
  String _searchError = '';
  String _pageError = '';
  List<Map<String, dynamic>> _customers = [];
  bool _booting = true;
  bool _searching = false;
  bool _crediting = false;
  bool _loadingSummary = false;
  bool _loadingReport = false;
  bool _exporting = false;
  bool _savingUpdate = false;
  bool _loadingUpdate = false;
  bool _canManage = false;
  bool _canCredit = false;
  bool _active = false;
  bool _forceUpdate = false;
  String? _requestKey;
  Map<String, dynamic>? _pendingCredit;
  static const String _pendingCreditPreference =
      'admin_customer_experience_pending_credit';

  @override
  void initState() {
    super.initState();
    _boot();
    _search.addListener(_searchChanged);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.removeListener(_searchChanged);
    _search.dispose();
    _amount.dispose();
    _description.dispose();
    _min.dispose();
    _max.dispose();
    _releaseTitle.dispose();
    _releaseNotes.dispose();
    _latestVersion.dispose();
    _latestCode.dispose();
    _minimumCode.dispose();
    _storeUrl.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _booting = true;
      _pageError = '';
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingRaw = prefs.getString(_pendingCreditPreference);
      if (pendingRaw != null) {
        try {
          final decoded = jsonDecode(pendingRaw);
          if (decoded is Map) {
            _pendingCredit = Map<String, dynamic>.from(decoded);
            _requestKey = _pendingCredit?['requestKey']?.toString();
            final minor =
                int.tryParse('${_pendingCredit?['amountMinor'] ?? ''}');
            if (minor != null) _amount.text = (minor / 100).toStringAsFixed(2);
            _description.text =
                _pendingCredit?['description']?.toString() ?? '';
          }
        } catch (_) {
          await prefs.remove(_pendingCreditPreference);
        }
      }
      final access = await _api.access();
      final value = access['success'] == true;
      if (!value) {
        throw const CustomerExperienceAdminException(
            'Access could not be confirmed.');
      }
      _canManage = access['canManage'] == true;
      _canCredit = access['canCreditCashback'] == true;
      await Future.wait([
        _loadCustomers(),
        _loadReport(),
        if (_canManage) _loadUpdate(),
      ]);
    } catch (error) {
      _pageError = error.toString();
    } finally {
      if (mounted) setState(() => _booting = false);
    }
  }

  void _searchChanged() {
    final value = _search.text.trim();
    if (value.length < 2) {
      if (mounted) {
        setState(() {
          _customers = [];
          _searchError = '';
        });
      }
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (mounted && _search.text.trim() == value) _loadCustomers(query: value);
    });
  }

  Future<void> _loadCustomers({String? query, int page = 1}) async {
    setState(() {
      _searching = true;
      _searchError = '';
    });
    try {
      final result =
          await _api.customers(query: query ?? _search.text, page: page);
      final raw = result['customers'];
      if (!mounted) return;
      setState(() {
        _customers = raw is List
            ? raw
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : [];
      });
    } catch (error) {
      if (mounted) setState(() => _searchError = error.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectCustomer(Map<String, dynamic> customer) async {
    final pendingCustomerId = _pendingCredit?['customerId']?.toString();
    if (pendingCustomerId != null &&
        pendingCustomerId != customer['_id']?.toString()) {
      _message(
          'Resolve the pending credit for the previously selected customer before switching customers.');
      return;
    }
    setState(() {
      _customer = customer;
      _customers = [];
      _search.text = customer['fullName']?.toString() ?? '';
      _customerSummary = null;
      _requestKey =
          _pendingCredit?['requestKey']?.toString() ?? _api.newIdempotencyKey();
    });
    await _loadCustomerSummary();
  }

  Future<void> _loadCustomerSummary() async {
    final id = _customer?['_id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() {
      _loadingSummary = true;
      _pageError = '';
    });
    try {
      final result = await _api.cashback(id);
      if (mounted) setState(() => _customerSummary = result);
    } catch (error) {
      if (mounted) setState(() => _pageError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  Future<void> _credit() async {
    if (_crediting || !_canCredit || _customer == null) return;
    int amountMinor;
    String description;
    String key;
    if (_pendingCredit != null) {
      if (_pendingCredit!['customerId']?.toString() !=
          _customer!['_id']?.toString()) {
        _message('The pending request belongs to another customer.');
        return;
      }
      amountMinor = int.parse('${_pendingCredit!['amountMinor']}');
      description = _pendingCredit!['description'].toString();
      key = _pendingCredit!['requestKey'].toString();
    } else {
      final parsedMinor = parseCashbackAmount(_amount.text);
      description = _description.text.trim();
      if (parsedMinor == null ||
          description.isEmpty || description.length > 500) {
        _message('Enter a valid amount in naira and a clear description.');
        return;
      }
      amountMinor = parsedMinor;
      key = _requestKey ??= _api.newIdempotencyKey();
      _pendingCredit = <String, dynamic>{
        'customerId': _customer!['_id'].toString(),
        'amountMinor': amountMinor,
        'description': description,
        'requestKey': key,
      };
    }
    setState(() {
      _crediting = true;
      _pageError = '';
    });
    try {
      await persistCashbackRequest(_pendingCreditPreference, _pendingCredit!);
      await _api.credit(
        customerId: _customer!['_id'].toString(),
        amountMinor: amountMinor,
        description: description,
        requestKey: key,
      );
      if (!mounted) return;
      setState(() {
        _amount.clear();
        _description.clear();
        _pendingCredit = null;
        _requestKey = _api.newIdempotencyKey();
      });
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.remove(_pendingCreditPreference);
      } catch (_) {
        // If local cleanup fails, the same idempotent request remains safe to
        // reconcile next time this screen is opened.
      }
      _message('Cashback credit confirmed.');
      await _loadCustomerSummary();
    } catch (error) {
      if (mounted) {
        setState(() => _pageError =
            '$error\nThe same request key is retained. Retry only after checking whether the previous request completed.');
      }
    } finally {
      if (mounted) setState(() => _crediting = false);
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      _loadingReport = true;
      _pageError = '';
    });
    try {
      final result = await _api.report(
        customerId: _customer?['_id']?.toString() ?? '',
        start: _dateKeyOrEmpty(_reportRange?.start),
        end: _dateKeyOrEmpty(_reportRange?.end),
        minMinor: _toMinorFilter(_min.text),
        maxMinor: _toMinorFilter(_max.text),
      );
      if (mounted) setState(() => _reportData = result);
    } catch (error) {
      if (mounted) setState(() => _pageError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingReport = false);
    }
  }

  String _toMinorFilter(String value) {
    final number = num.tryParse(value.trim().replaceAll(',', ''));
    return number == null ? '' : (number * 100).round().toString();
  }

  Future<void> _pickRange({required bool statement}) async {
    final current = statement ? _statementRange : _reportRange;
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: current ??
          DateTimeRange(
              start: now.subtract(const Duration(days: 29)), end: now),
    );
    if (selected == null) return;
    setState(() {
      if (statement) {
        _statementRange = selected;
      } else {
        _reportRange = selected;
      }
    });
  }

  Future<void> _exportCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final csv = await _api.reportCsv(
        customerId: _customer?['_id']?.toString() ?? '',
        start: _dateKeyOrEmpty(_reportRange?.start),
        end: _dateKeyOrEmpty(_reportRange?.end),
        minMinor: _toMinorFilter(_min.text),
        maxMinor: _toMinorFilter(_max.text),
      );
      if (kIsWeb) {
        await savePrivateAsset(
          Uint8List.fromList(utf8.encode(csv)),
          'servicepay-cashback-report.csv',
          'text/csv',
        );
      } else {
        final data =
            Uri.dataFromString(csv, mimeType: 'text/csv', encoding: utf8);
        if (!await launchUrl(data, webOnlyWindowName: '_blank')) {
          throw const CustomerExperienceAdminException(
              'The CSV export could not be opened on this device.');
        }
      }
      _message('Cashback report exported.');
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _downloadStatement() async {
    if (_customer == null || _statementRange == null) {
      _message('Select a customer and statement date range first.');
      return;
    }
    try {
      final Uint8List bytes = await _api.statement(
        customerId: _customer!['_id'].toString(),
        start: _dateKey(_statementRange!.start),
        end: _dateKey(_statementRange!.end),
      );
      if (kIsWeb) {
        await savePrivateAsset(
          bytes,
          'servicepay-customer-statement-${_customer!['_id']}.pdf',
          'application/pdf',
        );
      } else {
        final uri = Uri.dataFromBytes(bytes, mimeType: 'application/pdf');
        if (!await launchUrl(uri, webOnlyWindowName: '_blank')) {
          throw const CustomerExperienceAdminException(
              'The PDF could not be opened on this device.');
        }
      }
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _loadUpdate() async {
    setState(() {
      _loadingUpdate = true;
    });
    try {
      final result = await _api.appUpdate();
      final raw = result['update'];
      if (raw is Map && mounted) {
        final update = Map<String, dynamic>.from(raw);
        _releaseTitle.text = update['releaseTitle']?.toString() ?? '';
        _releaseNotes.text = update['releaseNotes']?.toString() ?? '';
        _latestVersion.text = update['latestVersion']?.toString() ?? '';
        _latestCode.text = update['latestVersionCode']?.toString() ?? '';
        _minimumCode.text = update['minimumVersionCode']?.toString() ?? '';
        _storeUrl.text = update['playStoreUrl']?.toString() ?? '';
        setState(() {
          _active = update['active'] == true;
          _forceUpdate = update['forceUpdate'] == true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _pageError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingUpdate = false);
    }
  }

  Future<void> _saveUpdate() async {
    if (_savingUpdate || !_canManage) return;
    final latestCode = int.tryParse(_latestCode.text.trim());
    final minimumCode = int.tryParse(_minimumCode.text.trim());
    if (latestCode == null ||
        minimumCode == null ||
        latestCode < 0 ||
        minimumCode < 0 ||
        _latestVersion.text.trim().isEmpty) {
      _message('Enter valid version values and integer version codes.');
      return;
    }
    setState(() => _savingUpdate = true);
    try {
      await _api.saveAppUpdate({
        'latestVersion': _latestVersion.text.trim(),
        'latestVersionCode': latestCode,
        'minimumVersionCode': minimumCode,
        'releaseTitle': _releaseTitle.text.trim(),
        'releaseNotes': _releaseNotes.text.trim(),
        'active': _active,
        'forceUpdate': _forceUpdate,
        'playStoreUrl': _storeUrl.text.trim(),
      });
      _message('App update settings saved.');
      await _loadUpdate();
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _savingUpdate = false);
    }
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  String _dateKeyOrEmpty(DateTime? value) =>
      value == null ? '' : _dateKey(value);
  String _money(dynamic minor) {
    final value = minor is num ? minor.toInt() : int.tryParse('$minor') ?? 0;
    final whole = (value.abs() ~/ 100)
        .toString()
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '${value < 0 ? '-' : ''}₦$whole.${(value.abs() % 100).toString().padLeft(2, '0')}';
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Customer Experience'),
          bottom: TabBar(controller: _tabs, isScrollable: true, tabs: const [
            Tab(text: 'Cashback customers'),
            Tab(text: 'Reports & statements'),
            Tab(text: 'App update'),
          ]),
        ),
        body: _booting
            ? const Center(child: CircularProgressIndicator())
            : _pageError.isNotEmpty
                ? _errorView()
                : TabBarView(controller: _tabs, children: [
                    _customerTab(),
                    _reportsTab(),
                    _updateTab(),
                  ]),
      );

  Widget _errorView() => Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined,
              size: 42, color: Colors.redAccent),
          const SizedBox(height: 10),
          Text(_pageError, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: _boot,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry')),
        ]),
      ));

  Widget _customerTab() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        _sectionTitle('Find a customer',
            'Search by name, email or phone. Select one before viewing or crediting cashback.'),
        if (_pendingCredit != null && _customer == null)
          Card(
            color: const Color(0xFFFFF8E7),
            child: ListTile(
              leading: const Icon(Icons.pending_actions_outlined),
              title: const Text('A cashback request is unresolved'),
              subtitle: Text(
                'Select customer ${_pendingCredit!['customerId']} to retry the exact same request safely.',
              ),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Customer search',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : null,
            )),
        if (_searchError.isNotEmpty)
          _inlineError(_searchError, () => _loadCustomers()),
        if (_customers.isNotEmpty)
          Card(
              child: Column(
                  children: _customers
                      .map((customer) => ListTile(
                            leading: CircleAvatar(
                                child: Text(_initials(
                                    customer['fullName']?.toString() ??
                                        'Customer'))),
                            title: Text(
                                customer['fullName']?.toString() ?? 'Customer'),
                            subtitle: Text([
                              customer['email'],
                              customer['phone']
                            ]
                                .where((v) => v != null && '$v'.isNotEmpty)
                                .join(' · ')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _selectCustomer(customer),
                          ))
                      .toList())),
        if (_search.text.trim().length >= 2 &&
            !_searching &&
            _customers.isEmpty &&
            _searchError.isEmpty)
          const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No matching customers found.')),
        if (_customer != null) ...[
          const SizedBox(height: 12),
          _sectionTitle('Selected customer', ''),
          Card(
              child: ListTile(
            leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5EC),
                child: Icon(Icons.person_outline, color: Color(0xFF087A45))),
            title: Text(_customer!['fullName']?.toString() ?? 'Customer'),
            subtitle: Text(_customer!['email']?.toString() ??
                _customer!['phone']?.toString() ??
                _customer!['_id'].toString()),
            trailing: IconButton(
                tooltip: 'Clear selected customer',
                onPressed: () => setState(() {
                      _customer = null;
                      _customerSummary = null;
                    }),
                icon: const Icon(Icons.close)),
          )),
          if (_loadingSummary) const LinearProgressIndicator(),
          if (_customerSummary != null) _summaryCard(_customerSummary!),
          if (_canCredit) ...[
            const SizedBox(height: 16),
            _sectionTitle('Manual cashback credit',
                'A request key stays fixed after uncertain outcomes. No automatic retry is performed.'),
            const SizedBox(height: 10),
            TextField(
                controller: _amount,
                readOnly: _pendingCredit != null,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Amount (₦)', prefixText: '₦ ')),
            const SizedBox(height: 10),
            TextField(
                controller: _description,
                readOnly: _pendingCredit != null,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Credit description')),
            const SizedBox(height: 10),
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E7),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(
                    'Idempotency key: ${_requestKey ?? 'created on submit'}',
                    style: const TextStyle(fontSize: 11))),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _crediting || _customer == null ? null : _credit,
              icon: _crediting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add_card_outlined),
              label: Text(_crediting
                  ? 'Submitting once…'
                  : _pendingCredit != null
                      ? 'Retry same credit request'
                      : 'Credit cashback'),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                  'This account can review cashback, but cannot issue credits.'),
            ),
          if (!_canManage && !_canCredit)
            const Text('Server permissions are read-only for this account.'),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: _EmptyState(
                icon: Icons.person_search_outlined,
                title: 'No customer selected',
                detail: 'Search above to inspect cashback history.'),
          ),
      ]);

  Widget _summaryCard(Map<String, dynamic> data) {
    final row = data['summary'] is Map
        ? Map<String, dynamic>.from(data['summary'])
        : data;
    final history = data['history'] is List
        ? (data['history'] as List).whereType<Map>().toList()
        : <Map>[];
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Cashback balance',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(_money(row['balanceMinor'] ?? row['totalMinor']),
                style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF087A45))),
            const SizedBox(height: 12),
            Wrap(spacing: 20, runSpacing: 8, children: [
              Text('This month  ${_money(row['monthMinor'])}'),
              Text('This year  ${_money(row['yearMinor'])}'),
            ]),
            const Divider(height: 24),
            const Text('Recent cashback history',
                style: TextStyle(fontWeight: FontWeight.w800)),
            if (history.isEmpty)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('No cashback history found.')),
            ...history.take(8).map((entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      entry['description']?.toString() ?? 'Cashback entry'),
                  subtitle: Text(
                      '${entry['createdAt'] ?? 'Date unavailable'} · ${entry['reference'] ?? 'No reference'} · ${entry['status'] ?? 'Unknown'}'),
                  trailing: Text(_money(entry['amountMinor']),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                )),
          ])),
    );
  }

  Widget _reportsTab() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        _sectionTitle('Cashback report',
            'Filter server-side by date, customer and amount; totals are supplied by ServicePay.'),
        const SizedBox(height: 12),
        Wrap(spacing: 9, runSpacing: 9, children: [
          OutlinedButton.icon(
              onPressed: () => _pickRange(statement: false),
              icon: const Icon(Icons.date_range),
              label: Text(_reportRange == null
                  ? 'Date range'
                  : '${_dateKey(_reportRange!.start)} — ${_dateKey(_reportRange!.end)}')),
          OutlinedButton.icon(
              onPressed: _customer == null ? null : () => _tabs.animateTo(0),
              icon: const Icon(Icons.person_search),
              label: Text(_customer == null
                  ? 'Customer not selected'
                  : (_customer!['fullName']?.toString() ??
                      'Selected customer'))),
        ]),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth < 560
              ? constraints.maxWidth
              : (constraints.maxWidth - 10) / 2;
          return Wrap(spacing: 10, children: [
            SizedBox(
                width: width,
                child: TextField(
                    controller: _min,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Minimum amount (₦)'))),
            SizedBox(
                width: width,
                child: TextField(
                    controller: _max,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Maximum amount (₦)'))),
          ]);
        }),
        const SizedBox(height: 10),
        Wrap(spacing: 10, children: [
          FilledButton.icon(
              onPressed: _loadingReport ? null : _loadReport,
              icon: _loadingReport
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.filter_alt_outlined),
              label: const Text('Apply filters')),
          OutlinedButton.icon(
              onPressed: _exporting ? null : _exportCsv,
              icon: const Icon(Icons.download_outlined),
              label: Text(_exporting ? 'Exporting…' : 'Download CSV')),
        ]),
        if (_reportData != null) ...[
          const SizedBox(height: 14),
          _reportSummary(_reportData!),
          _reportHistory(_reportData!),
        ] else if (!_loadingReport)
          const _EmptyState(
              icon: Icons.query_stats_outlined,
              title: 'No report loaded',
              detail:
                  'Apply filters to load authoritative cashback totals and activity.'),
        const Divider(height: 34),
        _sectionTitle('Customer statement PDF',
            'Select a customer and date range to ask the server for a statement.'),
        const SizedBox(height: 10),
        OutlinedButton.icon(
            onPressed: () => _tabs.animateTo(0),
            icon: const Icon(Icons.person_search),
            label: Text(_customer == null
                ? 'Select customer on Cashback customers tab'
                : _customer!['fullName']?.toString() ?? 'Customer selected')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: () => _pickRange(statement: true),
            icon: const Icon(Icons.calendar_month),
            label: Text(_statementRange == null
                ? 'Choose statement dates'
                : '${_dateKey(_statementRange!.start)} — ${_dateKey(_statementRange!.end)}')),
        const SizedBox(height: 8),
        FilledButton.icon(
            onPressed: _customer == null || _statementRange == null
                ? null
                : _downloadStatement,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Generate customer PDF')),
      ]);

  Widget _reportSummary(Map<String, dynamic> data) {
    final values = [
      ('Total credited', _money(data['totalMinor'])),
      ('This month', _money(data['monthMinor'])),
      ('This year', _money(data['yearMinor'])),
      ('Entries', '${data['total'] ?? 0}'),
    ];
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(15),
            child: Wrap(
              spacing: 24,
              runSpacing: 16,
              children: values
                  .map((item) => SizedBox(
                      width: 140,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.$1,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54)),
                            const SizedBox(height: 4),
                            Text(item.$2,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 17)),
                          ])))
                  .toList(),
            )));
  }

  Widget _reportHistory(Map<String, dynamic> data) {
    final history = data['history'] is List
        ? (data['history'] as List).whereType<Map>().toList()
        : <Map>[];
    if (history.isEmpty) {
      return const _EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No matching cashback',
          detail: 'Try adjusting the selected filters.');
    }
    return Card(
        margin: const EdgeInsets.only(top: 10),
        child: Column(
            children: history
                .map((entry) => ListTile(
                      title: Text(entry['description']?.toString() ??
                          'Cashback activity'),
                      subtitle: Text(
                          '${entry['customerName'] ?? entry['fullName'] ?? entry['customerId'] ?? 'Customer'} · ${entry['createdAt'] ?? ''} · ${entry['reference'] ?? ''}'),
                      trailing: Text(_money(entry['amountMinor']),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ))
                .toList()));
  }

  Widget _updateTab() {
    if (!_canManage) {
      return const _EmptyState(
          icon: Icons.lock_outline,
          title: 'Management access required',
          detail:
              'The server has not granted app update management permissions.');
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      _sectionTitle('Android app update',
          'Update rules are supplied by the server; inactive is the safe initial state.'),
      if (_loadingUpdate) const LinearProgressIndicator(),
      const SizedBox(height: 10),
      TextField(
          controller: _latestVersion,
          decoration: const InputDecoration(labelText: 'Latest version')),
      const SizedBox(height: 10),
      TextField(
          controller: _latestCode,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Latest version code')),
      const SizedBox(height: 10),
      TextField(
          controller: _minimumCode,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Minimum version code')),
      const SizedBox(height: 10),
      TextField(
          controller: _releaseTitle,
          decoration: const InputDecoration(labelText: 'Release title')),
      const SizedBox(height: 10),
      TextField(
          controller: _releaseNotes,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Release notes')),
      const SizedBox(height: 10),
      TextField(
          controller: _storeUrl,
          decoration: const InputDecoration(
              labelText: 'Play Store URL (server-normalized)')),
      SwitchListTile(
          value: _active,
          onChanged: (value) => setState(() => _active = value),
          title: const Text('Active'),
          subtitle: const Text('Inactive by default')),
      SwitchListTile(
          value: _forceUpdate,
          onChanged: (value) => setState(() => _forceUpdate = value),
          title: const Text('Force update'),
          subtitle: const Text(
              'Customers below minimum version cannot dismiss the update prompt')),
      FilledButton.icon(
          onPressed: _savingUpdate ? null : _saveUpdate,
          icon: _savingUpdate
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined),
          label: Text(_savingUpdate ? 'Saving…' : 'Save update settings')),
    ]);
  }

  Widget _sectionTitle(String title, String detail) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(detail,
              style: TextStyle(color: Colors.grey.shade700, height: 1.35))
        ],
      ]);

  Widget _inlineError(String error, VoidCallback retry) => Card(
      color: const Color(0xFFFFF2EF),
      child: ListTile(
        title: const Text('Request failed',
            style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(error),
        trailing: IconButton(onPressed: retry, icon: const Icon(Icons.refresh)),
      ));

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    final text = parts.map((part) => part[0]).join().toUpperCase();
    return text.isEmpty ? '?' : text;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant)),
        child: Column(children: [
          Icon(icon, size: 34, color: const Color(0xFF087A45)),
          const SizedBox(height: 9),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700)),
        ]),
      );
}
