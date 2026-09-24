import 'dart:async';

import 'package:flutter/material.dart';

import 'phase1_operations_api.dart';

/// Paginated, read-only drill-down through the current reporting relationships.
class HierarchyDownlineDialog extends StatefulWidget {
  const HierarchyDownlineDialog({super.key, required this.api});

  final Phase1OperationsApi api;

  @override
  State<HierarchyDownlineDialog> createState() => _HierarchyDownlineDialogState();
}

class _HierarchyDownlineDialogState extends State<HierarchyDownlineDialog> {
  final TextEditingController _search = TextEditingController();
  final List<Map<String, dynamic>> _trail = [];
  Timer? _debounce;
  int _generation = 0;
  int _page = 1;
  int _pages = 0;
  bool _loading = true;
  bool _directCustomers = false;
  String _error = '';
  List<Map<String, dynamic>> _users = [];

  Map<String, dynamic>? get _parent => _trail.isEmpty ? null : _trail.last;

  String get _role {
    switch ('${_parent?['role'] ?? ''}') {
      case 'ZONAL_MANAGER':
        return 'STATE_MANAGER';
      case 'STATE_MANAGER':
        return _directCustomers ? 'CUSTOMER' : 'AGENT';
      case 'AGENT':
        return 'CUSTOMER';
      default:
        return 'ZONAL_MANAGER';
    }
  }

  String get _roleLabel {
    switch (_role) {
      case 'ZONAL_MANAGER':
        return 'Zonal Managers';
      case 'STATE_MANAGER':
        return 'State Managers';
      case 'AGENT':
        return 'Aggregators';
      default:
        return 'Customers';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final role = _role;
    final parentId = '${_parent?['_id'] ?? ''}';
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final response = await widget.api.hierarchyUsers(
        role: role,
        parentId: parentId,
        search: _search.text,
        includeInactive: true,
        page: _page,
        limit: 25,
      );
      if (!mounted || generation != _generation) return;
      final raw = response['users'];
      final pagination = response['pagination'];
      setState(() {
        _users = raw is List
            ? raw.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
            : [];
        _pages = pagination is Map
            ? int.tryParse('${pagination['pages'] ?? 0}') ?? 0
            : 0;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  void _navigate(List<Map<String, dynamic>> trail, {bool direct = false}) {
    _debounce?.cancel();
    setState(() {
      _trail
        ..clear()
        ..addAll(trail);
      _directCustomers = direct;
      _page = 1;
      _search.clear();
    });
    _load();
  }

  void _select(Map<String, dynamic> user) {
    if (_role == 'CUSTOMER') return;
    _navigate([..._trail, user]);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Reporting chain'),
        content: SizedBox(
          width: 760,
          height: 610,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select a Zonal Manager, then a State Manager and '
                  'Aggregator to view each assigned downline.'),
              const SizedBox(height: 12),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: _trail.isEmpty ? null : () => _navigate([]),
                    child: const Text('Head Office'),
                  ),
                  ..._trail.map((item) =>
                    TextButton(
                      onPressed: identical(item, _trail.last) && !_directCustomers
                          ? null
                          : () => _navigate(_trail.take(_trail.indexOf(item) + 1).toList()),
                      child: Text('${item['fullName'] ?? 'Unnamed'}'),
                    ),
                  ),
                ],
              ),
              if (_parent?['role'] == 'STATE_MANAGER')
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Aggregators'),
                      selected: !_directCustomers,
                      onSelected: (_) => _navigate([..._trail]),
                    ),
                    ChoiceChip(
                      label: const Text('Direct customers'),
                      selected: _directCustomers,
                      onSelected: (_) => _navigate([..._trail], direct: true),
                    ),
                  ],
                ),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: 'Search $_roleLabel',
                  hintText: 'Name, phone, email or user ID',
                ),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 450), () {
                    _page = 1;
                    _load();
                  });
                },
              ),
              const SizedBox(height: 12),
              Text(_roleLabel, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error.isNotEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Unable to load reporting chain: $_error'),
                                TextButton(onPressed: _load, child: const Text('Retry')),
                              ],
                            ),
                          )
                        : _users.isEmpty
                            ? const Center(child: Text('No users in this reporting line.'))
                            : ListView.builder(
                                itemCount: _users.length,
                                itemBuilder: (context, index) {
                                  final user = _users[index];
                                  final name = '${user['fullName'] ?? 'Unnamed'}';
                                  return ListTile(
                                    leading: CircleAvatar(child: Text(name.substring(0, 1).toUpperCase())),
                                    title: Text(name),
                                    subtitle: Text(
                                      '${user['phone'] ?? ''} · ${user['state'] ?? user['zone'] ?? ''}'
                                      '${user['status'] == 'ACTIVE' ? '' : ' · ${user['status'] ?? 'INACTIVE'}'}',
                                    ),
                                    trailing: _role == 'CUSTOMER'
                                        ? null
                                        : const Icon(Icons.chevron_right),
                                    onTap: _role == 'CUSTOMER' ? null : () => _select(user),
                                  );
                                },
                              ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: _page > 1 && !_loading
                        ? () {
                            _page--;
                            _load();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('Page $_page of ${_pages == 0 ? 1 : _pages}'),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: _page < _pages && !_loading
                        ? () {
                            _page++;
                            _load();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
}