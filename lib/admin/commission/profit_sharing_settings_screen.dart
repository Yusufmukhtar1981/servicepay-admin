import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'profit_sharing_activation_panel.dart';
import 'profit_sharing_api.dart';

class ProfitSharingSettingsScreen extends StatefulWidget {
  const ProfitSharingSettingsScreen({
    super.key,
    this.api,
    this.client,
    this.tokenProvider,
  });

  final ProfitSharingApi? api;
  final http.Client? client;
  final Future<String?> Function()? tokenProvider;

  @override
  State<ProfitSharingSettingsScreen> createState() =>
      _ProfitSharingSettingsScreenState();
}

class _ProfitSharingSettingsScreenState extends State<ProfitSharingSettingsScreen> {
  static const Color ink = Color(0xFF20372F);
  static const Color green = Color(0xFF168A3A);
  static const Color paper = Color(0xFFF4F7F2);
  static const List<String> roleCodes = <String>[
    'HEAD_OFFICE',
    'ZONAL_MANAGER',
    'STATE_MANAGER',
    'AGGREGATOR',
  ];
  static const Map<String, String> roleNames = <String, String>{
    'HEAD_OFFICE': 'Head Office Percentage',
    'ZONAL_MANAGER': 'Zonal Managers Percentage',
    'STATE_MANAGER': 'State Managers Percentage',
    'AGGREGATOR': 'Aggregators Percentage',
  };
  static const Map<String, String> serviceNames = <String, String>{
    'AIRTIME': 'Airtime',
    'DATA': 'Data',
    'ELECTRICITY': 'Electricity',
    'CABLE': 'Cable TV',
    'EXAM_PIN': 'Exam PIN',
    'NIN_VERIFICATION': 'NIN Verification',
    'BVN_VERIFICATION': 'BVN Verification',
    'DELIVERY': 'Delivery',
    'SERVICEPAY_TRANSFER': 'ServicePay Transfer',
  };

  late final ProfitSharingApi _api = widget.api ??
      ProfitSharingApi(client: widget.client, tokenProvider: widget.tokenProvider);
  late final bool _ownsApi = widget.api == null;
  final Map<String, TextEditingController> _percentControllers =
      <String, TextEditingController>{
    for (final String role in roleCodes) role: TextEditingController(),
  };
  final TextEditingController _reasonController = TextEditingController();
  Map<String, dynamic> _data = <String, dynamic>{};
  Map<String, dynamic>? _engine;
  String? _service;
  DateTime? _effectiveAt;
  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;
  bool _canManage = false;
  bool _distributionLive = false;
  bool _legacyCurrentRule = false;
  bool _engineLoading = true;
  String? _engineError;
  String _readiness = 'Loading distribution readiness…';
  String? _error;
  String? _validationError;
  Map<String, dynamic>? _frozenPayload;
  String? _pendingKey;
  int _keySequence = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_ownsApi) _api.close();
    for (final TextEditingController controller in _percentControllers.values) {
      controller.dispose();
    }
    _reasonController.dispose();
    super.dispose();
  }

  List<String> get _services {
    final List<dynamic> values = _data['services'] is List
        ? _data['services'] as List<dynamic>
        : serviceNames.keys.toList();
    return values.map((dynamic value) => value.toString()).toList();
  }

  List<Map<String, dynamic>> get _items {
    final dynamic values = _data['items'];
    if (values is! List) return <Map<String, dynamic>>[];
    return values.whereType<Map>().map((Map item) => Map<String, dynamic>.from(item)).toList();
  }

  Map<String, dynamic>? get _selectedItem {
    for (final Map<String, dynamic> item in _items) {
      if (item['serviceType'] == _service) return item;
    }
    return null;
  }

  List<Map<String, dynamic>> get _versions {
    final dynamic values = _selectedItem?['versions'];
    if (values is! List) return <Map<String, dynamic>>[];
    // The API supplies versions newest first; preserve that audit ordering.
    return values.whereType<Map>().map((Map item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<void> _load({bool keepEditor = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> response = await _api.getSettings();
      final dynamic raw = response['data'];
      final Map<String, dynamic> data =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _data = data;
        _canManage = data['canManage'] == true;
        _distributionLive = false;
        _readiness = 'Checking live activation status with the backend…';
        final List<String> services = _services;
        if (_service == null || !services.contains(_service)) {
          _service = services.isEmpty ? null : services.first;
        }
        if (!keepEditor) _populateCurrentRule();
      });
    } on ProfitSharingApiException catch (exception) {
      if (mounted) setState(() => _error = exception.message);
    } on TimeoutException {
      if (mounted) setState(() => _error = 'The request timed out. Check your connection and refresh.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load profit-sharing settings. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _loadEngine();
  }

  Future<void> _loadEngine() async {
    if (mounted) {
      setState(() {
        _engineLoading = true;
        _engineError = null;
      });
    }
    try {
      final Map<String, dynamic> response = await _api.getEngine();
      final dynamic raw = response['data'];
      if (raw is! Map) {
        throw const ProfitSharingApiException('Engine status is incomplete.');
      }
      final Map<String, dynamic> engine = Map<String, dynamic>.from(raw);
      final dynamic rawServices = engine['services'];
      final bool validServices = rawServices is List &&
          rawServices.every((dynamic item) =>
              item is Map &&
              item['serviceType'] is String &&
              item['blockers'] is List);
      if (!<String>['PAUSED', 'BLOCKED', 'LIVE'].contains(engine['mode']) ||
          engine['distributionLive'] is! bool ||
          engine['revision'] is! num ||
          engine['ready'] is! bool ||
          engine['storageBlockers'] is! List ||
          !validServices) {
        throw const ProfitSharingApiException(
          'Backend engine status is incomplete or invalid.',
        );
      }
      if (mounted) {
        setState(() {
          _engine = engine;
          _distributionLive =
              engine['distributionLive'] == true && engine['mode'] == 'LIVE';
          final List<String> blockers = _engineBlockers(engine);
          _readiness = _distributionLive
              ? 'The backend reports LIVE distribution. Revision ${engine['revision'] ?? 'unknown'}.'
              : blockers.isNotEmpty
                  ? blockers.join(' · ')
                  : 'Backend mode: ${engine['mode'] ?? 'unknown'}. Distribution is not live.';
        });
      }
    } on ProfitSharingApiException catch (exception) {
      if (mounted) {
        setState(() {
          _engine = null;
          _distributionLive = false;
          _engineError = exception.message;
          _readiness = 'Activation status could not be verified. Distribution is treated as not live.';
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _engine = null;
          _distributionLive = false;
          _engineError = 'Engine status request timed out.';
          _readiness = 'Activation status could not be verified. Distribution is treated as not live.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _engine = null;
          _distributionLive = false;
          _engineError = 'Unable to verify backend activation status.';
          _readiness = 'Activation status could not be verified. Distribution is treated as not live.';
        });
      }
    } finally {
      if (mounted) setState(() => _engineLoading = false);
    }
  }

  List<String> _engineBlockers([Map<String, dynamic>? source]) {
    final Map<String, dynamic>? engine = source ?? _engine;
    if (engine == null) return const <String>['Backend engine status unavailable.'];
    final List<String> blockers = <String>[];
    final dynamic storage = engine['storageBlockers'];
    if (storage is List) {
      blockers.addAll(storage.map((dynamic value) => value.toString()));
    }
    final dynamic services = engine['services'];
    if (services is List) {
      for (final dynamic rawService in services) {
        if (rawService is! Map) continue;
        final Map<String, dynamic> item = Map<String, dynamic>.from(rawService);
        final dynamic rawBlockers = item['blockers'];
        if (rawBlockers is List) {
          for (final dynamic blocker in rawBlockers) {
            final String label =
                '${item['serviceType'] ?? 'Service'}: ${blocker.toString()}';
            if (!blockers.contains(label)) blockers.add(label);
          }
        }
      }
    }
    if (engine['ready'] != true && blockers.isEmpty) {
      blockers.add('Backend readiness is not confirmed.');
    }
    return blockers;
  }

  void _populateCurrentRule() {
    final Map<String, dynamic>? current = _versions.isEmpty ? null : _versions.first;
    final dynamic rawPercentages = current?['percentages'];
    final Map<String, dynamic> percentages =
        rawPercentages is Map ? Map<String, dynamic>.from(rawPercentages) : <String, dynamic>{};
    final bool compatible = current != null &&
        current['policyVersion'] == 3 &&
        roleCodes.every(percentages.containsKey) &&
        percentages.keys.toSet().containsAll(roleCodes) &&
        percentages.keys.every(roleCodes.contains);
    _legacyCurrentRule = current != null && !compatible;
    for (final String role in roleCodes) {
      _percentControllers[role]!.text = compatible && percentages[role] != null
          ? percentages[role].toString()
          : '';
    }
    _enabled = current?['enabled'] is bool ? current!['enabled'] as bool : true;
    _reasonController.clear();
    _effectiveAt = null;
    _validationError = null;
    _frozenPayload = null;
    _pendingKey = null;
  }

  void _changeService(String? value) {
    if (value == null || value == _service) return;
    setState(() {
      _service = value;
      _populateCurrentRule();
    });
  }

  int get _remainingBasisPoints {
    final int assignedBasisPoints = roleCodes.fold<int>(
      0,
      (int sum, String role) {
        final double? percentage =
            double.tryParse(_percentControllers[role]!.text.trim());
        return sum + (percentage == null ? 0 : (percentage * 100).round());
      },
    );
    return 10000 - assignedBasisPoints;
  }

  double get _remainingPercentage => _remainingBasisPoints / 100;

  String? _validate() {
    if (roleCodes.any(
      (String role) => _percentControllers[role]!.text.trim().isEmpty,
    )) {
      return 'Set all four beneficiary percentages explicitly. Zero is allowed.';
    }
    for (final String role in roleCodes) {
      final String text = _percentControllers[role]!.text.trim();
      final double? number = double.tryParse(text);
      if (number == null || !number.isFinite || number < 0 || number > 100) {
        return 'Each beneficiary percentage must be between 0 and 100.';
      }
      if (text.contains('.') && text.split('.').last.length > 2) {
        return 'Beneficiary percentages can have at most two decimal places.';
      }
    }
    final int totalBasisPoints = roleCodes.fold<int>(
      0,
      (int sum, String role) =>
          sum + ((double.parse(_percentControllers[role]!.text.trim()) * 100).round()),
    );
    if (totalBasisPoints != 10000) {
      return 'The four beneficiary percentages must add up to exactly 100%.';
    }
    if (_effectiveAt == null || !_effectiveAt!.isAfter(DateTime.now())) {
      return 'Choose a future date and time for this rule.';
    }
    if (_reasonController.text.trim().length < 10) {
      return 'Add an audit reason of at least 10 characters.';
    }
    return null;
  }

  Map<String, dynamic> _buildPayload() {
    _pendingKey ??= 'profit-${DateTime.now().microsecondsSinceEpoch}-${_keySequence++}';
    return <String, dynamic>{
      'serviceType': _service,
      'revision': _selectedItem?['revision'] ?? 0,
      'idempotencyKey': _pendingKey,
      'confirmation': true,
      'reason': _reasonController.text.trim(),
      'effectiveAt': _effectiveAt!.toUtc().toIso8601String(),
      'enabled': _enabled,
      'percentages': <String, num>{
        for (final String role in roleCodes)
          role: num.parse(_percentControllers[role]!.text.trim()),
      },
    };
  }

  Future<void> _confirmAndSave() async {
    if (_saving || !_canManage || _frozenPayload != null) return;
    final String? issue = _validate();
    if (issue != null) {
      setState(() => _validationError = issue);
      return;
    }
    setState(() => _validationError = null);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Review future rule'),
        content: Text(
          'Save this ${serviceNames[_service] ?? _service} distribution rule for '
          '${_effectiveAt!.toLocal()}? This creates a future version only; it does not activate settlement.',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Review again')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm save')),
        ],
      ),
    );
    if (confirmed == true && mounted) await _save();
  }

  Future<void> _save() async {
    if (_saving) return;
    final Map<String, dynamic> payload = _frozenPayload ?? _buildPayload();
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> result = await _api.saveRule(payload);
      if (!mounted) return;
      final dynamic raw = result['data'];
      if (raw is Map) {
        final Map<String, dynamic> saved = Map<String, dynamic>.from(raw);
        final List<Map<String, dynamic>> items = _items;
        final int index = items.indexWhere((Map<String, dynamic> item) => item['serviceType'] == _service);
        final Map<String, dynamic> updated = <String, dynamic>{
          if (index >= 0) ...items[index],
          'serviceType': _service,
          'revision': saved['revision'] ?? _selectedItem?['revision'],
          'versions': saved['versions'] ?? _versions,
        };
        if (index >= 0) {
          items[index] = updated;
        } else {
          items.add(updated);
        }
        _data['items'] = items;
      }
      setState(() {
        _frozenPayload = null;
        _pendingKey = null;
        _reasonController.clear();
        _effectiveAt = null;
      });
      _populateCurrentRule();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Future rule saved. Distribution remains subject to platform readiness.')),
      );
    } on ProfitSharingApiException catch (exception) {
      if (!mounted) return;
      if (exception.isConflict) {
        setState(() {
          _frozenPayload = null;
          _pendingKey = null;
        });
        await _load();
        if (mounted) {
          setState(() => _error = 'A newer rule was saved elsewhere. Refresh complete — review the latest version before saving again.');
        }
      } else if (exception.statusCode != null &&
          exception.statusCode! >= 400 &&
          exception.statusCode! < 500) {
        setState(() {
          if (exception.isForbidden) _canManage = false;
          _frozenPayload = null;
          _pendingKey = null;
          _validationError = exception.message;
        });
      } else {
        setState(() {
          _frozenPayload = Map<String, dynamic>.from(payload);
          _validationError = 'Outcome is unknown. Your exact request is preserved; retry only after reviewing the status.';
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _frozenPayload = Map<String, dynamic>.from(payload);
          _validationError = 'Outcome is unknown after timeout. The exact request is preserved; retry will use the same key and values.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _frozenPayload = Map<String, dynamic>.from(payload);
          _validationError = 'Outcome is unknown. The exact request is preserved; retry will use the same key and values.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseDateTime() async {
    final DateTime now = DateTime.now();
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: _effectiveAt?.isAfter(now) == true
          ? _effectiveAt!
          : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (day == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: _effectiveAt == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(_effectiveAt!),
    );
    if (time == null) return;
    setState(() {
      _effectiveAt = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    });
  }

  String _dateLabel(DateTime? date) => date == null
      ? 'Choose future date and time'
      : '${date.toLocal().day.toString().padLeft(2, '0')}/'
          '${date.toLocal().month.toString().padLeft(2, '0')}/'
          '${date.toLocal().year} · '
          '${TimeOfDay.fromDateTime(date.toLocal()).format(context)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
        backgroundColor: paper,
        foregroundColor: ink,
        title: const Text(
          'Company Profit Sharing Configuration',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh settings',
            onPressed: _loading || _saving
                ? null
                : () => _load(keepEditor: _frozenPayload != null),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading && _data.isEmpty
            ? const _LoadingState()
            : _error != null && _data.isEmpty
                ? Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                        child: _readinessBanner(includeBlockers: true),
                      ),
                      Expanded(
                        child: _ErrorState(
                          message: _error!,
                          onRetry: () => _load(),
                        ),
                      ),
                    ],
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(keepEditor: _frozenPayload != null),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                      children: <Widget>[
                        _readinessBanner(),
                        if (_error != null) ...<Widget>[
                          const SizedBox(height: 12),
                          _InlineMessage(message: _error!, danger: true),
                        ],
                        const SizedBox(height: 22),
                        const Text('RULE DESIGN', style: TextStyle(color: green, letterSpacing: 1.4, fontSize: 11, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 5),
                         const Text('Configure company profit sharing.', style: TextStyle(color: ink, fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
                        const SizedBox(height: 6),
                         const Text('Share 100% of verified positive company net profit across four administrator-controlled rates. The Head Office share remains in company custody and is not credited to the current administrator’s personal wallet.', style: TextStyle(color: Color(0xFF60736A), height: 1.45)),
                        const SizedBox(height: 22),
                        _servicePicker(),
                        const SizedBox(height: 18),
                        _percentEditor(),
                        const SizedBox(height: 18),
                        _scheduleEditor(),
                        const SizedBox(height: 18),
                        _auditEditor(),
                        if (_validationError != null) ...<Widget>[
                          const SizedBox(height: 12),
                          _InlineMessage(message: _validationError!, danger: true),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: !_canManage || _saving
                                ? null
                                : _frozenPayload == null ? _confirmAndSave : _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: green,
                              disabledBackgroundColor: const Color(0xFFB8C9BC),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            icon: _saving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Icon(_frozenPayload == null ? Icons.save_outlined : Icons.replay_rounded),
                            label: Text(
                              _saving ? 'Saving rule…' : _frozenPayload == null ? 'Save rule' : 'Retry same request',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        if (!_canManage) ...<Widget>[
                          const SizedBox(height: 9),
                          const Text('Your account can review rules but cannot save changes.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64756C))),
                        ],
                        const SizedBox(height: 28),
                        _versionHistory(),
                        const SizedBox(height: 18),
                        ProfitSharingActivationPanel(
                          api: _api,
                          engine: _engine,
                          service: _service,
                          canManage: _canManage,
                          refreshStatus: _loadEngine,
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _readinessBanner({bool includeBlockers = false}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _distributionLive ? const Color(0xFFE4F3E8) : const Color(0xFFFFF1D9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _distributionLive ? const Color(0xFFC4E2CC) : const Color(0xFFEBD7AC)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(_distributionLive ? Icons.verified_outlined : Icons.pause_circle_outline_rounded,
                color: _distributionLive ? green : const Color(0xFF96651D)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                 Text(_distributionLive ? 'Distribution is LIVE' : 'Distribution is not live',
                    style: TextStyle(fontWeight: FontWeight.w900, color: _distributionLive ? ink : const Color(0xFF704A12))),
                const SizedBox(height: 4),
                Text(_readiness, style: const TextStyle(height: 1.4, color: Color(0xFF5B625B))),
                 if (includeBlockers && _engine != null &&
                     _engineBlockers().isNotEmpty)
                   Padding(
                     padding: const EdgeInsets.only(top: 7),
                     child: Text(
                       'Backend blockers: ${_engineBlockers().join(' · ')}',
                       style: const TextStyle(
                         color: Color(0xFF754333),
                         fontWeight: FontWeight.w700,
                         height: 1.35,
                       ),
                     ),
                   ),
                 if (_engineLoading)
                   const Padding(
                     padding: EdgeInsets.only(top: 7),
                     child: LinearProgressIndicator(minHeight: 2),
                   ),
                 if (_engineError != null)
                   Padding(
                     padding: const EdgeInsets.only(top: 7),
                     child: Text('Backend status error: $_engineError',
                         style: const TextStyle(color: Color(0xFF8F352E), fontWeight: FontWeight.w700)),
                   ),
                if (!_distributionLive)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Saving a rule does not activate payouts or settlement.', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF704A12))),
                  ),
              ]),
            ),
          ],
        ),
      );

  Widget _servicePicker() => _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const _SectionHeading(number: '01', title: 'Choose a service'),
          const SizedBox(height: 13),
          DropdownButtonFormField<String>(
            key: const ValueKey<String>('profit-sharing-service-selector'),
            value: _services.contains(_service) ? _service : null,
            decoration: const InputDecoration(labelText: 'Service', border: OutlineInputBorder()),
            items: _services.map((String value) => DropdownMenuItem<String>(
              value: value,
              child: Text(serviceNames[value] ?? value.replaceAll('_', ' ')),
            )).toList(),
            onChanged: _canManage && _frozenPayload == null ? _changeService : null,
          ),
          if (_selectedItem?['revision'] != null) ...<Widget>[
            const SizedBox(height: 8),
            Text('Current revision ${_selectedItem!['revision']}', style: const TextStyle(color: Color(0xFF738179), fontSize: 12)),
          ],
        ]),
      );

  Widget _percentEditor() => _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const _SectionHeading(number: '02', title: 'Set beneficiary percentages'),
          const SizedBox(height: 5),
          const Text('These four percentages divide verified positive company net profit and must total exactly 100%.', style: TextStyle(color: Color(0xFF728078), fontSize: 13)),
          if (_legacyCurrentRule) ...<Widget>[
            const SizedBox(height: 10),
            const _InlineMessage(
              message: 'Legacy rule: its former configuration is preserved in history but is not compatible with policy v3. No values were migrated. Enter all four percentages explicitly to create a new configuration.',
              danger: true,
            ),
          ],
          const SizedBox(height: 14),
          ...roleCodes.asMap().entries.map((MapEntry<int, String> entry) {
            final String role = entry.value;
            return Padding(
              padding: EdgeInsets.only(bottom: entry.key == roleCodes.length - 1 ? 0 : 11),
              child: TextField(
                key: ValueKey<String>('percentage-$role'),
                controller: _percentControllers[role],
                enabled: _canManage && _frozenPayload == null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(?:\.\d{0,2})?')),
                ],
                decoration: InputDecoration(
                  labelText: roleNames[role],
                  suffixText: '%',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _validationError = null),
              ),
            );
          }),
          const SizedBox(height: 13),
          Container(
            key: const ValueKey<String>('profit-sharing-remaining-percentage'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5EF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              'Remaining unallocated: ${_remainingPercentage.toStringAsFixed(2)}%',
              style: const TextStyle(
                color: Color(0xFF44554A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 13),
          const Text('The Head Office allocation is held in company custody, not in the current administrator’s personal wallet.', style: TextStyle(color: Color(0xFF728078), fontSize: 12, height: 1.4)),
          const SizedBox(height: 13),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            activeTrackColor: green,
            title: const Text('Rule enabled', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Applies to this requested future rule only; it does not turn settlement on.'),
            onChanged: _canManage && _frozenPayload == null ? (bool value) => setState(() => _enabled = value) : null,
          ),
        ]),
      );

  Widget _scheduleEditor() => _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const _SectionHeading(number: '03', title: 'Set effective date'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _canManage && _frozenPayload == null ? _chooseDateTime : null,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(_dateLabel(_effectiveAt), overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: ink,
              side: const BorderSide(color: Color(0xFFD3DED5)),
            ),
          ),
          const SizedBox(height: 8),
          const Text('The date must be in the future. A saved version is not a payout activation.', style: TextStyle(color: Color(0xFF728078), fontSize: 12, height: 1.4)),
        ]),
      );

  Widget _auditEditor() => _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const _SectionHeading(number: '04', title: 'Record the reason'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey<String>('profit-sharing-audit-reason'),
            controller: _reasonController,
            enabled: _canManage && _frozenPayload == null,
            maxLines: 3,
            maxLength: 240,
            decoration: const InputDecoration(
              hintText: 'Why is this distribution changing?',
              helperText: 'At least 10 characters. Stored with the audit history.',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() => _validationError = null),
          ),
        ]),
      );

  Widget _versionHistory() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            const Expanded(child: Text('Version history', style: TextStyle(fontSize: 19, color: ink, fontWeight: FontWeight.w900))),
            Text('${_versions.length} ${_versions.length == 1 ? 'version' : 'versions'}', style: const TextStyle(color: Color(0xFF77847D), fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          if (_versions.isEmpty)
            const _Panel(
              child: Row(children: <Widget>[
                Icon(Icons.history_rounded, color: Color(0xFF7B8B81)),
                SizedBox(width: 11),
                Expanded(child: Text('No saved rule for this service yet. Percentages are intentionally blank.', style: TextStyle(height: 1.4, color: Color(0xFF63736A)))),
              ]),
            )
          else
            ..._versions.map((Map<String, dynamic> version) => _VersionCard(version: version)),
        ],
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFCFDFB),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFE1E9E1)),
          boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x080E3018), blurRadius: 16, offset: Offset(0, 5))],
        ),
        child: child,
      );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.number, required this.title});
  final String number;
  final String title;
  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
        Container(
          width: 27,
          height: 27,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFFE6F2E8), borderRadius: BorderRadius.circular(9)),
          child: Text(number, style: const TextStyle(color: Color(0xFF168A3A), fontSize: 11, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(title, style: const TextStyle(color: Color(0xFF263C31), fontSize: 16, fontWeight: FontWeight.w900))),
      ]);
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message, required this.danger});
  final String message;
  final bool danger;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: danger ? const Color(0xFFFFE8E5) : const Color(0xFFE4F3E8), borderRadius: BorderRadius.circular(13)),
        child: Text(message, style: TextStyle(color: danger ? const Color(0xFF8F352E) : const Color(0xFF27573A), height: 1.4)),
      );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(18),
        children: List<Widget>.generate(5, (int index) => Container(
          height: index == 0 ? 90 : 120,
          margin: const EdgeInsets.only(bottom: 13),
          decoration: BoxDecoration(color: const Color(0xFFE5ECE5), borderRadius: BorderRadius.circular(17)),
        )),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Icon(Icons.cloud_off_outlined, size: 38, color: Color(0xFF829087)),
            const SizedBox(height: 12),
            const Text('Settings could not load', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ]),
        ),
      );
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.version});
  final Map<String, dynamic> version;

  @override
  Widget build(BuildContext context) {
    final dynamic rawPercentages = version['percentages'];
    final Map<String, dynamic> percentages = rawPercentages is Map
        ? Map<String, dynamic>.from(rawPercentages)
        : <String, dynamic>{};
    final dynamic rawPrevious = version['previousPercentages'];
    final Map<String, dynamic> previousPercentages = rawPrevious is Map
        ? Map<String, dynamic>.from(rawPrevious)
        : <String, dynamic>{};
    final bool previousCompatible =
        ProfitSharingSettingsScreenRole.isCompatible(previousPercentages);
    final String date = version['effectiveAt']?.toString() ?? 'Date not recorded';
    final String created = version['createdAt']?.toString() ?? '';
    final String creator = version['createdBy']?.toString() ?? '';
    final bool legacy = version['policyVersion'] != 3 ||
        !ProfitSharingSettingsScreenRole.isCompatible(percentages);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: const Color(0xFFFCFDFB), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E9E1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text('Version ${version['id'] ?? '—'}', style: const TextStyle(color: Color(0xFF263C31), fontWeight: FontWeight.w900))),
          _StatusChip(enabled: version['enabled'] == true),
        ]),
        if (legacy) ...<Widget>[
          const SizedBox(height: 8),
          const _InlineMessage(
            message: 'Legacy version — preserved as recorded in backend history, but its former beneficiary layout is hidden here and is not compatible with current activation policy.',
            danger: true,
          ),
        ],
        if (!legacy) ...<Widget>[
          const SizedBox(height: 7),
          Text('Policy v${version['policyVersion']} · 100% of verified positive company net profit',
              style: const TextStyle(color: Color(0xFF52645A), fontWeight: FontWeight.w800, fontSize: 12)),
        ],
        const SizedBox(height: 7),
        Text('Effective $date', style: const TextStyle(color: Color(0xFF69776F), fontSize: 12)),
        if (created.isNotEmpty)
          Text(
            creator.isEmpty ? 'Recorded $created' : 'Recorded $created · $creator',
            style: const TextStyle(color: Color(0xFF87928B), fontSize: 11),
          ),
        if (!legacy) ...<Widget>[
          const SizedBox(height: 10),
          const Text('New configuration', style: TextStyle(color: Color(0xFF168A3A), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
          const SizedBox(height: 5),
          _percentageRows(percentages),
          const SizedBox(height: 10),
          const Text('Previous configuration', style: TextStyle(color: Color(0xFF168A3A), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
          const SizedBox(height: 5),
          if (previousCompatible)
            _percentageRows(previousPercentages)
          else
            const Text(
              'Unavailable — the prior configuration was legacy or not policy v3 compatible.',
              style: TextStyle(color: Color(0xFF69776F), fontSize: 12),
            ),
        ],
        if ((version['reason']?.toString() ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text('Reason', style: TextStyle(color: const Color(0xFF168A3A), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
          const SizedBox(height: 2),
          Text(version['reason'].toString(), style: const TextStyle(color: Color(0xFF52645A), height: 1.4)),
        ],
      ]),
    );
  }

  Widget _percentageRows(Map<String, dynamic> percentages) => Wrap(
        spacing: 7,
        runSpacing: 7,
        children: ProfitSharingSettingsScreenRole.supported.map(
          (String role) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5EF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '${_roleNames[role]}: ${percentages[role]}%',
              style: const TextStyle(
                color: Color(0xFF44554A),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ).toList(),
      );

  static const Map<String, String> _roleNames = <String, String>{
    'HEAD_OFFICE': 'Head Office',
    'ZONAL_MANAGER': 'Zonal Managers',
    'STATE_MANAGER': 'State Managers',
    'AGGREGATOR': 'Aggregator',
  };
}

class ProfitSharingSettingsScreenRole {
  static const List<String> supported = <String>[
    'HEAD_OFFICE',
    'ZONAL_MANAGER',
    'STATE_MANAGER',
    'AGGREGATOR',
  ];

  static bool isCompatible(Map<String, dynamic> percentages) =>
      percentages.keys.toSet().containsAll(supported) &&
      percentages.keys.every(supported.contains) &&
      supported.every((String role) => percentages[role] is num);
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.enabled});
  final bool enabled;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: enabled ? const Color(0xFFE4F3E8) : const Color(0xFFF0EFEB), borderRadius: BorderRadius.circular(20)),
        child: Text(enabled ? 'Enabled' : 'Disabled', style: TextStyle(color: enabled ? const Color(0xFF2C7041) : const Color(0xFF69736C), fontSize: 11, fontWeight: FontWeight.w800)),
      );
}
