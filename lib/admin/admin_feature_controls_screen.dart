import 'package:flutter/material.dart';

import 'admin_feature_controls_api.dart';
import 'admin_permissions.dart';

/// Head Office's customer-facing feature registry.
///
/// The registry route is preferred, while the legacy fintech-control response
/// remains a read/write fallback during a rolling backend deployment.
class AdminFeatureControlsScreen extends StatefulWidget {
  const AdminFeatureControlsScreen({super.key, this.api});

  final AdminFeatureControlsApi? api;

  @override
  State<AdminFeatureControlsScreen> createState() =>
      _AdminFeatureControlsScreenState();
}

class _AdminFeatureControlsScreenState
    extends State<AdminFeatureControlsScreen> {
  late final AdminFeatureControlsApi _api =
      widget.api ?? AdminFeatureControlsApi();
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _search = TextEditingController();
  List<FeatureControl> _saved = <FeatureControl>[];
  List<FeatureControl> _draft = <FeatureControl>[];
  Map<String, int> _metrics = <String, int>{};
  Map<String, dynamic> _sync = <String, dynamic>{};
  final Set<String> _selected = <String>{};
  String _category = 'All categories';
  String _status = 'All statuses';
  bool _loading = true;
  bool _saving = false;
  bool _canManage = false;
  bool _canProtectedManage = false;
  bool _legacyMode = false;
  String? _error;

  bool get _changed => _draft.any((feature) {
        final old = _findSaved(feature.key);
        return old == null ||
            old.enabled != feature.enabled ||
            old.visible != feature.visible ||
            old.maintenanceMode != feature.maintenanceMode ||
            old.maintenanceMessage != feature.maintenanceMessage ||
            old.scheduledEnabledAt != feature.scheduledEnabledAt ||
            old.scheduledDisabledAt != feature.scheduledDisabledAt;
      });

  FeatureControl? _findSaved(String key) {
    for (final feature in _saved) {
      if (feature.key == key) return feature;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_refreshView);
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _search
      ..removeListener(_refreshView)
      ..dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final access = await AdminSessionStore.loadAccess();
      final registry = await _api.loadRegistry();
      if (!mounted) return;
      setState(() {
        _canManage = access.canManageFeatureControls;
        _canProtectedManage = access.canProtectedManageFeatureControls;
        _saved = List<FeatureControl>.from(registry.features);
        _draft = List<FeatureControl>.from(registry.features);
        _metrics = Map<String, int>.from(registry.metrics);
        _sync = Map<String, dynamic>.from(registry.sync);
        _legacyMode = !_sync.containsKey('source');
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _refreshView() => setState(() {});

  List<FeatureControl> get _visibleFeatures {
    final query = _search.text.trim().toLowerCase();
    return _draft.where((feature) {
      final matchesQuery = query.isEmpty ||
          feature.displayName.toLowerCase().contains(query) ||
          feature.key.toLowerCase().contains(query);
      final matchesCategory =
          _category == 'All categories' || feature.category == _category;
      final matchesStatus = switch (_status) {
        'Enabled' => feature.available,
        'Disabled' => !feature.available,
        'Visible' => feature.visible,
        'Hidden' => !feature.visible,
        'Maintenance' => feature.maintenanceMode,
        _ => true,
      };
      return matchesQuery && matchesCategory && matchesStatus;
    }).toList();
  }

  List<String> get _categories => <String>{
        'All categories',
        ..._draft.map((feature) => feature.category),
      }.toList()
        ..sort();

  void _update(String key, FeatureControl Function(FeatureControl) change) {
    setState(() {
      _draft = _draft
          .map((feature) => feature.key == key ? change(feature) : feature)
          .toList();
    });
  }

  Future<void> _save() async {
    if (!_canManage || !_changed || _saving) return;
    final reason = _reason.text.trim();
    if (reason.length < 10) {
      _message('Provide a reason of at least 10 characters.');
      return;
    }
    final changed = _draft.where((feature) {
      final old = _findSaved(feature.key);
      return old != null &&
          (old.enabled != feature.enabled ||
              old.visible != feature.visible ||
              old.maintenanceMode != feature.maintenanceMode ||
              old.maintenanceMessage != feature.maintenanceMessage ||
              old.scheduledEnabledAt != feature.scheduledEnabledAt ||
              old.scheduledDisabledAt != feature.scheduledDisabledAt);
    }).toList();
    final protectedChanged =
        changed.where((feature) => feature.isProtected).toList();
    if (protectedChanged.isNotEmpty && !_canProtectedManage) {
      _message('Protected feature-control permission is required.');
      return;
    }
    final confirmed = await _confirm(
      title: 'Confirm feature-control changes',
      content: changed
          .map(
            (feature) =>
                '${feature.displayName}: ${feature.available ? "Enabled" : "Disabled"} · '
                '${feature.visible ? "Visible" : "Hidden"}',
          )
          .join('\n'),
      protectedChange: protectedChanged.isNotEmpty,
      expectedConfirmation:
          protectedChanged.map((feature) => feature.key).join(','),
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      if (_legacyMode) {
        await _api.save(
          <String, bool>{
            for (final feature in _draft) feature.key: feature.enabled
          },
          reason,
        );
      } else {
        var current = _draft;
        for (final feature in changed) {
          final updated = await _api.patchFeature(
            feature.key,
            <String, dynamic>{
              'enabled': feature.enabled,
              'visible': feature.visible,
              'maintenanceMode': feature.maintenanceMode,
              'maintenanceMessage': feature.maintenanceMessage,
              'scheduledEnabledAt':
                  feature.scheduledEnabledAt?.toUtc().toIso8601String(),
              'scheduledDisabledAt':
                  feature.scheduledDisabledAt?.toUtc().toIso8601String(),
            },
            reason,
            protectedConfirmation: feature.isProtected,
            confirmationText: feature.isProtected ? feature.key : null,
          );
          current = current
              .map((value) => value.key == updated.key ? updated : value)
              .toList();
        }
        _draft = current;
      }
      if (!mounted) return;
      setState(() {
        _saved = List<FeatureControl>.from(_draft);
        _reason.clear();
      });
      _message('Feature Controls saved.');
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required bool protectedChange,
    String expectedConfirmation = '',
  }) async {
    final confirmation = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(content),
              const SizedBox(height: 16),
              const Text(
                'Changes are applied to customer access after the server accepts them.',
              ),
              if (protectedChange) ...<Widget>[
                const SizedBox(height: 12),
                const Text(
                  'This includes a protected feature. Type the feature key to confirm.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextField(
                  key: const ValueKey<String>(
                    'feature-control-protected-confirmation',
                  ),
                  controller: confirmation,
                  decoration: const InputDecoration(
                    labelText: 'Protected confirmation',
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () {
              if (protectedChange &&
                  confirmation.text.trim() != expectedConfirmation) {
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('CONFIRM CHANGES'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    confirmation.dispose();
    return result == true;
  }

  Future<void> _bulk(String action) async {
    final selected =
        _draft.where((feature) => _selected.contains(feature.key)).toList();
    if (!_canManage || selected.isEmpty) return;
    final reason = await _reasonDialog('Bulk ${action.toLowerCase()}');
    if (reason == null) return;
    final protectedSelected =
        selected.where((feature) => feature.isProtected).toList();
    if (protectedSelected.isNotEmpty && !_canProtectedManage) {
      _message('Protected feature-control permission is required.');
      return;
    }
    if (protectedSelected.isNotEmpty) {
      final confirmed = await _confirm(
        title: 'Confirm protected bulk change',
        content:
            '${selected.map((feature) => feature.displayName).join(", ")}\n\n'
            'This action changes protected feature access.',
        protectedChange: true,
        expectedConfirmation:
            protectedSelected.map((feature) => feature.key).join(','),
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final result = await _api.bulk(
        selected.map((feature) => feature.key).toList(),
        action,
        reason,
        protectedConfirmation: protectedSelected.isNotEmpty,
        confirmationText:
            protectedSelected.map((feature) => feature.key).join(','),
      );
      if (!mounted) return;
      setState(() {
        _draft = result.features;
        _saved = result.features;
        _metrics = result.metrics;
        _selected.clear();
      });
      _message('Bulk feature control saved.');
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _reasonDialog(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Required audit reason',
            hintText: 'Explain this operational change.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length >= 10) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('CONTINUE'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _configure(FeatureControl feature) async {
    final message = TextEditingController(text: feature.maintenanceMessage);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Configure ${feature.displayName}'),
        content: TextField(
          controller: message,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Customer maintenance message',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, message.text.trim()),
            child: const Text('APPLY'),
          ),
        ],
      ),
    );
    message.dispose();
    if (result != null) {
      _update(
        feature.key,
        (value) => _copy(value, maintenanceMessage: result),
      );
    }
  }

  Future<void> _schedule(FeatureControl feature) async {
    final start = await _pickTimestamp(
      initial: feature.scheduledDisabledAt ?? DateTime.now(),
      helpText: 'Disable at',
    );
    if (start == null || !mounted) return;
    final end = await _pickTimestamp(
      initial:
          feature.scheduledEnabledAt ?? start.add(const Duration(hours: 1)),
      helpText: 'Re-enable at',
      firstDate: DateTime(start.year, start.month, start.day),
    );
    if (!mounted) return;
    if (end != null && !end.isAfter(start)) {
      _message('Re-enable time must be after the disable time.');
      return;
    }
    _update(
      feature.key,
      (value) => _copy(
        value,
        scheduledDisabledAt: start,
        scheduledEnabledAt: end,
      ),
    );
  }

  Future<DateTime?> _pickTimestamp({
    required DateTime initial,
    required String helpText,
    DateTime? firstDate,
  }) async {
    final now = DateTime.now();
    final minimum = firstDate ?? DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      firstDate: minimum,
      lastDate: DateTime(now.year + 1, now.month, now.day),
      initialDate: initial.isBefore(minimum) ? minimum : initial,
      helpText: helpText,
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: '$helpText time',
    );
    if (time == null || !mounted) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _showAudit(FeatureControl feature) async {
    try {
      final rows = await _api.audit(featureKey: feature.key);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${feature.displayName} history'),
          content: SizedBox(
            width: 520,
            child: rows.isEmpty
                ? const Text('No changes have been recorded for this feature.')
                : ListView(
                    shrinkWrap: true,
                    children: rows
                        .map(
                          (row) => ListTile(
                            dense: true,
                            title: Text((row['reason'] ?? 'Change').toString()),
                            subtitle: Text(
                              '${row['actorName'] ?? 'Admin'} · '
                              '${row['createdAt'] ?? ''}',
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _message(error.toString());
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feature Controls'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Reload Feature Controls',
            onPressed: _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: <Widget>[
                      _hero(),
                      const SizedBox(height: 18),
                      _metricsBar(),
                      const SizedBox(height: 18),
                      _filters(),
                      if (_selected.isNotEmpty) _bulkBar(),
                      const SizedBox(height: 12),
                      ..._visibleFeatures.map(_featureCard),
                      if (_visibleFeatures.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text('No features match these filters.'),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _reasonAndSave(),
                    ],
                  ),
                ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('TRY AGAIN')),
            ],
          ),
        ),
      );

  Widget _hero() {
    final healthy = _sync['healthy'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Feature Control Center',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Customer experience, at a glance',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _canManage
                  ? 'Control availability and visibility without a redeploy. '
                      'Every change requires an audit reason.'
                  : 'You have read-only access. Only authorized administrators '
                      'can save changes.',
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  healthy ? Icons.check_circle : Icons.info_outline,
                  size: 17,
                  color: healthy ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    healthy
                        ? 'Configuration API healthy · database settings source'
                        : 'Sync status unavailable; no health claim is made',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricsBar() {
    final values = <List<dynamic>>[
      <dynamic>[
        'Total Features',
        _metrics['total'] ?? _draft.length,
        Icons.grid_view,
      ],
      <dynamic>[
        'Enabled',
        _metrics['enabled'] ?? _draft.where((f) => f.available).length,
        Icons.check_circle_outline,
      ],
      <dynamic>[
        'Disabled',
        _metrics['disabled'] ?? _draft.where((f) => !f.available).length,
        Icons.pause_circle_outline,
      ],
      <dynamic>[
        'Hidden',
        _metrics['hidden'] ?? _draft.where((f) => !f.visible).length,
        Icons.visibility_off_outlined,
      ],
      <dynamic>[
        'Maintenance',
        _metrics['maintenance'] ??
            _draft.where((f) => f.maintenanceMode).length,
        Icons.build_outlined,
      ],
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columns = constraints.maxWidth >= 900
            ? 5
            : constraints.maxWidth >= 600
                ? 3
                : 2;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: values
              .map(
                (item) => SizedBox(
                  width: width,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: <Widget>[
                          Icon(item[2] as IconData),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '${item[1]}',
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(item[0] as String),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _filters() => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          SizedBox(
            width: 280,
            child: SearchBar(
              controller: _search,
              leading: const Icon(Icons.search),
              hintText: 'Search features',
            ),
          ),
          _dropdown(
            _category,
            _categories,
            (value) => setState(() => _category = value!),
          ),
          _dropdown(
            _status,
            const <String>[
              'All statuses',
              'Enabled',
              'Disabled',
              'Visible',
              'Hidden',
              'Maintenance',
            ],
            (value) => setState(() => _status = value!),
          ),
        ],
      );

  Widget _dropdown(
    String value,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) =>
      DropdownButton<String>(
        value: values.contains(value) ? value : values.first,
        items: values
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
      );

  Widget _bulkBar() => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: <Widget>[
              Text('${_selected.length} selected'),
              for (final action in const <String>[
                'ENABLE',
                'DISABLE',
                'SHOW',
                'HIDE',
              ])
                OutlinedButton(
                  onPressed: _saving ? null : () => _bulk(action),
                  child: Text(action),
                ),
            ],
          ),
        ),
      );

  Widget _featureCard(FeatureControl feature) {
    final selected = _selected.contains(feature.key);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Checkbox(
                  value: selected,
                  onChanged: _canManage
                      ? (_) => setState(
                            () => selected
                                ? _selected.remove(feature.key)
                                : _selected.add(feature.key),
                          )
                      : null,
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Icon(_icon(feature.category))),
                    title: Text(
                      feature.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${feature.category} · ${feature.description}',
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                children: <Widget>[
                  _badge(
                    feature.available ? 'Enabled' : 'Disabled',
                    feature.available ? Colors.green : Colors.orange,
                  ),
                  _badge(
                    feature.visible ? 'Visible' : 'Hidden',
                    feature.visible ? Colors.blue : Colors.grey,
                  ),
                  if (feature.isProtected)
                    _badge('Protected', Colors.deepPurple),
                ],
              ),
            ),
            SwitchListTile(
              key: ValueKey<String>('feature-control-enabled-${feature.key}'),
              title: Text(feature.displayName),
              subtitle: Text(
                feature.available
                    ? 'Availability enabled'
                    : feature.maintenanceMode
                        ? feature.maintenanceMessage
                        : 'Temporarily unavailable',
              ),
              value: feature.enabled,
              onChanged: _canManage && !_saving
                  ? (value) => _update(
                        feature.key,
                        (old) => _copy(old, enabled: value),
                      )
                  : null,
            ),
            if (feature.maintenanceMode)
              ListTile(
                dense: true,
                leading: const Icon(Icons.build_outlined),
                title: const Text('Maintenance mode'),
                subtitle: Text(feature.maintenanceMessage),
              ),
            OverflowBar(
              children: <Widget>[
                TextButton.icon(
                  onPressed: _canManage
                      ? () => _update(
                            feature.key,
                            (old) => _copy(old, visible: !old.visible),
                          )
                      : null,
                  icon: Icon(
                    feature.visible ? Icons.visibility_off : Icons.visibility,
                  ),
                  label: Text(feature.visible ? 'Hide' : 'Show'),
                ),
                TextButton.icon(
                  onPressed: _canManage
                      ? () => _update(
                            feature.key,
                            (old) => _copy(
                              old,
                              maintenanceMode: !old.maintenanceMode,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.build_outlined),
                  label: Text(
                    feature.maintenanceMode ? 'End maintenance' : 'Maintenance',
                  ),
                ),
                TextButton.icon(
                  onPressed: _canManage ? () => _configure(feature) : null,
                  icon: const Icon(Icons.tune),
                  label: const Text('Configure'),
                ),
                TextButton.icon(
                  onPressed: _canManage ? () => _schedule(feature) : null,
                  icon: const Icon(Icons.schedule),
                  label: const Text('Schedule'),
                ),
                TextButton.icon(
                  onPressed: () => _showAudit(feature),
                  icon: const Icon(Icons.history),
                  label: const Text('Audit history'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _reasonAndSave() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const ValueKey<String>('feature-control-reason'),
            controller: _reason,
            enabled: _canManage && !_saving,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Audit reason',
              hintText: 'Explain why these service controls are changing.',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _canManage && _changed && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('SAVE FEATURE CONTROLS'),
          ),
        ],
      );

  Widget _badge(String label, Color color) => Chip(
        label: Text(label),
        labelStyle: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
        visualDensity: VisualDensity.compact,
      );

  IconData _icon(String category) => switch (category) {
        'Payments' => Icons.payments_outlined,
        'Money' => Icons.account_balance_wallet_outlined,
        'Business & Community' => Icons.business_outlined,
        'Lifestyle & Services' => Icons.auto_awesome_outlined,
        _ => Icons.tune,
      };

  FeatureControl _copy(
    FeatureControl value, {
    bool? enabled,
    bool? visible,
    bool? maintenanceMode,
    String? maintenanceMessage,
    DateTime? scheduledEnabledAt,
    DateTime? scheduledDisabledAt,
  }) =>
      FeatureControl(
        key: value.key,
        displayName: value.displayName,
        category: value.category,
        description: value.description,
        enabled: enabled ?? value.enabled,
        effectiveEnabled: value.effectiveEnabled,
        visible: visible ?? value.visible,
        maintenanceMode: maintenanceMode ?? value.maintenanceMode,
        maintenanceTitle: value.maintenanceTitle,
        maintenanceMessage: maintenanceMessage ?? value.maintenanceMessage,
        scope: value.scope,
        scheduledEnabledAt: scheduledEnabledAt ?? value.scheduledEnabledAt,
        scheduledDisabledAt: scheduledDisabledAt ?? value.scheduledDisabledAt,
        expectedReturnAt: value.expectedReturnAt,
        minimumAppVersion: value.minimumAppVersion,
        updatedAt: value.updatedAt,
        updatedBy: value.updatedBy,
        isProtected: value.isProtected,
      );
}
