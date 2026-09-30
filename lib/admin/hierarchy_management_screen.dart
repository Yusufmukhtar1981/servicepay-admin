import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'admin_permissions.dart';
import 'hierarchy_downline_dialog.dart';
import 'phase1_operations_api.dart';

/// Head Office's safe, explicit reporting-chain assignment surface.
class HierarchyManagementScreen extends StatefulWidget {
  const HierarchyManagementScreen({
    super.key,
    required this.role,
    required this.permissions,
    this.api,
    this.initialRole,
    this.initialSearch = '',
  });

  final String role;
  final Set<String> permissions;
  final Phase1OperationsApi? api;
  final String? initialRole;
  final String initialSearch;

  @override
  State<HierarchyManagementScreen> createState() =>
      _HierarchyManagementScreenState();
}

class _HierarchyManagementScreenState extends State<HierarchyManagementScreen> {
  late final Phase1OperationsApi _api = widget.api ?? Phase1OperationsApi();
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  late String _selectedRole = widget.initialRole ?? 'STATE_MANAGER';
  String _error = '';
  bool _loading = true;
  bool _saving = false;
  bool _reviewing = false;
  String? _pendingAssignmentIntent;
  String? _pendingAssignmentRequestId;
  List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];

  static const List<Map<String, String>> _roleOptions = <Map<String, String>>[
    {
      'role': 'STATE_MANAGER',
      'label': 'State Manager',
      'parent': 'ZONAL_MANAGER'
    },
    {'role': 'AGENT', 'label': 'Aggregator', 'parent': 'STATE_MANAGER'},
    {'role': 'CUSTOMER', 'label': 'Customer', 'parent': 'AGENT'},
  ];

  bool get _canManage {
    final AdminAccess access =
        AdminAccess(role: widget.role, permissions: widget.permissions);
    return access.hasHeadOfficePermission(AdminPermissions.hierarchyManage);
  }

  String get _parentRole => _roleOptions.firstWhere(
      (Map<String, String> item) => item['role'] == _selectedRole)['parent']!;

  String _text(Map<String, dynamic> item, String key, [String fallback = '—']) {
    final String value = '${item[key] ?? ''}'.trim();
    return value.isEmpty ? fallback : value;
  }

  String _name(Map<String, dynamic> item) =>
      _text(item, 'fullName', 'Unnamed user');
  String _id(Map<String, dynamic> item) =>
      _text(item, '_id', _text(item, 'id', ''));

  @override
  void initState() {
    super.initState();
    _search.text = widget.initialSearch;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final String query = _search.text.trim();
      final Map<String, dynamic> users = await _api.roleUsers(
        role: _selectedRole,
        search: query,
      );
      List<Map<String, dynamic>> parse(dynamic raw) {
        return raw is List
            ? raw
                .whereType<Map>()
                .map((Map value) => Map<String, dynamic>.from(value))
                .toList()
            : <Map<String, dynamic>>[];
      }

      if (!mounted) return;
      setState(() {
        _users = parse(users['users']);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _load);
  }

  Future<void> _assign(Map<String, dynamic> user) async {
    if (!_canManage || _saving || _reviewing) return;
    final String userId = _id(user);
    if (userId.isEmpty) {
      _snack('This user has no assignable ID.', error: true);
      return;
    }
    setState(() => _reviewing = true);
    try {
      final Map<String, dynamic> detailResponse = await _api.roleUser(userId);
      final dynamic rawTarget = detailResponse['user'];
      if (rawTarget is! Map) {
        throw Exception('Unable to read this user’s current reporting line.');
      }
      final Map<String, dynamic> target = Map<String, dynamic>.from(rawTarget);
      final String directParentId =
          _idForRole(target, _parentRoleFor(_selectedRole));
      target['_currentParentId'] = directParentId;
      final Map<String, Map<String, dynamic>> lineage =
          <String, Map<String, dynamic>>{};
      for (final String field in const <String>[
        'zonalManagerId',
        'stateManagerId',
        'agentId'
      ]) {
        final String ancestorId = _text(target, field, '');
        if (ancestorId.isEmpty || lineage.containsKey(ancestorId)) continue;
        try {
          final Map<String, dynamic> response = await _api.roleUser(ancestorId);
          final dynamic rawAncestor = response['user'];
          if (rawAncestor is Map) {
            lineage[ancestorId] = Map<String, dynamic>.from(rawAncestor);
          }
        } on Phase1OperationsException catch (error) {
          // Keep the immutable IDs visible even when a former parent was
          // deleted or can no longer be loaded.
          lineage[ancestorId] = <String, dynamic>{
            '_id': ancestorId,
            'fullName': 'Unavailable parent',
            'role': _parentRoleFor(_selectedRole),
            '_loadError': error.message,
          };
        }
      }
      target['currentParent'] = lineage[directParentId];
      target['lineage'] = lineage;
      final Map<String, dynamic>? parent = await _chooseParent(target);
      if (parent == null) return;

      final TextEditingController reason = TextEditingController();
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(directParentId.isEmpty
              ? 'Confirm assignment'
              : 'Confirm reassignment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${_roleLabel(_selectedRole)}: ${_name(target)}'),
              const SizedBox(height: 8),
              ..._lineageRows(target),
              const Divider(height: 20),
              Text(
                  'New $_parentRoleLabel: ${_name(parent)} (${_text(parent, '_id', '')})'),
              const SizedBox(height: 16),
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Why is this reporting line changing?',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Older transactions without verified creation-time hierarchy '
                'history may block this change. Existing financial history is '
                'never reassigned.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().length < 10) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Enter a reason of at least 10 characters.')),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save assignment'),
            ),
          ],
        ),
      );
      final String reasonText = reason.text.trim();
      Future<void>.delayed(const Duration(milliseconds: 350), reason.dispose);
      if (confirmed != true) return;

      if (mounted) setState(() => _saving = true);
      final String assignmentIntent =
          '$userId|${_id(parent)}|$directParentId|$reasonText';
      if (_pendingAssignmentIntent != assignmentIntent) {
        _pendingAssignmentIntent = assignmentIntent;
        _pendingAssignmentRequestId =
            '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
      }
      final Map<String, dynamic> result = await _api.assignRoleUser(
        userId: userId,
        parentId: _id(parent),
        expectedParentId: directParentId.isEmpty ? null : directParentId,
        reason: reasonText,
        requestId: _pendingAssignmentRequestId!,
      );
      _pendingAssignmentIntent = null;
      _pendingAssignmentRequestId = null;
      if (!mounted) return;
      final dynamic updated = result['user'];
      final String assignedName = updated is Map
          ? _text(Map<String, dynamic>.from(updated), 'fullName', _name(target))
          : _name(target);
      _snack(
          '$assignedName was assigned to ${_name(parent)}. The change was audited.');
      await _load();
    } catch (error) {
      if (mounted) _snack(_assignmentError(error), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _reviewing = false;
        });
      }
    }
  }

  String _parentRoleFor(String role) => _roleOptions.firstWhere(
      (Map<String, String> item) => item['role'] == role)['parent']!;

  String _idForRole(Map<String, dynamic> user, String parentRole) {
    final String field = switch (parentRole) {
      'ZONAL_MANAGER' => 'zonalManagerId',
      'STATE_MANAGER' => 'stateManagerId',
      _ => 'agentId',
    };
    return _text(user, field, '');
  }

  String? _normalizedLocation(Map<String, dynamic> user, String field) {
    final String value = _text(user, field, '').trim();
    return value.isEmpty ? null : value.toUpperCase();
  }

  bool _locationMatchesWhenKnown(
    Map<String, dynamic> target,
    Map<String, dynamic> candidate,
    String field,
  ) {
    final String? targetLocation = _normalizedLocation(target, field);
    return targetLocation == null ||
        targetLocation == _normalizedLocation(candidate, field);
  }

  List<Widget> _lineageRows(
    Map<String, dynamic> target,
  ) {
    final Map<String, Map<String, dynamic>> lineage =
        <String, Map<String, dynamic>>{};
    final dynamic rawLineage = target['lineage'];
    if (rawLineage is Map) {
      for (final MapEntry<dynamic, dynamic> entry in rawLineage.entries) {
        if (entry.value is Map) {
          lineage['${entry.key}'] =
              Map<String, dynamic>.from(entry.value as Map);
        }
      }
    }
    final List<(String, String)> fields = <(String, String)>[
      ('Zonal Manager', 'zonalManagerId'),
      ('State Manager', 'stateManagerId'),
      ('Aggregator', 'agentId'),
    ];
    return <Widget>[
      const Text('Current reporting line',
          style: TextStyle(fontWeight: FontWeight.w700)),
      for (final (String label, String field) in fields)
        if ((target[field] ?? '').toString().trim().isNotEmpty)
          Text(
              '$label: ${_name(lineage['${target[field]}'] ?? <String, dynamic>{})}'
              ' (${target[field]})')
        else
          Text('$label: Not assigned'),
      if (_text(target, 'zone', '').isNotEmpty)
        Text('Zone: ${_text(target, 'zone')}'),
      if (_text(target, 'state', '').isNotEmpty)
        Text('State: ${_text(target, 'state')}'),
    ];
  }

  String _assignmentError(Object error) {
    if (error is Phase1OperationsException && error.statusCode == 409) {
      if (error.code == 'HIERARCHY_HISTORY_UNVERIFIED') {
        return 'Assignment blocked: this account has transactions without '
            'verified creation-time hierarchy history. Reconcile that history '
            'before changing the reporting line. No assignment was made.';
      }
      return '${error.message} No assignment was made.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<Map<String, dynamic>?> _chooseParent(Map<String, dynamic> user) async {
    String filter = '';
    Timer? debounce;
    final String currentParentId = _text(user, '_currentParentId', '');
    Future<Map<String, dynamic>> fetch() => _api.roleUsers(
          role: _parentRole,
          search: filter,
        );
    Future<Map<String, dynamic>> request = fetch();
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          return AlertDialog(
            title: Text('Select $_parentRoleLabel'),
            content: SizedBox(
              width: 560,
              height: 420,
              child: Column(
                children: <Widget>[
                  ..._lineageRows(user),
                  const Divider(height: 18),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search name, phone, email, state or zone',
                    ),
                    onChanged: (String value) {
                      debounce?.cancel();
                      debounce = Timer(const Duration(milliseconds: 400), () {
                        if (context.mounted) {
                          setDialogState(() {
                            filter = value;
                            request = fetch();
                          });
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: request,
                      builder:
                          (_, AsyncSnapshot<Map<String, dynamic>> snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                                'Unable to load managers: ${snapshot.error}'),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final dynamic raw = snapshot.data!['users'];
                        final List<Map<String, dynamic>> matches = raw is List
                            ? raw
                                .whereType<Map>()
                                .map((Map value) =>
                                    Map<String, dynamic>.from(value))
                                .toList()
                            : <Map<String, dynamic>>[];
                        final List<Map<String, dynamic>> eligible =
                            matches.where((Map<String, dynamic> candidate) {
                          if (_id(candidate) == currentParentId) return false;
                          if (_text(candidate, 'status', '').toUpperCase() !=
                              'ACTIVE') {
                            return false;
                          }
                          if (!_locationMatchesWhenKnown(
                              user, candidate, 'zone')) {
                            return false;
                          }
                          return _selectedRole == 'STATE_MANAGER' ||
                              _locationMatchesWhenKnown(
                                  user, candidate, 'state');
                        }).toList();
                        return Column(
                          children: <Widget>[
                            Expanded(
                              child: eligible.isEmpty
                                  ? const Center(
                                      child: Text(
                                          'No active parent with matching location was found.'))
                                  : ListView.separated(
                                      itemCount: eligible.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (_, int index) {
                                        final Map<String, dynamic> candidate =
                                              eligible[index];
                                        return ListTile(
                                          leading: CircleAvatar(
                                              child: Text(_name(candidate)
                                                  .substring(0, 1)
                                                  .toUpperCase())),
                                          title: Text(_name(candidate)),
                                          subtitle: Text(
                                              '${_text(candidate, 'phone')} · ${_text(candidate, 'email')}\n'
                                               '${_text(candidate, 'state', _text(candidate, 'zone'))}'),
                                          isThreeLine: true,
                                          onTap: () => Navigator.pop(
                                              dialogContext, candidate),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
            ],
          );
        },
      ),
    ).whenComplete(() => debounce?.cancel());
  }

  String get _parentRoleLabel {
    switch (_parentRole) {
      case 'ZONAL_MANAGER':
        return 'Zonal Manager';
      case 'STATE_MANAGER':
        return 'State Manager';
      case 'AGENT':
        return 'Aggregator';
      default:
        return 'Manager';
    }
  }

  String _roleLabel(String role) =>
      role == 'AGENT' ? 'Aggregator' : role.replaceAll('_', ' ');

  Future<void> _showHistory() async {
    final TextEditingController user = TextEditingController();
    final TextEditingController admin = TextEditingController();
    final TextEditingController from = TextEditingController();
    final TextEditingController to = TextEditingController();
    String role = _selectedRole;
    String type = '';
    int page = 1;
    Future<Map<String, dynamic>> fetch() => _api.hierarchyHistory(
          userId: user.text,
          role: role,
          actorId: admin.text,
          type: type,
          from: from.text,
          to: to.text,
          page: page,
          limit: 25,
        );
    Future<Map<String, dynamic>> request = fetch();
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          return AlertDialog(
            title: const Text('Hierarchy Assignment History'),
            content: SizedBox(
              width: 760,
              height: 620,
              child: Column(
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      SizedBox(
                          width: 220,
                          child: TextField(
                              controller: user,
                              decoration: const InputDecoration(
                                  labelText: 'User ID'))),
                      SizedBox(
                          width: 180,
                          child: TextField(
                              controller: admin,
                              decoration: const InputDecoration(
                                  labelText: 'Admin ID'))),
                      SizedBox(
                          width: 150,
                          child: TextField(
                              controller: from,
                              decoration: const InputDecoration(
                                  labelText: 'From (ISO date)'))),
                      SizedBox(
                          width: 150,
                          child: TextField(
                              controller: to,
                              decoration: const InputDecoration(
                                  labelText: 'To (ISO date)'))),
                      DropdownButton<String>(
                        value: role,
                        items: <String>[
                          '',
                          'STATE_MANAGER',
                          'AGENT',
                          'CUSTOMER'
                        ]
                            .map((String value) => DropdownMenuItem(
                                value: value,
                                child: Text(value.isEmpty
                                    ? 'All roles'
                                    : _roleLabel(value))))
                            .toList(),
                        onChanged: (String? value) => setDialogState(() {
                          role = value ?? '';
                          page = 1;
                          request = fetch();
                        }),
                      ),
                      DropdownButton<String>(
                        value: type,
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(
                              value: '', child: Text('All assignment types')),
                          DropdownMenuItem(
                              value: 'ASSIGNMENT', child: Text('Assignment')),
                          DropdownMenuItem(
                              value: 'REASSIGNMENT',
                              child: Text('Reassignment')),
                        ],
                        onChanged: (String? value) => setDialogState(() {
                          type = value ?? '';
                          page = 1;
                          request = fetch();
                        }),
                      ),
                      FilledButton.icon(
                          onPressed: () => setDialogState(() {
                            page = 1;
                            request = fetch();
                          }),
                          icon: const Icon(Icons.filter_alt),
                          label: const Text('Apply filters')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: request,
                      builder:
                          (_, AsyncSnapshot<Map<String, dynamic>> snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Unable to load history: ${snapshot.error}'),
                          );
                        }
                        if (!snapshot.hasData)
                          return const Center(
                              child: CircularProgressIndicator());
                        final dynamic raw = snapshot.data!['records'];
                        final List<Map<String, dynamic>> records = raw is List
                            ? raw
                                .whereType<Map>()
                                .map((Map value) =>
                                    Map<String, dynamic>.from(value))
                                .toList()
                            : <Map<String, dynamic>>[];
                        final dynamic pagination = snapshot.data!['pagination'];
                        final int totalPages = pagination is Map
                            ? int.tryParse(
                                    '${pagination['totalPages'] ?? pagination['pages'] ?? page}') ??
                                page
                            : page;
                        return Column(
                          children: <Widget>[
                            Expanded(
                              child: records.isEmpty
                                  ? const Center(
                                      child:
                                          Text('No assignment records found.'))
                                  : ListView.separated(
                                      itemCount: records.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (_, int index) {
                                        final Map<String, dynamic> record =
                                            records[index];
                                        return ListTile(
                                          dense: true,
                                          title: Text(
                                              '${_text(record, 'targetUserName')} · ${_roleLabel(_text(record, 'affectedRole'))}'),
                                          subtitle: Text(
                                              '${_text(record, 'previousParentName', 'Unassigned')} → ${_text(record, 'newParentName', 'Unassigned')}\n${_text(record, 'reason')} · ${_text(record, 'actorName')} · ${_text(record, 'createdAt')}'),
                                        );
                                      },
                                    ),
                            ),
                            Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  IconButton(
                                      onPressed: page > 1
                                           ? () => setDialogState(() {
                                               page--;
                                               request = fetch();
                                             })
                                          : null,
                                      icon: const Icon(Icons.chevron_left)),
                                  Text('Page $page of $totalPages'),
                                  IconButton(
                                      onPressed: page < totalPages
                                           ? () => setDialogState(() {
                                               page++;
                                               request = fetch();
                                             })
                                          : null,
                                      icon: const Icon(Icons.chevron_right)),
                                ]),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'))
            ],
          );
        },
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      user.dispose();
      admin.dispose();
      from.dispose();
      to.dispose();
    });
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor:
              error ? Colors.red.shade800 : Colors.green.shade800));
  }

  @override
  Widget build(BuildContext context) {
    if (!_canManage) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
              'Hierarchy Management requires Head Office access and hierarchy.manage.'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Hierarchy Management',
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w800)),
                    SizedBox(height: 6),
                    Text(
                        'Move current reporting lines without changing roles or historical financial ownership.'),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => HierarchyDownlineDialog(api: _api),
                    ),
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('View reporting chain'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showHistory,
                    icon: const Icon(Icons.history),
                    label: const Text('Assignment history'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: <Widget>[
                  _chainNode('Zonal Manager', Icons.public),
                  const Icon(Icons.arrow_forward, size: 18),
                  _chainNode('State Manager', Icons.location_city),
                  const Icon(Icons.arrow_forward, size: 18),
                  _chainNode('Aggregator', Icons.groups),
                  const Icon(Icons.arrow_forward, size: 18),
                  _chainNode('Customer', Icons.person),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: _roleOptions
                .map((Map<String, String> item) => ButtonSegment<String>(
                      value: item['role']!,
                      label: Text(item['label']!),
                    ))
                .toList(),
            selected: <String>{_selectedRole},
            onSelectionChanged: (Set<String> value) {
              setState(() => _selectedRole = value.first);
              _load();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: _searchChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: 'Search ${_roleLabel(_selectedRole)}s',
              hintText: 'Name, phone, email, state or zone',
              suffixIcon: IconButton(
                  onPressed: () {
                    _search.clear();
                    _load();
                  },
                  icon: const Icon(Icons.clear)),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const LinearProgressIndicator()
          else if (_error.isNotEmpty)
            Card(
                child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Unable to load hierarchy users'),
              subtitle: Text(_error),
              trailing:
                  TextButton(onPressed: _load, child: const Text('Retry')),
            ))
          else if (_users.isEmpty)
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: Text('No matching users found.'))))
          else
            ..._users.map(_userTile),
          if (_reviewing && !_saving)
            const Card(
              child: ListTile(
                leading: Icon(Icons.manage_search),
                title: Text('Loading verified current reporting line…'),
              ),
            ),
          if (_saving)
            const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator()),
        ],
      ),
    );
  }

  Widget _userTile(Map<String, dynamic> user) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
            child: Text(_name(user).substring(0, 1).toUpperCase())),
        title: Text(_name(user),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${_text(user, 'phone')} · ${_text(user, 'email')}\n'
            '${_text(user, 'zone', '').isEmpty ? '' : 'Zone: ${_text(user, 'zone')} · ' }'
            '${_text(user, 'state', '').isEmpty ? '' : 'State: ${_text(user, 'state')} · ' }'
            'Review to inspect the verified current reporting line'),
        isThreeLine: true,
        trailing: FilledButton.tonal(
          onPressed: _saving || _reviewing ? null : () => _assign(user),
          child:
              const Text('Review / assign'),
        ),
      ),
    );
  }

  Widget _chainNode(String label, IconData icon) =>
      Chip(avatar: Icon(icon, size: 18), label: Text(label));
}
