part of 'business_network_screen.dart';

class _BusinessNetworkPremiumPanel extends StatefulWidget {
  const _BusinessNetworkPremiumPanel({
    required this.api,
    required this.section,
    required this.onOpenCommissionRules,
  });

  final BusinessNetworkAdminApi api;
  final String section;
  final VoidCallback onOpenCommissionRules;

  @override
  State<_BusinessNetworkPremiumPanel> createState() =>
      _BusinessNetworkPremiumPanelState();
}

class _BusinessNetworkPremiumPanelState
    extends State<_BusinessNetworkPremiumPanel> {
  AdminReferralsApi? _referrals;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _period = 'month';
  Map<String, dynamic> _premium = {};
  List<dynamic> _rules = [];
  List<dynamic> _performance = [];
  Map<String, dynamic> _voucherReport = {};
  List<dynamic> _loyaltyRows = [];
  int _loyaltyPage = 1;
  int _loyaltyTotal = 0;
  Map<String, dynamic> _referralSummary = {};
  List<dynamic> _referralsRows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _BusinessNetworkPremiumPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) _load();
  }

  @override
  void dispose() {
    _referrals?.close();
    super.dispose();
  }

  String? get _performanceKind => widget.section == 'Agent Performance'
      ? 'AGENT'
      : widget.section == 'Merchant Performance'
          ? 'MERCHANT'
          : null;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final premiumFuture = widget.api.get('premium');
      final requests = <Future<dynamic>>[premiumFuture];
      if (widget.section == 'Agent Pricing' ||
          widget.section == 'Merchant Pricing') {
        requests.add(widget.api.get('rules'));
      }
      if (_performanceKind != null) {
        requests.add(widget.api.get('performance', query: {
          'kind': _performanceKind!,
          'period': _period,
        }));
      }
      if (widget.section == 'Referral Management') {
        final referrals =
            _referrals ??= AdminReferralsApi(baseUrl: widget.api.baseUrl);
        requests.add(referrals.summary());
        requests.add(referrals.search(page: 1, limit: 20));
      }
      if (widget.section == 'Recharge Voucher Inventory' ||
          widget.section == 'Data Voucher Inventory') {
        requests.add(widget.api.get('vouchers'));
      }
      if (widget.section == 'Loyalty & Goals') {
        requests.add(widget.api.get('loyalty', query: {
          'page': '$_loyaltyPage',
        }));
      }
      final results = await Future.wait<dynamic>(requests);
      if (!mounted) return;
      var index = 0;
      final premium = Map<String, dynamic>.from(results[index++] as Map);
      List<dynamic> rules = const [];
      List<dynamic> performance = const [];
      Map<String, dynamic> referralSummary = const {};
      List<dynamic> referralRows = const [];
      Map<String, dynamic> voucherReport = const {};
      List<dynamic> loyaltyRows = const [];
      var loyaltyTotal = 0;
      if (widget.section == 'Agent Pricing' ||
          widget.section == 'Merchant Pricing') {
        rules = (results[index++] as Map)['items'] as List? ?? [];
      }
      if (_performanceKind != null) {
        performance = (results[index++] as Map)['items'] as List? ?? [];
      }
      if (widget.section == 'Referral Management') {
        referralSummary = results[index++] as Map<String, dynamic>;
        final listing = results[index++] as Map<String, dynamic>;
        referralRows = listing['rows'] as List? ?? [];
      }
      if (widget.section == 'Recharge Voucher Inventory' ||
          widget.section == 'Data Voucher Inventory') {
        voucherReport = Map<String, dynamic>.from(results[index++] as Map);
      }
      if (widget.section == 'Loyalty & Goals') {
        final report = results[index++] as Map;
        loyaltyRows = report['items'] as List? ?? [];
        loyaltyTotal =
            report['total'] is num ? (report['total'] as num).toInt() : 0;
      }
      setState(() {
        _premium = premium;
        _rules = rules;
        _performance = performance;
        _referralSummary = referralSummary;
        _referralsRows = referralRows;
        _voucherReport = voucherReport;
        _loyaltyRows = loyaltyRows;
        _loyaltyTotal = loyaltyTotal;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Map<String, dynamic> get _capabilities => _premium['capabilityReasons'] is Map
      ? Map<String, dynamic>.from(_premium['capabilityReasons'] as Map)
      : const {};

  Map<String, dynamic> get _features => _premium['features'] is Map
      ? Map<String, dynamic>.from(_premium['features'] as Map)
      : const {};

  Map<String, dynamic> get _configuration => {
        'businessServices': _premium['businessServices'] is Map
            ? Map<String, dynamic>.from(_premium['businessServices'] as Map)
            : <String, dynamic>{},
        'levels': _premium['levels'] as List? ?? const [],
        'loyalty': _premium['loyalty'] is Map
            ? Map<String, dynamic>.from(_premium['loyalty'] as Map)
            : <String, dynamic>{},
        'goals': _premium['goals'] as List? ?? const [],
        'campaigns': _premium['campaigns'] as List? ?? const [],
      };

  Future<String?> _reasonDialog(String title) async {
    var reason = '';
    String? validation;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) => setDialog(() {
                  reason = value;
                  validation = null;
                }),
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Reason for the audited change',
                ),
              ),
              if (validation != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(validation!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final value = reason.trim();
                if (value.isEmpty) {
                  setDialog(
                      () => validation = 'Enter a reason for this change.');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(Map<String, dynamic> configuration,
      {required String title}) async {
    final reason = await _reasonDialog(title);
    if (reason == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await widget.api.put('premium', {
        'configuration': configuration,
        'revision': _premium['revision'] ?? 0,
        'reason': reason,
      });
      if (!mounted) return;
      setState(() => _premium = {
            ..._premium,
            ...Map<String, dynamic>.from(data as Map),
          });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Premium settings saved and audited.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Map<String, dynamic>> _servicesFor(String kind) {
    final catalogue = _premium['serviceCatalogue'];
    final rows = catalogue is Map ? catalogue[kind] : null;
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Widget _card(String title, Widget child) => Card(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFDCE7DF)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      );

  Widget _unsupported(String label, String capability) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.lock_outline),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${_features.containsKey(capability) ? (_features[capability] == true ? 'Reported enabled' : 'Disabled') : 'Unavailable'} · ${_capabilities[capability]?.toString() ?? 'No verified provider capability is configured.'}',
        ),
      );

  Widget _pricing() {
    final kind = widget.section == 'Agent Pricing' ? 'AGENT' : 'MERCHANT';
    final label = kind == 'AGENT' ? 'Agent' : 'Merchant';
    final applicable = _rules
        .whereType<Map>()
        .map((rule) => Map<String, dynamic>.from(rule))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          'Purchase pricing is not configurable here',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _capabilities['specialPurchasePricing']?.toString() ??
                    'Existing secure ServicePay purchase quotes remain authoritative.',
              ),
              const SizedBox(height: 8),
              const Text(
                'These rows are commission rules only. They do not discount customer purchase prices or override the existing bill-payment quote.',
              ),
              TextButton.icon(
                onPressed: widget.onOpenCommissionRules,
                icon: const Icon(Icons.tune),
                label: const Text('Open commission rules'),
              ),
            ],
          ),
        ),
        _card(
          '$label commission rules',
          applicable.isEmpty
              ? const Text('No commission rules were returned by the API.')
              : Column(
                  children: applicable.map((rule) {
                    final enabled = rule['enabled'] == true;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '${rule['service'] ?? 'Service'} · ${rule['mode'] ?? ''} ${rule['value'] ?? ''}'),
                      subtitle: Text(
                          '${rule['group'] ?? 'All groups'} · ${rule['state'] ?? 'All states'} ${rule['lga'] ?? ''}'),
                      trailing: Text(enabled ? 'Enabled' : 'Disabled'),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Future<void> _saveServices(String kind, Set<String> values) async {
    await _save(
      {
        'businessServices': {kind: values.toList()},
      },
      title: 'Save $kind service preferences',
    );
  }

  Widget _serviceConfiguration(String kind) {
    final config = _configuration['businessServices'] as Map;
    final selected = (config[kind] as List? ?? const [])
        .map((code) => code.toString())
        .toSet();
    final rows = _servicesFor(kind);
    return _card(
      '$kind service preferences',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Head Office controls preference visibility for each business type. A listed preference does not grant a purchase or commission capability.',
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('No service catalogue rows were returned.'),
            ),
          ...rows.map((row) {
            final code = row['code']?.toString() ?? '';
            final available = row['available'] == true;
            final checked = selected.contains(code);
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: checked,
              title: Text(row['label']?.toString() ?? code),
              subtitle: Text(
                !available
                    ? row['reason']?.toString() ??
                        'Globally unavailable in the existing ServicePay catalogue.'
                    : row['processable'] == true
                        ? 'Processable own-wallet bill service'
                        : 'Business interest only · no processing or commission',
              ),
              onChanged: _saving || (!available && !checked)
                  ? null
                  : (value) async {
                      final next = Set<String>.from(selected);
                      if (value == true) {
                        next.add(code);
                      } else {
                        next.remove(code);
                      }
                      await _saveServices(kind, next);
                    },
            );
          }),
        ],
      ),
    );
  }

  Future<void> _editLevels() async {
    final original = (_configuration['levels'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final values =
        original.map((row) => Map<String, dynamic>.from(row)).toList();
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('Agent levels'),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: values.map((level) {
                    final index = values.indexOf(level);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(level['code'].toString(),
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enabled'),
                          value: level['enabled'] == true,
                          onChanged: (value) => setDialog(() {
                            level['enabled'] = value;
                          }),
                        ),
                        TextFormField(
                          initialValue: level['label']?.toString() ?? '',
                          decoration: const InputDecoration(labelText: 'Label'),
                          onChanged: (value) => level['label'] = value,
                          validator: (value) => value?.trim().isEmpty == true
                              ? 'Enter a level label'
                              : null,
                        ),
                        TextFormField(
                          initialValue: '${level['minTransactions'] ?? 0}',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Minimum verified transactions'),
                          onChanged: (value) => level['minTransactions'] =
                              int.tryParse(value) ?? -1,
                          validator: (value) =>
                              int.tryParse(value ?? '') == null ||
                                      int.parse(value!) < 0
                                  ? 'Enter a nonnegative whole number'
                                  : null,
                        ),
                        TextFormField(
                          initialValue: '${level['minVolumeKobo'] ?? 0}',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Minimum verified volume (kobo)'),
                          onChanged: (value) => level['minVolumeKobo'] =
                              int.tryParse(value) ?? -1,
                          validator: (value) =>
                              int.tryParse(value ?? '') == null ||
                                      int.parse(value!) < 0
                                  ? 'Enter a nonnegative whole number'
                                  : null,
                        ),
                        TextFormField(
                          initialValue:
                              level['commissionGroup']?.toString() ?? '',
                          decoration: const InputDecoration(
                              labelText: 'Commission group'),
                          onChanged: (value) =>
                              level['commissionGroup'] = value,
                        ),
                        if (index != values.length - 1)
                          const Divider(height: 24),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                final enabledInvalid = values.any((row) =>
                    row['enabled'] == true &&
                    (row['minTransactions'] == 0 && row['minVolumeKobo'] == 0));
                if (enabledInvalid) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Each enabled level requires a positive qualification target.')),
                  );
                  return;
                }
                Navigator.pop(dialogContext);
                await _save({'levels': values},
                    title: 'Save Agent level requirements');
              },
              child: const Text('Save levels'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editLoyalty() async {
    final current = Map<String, dynamic>.from(
      _configuration['loyalty'] as Map? ?? const {},
    );
    final eligible = (current['eligibleServices'] as List? ?? const [])
        .map((code) => code.toString())
        .toSet();
    var points = '${current['pointsPerTransaction'] ?? 0}';
    var cap = '${current['maxPointsPerCustomer'] ?? 0}';
    var expiry = '${current['expiryDays'] ?? 30}';
    var enabled = current['enabled'] == true;
    String? error;
    final rows = [
      ..._servicesFor('AGENT'),
      ..._servicesFor('MERCHANT'),
    ]
        .where((row) => row['processable'] == true)
        .fold<Map<String, Map<String, dynamic>>>({}, (map, row) {
          map[row['code'].toString()] = row;
          return map;
        })
        .values
        .toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Non-cash loyalty settings'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable loyalty accrual'),
                  subtitle: const Text(
                      'Backend eligibility, source transaction verification and audit remain authoritative.'),
                  value: enabled,
                  onChanged: (value) => setDialog(() => enabled = value),
                ),
                TextField(
                  onChanged: (value) => points = value,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Points per eligible transaction'),
                ),
                TextField(
                  onChanged: (value) => cap = value,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Maximum points per customer'),
                ),
                TextField(
                  onChanged: (value) => expiry = value,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Expiry days'),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Eligible processable bill services'),
                  ),
                ),
                ...rows.map((row) {
                  final code = row['code'].toString();
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(row['label']?.toString() ?? code),
                    value: eligible.contains(code),
                    onChanged: (value) => setDialog(() {
                      if (value == true) {
                        eligible.add(code);
                      } else {
                        eligible.remove(code);
                      }
                    }),
                  );
                }),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                const Text(
                  'No effective date is editable. No cash redemption, wallet credit or payout is created.',
                  style: TextStyle(fontSize: 12),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final p = int.tryParse(points);
                final max = int.tryParse(cap);
                final days = int.tryParse(expiry);
                if (p == null ||
                    max == null ||
                    days == null ||
                    p < 0 ||
                    max < 0 ||
                    days < 1 ||
                    (enabled && (p < 1 || max < p || eligible.isEmpty))) {
                  setDialog(() => error =
                      'Enter whole-number limits and, when enabled, positive points, a sufficient cap and eligible services.');
                  return;
                }
                Navigator.pop(dialogContext);
                await _save({
                  'loyalty': {
                    'enabled': enabled,
                    'pointsPerTransaction': p,
                    'maxPointsPerCustomer': max,
                    'expiryDays': days,
                    'eligibleServices': eligible.toList(),
                  }
                }, title: 'Save loyalty configuration');
              },
              child: const Text('Save loyalty'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addGoal() async {
    var title = '';
    var transactions = '1';
    var volume = '0';
    var kind = 'AGENT';
    var period = 'month';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Add business goal'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                onChanged: (value) => title = value,
                decoration: const InputDecoration(labelText: 'Goal title')),
            DropdownButtonFormField<String>(
              value: kind,
              items: const [
                DropdownMenuItem(value: 'AGENT', child: Text('Agent')),
                DropdownMenuItem(value: 'MERCHANT', child: Text('Merchant')),
              ],
              onChanged: (value) => setDialog(() => kind = value ?? kind),
            ),
            DropdownButtonFormField<String>(
              value: period,
              items: const [
                DropdownMenuItem(value: 'day', child: Text('Daily')),
                DropdownMenuItem(value: 'week', child: Text('Weekly')),
                DropdownMenuItem(value: 'month', child: Text('Monthly')),
              ],
              onChanged: (value) => setDialog(() => period = value ?? period),
            ),
            TextField(
              onChanged: (value) => transactions = value,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Target transactions'),
            ),
            TextField(
              onChanged: (value) => volume = value,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Target purchase volume (kobo)'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final count = int.tryParse(transactions);
                final amount = int.tryParse(volume);
                if (title.trim().isEmpty ||
                    count == null ||
                    amount == null ||
                    count < 0 ||
                    amount < 0 ||
                    (count == 0 && amount == 0)) {
                  return;
                }
                Navigator.pop(dialogContext, {
                  'title': title.trim(),
                  'kind': kind,
                  'period': period,
                  'targetTransactions': count,
                  'targetVolumeKobo': amount,
                });
              },
              child: const Text('Add goal'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final goals = (_configuration['goals'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList()
      ..add(result);
    await _save({'goals': goals}, title: 'Save business goals');
  }

  Future<void> _addCampaign() async {
    var title = '';
    var description = '';
    var kind = 'AGENT';
    var enabled = true;
    DateTime startsAt = DateTime.now();
    DateTime endsAt = DateTime.now().add(const Duration(days: 14));
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Add campaign'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  onChanged: (value) => setDialog(() => title = value),
                  decoration: const InputDecoration(labelText: 'Title')),
              TextField(
                onChanged: (value) => setDialog(() => description = value),
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              DropdownButtonFormField<String>(
                value: kind,
                items: const [
                  DropdownMenuItem(value: 'AGENT', child: Text('Agent')),
                  DropdownMenuItem(value: 'MERCHANT', child: Text('Merchant')),
                ],
                onChanged: (value) => setDialog(() => kind = value ?? kind),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Starts'),
                subtitle: Text(startsAt.toLocal().toString()),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: startsAt,
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (date != null) setDialog(() => startsAt = date);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ends'),
                subtitle: Text(endsAt.toLocal().toString()),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: endsAt,
                    firstDate: startsAt.add(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (date != null) setDialog(() => endsAt = date);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Published'),
                value: enabled,
                onChanged: (value) => setDialog(() => enabled = value),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: title.trim().isNotEmpty &&
                      description.trim().isNotEmpty &&
                      endsAt.isAfter(startsAt)
                  ? () => Navigator.pop(dialogContext, {
                        'title': title.trim(),
                        'description': description.trim(),
                        'kind': kind,
                        'startsAt': startsAt.toUtc().toIso8601String(),
                        'endsAt': endsAt.toUtc().toIso8601String(),
                        'enabled': enabled,
                      })
                  : null,
              child: const Text('Add campaign'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final campaigns = (_configuration['campaigns'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList()
      ..add(result);
    await _save({'campaigns': campaigns}, title: 'Save business campaigns');
  }

  Widget _loyaltyAndGoals() {
    final loyalty = _configuration['loyalty'] as Map;
    final levels = (_configuration['levels'] as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final goals = (_configuration['goals'] as List? ?? const []);
    final campaigns = (_configuration['campaigns'] as List? ?? const []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          'Agent level requirements',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Qualification is based on verified existing transactions. Assignment is a separate Head Office action and never automatic.',
              ),
              ...levels.map((level) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${level['label'] ?? level['code']} · ${level['enabled'] == true ? 'Enabled' : 'Disabled'}'),
                    subtitle: Text(
                        '${level['minTransactions']} transactions · ${_moneyIfKobo('minVolumeKobo', level['minVolumeKobo'])} · ${level['commissionGroup']}'),
                  )),
              OutlinedButton.icon(
                onPressed: _saving ? null : _editLevels,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit level requirements'),
              ),
            ],
          ),
        ),
        _card(
          'Customer loyalty configuration',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Status: ${loyalty['enabled'] == true ? 'Enabled' : 'Disabled'} · ${loyalty['pointsPerTransaction'] ?? 0} points per transaction · cap ${loyalty['maxPointsPerCustomer'] ?? 0} · ${loyalty['expiryDays'] ?? 30} days'),
              const Text(
                'Points remain non-cash. Verified source transactions and reversals are audited; no wallet balance is credited.',
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _editLoyalty,
                icon: const Icon(Icons.loyalty_outlined),
                label: const Text('Configure loyalty'),
              ),
            ],
          ),
        ),
        _card(
          'Non-cash loyalty statements',
          Column(
            children: [
              const Text(
                'Live paginated statements from the audited loyalty ledger. Cash value is zero and redemption is disabled.',
              ),
              if (_loyaltyRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('No loyalty statements were returned.'),
                ),
              ..._loyaltyRows.map((raw) {
                final row = Map<String, dynamic>.from(raw as Map);
                final profile = row['profile'] is Map
                    ? Map<String, dynamic>.from(row['profile'] as Map)
                    : const <String, dynamic>{};
                final details = profile['details'] is Map
                    ? Map<String, dynamic>.from(profile['details'] as Map)
                    : const <String, dynamic>{};
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(details['businessName']?.toString() ??
                      profile['networkId']?.toString() ??
                      'Business'),
                  subtitle: Text(
                      '${profile['networkId'] ?? ''} · Earned ${row['earned'] ?? 0} · Reversed ${row['reversed'] ?? 0} · Available ${row['available'] ?? 0} · Expired ${row['expired'] ?? 0}'),
                  trailing:
                      Text(row['cashValueKobo'] == 0 ? '₦0.00' : 'Non-cash'),
                );
              }),
              if (_loyaltyTotal > 25)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _loyaltyPage > 1
                          ? () {
                              setState(() => _loyaltyPage--);
                              _load();
                            }
                          : null,
                      child: const Text('Previous'),
                    ),
                    Text('Page $_loyaltyPage · $_loyaltyTotal accounts'),
                    TextButton(
                      onPressed: _loyaltyPage * 25 < _loyaltyTotal
                          ? () {
                              setState(() => _loyaltyPage++);
                              _load();
                            }
                          : null,
                      child: const Text('Next'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        _card(
          'Business goals',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...goals.map((raw) {
                final goal = Map<String, dynamic>.from(raw as Map);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(goal['title']?.toString() ?? 'Goal'),
                  subtitle: Text(
                      '${goal['kind']} · ${goal['period']} · ${goal['targetTransactions']} transactions · ${_moneyIfKobo('targetVolumeKobo', goal['targetVolumeKobo'])}'),
                  trailing: IconButton(
                    tooltip: 'Remove goal',
                    onPressed:
                        _saving ? null : () => _removeConfig('goals', goal),
                    icon: const Icon(Icons.delete_outline),
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: _saving ? null : _addGoal,
                icon: const Icon(Icons.add),
                label: const Text('Add goal'),
              ),
            ],
          ),
        ),
        _card(
          'Business campaigns',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...campaigns.map((raw) {
                final campaign = Map<String, dynamic>.from(raw as Map);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(campaign['title']?.toString() ?? 'Campaign'),
                  subtitle: Text(
                      '${campaign['kind']} · ${campaign['startsAt']} – ${campaign['endsAt']} · ${campaign['enabled'] == true ? 'Published' : 'Paused'}'),
                  trailing: IconButton(
                    tooltip: 'Remove campaign',
                    onPressed: _saving
                        ? null
                        : () => _removeConfig('campaigns', campaign),
                    icon: const Icon(Icons.delete_outline),
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: _saving ? null : _addCampaign,
                icon: const Icon(Icons.add),
                label: const Text('Add campaign'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _removeConfig(String key, Map<String, dynamic> target) async {
    final current = (_configuration[key] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((row) => row['id'] != target['id'])
        .toList();
    await _save({key: current}, title: 'Save $key configuration');
  }

  Future<void> _assignLevel(Map<String, dynamic> row) async {
    final profile = row['profile'] is Map
        ? Map<String, dynamic>.from(row['profile'] as Map)
        : const <String, dynamic>{};
    final id = profile['_id']?.toString();
    if (id == null) return;
    final levels = (_configuration['levels'] as List? ?? const [])
        .whereType<Map>()
        .map((level) => Map<String, dynamic>.from(level))
        .where((level) => level['enabled'] == true)
        .toList();
    if (levels.isEmpty) {
      setState(() => _error = 'No enabled Agent levels are configured.');
      return;
    }
    String selected = levels.first['code'].toString();
    String reason = '';
    String? reasonError;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Assign qualified Agent level'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: selected,
              items: levels
                  .map((level) => DropdownMenuItem(
                      value: level['code'].toString(),
                      child: Text(level['label']?.toString() ??
                          level['code'].toString())))
                  .toList(),
              onChanged: (value) =>
                  setDialog(() => selected = value ?? selected),
            ),
            TextField(
              onChanged: (value) => setDialog(() {
                reason = value;
                reasonError = null;
              }),
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Audit reason'),
            ),
            if (reasonError != null)
              Text(reasonError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const Text(
              'Finance approval is enforced by the backend. Qualification and KYC are checked again at assignment.',
              style: TextStyle(fontSize: 12),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (reason.trim().isEmpty) {
                  setDialog(() => reasonError = 'Enter an audit reason.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Assign level'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final detail =
          await widget.api.get('profiles/${Uri.encodeComponent(id)}') as Map;
      final current = detail['profile'] is Map
          ? Map<String, dynamic>.from(detail['profile'] as Map)
          : Map<String, dynamic>.from(detail);
      await widget.api.post('profiles/${Uri.encodeComponent(id)}/level', {
        'level': selected,
        'revision': current['revision'],
        'reason': reason.trim(),
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {}
  }

  Widget _performanceView() {
    final kind = _performanceKind!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          '$kind verified performance',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'day', label: Text('Day')),
                  ButtonSegment(value: 'week', label: Text('Week')),
                  ButtonSegment(value: 'month', label: Text('Month')),
                ],
                selected: {_period},
                onSelectionChanged: (value) {
                  setState(() => _period = value.first);
                  _load();
                },
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  'Ranking uses verified successful transactions. Level assignment is separately authorized and rechecked by the service.',
                ),
              ),
              if (_performance.isEmpty)
                const Text('No verified performance rows were returned.'),
              ..._performance.map((raw) {
                final item = Map<String, dynamic>.from(raw as Map);
                final profile = item['profile'] is Map
                    ? Map<String, dynamic>.from(item['profile'] as Map)
                    : const <String, dynamic>{};
                final details = profile['details'] is Map
                    ? Map<String, dynamic>.from(profile['details'] as Map)
                    : const <String, dynamic>{};
                final currentLevel =
                    profile['level']?.toString() ?? 'Unassigned';
                return Card(
                  color: const Color(0xFFF4F8F5),
                  elevation: 0,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE1F0E6),
                      child: Text('${item['rank'] ?? '—'}'),
                    ),
                    title: Text(details['businessName']?.toString() ??
                        profile['networkId']?.toString() ??
                        'Business'),
                    subtitle: Text(
                        '${profile['networkId'] ?? ''} · $currentLevel · ${item['transactions'] ?? 0} verified transactions · ${_moneyIfKobo('volumeKobo', item['volumeKobo'])}\nLifetime qualification is checked again by the backend when a level is assigned.'),
                    isThreeLine: true,
                    trailing: kind == 'AGENT'
                        ? IconButton(
                            tooltip: 'Assign a qualified level',
                            onPressed:
                                _saving ? null : () => _assignLevel(item),
                            icon: const Icon(Icons.workspace_premium_outlined),
                          )
                        : null,
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _referralManagement() {
    final summary = _referralSummary['summary'] is Map
        ? Map<String, dynamic>.from(_referralSummary['summary'] as Map)
        : const <String, dynamic>{};
    final policy = _referralSummary['policy'] is Map
        ? Map<String, dynamic>.from(_referralSummary['policy'] as Map)
        : const <String, dynamic>{};
    return Column(
      children: [
        _card(
          'Existing ServicePay referral programme',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This view reads the existing Head Office referral monitor. Business Network does not create a second reward policy or payout engine.',
              ),
              Wrap(
                spacing: 18,
                runSpacing: 12,
                children: [
                  _premiumMetric('Referrals', summary['total']),
                  _premiumMetric('Qualified', summary['qualified']),
                  _premiumMetric('Pending', summary['pending']),
                  _premiumMetric('Awarded', summary['paid']),
                  _premiumMetric('Clawbacks', summary['clawbacks']),
                ],
              ),
              if (policy.isNotEmpty)
                Text(
                    'Current existing policy · ${policy['threshold'] ?? '—'} qualifying actions · ${_moneyIfKobo('amount', policy['amount'])}'),
              const Text(
                'Reward policy changes remain in the existing referral programme controls and are not duplicated here.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        _card(
          'Recent privacy-safe referral records',
          _referralsRows.isEmpty
              ? const Text('No referral rows were returned.')
              : Column(
                  children: _referralsRows.map((raw) {
                    final row = Map<String, dynamic>.from(raw as Map);
                    final user = row['customer'] is Map
                        ? Map<String, dynamic>.from(row['customer'] as Map)
                        : const <String, dynamic>{};
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(user['firstName']?.toString() ??
                          row['firstName']?.toString() ??
                          'Referred customer'),
                      subtitle: Text(
                          '${row['rewardStatus'] ?? row['status'] ?? ''} · ${row['winningCategory'] ?? ''}'),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _premiumMetric(String label, dynamic value) => SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Color(0xFF66756D))),
            Text('${value ?? 0}',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
      );

  Widget _capabilityControls() {
    final services = Column(
      children: [
        _serviceConfiguration('AGENT'),
        _serviceConfiguration('MERCHANT'),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          'Verified feature capabilities',
          Column(
            children: [
              _unsupported(
                  'Recharge voucher PIN generation', 'rechargeVouchers'),
              _unsupported('Data voucher PIN generation', 'dataVouchers'),
              _unsupported('Discounted special purchase pricing',
                  'specialPurchasePricing'),
              _unsupported('Bulk purchases', 'bulkPurchases'),
              _unsupported('Payment QR', 'merchantQr'),
              _unsupported('Payment links', 'payByLink'),
              _unsupported('Automatic payouts', 'automaticPayouts'),
            ],
          ),
        ),
        services,
      ],
    );
  }

  Widget _voucherUnavailable({required bool dataVoucher}) {
    final key = dataVoucher ? 'dataVouchers' : 'rechargeVouchers';
    final contract = _voucherReport['contract'] is Map
        ? Map<String, dynamic>.from(_voucherReport['contract'] as Map)
        : const <String, dynamic>{};
    final endpoint = dataVoucher ? contract['data'] : contract['airtime'];
    final endpointDetails = endpoint is Map
        ? Map<String, dynamic>.from(endpoint)
        : const <String, dynamic>{};
    return _card(
      dataVoucher
          ? 'Data voucher inventory unavailable'
          : 'Recharge voucher inventory unavailable',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Official Telecom Abode airtime and data PIN request documentation exists. Live purchases, stock and printing remain disabled until the safety prerequisites below are verified.',
            style: TextStyle(height: 1.45),
          ),
          Text(
            'Enabled: ${_voucherReport['enabled'] == true} · Inventory verified: ${_voucherReport['inventoryVerified'] == true} · Items returned: ${(_voucherReport['items'] as List? ?? const []).length}',
          ),
          if (endpointDetails['documentation'] != null)
            SelectableText(
                'Official documentation: ${endpointDetails['documentation']}'),
          if (endpointDetails['issue'] != null)
            SelectableText(
                'Documented issue endpoint: ${endpointDetails['issue']}'),
          if (endpointDetails['catalogueVerified'] == false)
            const Text(
              'Data PIN catalogue/body examples are not verified against each other.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 8),
          Text(_capabilities[key]?.toString() ??
              'No live voucher purchase or inventory is enabled.'),
          if (contract['prerequisites'] is List) ...[
            const SizedBox(height: 6),
            const Text('Remaining prerequisites:',
                style: TextStyle(fontWeight: FontWeight.w800)),
            ...(contract['prerequisites'] as List)
                .map((item) => Text('• ${item.toString()}')),
          ],
          const SizedBox(height: 8),
          const Text(
            'Ordinary airtime or data top-ups are not voucher generation.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    if (widget.section == 'Agent Pricing' ||
        widget.section == 'Merchant Pricing') {
      return _pricing();
    }
    if (widget.section == 'Recharge Voucher Inventory') {
      return _voucherUnavailable(dataVoucher: false);
    }
    if (widget.section == 'Data Voucher Inventory') {
      return _voucherUnavailable(dataVoucher: true);
    }
    if (_performanceKind != null) return _performanceView();
    if (widget.section == 'Loyalty & Goals') return _loyaltyAndGoals();
    if (widget.section == 'Referral Management') return _referralManagement();
    return _capabilityControls();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _premium.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 16),
            _AdminPremiumSkeleton(),
            SizedBox(height: 12),
            _AdminPremiumSkeleton(),
          ],
        ),
      );
    }
    if (_error != null && _premium.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_error!),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        if (widget.section == 'Loyalty & Goals')
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _editLoyalty,
              icon: const Icon(Icons.tune),
              label: const Text('Edit loyalty'),
            ),
          ),
        _content(),
      ],
    );
  }
}

class _AdminPremiumSkeleton extends StatelessWidget {
  const _AdminPremiumSkeleton();

  @override
  Widget build(BuildContext context) => Container(
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFFE5ECE7),
          borderRadius: BorderRadius.circular(14),
        ),
      );
}
