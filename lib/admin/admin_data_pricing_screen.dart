import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_api_configuration.dart';

class AdminDataPricingScreen extends StatefulWidget {
  const AdminDataPricingScreen({
    super.key,
    this.client,
    this.baseUrl = AdminApiConfiguration.baseUrl,
  });

  final http.Client? client;
  final String baseUrl;

  @override
  State<AdminDataPricingScreen> createState() => _AdminDataPricingScreenState();
}

class _AdminDataPricingScreenState extends State<AdminDataPricingScreen> {
  static const Color _primary = Color(0xFF08783E);
  static const Color _ink = Color(0xFF183126);
  static const Color _canvas = Color(0xFFF5F8F5);
  static const List<String> _networks = <String>[
    'MTN',
    'Airtel',
    'Glo',
    '9mobile',
  ];

  late final http.Client _client = widget.client ?? http.Client();
  late final bool _ownsClient = widget.client == null;

  String _network = 'MTN';
  String _search = '';
  String _provider = 'All providers';
  String _dataType = 'All types';
  String _activeFilter = 'All plans';
  bool _loading = true;
  bool _changingAvailability = false;
  String? _error;
  List<Map<String, dynamic>> _plans = <Map<String, dynamic>>[];
  final Map<String, TextEditingController> _priceControllers =
      <String, TextEditingController>{};
  final Set<String> _selectedCodes = <String>{};
  final Set<String> _savingCodes = <String>{};

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _priceControllers.values) {
      controller.dispose();
    }
    if (_ownsClient) _client.close();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for (final String key in <String>[
      'auth_token',
      'token',
      'access_token',
      'accessToken',
      'jwt_token',
      'jwt',
    ]) {
      final String value = (prefs.getString(key) ?? '').trim();
      if (value.isNotEmpty) {
        return value.startsWith('Bearer ') ? value.substring(7) : value;
      }
    }
    return null;
  }

  dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _message(dynamic decoded, String fallback) =>
      decoded is Map ? (decoded['message'] ?? fallback).toString() : fallback;

  String _code(Map<String, dynamic> plan) => (plan['code'] ?? '').toString();

  bool _active(Map<String, dynamic> plan) => plan['active'] == true;

  bool _canEnable(Map<String, dynamic> plan) => plan['canEnable'] == true;

  double _number(dynamic value) =>
      double.tryParse(
        value.toString().replaceAll('₦', '').replaceAll(',', '').trim(),
      ) ??
      0;

  String _money(dynamic value) {
    final double amount = _number(value);
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  Future<void> _loadPlans() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final String? token = await _getToken();
      if (token == null) throw Exception('Admin session not found.');
      final http.Response response = await _client.get(
        Uri.parse('${widget.baseUrl}/clubkonnect/admin/data-pricing/$_network'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final dynamic decoded = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(decoded, 'Unable to load DATA plans.'));
      }
      final dynamic raw = decoded is Map ? decoded['plans'] : null;
      final List<Map<String, dynamic>> next = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final dynamic row in raw) {
          if (row is Map) next.add(Map<String, dynamic>.from(row));
        }
      }
      next.sort((a, b) => _number(a['providerPrice']).compareTo(
            _number(b['providerPrice']),
          ));

      for (final TextEditingController controller in _priceControllers.values) {
        controller.dispose();
      }
      _priceControllers.clear();
      for (final Map<String, dynamic> plan in next) {
        final String code = _code(plan);
        if (code.isNotEmpty) {
          _priceControllers[code] = TextEditingController(
            text: _money(plan['sellingPrice']),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _plans = next;
        _selectedCodes.removeWhere(
          (String code) =>
              !next.any((Map<String, dynamic> p) => _code(p) == code),
        );
        if (!_providers.contains(_provider)) _provider = 'All providers';
        if (!_dataTypes.contains(_dataType)) _dataType = 'All types';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _providers => <String>{
        'All providers',
        ..._plans
            .map((Map<String, dynamic> p) => (p['provider'] ?? '').toString())
            .where((String s) => s.isNotEmpty),
      }.toList()
        ..sort((String a, String b) {
          if (a == 'All providers') return -1;
          if (b == 'All providers') return 1;
          return a.compareTo(b);
        });

  List<String> get _dataTypes => <String>{
        'All types',
        ..._plans
            .map((Map<String, dynamic> p) => (p['dataType'] ?? '').toString())
            .where((String s) => s.isNotEmpty),
      }.toList()
        ..sort((String a, String b) {
          if (a == 'All types') return -1;
          if (b == 'All types') return 1;
          return a.compareTo(b);
        });

  List<Map<String, dynamic>> get _filteredPlans {
    final String query = _search.trim().toLowerCase();
    return _plans.where((Map<String, dynamic> plan) {
      final String provider = (plan['provider'] ?? '').toString();
      final String type = (plan['dataType'] ?? '').toString();
      if (_provider != 'All providers' && provider != _provider) return false;
      if (_dataType != 'All types' && type != _dataType) return false;
      if (_activeFilter == 'Enabled' && !_active(plan)) return false;
      if (_activeFilter == 'Disabled' && _active(plan)) return false;
      if (query.isEmpty) return true;
      return <dynamic>[
        plan['name'],
        plan['code'],
        plan['provider'],
        plan['providerPlanId'],
        plan['networkCode'],
        plan['dataType'],
        plan['dataVolume'],
        plan['validity'],
      ].any((dynamic value) => value.toString().toLowerCase().contains(query));
    }).toList();
  }

  void _notify(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? const Color(0xFF9C3434) : _primary,
      ));
  }

  Future<void> _savePrice(Map<String, dynamic> plan) async {
    final String code = _code(plan);
    final double? price =
        double.tryParse(_priceControllers[code]?.text.trim() ?? '');
    if (price == null || price <= 0) {
      _notify('Enter a valid selling price.', error: true);
      return;
    }
    setState(() => _savingCodes.add(code));
    try {
      final String? token = await _getToken();
      if (token == null) throw Exception('Admin session not found.');
      final http.Response response = await _client.put(
        Uri.parse(
            '${widget.baseUrl}/clubkonnect/admin/data-pricing/$_network/$code'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        // Deliberately send price only: a price edit must never enable a plan.
        body: jsonEncode(<String, dynamic>{'sellingPrice': price}),
      );
      final dynamic decoded = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(decoded, 'Unable to save selling price.'));
      }
      _notify('Selling price saved.');
      await _loadPlans();
    } catch (error) {
      _notify(error.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _savingCodes.remove(code));
    }
  }

  Future<void> _confirmAvailability({
    required List<Map<String, dynamic>> candidates,
    required bool active,
    required String actionLabel,
  }) async {
    final List<String> codes = candidates
        .map(_code)
        .where((String code) => code.isNotEmpty)
        .toSet()
        .take(250)
        .toList();
    if (active) {
      final Set<String> allowed =
          candidates.where(_canEnable).map(_code).toSet();
      codes.removeWhere((String code) => !allowed.contains(code));
    }
    if (codes.isEmpty) {
      _notify(active
          ? 'No eligible disabled plans in the current view.'
          : 'No enabled plans in the current view.');
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
            '$actionLabel ${codes.length} ${codes.length == 1 ? 'plan' : 'plans'}?'),
        content: Text(
          'This will ${active ? 'enable' : 'disable'} exactly ${codes.length} '
          '${codes.length == 1 ? 'DATA plan' : 'DATA plans'} in the current filtered view. '
          '${active ? 'Only plans with a configured price and provider availability can be enabled.' : 'Customers will no longer be able to purchase these plans.'}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _changingAvailability = true);
    try {
      final String? token = await _getToken();
      if (token == null) throw Exception('Admin session not found.');
      final http.Response response = await _client.patch(
        Uri.parse(
            '${widget.baseUrl}/clubkonnect/admin/data-pricing/$_network/availability'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, dynamic>{
          'planCodes': codes,
          'active': active,
          'confirmed': true,
        }),
      );
      final dynamic decoded = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
            _message(decoded, 'Unable to update plan availability.'));
      }
      _selectedCodes.removeAll(codes);
      _notify('${active ? 'Enabled' : 'Disabled'} ${codes.length} '
          '${codes.length == 1 ? 'plan' : 'plans'}.');
      await _loadPlans();
    } catch (error) {
      _notify(error.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _changingAvailability = false);
    }
  }

  List<Map<String, dynamic>> _bulkCandidates(bool active,
      {bool selected = false}) {
    return _filteredPlans.where((Map<String, dynamic> plan) {
      if (selected && !_selectedCodes.contains(_code(plan))) return false;
      if (_active(plan) == active) return false;
      return !active || _canEnable(plan);
    }).toList();
  }

  Widget _networkTabs() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _networks.map((String network) {
            final bool selected = network == _network;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(network),
                selected: selected,
                selectedColor: _primary,
                backgroundColor: _canvas,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : _ink,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) {
                  if (selected) return;
                  setState(() {
                    _network = network;
                    _selectedCodes.clear();
                  });
                  _loadPlans();
                },
              ),
            );
          }).toList(),
        ),
      );

  Widget _filters() => Column(
        children: <Widget>[
          TextField(
            onChanged: (String value) => setState(() => _search = value),
            decoration: InputDecoration(
              hintText: 'Search plan, provider or code',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => setState(() => _search = ''),
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: _canvas,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (BuildContext context, BoxConstraints size) {
            final bool compact = size.maxWidth < 620;
            final List<Widget> controls = <Widget>[
              _filterDropdown(
                  'Provider',
                  _provider,
                  _providers,
                  (String? value) =>
                      setState(() => _provider = value ?? 'All providers')),
              _filterDropdown(
                  'Data type',
                  _dataType,
                  _dataTypes,
                  (String? value) =>
                      setState(() => _dataType = value ?? 'All types')),
              _filterDropdown(
                  'Availability',
                  _activeFilter,
                  const <String>['All plans', 'Enabled', 'Disabled'],
                  (String? value) =>
                      setState(() => _activeFilter = value ?? 'All plans')),
            ];
            if (compact) {
              return Column(
                children: controls
                    .map((Widget child) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: child,
                        ))
                    .toList(),
              );
            }
            return Row(
              children: controls
                  .map((Widget child) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: child,
                        ),
                      ))
                  .toList(),
            );
          }),
        ],
      );

  Widget _filterDropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) =>
      DropdownButtonFormField<String>(
        value: options.contains(value) ? value : options.first,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: _canvas,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        items: options
            .map((String option) => DropdownMenuItem<String>(
                  value: option,
                  child: Text(option, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: onChanged,
      );

  Widget _bulkActions() {
    final List<Map<String, dynamic>> visible = _filteredPlans;
    final List<Map<String, dynamic>> enableAll = _bulkCandidates(true);
    final List<Map<String, dynamic>> disableAll = _bulkCandidates(false);
    final List<Map<String, dynamic>> enableSelected =
        _bulkCandidates(true, selected: true);
    final List<Map<String, dynamic>> disableSelected =
        _bulkCandidates(false, selected: true);
    final bool allVisibleSelected = visible.isNotEmpty &&
        visible.every((Map<String, dynamic> plan) =>
            _selectedCodes.contains(_code(plan)));

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E9E2)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              TextButton.icon(
                onPressed: visible.isEmpty
                    ? null
                    : () => setState(() {
                          if (allVisibleSelected) {
                            _selectedCodes.removeAll(visible.map(_code));
                          } else {
                            _selectedCodes.addAll(visible.map(_code));
                          }
                        }),
                icon: Icon(allVisibleSelected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded),
                label: Text(
                    allVisibleSelected ? 'Clear visible' : 'Select visible'),
              ),
              Text('${_selectedCodes.length} selected',
                  style: const TextStyle(color: Color(0xFF627268))),
              OutlinedButton(
                onPressed: _changingAvailability || enableSelected.isEmpty
                    ? null
                    : () => _confirmAvailability(
                          candidates: enableSelected,
                          active: true,
                          actionLabel: 'Enable selected',
                        ),
                child: const Text('Enable selected'),
              ),
              OutlinedButton(
                onPressed: _changingAvailability || disableSelected.isEmpty
                    ? null
                    : () => _confirmAvailability(
                          candidates: disableSelected,
                          active: false,
                          actionLabel: 'Disable selected',
                        ),
                child: const Text('Disable selected'),
              ),
            ],
          ),
          const Divider(height: 18),
          Wrap(
            spacing: 9,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: _changingAvailability || enableAll.isEmpty
                    ? null
                    : () => _confirmAvailability(
                          candidates: enableAll,
                          active: true,
                          actionLabel: 'Enable all',
                        ),
                child: Text('Enable all (${enableAll.length})'),
              ),
              OutlinedButton(
                onPressed: _changingAvailability || disableAll.isEmpty
                    ? null
                    : () => _confirmAvailability(
                          candidates: disableAll,
                          active: false,
                          actionLabel: 'Disable all',
                        ),
                child: Text('Disable all (${disableAll.length})'),
              ),
              if (_changingAvailability)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _planCard(Map<String, dynamic> plan) {
    final String code = _code(plan);
    final String name = (plan['name'] ?? 'DATA plan').toString();
    final String provider =
        (plan['provider'] ?? 'Provider not specified').toString();
    final String dataVolume = (plan['dataVolume'] ?? '—').toString();
    final String validity = (plan['validity'] ?? '—').toString();
    final String type = (plan['dataType'] ?? '—').toString();
    final double cost = _number(plan['providerPrice']);
    final TextEditingController controller =
        _priceControllers[code] ?? TextEditingController();
    final double sellingPrice = double.tryParse(controller.text.trim()) ??
        _number(plan['sellingPrice']);
    final double margin = sellingPrice - cost;
    final bool active = _active(plan);
    final bool selectable = code.isNotEmpty && (!active || _canEnable(plan));

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE1E9E2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Checkbox(
                  value: _selectedCodes.contains(code),
                  onChanged: selectable
                      ? (bool? value) => setState(() {
                            if (value == true) {
                              _selectedCodes.add(code);
                            } else {
                              _selectedCodes.remove(code);
                            }
                          })
                      : null,
                ),
                Container(
                  width: 42,
                  height: 42,
                  margin: const EdgeInsets.only(top: 6, right: 11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF4ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.wifi_rounded, color: _primary),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(name,
                            style: const TextStyle(
                                color: _ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('$provider  ·  $code',
                            style: const TextStyle(
                                color: Color(0xFF68786E), fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _statusPill(active),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 5),
              child: Wrap(
                spacing: 7,
                runSpacing: 6,
                children: <Widget>[
                  _tag('Data volume · $dataVolume'),
                  _tag('Validity · $validity'),
                  _tag('Type · $type'),
                  if (plan['available'] == false)
                    _tag('Unavailable at provider'),
                  if (!_canEnable(plan) && !active)
                    _tag('Not eligible to enable'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (BuildContext context, BoxConstraints size) {
              final bool narrow = size.maxWidth < 510;
              final Widget costMetric =
                  _metric('Provider cost', '₦${_money(cost)}');
              final Widget marginMetric = _metric(
                'Margin',
                '${margin >= 0 ? '+' : ''}₦${_money(margin)}',
                valueColor: margin >= 0 ? _primary : const Color(0xFF9C3434),
              );
              if (narrow) {
                return Column(
                  children: <Widget>[
                    Row(children: <Widget>[
                      Expanded(child: costMetric),
                      Expanded(child: marginMetric),
                    ]),
                    const SizedBox(height: 11),
                    _priceEditor(plan, controller),
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: costMetric),
                  Expanded(child: marginMetric),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: _priceEditor(plan, controller)),
                ],
              );
            }),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _changingAvailability ||
                        (active ? false : !_canEnable(plan))
                    ? null
                    : () => _confirmAvailability(
                          candidates: <Map<String, dynamic>>[plan],
                          active: !active,
                          actionLabel: active ? 'Disable plan' : 'Enable plan',
                        ),
                icon: Icon(active
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded),
                label: Text(active ? 'Disable plan' : 'Enable plan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, {Color valueColor = _ink}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF748178), height: 1.2)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  color: valueColor,
                  fontWeight: FontWeight.w800)),
        ],
      );

  Widget _priceEditor(
    Map<String, dynamic> plan,
    TextEditingController controller,
  ) {
    final String code = _code(plan);
    final bool saving = _savingCodes.contains(code);
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
        FilledButton(
          onPressed: saving ? null : () => _savePrice(plan),
          child: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _statusPill(bool active) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE7F4EA) : const Color(0xFFF2F0E8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          active ? 'Enabled' : 'Disabled',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: active ? _primary : const Color(0xFF786B48),
          ),
        ),
      );

  Widget _tag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _canvas,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF56675D),
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(17),
                decoration: const BoxDecoration(
                    color: Color(0xFFEAF4ED), shape: BoxShape.circle),
                child: const Icon(Icons.manage_search_rounded,
                    size: 31, color: _primary),
              ),
              const SizedBox(height: 12),
              const Text('No plans match these filters',
                  style: TextStyle(
                      color: _ink, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 5),
              const Text(
                  'Try a different provider, availability or search term.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6B7B71))),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> shown = _filteredPlans;
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        title: const Text('DATA · Manage Plans',
            style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh plans',
            onPressed: _loading ? null : _loadPlans,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 15),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Admin  /  Services  /  DATA  /  Manage Plans',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF68786E),
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('Set prices. Control availability.',
                    style: TextStyle(
                        color: _ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text(
                    'Plan availability can only be enabled when the provider offers the plan and a selling price is configured.',
                    style: TextStyle(
                        color: Color(0xFF68786E), fontSize: 12, height: 1.4)),
                const SizedBox(height: 13),
                _networkTabs(),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: List<Widget>.generate(
                      4,
                      (int i) => Container(
                        height: 142,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE5ECE6)),
                        ),
                        child: const Center(
                            child: LinearProgressIndicator(
                                minHeight: 2, color: _primary)),
                      ),
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(Icons.cloud_off_outlined,
                                  size: 42, color: Color(0xFF9C3434)),
                              const SizedBox(height: 10),
                              const Text('Plans could not be loaded',
                                  style: TextStyle(
                                      color: _ink,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed: _loadPlans,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
                        children: <Widget>[
                          _filters(),
                          const SizedBox(height: 12),
                          _bulkActions(),
                          const SizedBox(height: 13),
                          Row(
                            children: <Widget>[
                              const Expanded(
                                child: Text('Supported catalog plans',
                                    style: TextStyle(
                                        color: _ink,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800)),
                              ),
                              Text('${shown.length} shown',
                                  style: const TextStyle(
                                      color: Color(0xFF68786E),
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 9),
                          if (shown.isEmpty)
                            SizedBox(height: 270, child: _emptyState())
                          else
                            ...shown.map(_planCard),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
