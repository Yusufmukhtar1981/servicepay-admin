import 'package:flutter/material.dart';

import 'business_network_admin_api.dart';

/// Head Office controls for Agent and Merchant pricing on own-wallet services.
class BusinessPricingManagement extends StatefulWidget {
  const BusinessPricingManagement({super.key, required this.api});

  final BusinessNetworkAdminApi api;

  @override
  State<BusinessPricingManagement> createState() =>
      _BusinessPricingManagementState();
}

class _BusinessPricingManagementState extends State<BusinessPricingManagement> {
  static const Color _green = Color(0xFF08783E);
  static const Color _ink = Color(0xFF183126);
  static const Color _canvas = Color(0xFFF4F8F4);
  static const List<String> _networks = <String>['01', '02', '03', '04'];

  String _network = '01';
  String _search = '';
  bool _loading = true;
  bool _airtimeLoading = true;
  String? _error;
  String? _airtimeError;
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _airtimeItems = <Map<String, dynamic>>[];
  int _airtimeRevision = 0;
  String _airtimeProvider = '';
  String _airtimeWarning = '';
  dynamic _customerMarkupBps;
  final TextEditingController _reason = TextEditingController();
  final Map<String, TextEditingController> _prices =
      <String, TextEditingController>{};
  final Map<String, TextEditingController> _ceilings =
      <String, TextEditingController>{};
  final Map<String, bool> _enabled = <String, bool>{};
  final Set<String> _saving = <String>{};
  final Map<String, _PricingSnapshot> _loadedRules =
      <String, _PricingSnapshot>{};
  bool _savingAll = false;
  final Map<String, TextEditingController> _airtimeMarkup =
      <String, TextEditingController>{};
  final Map<String, bool> _airtimeEnabled = <String, bool>{};
  final Set<String> _airtimeSaving = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final TextEditingController controller in _prices.values) {
      controller.dispose();
    }
    for (final TextEditingController controller in _ceilings.values) {
      controller.dispose();
    }
    for (final TextEditingController controller in _airtimeMarkup.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _key(String code, String category) => '$code::$category';

  double? _number(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString().replaceAll(',', '').trim());
  }

  String _amount(dynamic value) {
    final double? number = _number(value);
    if (number == null) return '';
    return number == number.roundToDouble()
        ? number.toStringAsFixed(0)
        : number.toStringAsFixed(2);
  }

  String _money(dynamic value) {
    final String amount = _amount(value);
    return amount.isEmpty ? 'Not priced' : '₦$amount';
  }

  Future<void> _load() async {
    _loadAirtime();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dynamic response = await widget.api.get(
        'pricing',
        query: <String, String>{'network': _network, 'search': _search},
      );
      final Map<String, dynamic> data = Map<String, dynamic>.from(response as Map);
      final dynamic rawItems = data['items'];
      final List<Map<String, dynamic>> next = rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((Map row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      for (final TextEditingController controller in _prices.values) {
        controller.dispose();
      }
      for (final TextEditingController controller in _ceilings.values) {
        controller.dispose();
      }
      _prices.clear();
      _ceilings.clear();
      _enabled.clear();
      _loadedRules.clear();
      for (final Map<String, dynamic> item in next) {
        final String code = (item['code'] ?? '').toString();
        final double? providerCost = _number(item['providerCost']);
        final dynamic categories = item['categories'];
        if (categories is! Map) continue;
        for (final String category in <String>['AGENT', 'MERCHANT']) {
          final dynamic rawRule = categories[category];
          if (rawRule is! Map) continue;
          final Map<String, dynamic> rule = Map<String, dynamic>.from(rawRule);
          final dynamic sellingPrice =
              rule['configured'] == true && rule['sellingPrice'] != null
                  ? rule['sellingPrice']
                  : rule['effectivePrice'];
          final dynamic maximum = rule['maximumProviderCost'] ?? providerCost;
          final String key = _key(code, category);
          _prices[key] = TextEditingController(text: _amount(sellingPrice));
          _ceilings[key] = TextEditingController(text: _amount(maximum));
          _enabled[key] = rule['enabled'] == true;
          _loadedRules[key] = _PricingSnapshot(
            sellingPrice: _number(sellingPrice),
            maximumProviderCost: _number(maximum),
            enabled: rule['enabled'] == true,
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _items = next;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAirtime() async {
    if (mounted) {
      setState(() {
        _airtimeLoading = true;
        _airtimeError = null;
      });
    }
    try {
      final dynamic response = await widget.api.get('airtime-pricing');
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(response as Map);
      final dynamic rawItems = data['items'];
      final List<Map<String, dynamic>> next = rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((Map row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      for (final TextEditingController controller in _airtimeMarkup.values) {
        controller.dispose();
      }
      _airtimeMarkup.clear();
      _airtimeEnabled.clear();
      for (final Map<String, dynamic> item in next) {
        final String network = (item['network'] ?? '').toString();
        final dynamic categories = item['categories'];
        if (categories is! Map) continue;
        for (final String category in <String>['AGENT', 'MERCHANT']) {
          final dynamic rawRule = categories[category];
          final Map<String, dynamic> rule = rawRule is Map
              ? Map<String, dynamic>.from(rawRule)
              : <String, dynamic>{};
          final String key = _key(network, category);
          final dynamic markup = rule['markupBps'] ?? data['customerMarkupBps'];
          _airtimeMarkup[key] =
              TextEditingController(text: markup?.toString() ?? '');
          _airtimeEnabled[key] = rule['enabled'] == true;
        }
      }
      if (!mounted) return;
      setState(() {
        _airtimeItems = next;
        _airtimeRevision = data['revision'] as int? ?? 0;
        _airtimeProvider = (data['provider'] ?? '').toString();
        _airtimeWarning = (data['costWarning'] ?? '').toString();
        _customerMarkupBps = data['customerMarkupBps'];
      });
    } catch (error) {
      if (mounted) setState(() => _airtimeError = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _airtimeLoading = false);
    }
  }

  Future<void> _saveAirtime(
      Map<String, dynamic> item, String category) async {
    final String reason = _reason.text.trim();
    if (reason.isEmpty) {
      _notice('Add a reason before saving pricing.', isError: true);
      return;
    }
    final String network = (item['network'] ?? '').toString();
    final String key = _key(network, category);
    final int? markupBps = int.tryParse(_airtimeMarkup[key]?.text.trim() ?? '');
    if (markupBps == null || markupBps < 0 || markupBps > 10000) {
      _notice('Markup must be a whole number from 0 to 10,000 basis points.',
          isError: true);
      return;
    }
    setState(() => _airtimeSaving.add(key));
    try {
      await widget.api.put('airtime-pricing', <String, dynamic>{
        'revision': _airtimeRevision,
        'reason': reason,
        'changes': <Map<String, dynamic>>[
          <String, dynamic>{
            'network': network,
            'category': category,
            'enabled': _airtimeEnabled[key] == true,
            'markupBps': markupBps,
          },
        ],
      });
      _notice('$category Airtime markup saved.');
      await _loadAirtime();
    } catch (error) {
      _notice(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _airtimeSaving.remove(key));
    }
  }

  String _errorMessage(Object error) =>
      error.toString().replaceFirst('BusinessNetworkAdminException: ', '');

  bool get _dataSaveBusy => _savingAll || _saving.isNotEmpty;

  List<_PricingDraft> get _changedDrafts {
    final List<_PricingDraft> changed = <_PricingDraft>[];
    for (final Map<String, dynamic> item in _items) {
      final dynamic categories = item['categories'];
      if (categories is! Map) continue;
      final String code = (item['code'] ?? '').toString();
      for (final String category in <String>['AGENT', 'MERCHANT']) {
        final String key = _key(code, category);
        final _PricingSnapshot? original = _loadedRules[key];
        if (original == null) continue;
        final bool priceChanged =
            _amountChanged(_prices[key]?.text, original.sellingPrice);
        final bool ceilingChanged = _amountChanged(
            _ceilings[key]?.text, original.maximumProviderCost);
        final bool enabledChanged = _enabled[key] != original.enabled;
        if (priceChanged || ceilingChanged || enabledChanged) {
          changed.add(_PricingDraft(
            item: item,
            category: category,
            key: key,
          ));
        }
      }
    }
    return changed;
  }

  bool _amountChanged(String? raw, double? original) {
    final String text = (raw ?? '').trim();
    if (text.isEmpty) return original != null;
    final double? current = _number(text);
    return current == null || current != original;
  }

  String? _validateDraft(_PricingDraft draft) {
    final double? sellingPrice = _number(_prices[draft.key]?.text);
    final double? maximumProviderCost = _number(_ceilings[draft.key]?.text);
    final double? providerCost = _number(draft.item['providerCost']);
    final String name =
        '${draft.category} · ${draft.item['name'] ?? draft.item['code']}';
    if (_revisionOf(draft.item['revision']) == null) {
      return '$name has no valid pricing revision.';
    }
    if (sellingPrice == null || sellingPrice <= 0) {
      return '$name needs a selling price greater than zero.';
    }
    if (maximumProviderCost == null || maximumProviderCost <= 0) {
      return '$name needs a provider-cost ceiling greater than zero.';
    }
    if (providerCost == null || maximumProviderCost < providerCost) {
      return '$name ceiling must cover the current provider cost '
          '(${_money(draft.item['providerCost'])}).';
    }
    if (sellingPrice < maximumProviderCost) {
      return '$name selling price must cover its provider-cost ceiling.';
    }
    return null;
  }

  int? _revisionOf(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Future<void> _saveAll() async {
    if (_dataSaveBusy || _loading) return;
    final String reason = _reason.text.trim();
    if (reason.isEmpty) {
      _notice('Add a reason before saving pricing.', isError: true);
      return;
    }
    final List<_PricingDraft> changes = _changedDrafts;
    if (changes.isEmpty) {
      _notice('There are no changed Data rules to save.');
      return;
    }
    if (changes.length > 50) {
      _notice(
        'This batch has ${changes.length} changes. Save no more than 50 at a time.',
        isError: true,
      );
      return;
    }
    final List<String> invalid = <String>[];
    for (final _PricingDraft draft in changes) {
      final String? error = _validateDraft(draft);
      if (error != null) invalid.add(error);
    }
    if (invalid.isNotEmpty) {
      final String details = invalid.take(3).join(' ');
      _notice(
        invalid.length > 3
            ? '$details ${invalid.length - 3} more change(s) need attention.'
            : details,
        isError: true,
      );
      return;
    }

    setState(() => _savingAll = true);
    try {
      await widget.api.put('pricing', <String, dynamic>{
        'network': _network,
        'reason': reason,
        'changes': changes.map((_PricingDraft draft) {
          return <String, dynamic>{
            'code': (draft.item['code'] ?? '').toString(),
            'category': draft.category,
            'revision': _revisionOf(draft.item['revision']),
            'rule': <String, dynamic>{
              'enabled': _enabled[draft.key] == true,
              'sellingPrice': _number(_prices[draft.key]?.text),
              'maximumProviderCost':
                  _number(_ceilings[draft.key]?.text),
            },
          };
        }).toList(),
      });
      _notice('Saved ${changes.length} Data pricing '
          '${changes.length == 1 ? 'change' : 'changes'}.');
      await _load();
    } catch (error) {
      _notice(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _savingAll = false);
    }
  }

  void _notice(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: isError ? const Color(0xFF9C3434) : _green,
      ));
  }

  Future<void> _save(
      Map<String, dynamic> item, String category) async {
    if (_dataSaveBusy || _loading) return;
    final String reason = _reason.text.trim();
    if (reason.isEmpty) {
      _notice('Add a reason before saving pricing.', isError: true);
      return;
    }
    final String code = (item['code'] ?? '').toString();
    final String key = _key(code, category);
    final _PricingDraft draft =
        _PricingDraft(item: item, category: category, key: key);
    final String? validationError = _validateDraft(draft);
    if (validationError != null) {
      _notice(validationError, isError: true);
      return;
    }
    setState(() => _saving.add(key));
    try {
      await widget.api.put('pricing', <String, dynamic>{
        'network': _network,
        'reason': reason,
        'changes': <Map<String, dynamic>>[
          <String, dynamic>{
            'code': code,
            'category': category,
            'revision': _revisionOf(item['revision']),
            'rule': <String, dynamic>{
              'enabled': _enabled[key] == true,
              'sellingPrice': _number(_prices[key]?.text),
              'maximumProviderCost': _number(_ceilings[key]?.text),
            },
          },
        ],
      });
      _notice('$category pricing saved.');
      await _load();
    } catch (error) {
      _notice(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  List<Map<String, dynamic>> get _visibleItems {
    final String query = _search.trim().toLowerCase();
    return _items.where((Map<String, dynamic> item) {
      if (query.isEmpty) return true;
      return <dynamic>[
        item['name'],
        item['code'],
        item['pricingCode'],
        item['provider'],
      ].any((dynamic value) => value.toString().toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) => Container(
        color: _canvas,
        child: ListView(
          shrinkWrap: true,
          primary: false,
          padding: const EdgeInsets.all(18),
          children: <Widget>[
            _heading(),
            const SizedBox(height: 16),
            _airtimeSection(),
            const SizedBox(height: 14),
            _filters(),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('business-pricing-reason'),
              controller: _reason,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'Change reason (required for each save)',
                hintText: 'For example: approved provider cost review',
                filled: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 2),
            _bulkSaveBar(),
            const SizedBox(height: 8),
            if (_loading)
              ...List<Widget>.generate(3, (_) => _skeleton())
            else if (_error != null)
              _errorPanel()
            else if (_visibleItems.isEmpty)
              _emptyPanel()
            else ..._visibleItems.map(_itemCard),
          ],
        ),
      );

  Widget _bulkSaveBar() {
    final int changedCount = _changedDrafts.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3EC),
        border: Border.all(color: const Color(0xFFD4E5D8)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: <Widget>[
          Text(
            '$changedCount unsaved Data ${changedCount == 1 ? 'change' : 'changes'}',
            style: const TextStyle(
                color: Color(0xFF355844), fontWeight: FontWeight.w700),
          ),
          FilledButton.icon(
            key: const ValueKey<String>('business-pricing-save-all'),
            onPressed: _loading ||
                    _error != null ||
                    changedCount == 0 ||
                    _dataSaveBusy
                ? null
                : _saveAll,
            icon: _savingAll
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_savingAll ? 'Saving batch…' : 'Save all Data edits'),
          ),
        ],
      ),
    );
  }

  Widget _heading() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE3F1E7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.price_change_outlined, color: _green),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Business pricing',
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: _ink)),
                SizedBox(height: 4),
                Text('Configure own-wallet Agent and Merchant prices.',
                    style: TextStyle(color: Color(0xFF637268))),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh pricing',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      );

  Widget _airtimeSection() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E8),
          border: Border.all(color: const Color(0xFFEAD9B2)),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.phone_android_rounded,
                    color: Color(0xFF775B20), size: 20),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text('Airtime markups',
                      style: TextStyle(
                          color: Color(0xFF604A1A),
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                ),
                IconButton(
                  tooltip: 'Refresh Airtime markups',
                  onPressed: _airtimeLoading ? null : _loadAirtime,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              _airtimeProvider.isEmpty
                  ? 'Independent add-on above face value.'
                  : '$_airtimeProvider · independent add-on above face value.',
              style: const TextStyle(color: Color(0xFF705F3C), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: <Widget>[
                Text(
                  'Customer markup · ${_basisPoints(_customerMarkupBps)} (read-only)',
                  style: const TextStyle(
                      color: Color(0xFF594A2C),
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                ),
                const Text('Provider cost · unknown until invoice',
                    style: TextStyle(
                        color: Color(0xFF705F3C), fontSize: 12)),
                const Text('Profit · not available before invoice',
                    style: TextStyle(
                        color: Color(0xFF705F3C), fontSize: 12)),
              ],
            ),
            if (_airtimeWarning.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(_airtimeWarning,
                  style: const TextStyle(
                      color: Color(0xFF775B20), fontSize: 12)),
            ],
            const SizedBox(height: 5),
            const Text(
              'Face value is never discounted. Selling price = round(face value × (10,000 + markup bps) ÷ 10,000).',
              style: TextStyle(color: Color(0xFF705F3C), fontSize: 11),
            ),
            if (_airtimeLoading)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _skeleton(),
              )
            else if (_airtimeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(_airtimeError!,
                          style: const TextStyle(
                              color: Color(0xFF9C3434), fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: _loadAirtime,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (_airtimeItems.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No Airtime networks returned.',
                    style: TextStyle(color: Color(0xFF705F3C), fontSize: 12)),
              )
            else ..._airtimeItems.map(_airtimeItem),
          ],
        ),
      );

  String _basisPoints(dynamic value) =>
      value == null ? 'Not configured' : '${value.toString()} bps';

  Widget _airtimeItem(Map<String, dynamic> item) {
    final dynamic categories = item['categories'];
    final Map<String, dynamic> categoryMap =
        categories is Map ? Map<String, dynamic>.from(categories) : {};
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFECE1C9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${item['name'] ?? 'Airtime'} · ${item['network'] ?? '—'}',
              style: const TextStyle(
                  color: _ink, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final List<Widget> editors = <Widget>[
                _airtimeCategoryEditor(item, categoryMap, 'AGENT'),
                _airtimeCategoryEditor(item, categoryMap, 'MERCHANT'),
              ];
              if (constraints.maxWidth < 650) {
                return Column(children: <Widget>[
                  editors[0],
                  const SizedBox(height: 8),
                  editors[1],
                ]);
              }
              return Row(children: <Widget>[
                Expanded(child: editors[0]),
                const SizedBox(width: 9),
                Expanded(child: editors[1]),
              ]);
            },
          ),
        ],
      ),
    );
  }

  Widget _airtimeCategoryEditor(Map<String, dynamic> item,
      Map<String, dynamic> categories, String category) {
    final String network = (item['network'] ?? '').toString();
    final String key = _key(network, category);
    final dynamic rawRule = categories[category];
    final Map<String, dynamic> rule =
        rawRule is Map ? Map<String, dynamic>.from(rawRule) : {};
    final bool inherited = rawRule == null;
    final bool saving = _airtimeSaving.contains(key);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFECE6D8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            Expanded(
              child: Text(category,
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            Text(inherited ? 'Inherits customer markup' : 'Independent rule',
                style: const TextStyle(
                    color: Color(0xFF756340), fontSize: 10)),
          ]),
          const SizedBox(height: 6),
          Row(children: <Widget>[
            Expanded(
              child: TextField(
                key: ValueKey<String>('airtime-markup-$network-$category'),
                controller: _airtimeMarkup[key],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Markup',
                  suffixText: 'bps',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 7),
            const Text('Enabled', style: TextStyle(fontSize: 11)),
            Switch.adaptive(
              key: ValueKey<String>('airtime-enabled-$network-$category'),
              value: _airtimeEnabled[key] == true,
              activeColor: _green,
              onChanged: (bool value) =>
                  setState(() => _airtimeEnabled[key] = value),
            ),
            FilledButton(
              key: ValueKey<String>('airtime-save-$network-$category'),
              onPressed:
                  saving ? null : () => _saveAirtime(item, category),
              child: saving
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ]),
          if (rule['updatedBy'] != null || rule['updatedAt'] != null)
            Text(
              'Last updated ${rule['updatedBy'] ?? '—'} · ${rule['updatedAt'] ?? '—'}',
              style: const TextStyle(
                  color: Color(0xFF77705F), fontSize: 10),
            ),
        ],
      ),
    );
  }

  Widget _filters() => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget networkPicker = DropdownButtonFormField<String>(
            value: _network,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Network',
              border: OutlineInputBorder(),
              filled: true,
            ),
            items: _networks
                .map((String code) => DropdownMenuItem<String>(
                      value: code,
                      child: Text(_networkName(code)),
                    ))
                .toList(),
            onChanged: (String? value) {
              if (value == null) return;
              setState(() => _network = value);
              _load();
            },
          );
          final Widget search = TextField(
            key: const ValueKey<String>('business-pricing-search'),
            onChanged: (String value) {
              setState(() => _search = value);
            },
            onSubmitted: (_) => _load(),
            decoration: const InputDecoration(
              labelText: 'Search service or provider',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
              filled: true,
            ),
          );
          if (constraints.maxWidth < 600) {
            return Column(children: <Widget>[
              networkPicker,
              const SizedBox(height: 10),
              search,
            ]);
          }
          return Row(children: <Widget>[
            SizedBox(width: 190, child: networkPicker),
            const SizedBox(width: 10),
            Expanded(child: search),
          ]);
        },
      );

  String _networkName(String code) => <String, String>{
        '01': 'MTN · 01',
        '02': 'Glo · 02',
        '03': '9mobile · 03',
        '04': 'Airtel · 04',
      }[code]!;

  Widget _itemCard(Map<String, dynamic> item) {
    final dynamic categories = item['categories'];
    final Map<String, dynamic> categoryMap =
        categories is Map ? Map<String, dynamic>.from(categories) : {};
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFDCE8DE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 8,
              children: <Widget>[
                SizedBox(
                  width: 380,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text((item['name'] ?? item['pricingCode'] ?? 'Service')
                          .toString(),
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _ink)),
                      const SizedBox(height: 3),
                      Text('${item['provider'] ?? 'Provider'}  ·  '
                          '${item['code'] ?? '—'}',
                          style: const TextStyle(
                              color: Color(0xFF6B796F), fontSize: 12)),
                    ],
                  ),
                ),
                _tag('Provider cost  ${_money(item['providerCost'])}'),
              ],
            ),
            const SizedBox(height: 11),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5F0),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                'Customer price · ${_money((item['customer'] as Map?)?['sellingPrice'])}'
                '  ·  Read-only. Use the existing Admin DATA Pricing screen to change customer prices.',
                style: const TextStyle(
                    color: Color(0xFF52645A), fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final List<Widget> editors = <Widget>[
                  _categoryEditor(item, categoryMap, 'AGENT'),
                  _categoryEditor(item, categoryMap, 'MERCHANT'),
                ];
                if (constraints.maxWidth < 700) {
                  return Column(children: <Widget>[
                    editors[0],
                    const SizedBox(height: 10),
                    editors[1],
                  ]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: editors[0]),
                    const SizedBox(width: 10),
                    Expanded(child: editors[1]),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryEditor(Map<String, dynamic> item,
      Map<String, dynamic> categories, String category) {
    final String code = (item['code'] ?? '').toString();
    final String key = _key(code, category);
    final dynamic raw = categories[category];
    final Map<String, dynamic> rule =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final bool configured = rule['configured'] == true;
    final bool inherited = rule['inherited'] == true || !configured;
    final double? price = _number(_prices[key]?.text);
    final double? cost = _number(item['providerCost']);
    final double margin = price == null || cost == null ? 0 : price - cost;
    final bool saving = _saving.contains(key);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFA),
        border: Border.all(color: const Color(0xFFE4ECE5)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            Expanded(
              child: Text(category,
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w800)),
            ),
            _stateTag(_enabled[key] == true),
          ]),
          const SizedBox(height: 4),
          Text(
            '${inherited ? 'Inherited price' : 'Configured'} · '
            'Effective ${_money(rule['effectivePrice'])}',
            style: const TextStyle(color: Color(0xFF68786D), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: ValueKey<String>('pricing-price-$code-$category'),
                  controller: _prices[key],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Selling price',
                    prefixText: '₦ ',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: ValueKey<String>('pricing-ceiling-$code-$category'),
                  controller: _ceilings[key],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Provider ceiling',
                    prefixText: '₦ ',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              Text(
                'Margin ${price == null || cost == null ? '—' : '${margin >= 0 ? '+' : ''}₦${_amount(margin)}'}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: price == null
                      ? const Color(0xFF68786D)
                      : margin >= 0
                          ? _green
                          : const Color(0xFF9C3434),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('Enabled', style: TextStyle(fontSize: 12)),
                  Switch.adaptive(
                    key: ValueKey<String>('pricing-enabled-$code-$category'),
                    value: _enabled[key] == true,
                    activeColor: _green,
                    onChanged: (bool value) =>
                        setState(() => _enabled[key] = value),
                  ),
                  FilledButton(
                    key: ValueKey<String>('pricing-save-$code-$category'),
                    onPressed: _dataSaveBusy || _loading
                        ? null
                        : () => _save(item, category),
                    child: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF3EC),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF365843),
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );

  Widget _stateTag(bool enabled) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFE5F3E9) : const Color(0xFFF4EEE5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(enabled ? 'Enabled' : 'Disabled',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: enabled
                    ? const Color(0xFF08783E)
                    : const Color(0xFF795F36))),
      );

  Widget _skeleton() => Container(
        height: 150,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFE7EEE8),
          borderRadius: BorderRadius.circular(14),
        ),
      );

  Widget _errorPanel() => _messagePanel(
        icon: Icons.cloud_off_outlined,
        title: 'Pricing could not be loaded',
        body: _error!,
        action: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      );

  Widget _emptyPanel() => _messagePanel(
        icon: Icons.search_off_rounded,
        title: 'No matching services',
        body: 'Try a different network or search term.',
      );

  Widget _messagePanel(
      {required IconData icon,
      required String title,
      required String body,
      Widget? action}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDCE8DE))),
      child: Column(children: <Widget>[
        Icon(icon, color: _green, size: 30),
        const SizedBox(height: 9),
        Text(title,
            style: const TextStyle(
                color: _ink, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 5),
        Text(body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF66756B))),
        if (action != null) action,
      ]),
    );
  }
}

class _PricingSnapshot {
  const _PricingSnapshot({
    required this.sellingPrice,
    required this.maximumProviderCost,
    required this.enabled,
  });

  final double? sellingPrice;
  final double? maximumProviderCost;
  final bool enabled;
}

class _PricingDraft {
  const _PricingDraft({
    required this.item,
    required this.category,
    required this.key,
  });

  final Map<String, dynamic> item;
  final String category;
  final String key;
}
