import 'package:flutter/material.dart';

import 'admin_marketplace_screen.dart';
import 'admin_staff_workspace_api.dart';

typedef JsonMap = Map<String, dynamic>;

JsonMap _jsonMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<JsonMap> _jsonRows(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList()
    : <JsonMap>[];

String _display(dynamic value) =>
    value == null || '$value'.trim().isEmpty ? 'Not recorded' : '$value';

class OperationalHubScreen extends StatefulWidget {
  const OperationalHubScreen({super.key, required this.api});
  final AdminStaffWorkspaceApi api;

  @override
  State<OperationalHubScreen> createState() => _OperationalHubScreenState();
}

class _OperationalHubScreenState extends State<OperationalHubScreen> {
  JsonMap _data = {};
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final result = await widget.api.operationalHub();
      if (mounted) setState(() => _data = _jsonMap(result['data']));
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _metric(String label, dynamic count, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(icon, color: const Color(0xff167461)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(count is num ? count.toInt().toString() : '—',
                        style: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w800)),
                  ]),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final customers = _jsonMap(_data['customers']);
    final deliveries = _jsonMap(_data['deliveries']);
    final products = _jsonMap(_data['products']);
    final staff = _jsonMap(_data['staff']);
    final permissions = _jsonMap(_data['permissions']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Operations overview',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xff173e35),
                  fontWeight: FontWeight.w800,
                )),
        const SizedBox(height: 4),
        const Text('Live counts returned by the operational hub.'),
        if (_error.isNotEmpty)
          _WorkspaceError(message: _error, retry: _load)
        else if (_loading && _data.isEmpty)
          const _WorkspaceLoading()
        else ...[
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _metric('Customers', customers['total'], Icons.people_outline),
            _metric(
                'Active customers', customers['active'], Icons.person_outline),
            _metric('Inactive customers', customers['inactive'],
                Icons.person_off_outlined),
            _metric(
                'Zonal managers', staff['ZONAL_MANAGER'], Icons.map_outlined),
            _metric('State managers', staff['STATE_MANAGER'],
                Icons.location_city_outlined),
            _metric('Aggregators', staff['AGGREGATOR'], Icons.hub_outlined),
          ]),
          _CountGroup(title: 'Deliveries by status', counts: deliveries),
          _CountGroup(
              title: 'Marketplace products by status', counts: products),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Workspace access',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 9),
                    for (final entry in permissions.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Icon(
                              entry.value == true
                                  ? Icons.check_circle_outline
                                  : Icons.remove_circle_outline,
                              size: 17,
                              color: entry.value == true
                                  ? const Color(0xff167461)
                                  : const Color(0xff84958c)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(entry.key)),
                          Text(entry.value == true ? 'Granted' : 'Not granted'),
                        ]),
                      ),
                  ]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _CountGroup extends StatelessWidget {
  const _CountGroup({required this.title, required this.counts});
  final String title;
  final JsonMap counts;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (counts.isEmpty)
              const Text('No status counts were returned.')
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final entry in counts.entries)
                  Chip(
                    label: Text(
                        '${entry.key.replaceAll('_', ' ')} · ${entry.value is num ? (entry.value as num).toInt() : '—'}'),
                  ),
              ]),
          ]),
        ),
      );
}

class DirectoryOperationsScreen extends StatefulWidget {
  const DirectoryOperationsScreen({
    super.key,
    required this.api,
    required this.role,
    this.parentId,
  });
  final AdminStaffWorkspaceApi api;
  final String role;
  final String? parentId;

  @override
  State<DirectoryOperationsScreen> createState() =>
      _DirectoryOperationsScreenState();
}

class _DirectoryOperationsScreenState extends State<DirectoryOperationsScreen> {
  final TextEditingController _search = TextEditingController();
  List<JsonMap> _items = [];
  int _page = 1;
  int _pages = 1;
  int _total = 0;
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({int? page}) async {
    setState(() {
      _loading = true;
      _error = '';
      if (page != null) _page = page;
    });
    try {
      final result = await widget.api.directory(
        role: widget.role,
        parentId: widget.parentId,
        query: _search.text,
        page: _page,
      );
      final data = _jsonMap(result['data']);
      if (mounted) {
        setState(() {
          _items = _jsonRows(data['items']);
          _total = data['total'] is num ? (data['total'] as num).toInt() : 0;
          _page = data['page'] is num ? (data['page'] as num).toInt() : _page;
          _pages = data['pages'] is num
              ? (data['pages'] as num).toInt().clamp(1, 999999)
              : 1;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(widget.role.replaceAll('_', ' '),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xff173e35),
                    fontWeight: FontWeight.w800,
                  )),
          const SizedBox(height: 4),
          const Text(
              'Assignments shown only when populated by the directory service.'),
          const Text('Head Office → Zonal Managers → State Managers → Aggregators'),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(page: 1),
            decoration: InputDecoration(
              labelText: 'Search name, phone or email',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: () => _load(page: 1),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('$_total records · page $_page of $_pages',
              style: const TextStyle(color: Color(0xff64776d), fontSize: 12)),
          if (_error.isNotEmpty)
            _WorkspaceError(message: _error, retry: _load)
          else if (_loading && _items.isEmpty)
            const _WorkspaceLoading()
          else if (_items.isEmpty)
            const _WorkspaceEmpty(
                title: 'No directory records',
                message: 'No matching staff records were returned.')
          else
            ..._items.map((person) {
              final zonal = _jsonMap(person['zonalManagerId']);
              final state = _jsonMap(person['stateManagerId']);
              final isAggregator = widget.role == 'AGGREGATOR';
              return Card(
                margin: const EdgeInsets.only(top: 9),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xffe3eee7),
                                child: Icon(Icons.person_outline,
                                    color: Color(0xff167461)),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(_display(person['fullName']),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    Text(
                                        '${_display(person['status'])} · ${_display(person['phone'])}'),
                                    Text(_display(person['email']),
                                        style: const TextStyle(fontSize: 12)),
                                  ])),
                            ]),
                        const Divider(height: 22),
                        Wrap(spacing: 8, runSpacing: 6, children: [
                          _DirectoryTag('Zone', person['zone']),
                          _DirectoryTag('State', person['state']),
                          _DirectoryTag('LGA', person['lga']),
                        ]),
                        if (isAggregator) ...[
                          const SizedBox(height: 8),
                          Text(
                              'Zonal manager · ${_display(zonal['fullName'])}'),
                          Text(
                              'State manager · ${_display(state['fullName'])}'),
                        ],
                        if (!isAggregator && person['zonalManagerId'] != null)
                          Text(
                              'Zonal manager · ${_display(zonal['fullName'])}'),
                        if (!isAggregator)
                          TextButton.icon(
                            icon: const Icon(Icons.account_tree_outlined),
                            label: Text(widget.role == 'ZONAL_MANAGER'
                                ? 'View assigned State Managers'
                                : 'View assigned Aggregators'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: Text(_display(person['fullName']))),
                                  body: DirectoryOperationsScreen(
                                    api: widget.api,
                                    role: widget.role == 'ZONAL_MANAGER'
                                        ? 'STATE_MANAGER' : 'AGGREGATOR',
                                    parentId: '${person['_id']}',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (!isAggregator && person['stateManagerId'] != null)
                          Text(
                              'State manager · ${_display(state['fullName'])}'),
                        const SizedBox(height: 5),
                        Text('Created · ${_display(person['createdAt'])}',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xff71847a))),
                      ]),
                ),
              );
            }),
          if (!_loading && _pages > 1)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: _page > 1 ? () => _load(page: _page - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$_page / $_pages'),
              IconButton(
                tooltip: 'Next page',
                onPressed: _page < _pages ? () => _load(page: _page + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
        ]),
      );
}

class _DirectoryTag extends StatelessWidget {
  const _DirectoryTag(this.label, this.value);
  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) => Chip(
        visualDensity: VisualDensity.compact,
        label: Text('$label · ${_display(value)}'),
      );
}

class ActivityOperationsScreen extends StatefulWidget {
  const ActivityOperationsScreen({super.key, required this.api});
  final AdminStaffWorkspaceApi api;

  @override
  State<ActivityOperationsScreen> createState() =>
      _ActivityOperationsScreenState();
}

class _ActivityOperationsScreenState extends State<ActivityOperationsScreen> {
  String _period = 'day';
  int _page = 1;
  int _pages = 1;
  int _total = 0;
  bool _loading = true;
  String _error = '';
  List<JsonMap> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? page}) async {
    setState(() {
      _loading = true;
      _error = '';
      if (page != null) _page = page;
    });
    try {
      final result = await widget.api.activity(period: _period, page: _page);
      final data = _jsonMap(result['data']);
      if (mounted) {
        setState(() {
          _items = _jsonRows(data['items']);
          _total = data['total'] is num ? (data['total'] as num).toInt() : 0;
          _page = data['page'] is num ? (data['page'] as num).toInt() : _page;
          _pages = data['pages'] is num
              ? (data['pages'] as num).toInt().clamp(1, 999999)
              : 1;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Activity logs',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xff173e35),
                    fontWeight: FontWeight.w800,
                  )),
          const Text('Audited actions returned by the operations service.'),
          const SizedBox(height: 10),
          Row(children: [
            const Text('Period'),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _period,
              items: const [
                DropdownMenuItem(value: 'day', child: Text('Day')),
                DropdownMenuItem(value: 'week', child: Text('Week')),
                DropdownMenuItem(value: 'month', child: Text('Month')),
                DropdownMenuItem(value: 'year', child: Text('Year')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _period = value);
                _load(page: 1);
              },
            ),
            const Spacer(),
            Text('$_total records'),
          ]),
          if (_error.isNotEmpty)
            _WorkspaceError(message: _error, retry: _load)
          else if (_loading && _items.isEmpty)
            const _WorkspaceLoading()
          else if (_items.isEmpty)
            const _WorkspaceEmpty(
                title: 'No activity recorded',
                message: 'No entries were returned for this period.')
          else
            ..._items.map((item) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading:
                        const Icon(Icons.history, color: Color(0xff167461)),
                    title: Text(_display(item['action']),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${_display(item['actorName'])} · ${_display(item['createdAt'])}\n'
                        'Target · ${_display(item['targetUserName'])}'
                        '${item['reason'] == null ? '' : '\nReason · ${item['reason']}'}'),
                    isThreeLine: true,
                  ),
                )),
          if (!_loading && _pages > 1)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: _page > 1 ? () => _load(page: _page - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$_page / $_pages'),
              IconButton(
                tooltip: 'Next page',
                onPressed: _page < _pages ? () => _load(page: _page + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
        ]),
      );
}

class MarketplaceOperationsScreen extends StatefulWidget {
  const MarketplaceOperationsScreen({
    super.key,
    required this.api,
    required this.canModerate,
  });
  final AdminStaffWorkspaceApi api;
  final bool canModerate;

  @override
  State<MarketplaceOperationsScreen> createState() =>
      _MarketplaceOperationsScreenState();
}

class _MarketplaceOperationsScreenState
    extends State<MarketplaceOperationsScreen> {
  final TextEditingController _search = TextEditingController();
  String _kind = 'sellers';
  int _page = 1;
  int _pages = 1;
  int _total = 0;
  bool _loading = true;
  String _error = '';
  List<JsonMap> _items = [];
  static const _statuses = ['PENDING', 'ACTIVE', 'SUSPENDED', 'REJECTED'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({int? page}) async {
    setState(() {
      _loading = true;
      _error = '';
      if (page != null) _page = page;
    });
    try {
      final result = await widget.api.marketplaceOperations(
        kind: _kind,
        query: _search.text,
        page: _page,
      );
      final data = _jsonMap(result['data']);
      if (mounted) {
        setState(() {
          _items = _jsonRows(data['items']);
          _total = data['total'] is num ? (data['total'] as num).toInt() : 0;
          _page = data['page'] is num ? (data['page'] as num).toInt() : _page;
          _pages = data['pages'] is num
              ? (data['pages'] as num).toInt().clamp(1, 999999)
              : 1;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeStatus(JsonMap seller) async {
    final current = '${seller['status'] ?? 'PENDING'}'.toUpperCase();
    final reasonController = TextEditingController();
    String next = current;
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Update seller status'),
          content: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: _statuses.contains(next) ? next : 'PENDING',
                decoration: const InputDecoration(labelText: 'New status'),
                items: _statuses
                    .map((status) =>
                        DropdownMenuItem(value: status, child: Text(status)))
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => next = value ?? next),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Reason', border: OutlineInputBorder()),
                validator: (value) =>
                    (value?.trim().length ?? 0) < 4 ? 'Enter a reason.' : null,
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => form.currentState!.validate()
                  ? Navigator.pop(context, true)
                  : null,
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (accepted != true) return;
    try {
      await widget.api.updateMarketplaceSellerStatus(
        '${seller['_id']}',
        status: next,
        expectedStatus: current,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seller status updated.')));
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Marketplace approvals',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xff173e35),
                    fontWeight: FontWeight.w800,
                  )),
          const Text(
              'Seller and order records. No financial actions are available here.'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: const Text('Sellers'),
              selected: _kind == 'sellers',
              onSelected: (_) {
                setState(() => _kind = 'sellers');
                _load(page: 1);
              },
            ),
            ChoiceChip(
              label: const Text('Orders'),
              selected: _kind == 'orders',
              onSelected: (_) {
                setState(() => _kind = 'orders');
                _load(page: 1);
              },
            ),
            if (widget.canModerate)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const AdminMarketplaceScreen(
                            requireReason: true,
                          )),
                ),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Product moderation'),
              ),
          ]),
          const SizedBox(height: 9),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(page: 1),
            decoration: InputDecoration(
              labelText: 'Search ${_kind == 'sellers' ? 'sellers' : 'orders'}',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: () => _load(page: 1),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text('$_total records · page $_page of $_pages',
              style: const TextStyle(fontSize: 12, color: Color(0xff64776d))),
          if (_error.isNotEmpty)
            _WorkspaceError(message: _error, retry: _load)
          else if (_loading && _items.isEmpty)
            const _WorkspaceLoading()
          else if (_items.isEmpty)
            const _WorkspaceEmpty(
                title: 'No marketplace records',
                message: 'No matching sellers or orders were returned.')
          else if (_kind == 'sellers')
            ..._items.map((seller) => Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(_display(seller['storeName']),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                            ),
                            Chip(label: Text(_display(seller['status']))),
                          ]),
                          Text(
                              '${_display(seller['phone'])} · ${_display(seller['email'])}'),
                          Text('State · ${_display(seller['state'])}'),
                          if (widget.canModerate)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _changeStatus(seller),
                                icon: const Icon(Icons.fact_check_outlined),
                                label: const Text('Change status'),
                              ),
                            ),
                        ]),
                  ),
                ))
          else
            ..._items.map((order) => Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    leading: const Icon(Icons.shopping_bag_outlined),
                    title: Text(_display(order['orderReference']),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                        '${_display(order['customerName'])} · ${_display(order['status'])}\n'
                        '${_display(order['createdAt'])}'),
                    trailing: Text(order['totalAmount'] == null
                        ? 'Amount unavailable'
                        : '₦${order['totalAmount']}'),
                    isThreeLine: true,
                  ),
                )),
          if (!_loading && _pages > 1)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: _page > 1 ? () => _load(page: _page - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$_page / $_pages'),
              IconButton(
                tooltip: 'Next page',
                onPressed: _page < _pages ? () => _load(page: _page + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
          if (!widget.canModerate)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                  'Seller status controls require marketplaceModerate permission.',
                  style: TextStyle(fontSize: 12, color: Color(0xff64776d))),
            ),
        ]),
      );
}

class CustomerProfileEditForm extends StatefulWidget {
  const CustomerProfileEditForm({
    super.key,
    required this.api,
    this.initialCustomer = const <String, dynamic>{},
  });
  final AdminStaffWorkspaceApi api;
  final JsonMap initialCustomer;

  @override
  State<CustomerProfileEditForm> createState() =>
      _CustomerProfileEditFormState();
}

class _CustomerProfileEditFormState extends State<CustomerProfileEditForm> {
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _id.text =
        '${widget.initialCustomer['_id'] ?? widget.initialCustomer['id'] ?? ''}';
    _name.text = '${widget.initialCustomer['fullName'] ?? ''}';
    _address.text = '${widget.initialCustomer['address'] ?? ''}';
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _address.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_id.text.trim().isEmpty ||
        _name.text.trim().isEmpty ||
        _address.text.trim().isEmpty ||
        _reason.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter customer ID, name, address and a reason.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final response = await widget.api.updateCustomerProfile(
        _id.text.trim(),
        fullName: _name.text.trim(),
        address: _address.text.trim(),
        reason: _reason.text.trim(),
      );
      final user = _jsonMap(_jsonMap(response['data'])['user']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Profile updated for ${_display(user['fullName'])}.')));
        _reason.clear();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
              controller: _id,
              decoration: const InputDecoration(labelText: 'Customer ID')),
          TextField(
              controller: _name,
              decoration:
                  const InputDecoration(labelText: 'Updated full name')),
          TextField(
              controller: _address,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Updated address')),
          const SizedBox(height: 8),
          TextField(
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Phone and email · read-only',
              hintText: 'Contact Head Office for verification',
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Phone and email remain read-only. Contact Head Office for verification and any contact-detail correction.',
              style: TextStyle(fontSize: 12, color: Color(0xff64776d)),
            ),
          ),
          TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: 'Reason for audited change')),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Update profile'),
            ),
          ),
        ],
      );
}

class _WorkspaceError extends StatelessWidget {
  const _WorkspaceError({required this.message, required this.retry});
  final String message;
  final Future<void> Function() retry;

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xfffff3ee),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(message),
            TextButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry')),
          ]),
        ),
      );
}

class _WorkspaceLoading extends StatelessWidget {
  const _WorkspaceLoading();

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < 3; i++)
          Card(
            child: Container(
              height: 68,
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xffe5eee8),
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
      ]);
}

class _WorkspaceEmpty extends StatelessWidget {
  const _WorkspaceEmpty({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Icon(Icons.inbox_outlined,
                size: 32, color: Color(0xff668075)),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(message, textAlign: TextAlign.center),
          ]),
        ),
      );
}
