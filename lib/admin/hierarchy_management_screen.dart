import 'dart:async';

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
      final Map<String, dynamic> users = await _api.hierarchyUsers(
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

  String _parentName(Map<String, dynamic> user) {
    final dynamic parent = user['currentParent'];
    if (parent is Map)
      return _text(Map<String, dynamic>.from(parent), 'fullName');
    return 'Unassigned';
  }

  Future<void> _assign(Map<String, dynamic> user) async {
    if (!_canManage || _saving) return;
    final String userId = _id(user);
    if (userId.isEmpty) {
      _snack('This user has no assignable ID.', error: true);
      return;
    }
    final Map<String, dynamic>? parent = await _chooseParent(user);
    if (parent == null) return;
    final TextEditingController reason = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_parentName(user) == 'Unassigned'
            ? 'Confirm assignment'
            : 'Confirm reassignment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${_roleLabel(_selectedRole)}: ${_name(user)}'),
            const SizedBox(height: 8),
            Text(
                '${_parentRoleLabel}: ${_parentName(user)} → ${_name(parent)}'),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Why is this reporting line changing?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Only the current reporting relationship changes. Role, wallet, '
              'transactions and historical records remain unchanged.',
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
              if (reason.text.trim().length < 5) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                      content:
                          Text('Enter a reason of at least 5 characters.')),
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
    // showDialog completes before its reverse transition has removed the
    // TextField. Disposing its controller immediately can rebuild that field
    // outside the active dialog's build scope.
    Future<void>.delayed(const Duration(milliseconds: 350), reason.dispose);
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> result = await _api.assignHierarchy(
        userId: userId,
        parentId: _id(parent),
        reason: reasonText,
        requestId: 'hierarchy-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      _snack(result['duplicate'] == true
          ? 'Assignment already exists; no change was made.'
          : 'Assignment saved and recorded in audit history.');
      await _load();
    } catch (error) {
      if (mounted)
        _snack(error.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Map<String, dynamic>?> _chooseParent(Map<String, dynamic> user) async {
    String filter = '';
    int page = 1;
    Timer? debounce;
    Future<Map<String, dynamic>> fetch() => _api.hierarchyUsers(
          role: _parentRole,
          search: filter,
          page: page,
          limit: 25,
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
                            page = 1;
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
                            child: Text('Unable to load managers: ${snapshot.error}'),
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
                        final dynamic pagination = snapshot.data!['pagination'];
                        final int totalPages = pagination is Map
                            ? int.tryParse(
                                    '${pagination['totalPages'] ?? pagination['pages'] ?? page}') ??
                                page
                            : page;
                        return Column(
                          children: <Widget>[
                            Expanded(
                              child: matches.isEmpty
                                  ? const Center(
                                      child:
                                          Text('No valid active parent found.'))
                                  : ListView.separated(
                                      itemCount: matches.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (_, int index) {
                                        final Map<String, dynamic> candidate =
                                            matches[index];
                                        final dynamic currentParent =
                                            user['currentParent'];
                                        final String currentId = currentParent
                                                is Map
                                            ? '${currentParent['_id'] ?? ''}'
                                            : '';
                                        final bool current =
                                            _id(candidate) == currentId;
                                        return ListTile(
                                          leading: CircleAvatar(
                                              child: Text(_name(candidate)
                                                  .substring(0, 1)
                                                  .toUpperCase())),
                                          title: Text(_name(candidate)),
                                          subtitle: Text(
                                              '${_text(candidate, 'phone')} · ${_text(candidate, 'email')}\n'
                                              '${_text(candidate, 'state', _text(candidate, 'zone'))}'
                                              '${current ? ' · Current parent' : ''}'),
                                          isThreeLine: true,
                                          onTap: () => Navigator.pop(
                                              dialogContext, candidate),
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
                              ],
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
      default:
        return 'Aggregator';
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
              hintText: 'Name, phone, email or user ID',
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
            'Current $_parentRoleLabel: ${_parentName(user)}'
            '${_text(user, 'state', '').isEmpty ? '' : ' · ${_text(user, 'state')}'}'),
        isThreeLine: true,
        trailing: FilledButton.tonal(
          onPressed: _saving ? null : () => _assign(user),
          child:
              Text(_parentName(user) == 'Unassigned' ? 'Assign' : 'Reassign'),
        ),
      ),
    );
  }

  Widget _chainNode(String label, IconData icon) =>
      Chip(avatar: Icon(icon, size: 18), label: Text(label));
}
