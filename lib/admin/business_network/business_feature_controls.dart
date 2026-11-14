import 'package:flutter/material.dart';

import 'business_network_admin_api.dart';

/// Per-customer-category capability access for own-wallet business customers.
class BusinessFeatureControls extends StatefulWidget {
  const BusinessFeatureControls({super.key, required this.api});

  final BusinessNetworkAdminApi api;

  @override
  State<BusinessFeatureControls> createState() =>
      _BusinessFeatureControlsState();
}

class _BusinessFeatureControlsState extends State<BusinessFeatureControls> {
  static const Color _green = Color(0xFF08783E);
  static const Color _ink = Color(0xFF183126);
  static const Color _canvas = Color(0xFFF4F8F4);
  static const List<String> _categories = <String>[
    'CUSTOMER',
    'AGENT',
    'MERCHANT',
  ];

  bool _loading = true;
  bool _saving = false;
  bool _historyLoading = false;
  bool _showHistory = false;
  String? _error;
  String? _historyError;
  String _provider = '';
  int _revision = 0;
  List<String> _states = <String>[];
  List<Map<String, dynamic>> _features = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  final TextEditingController _reasonController = TextEditingController();
  final Map<String, String> _draft = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  String _draftKey(String category, String key) => '$category::$key';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dynamic response = await widget.api.get('controls');
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(response as Map);
      final dynamic rawFeatures = data['features'];
      final List<Map<String, dynamic>> next = rawFeatures is List
          ? rawFeatures
              .whereType<Map>()
              .map((Map row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      final dynamic rawStates = data['states'];
      final List<String> nextStates = rawStates is List
          ? rawStates.map((dynamic state) => state.toString()).toList()
          : <String>[];
      if (!mounted) return;
      setState(() {
        _features = next;
        _states = nextStates;
        _revision = data['revision'] as int? ?? 0;
        _provider = (data['provider'] ?? '').toString();
        _draft.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _errorMessage(Object error) =>
      error.toString().replaceFirst('BusinessNetworkAdminException: ', '');

  String _currentState(Map<String, dynamic> feature, String category) {
    final dynamic categories = feature['categories'];
    if (categories is Map) {
      final dynamic state = categories[category];
      if (state != null) return state.toString();
    }
    return 'DISABLED';
  }

  String _selectedState(Map<String, dynamic> feature, String category) {
    final String key = _draftKey(category, (feature['key'] ?? '').toString());
    return _draft[key] ?? _currentState(feature, category);
  }

  bool _changed() {
    for (final Map<String, dynamic> feature in _features) {
      final String key = (feature['key'] ?? '').toString();
      for (final String category in _categories) {
        final String draftKey = _draftKey(category, key);
        if (_draft.containsKey(draftKey) &&
            _draft[draftKey] != _currentState(feature, category)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _hasCategory(Map<String, dynamic> feature, String category) {
    final dynamic categories = feature['categories'];
    return categories is Map && categories.containsKey(category);
  }

  List<String> _options(Map<String, dynamic> feature, String category) {
    final String current = _currentState(feature, category);
    if (feature['history'] == true && current == 'ENABLED') {
      return <String>['ENABLED'];
    }
    final List<String> options = List<String>.from(_states);
    if (feature['ready'] != true) options.remove('ENABLED');
    return options;
  }

  Future<void> _save() async {
    final String reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      _notice('Add a reason before saving capability changes.', isError: true);
      return;
    }
    final Map<String, Map<String, String>> changes =
        <String, Map<String, String>>{};
    for (final Map<String, dynamic> feature in _features) {
      final String key = (feature['key'] ?? '').toString();
      for (final String category in _categories) {
        final String draftKey = _draftKey(category, key);
        final String? nextState = _draft[draftKey];
        if (nextState == null ||
            nextState == _currentState(feature, category)) {
          continue;
        }
        changes.putIfAbsent(category, () => <String, String>{})[key] =
            nextState;
      }
    }
    if (changes.isEmpty) {
      _notice('There are no capability changes to save.');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.put('controls', <String, dynamic>{
        'revision': _revision,
        'reason': reason,
        'features': changes,
      });
      _notice('Capability access saved.');
      await _load();
    } catch (error) {
      _notice(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final dynamic response = await widget.api.get('configuration-history');
      final dynamic raw = (response as Map)['items'];
      final List<Map<String, dynamic>> next = raw is List
          ? raw
              .whereType<Map>()
              .map((Map row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      if (mounted) setState(() => _history = next);
    } catch (error) {
      if (mounted) setState(() => _historyError = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _historyLoading = false);
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

  @override
  Widget build(BuildContext context) => Container(
        color: _canvas,
        child: ListView(
          shrinkWrap: true,
          primary: false,
          padding: const EdgeInsets.all(18),
          children: <Widget>[
            _header(),
            const SizedBox(height: 16),
            _identityNote(),
            const SizedBox(height: 13),
            if (_loading)
              ...List<Widget>.generate(3, (_) => _skeleton())
            else if (_error != null)
              _errorPanel()
            else if (_features.isEmpty)
              _emptyPanel()
            else ..._features.map(_featureCard),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey<String>('business-feature-reason'),
              controller: _reasonController,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'Change reason (required to save)',
                hintText: 'Record the operational reason for this change',
                filled: true,
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey<String>('business-feature-save'),
                onPressed: _saving || _loading || !_changed() ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save changes'),
              ),
            ),
            const SizedBox(height: 12),
            _historyPanel(),
          ],
        ),
      );

  Widget _header() => Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE3F1E7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.tune_rounded, color: _green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Benefits & feature access',
                    style: TextStyle(
                        color: _ink,
                        fontSize: 21,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  _provider.isEmpty
                      ? 'Set customer capabilities by account category.'
                      : 'Provider · $_provider',
                  style: const TextStyle(color: Color(0xFF637268)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh feature access',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      );

  Widget _identityNote() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF3EC),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFD4E5D8)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.account_balance_wallet_outlined,
                size: 19, color: _green),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'These controls apply to ServicePay own-wallet customer accounts. '
                'Customer, Agent and Merchant are customer categories, not staff roles.',
                style: TextStyle(
                    color: Color(0xFF355844),
                    height: 1.35,
                    fontSize: 12),
              ),
            ),
          ],
        ),
      );

  Widget _featureCard(Map<String, dynamic> feature) {
    final String key = (feature['key'] ?? '').toString();
    final String label = (feature['label'] ?? key).toString();
    final bool ready = feature['ready'] == true;
    final bool historyLocked = feature['history'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: Color(0xFFDCE8DE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF3EC),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.widgets_outlined,
                      color: _green, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(label,
                          style: const TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      const SizedBox(height: 3),
                      Text(
                        ready
                            ? 'Available capability'
                            : 'Not ready · enabling is unavailable',
                        style: TextStyle(
                            color: ready
                                ? const Color(0xFF68786D)
                                : const Color(0xFF9A5B23),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                _readyTag(ready),
              ],
            ),
            if ((feature['reason'] ?? '').toString().trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 9),
              Text(feature['reason'].toString(),
                  style: const TextStyle(
                      color: Color(0xFF66756B), fontSize: 12)),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final List<Widget> fields = _categories
                    .where((String category) => _hasCategory(feature, category))
                    .map((String category) =>
                        _categoryControl(feature, category))
                    .toList();
                if (constraints.maxWidth < 570) {
                  return Column(
                    children: fields
                        .map((Widget child) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: child,
                            ))
                        .toList(),
                  );
                }
                return Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: fields
                      .map((Widget child) => SizedBox(
                            width: (constraints.maxWidth - 18) / 3,
                            child: child,
                          ))
                      .toList(),
                );
              },
            ),
            if (historyLocked) ...<Widget>[
              const SizedBox(height: 5),
              const Text(
                'This capability has history and remains enabled.',
                style: TextStyle(
                    color: Color(0xFF53685A),
                    fontSize: 11,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _categoryControl(Map<String, dynamic> feature, String category) {
    final String key = (feature['key'] ?? '').toString();
    final String current = _currentState(feature, category);
    final List<String> options = _options(feature, category);
    final String selected = _selectedState(feature, category);
    final bool locked = feature['history'] == true && current == 'ENABLED';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4ECE5)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(category,
                style: const TextStyle(
                    color: _ink, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: DropdownButtonFormField<String>(
              key: ValueKey<String>('feature-$category-$key'),
              value: options.contains(selected)
                  ? selected
                  : (options.isNotEmpty ? options.first : null),
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 9, vertical: 9),
                border: OutlineInputBorder(),
              ),
              items: options
                  .map((String state) => DropdownMenuItem<String>(
                        value: state,
                        child: Text(_prettyState(state),
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: locked || options.isEmpty
                  ? null
                  : (String? value) {
                      if (value == null) return;
                      setState(() =>
                          _draft[_draftKey(category, key)] = value);
                    },
            ),
          ),
        ],
      ),
    );
  }

  String _prettyState(String state) => switch (state) {
        'ENABLED' => 'Enabled',
        'DISABLED' => 'Disabled',
        'COMING_SOON' => 'Coming soon',
        'MAINTENANCE' => 'Maintenance',
        _ => state.replaceAll('_', ' ').toLowerCase(),
      };

  Widget _readyTag(bool ready) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: ready ? const Color(0xFFE5F3E9) : const Color(0xFFFFF1DD),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(ready ? 'Ready' : 'Pending',
            style: TextStyle(
                color: ready
                    ? const Color(0xFF08783E)
                    : const Color(0xFF8A5B1B),
                fontWeight: FontWeight.w700,
                fontSize: 11)),
      );

  Widget _historyPanel() => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: const BorderSide(color: Color(0xFFDCE8DE)),
        ),
        child: ExpansionTile(
          key: const ValueKey<String>('business-feature-history'),
          title: const Text('Configuration history',
              style: TextStyle(color: _ink, fontWeight: FontWeight.w800)),
          subtitle: const Text('Review recent access changes'),
          onExpansionChanged: (bool expanded) {
            setState(() => _showHistory = expanded);
            if (expanded && _history.isEmpty && !_historyLoading) {
              _loadHistory();
            }
          },
          children: <Widget>[
            if (_showHistory && _historyLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(color: _green),
              )
            else if (_historyError != null)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: <Widget>[
                  Text(_historyError!,
                      style: const TextStyle(color: Color(0xFF9C3434))),
                  TextButton(
                    onPressed: _loadHistory,
                    child: const Text('Retry history'),
                  ),
                ]),
              )
            else if (_history.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No recent configuration entries.',
                    style: TextStyle(color: Color(0xFF68786D))),
              )
            else
              ..._history.take(8).map(_historyRow),
          ],
        ),
      );

  Widget _historyRow(Map<String, dynamic> item) {
    final String metadata = item['metadata'] is Map
        ? (item['metadata'] as Map).entries
            .take(3)
            .map((MapEntry<dynamic, dynamic> entry) =>
                '${entry.key}: ${entry.value}')
            .join(' · ')
        : '';
    return ListTile(
      dense: true,
      leading: const Icon(Icons.history_rounded,
          color: Color(0xFF65806D), size: 20),
      title: Text('${item['action'] ?? 'Updated'}'
          '${metadata.isEmpty ? '' : ' · $metadata'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      subtitle: Text(
        '${item['actor'] ?? 'Admin'} · ${item['createdAt'] ?? ''}'
        '${(item['reason'] ?? '').toString().isEmpty ? '' : ' · ${item['reason']}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _skeleton() => Container(
        height: 112,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: const Color(0xFFE7EEE8),
            borderRadius: BorderRadius.circular(13)),
      );

  Widget _errorPanel() => _messagePanel(
        icon: Icons.cloud_off_outlined,
        title: 'Feature access could not be loaded',
        body: _error!,
        action: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      );

  Widget _emptyPanel() => _messagePanel(
        icon: Icons.tune_rounded,
        title: 'No capabilities available',
        body: 'There are no feature controls in this configuration.',
      );

  Widget _messagePanel(
      {required IconData icon,
      required String title,
      required String body,
      Widget? action}) {
    return Container(
      padding: const EdgeInsets.all(23),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
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
