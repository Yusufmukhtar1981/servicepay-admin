import 'package:flutter/material.dart';

import 'admin_staff_workspace_api.dart';
import 'admin_customer_support_screen.dart';

class OperationsManagerDashboard extends StatefulWidget {
  const OperationsManagerDashboard({super.key, this.api});
  final AdminStaffWorkspaceApi? api;
  @override
  State<OperationsManagerDashboard> createState() =>
      _OperationsManagerDashboardState();
}

class _OperationsManagerDashboardState
    extends State<OperationsManagerDashboard> {
  late final AdminStaffWorkspaceApi _api =
      widget.api ?? AdminStaffWorkspaceApi();
  Map<String, dynamic> _data = {};
  bool _loading = true;
  bool _transactionsLoading = false;
  String _error = '';
  String _transactionError = '';
  String _statusFilter = '';
  String _typeFilter = '';
  int _transactionPage = 1;
  int _transactionTotal = 0;
  List<Map<String, dynamic>> _transactionRows = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadTransactions();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final Map<String, dynamic> result = await _api.overview();
      final dynamic raw = result['data'];
      if (!mounted) return;
      setState(() => _data = raw is Map ? Map<String, dynamic>.from(raw) : {});
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTransactions({int page = 1}) async {
    setState(() {
      _transactionsLoading = true;
      _transactionError = '';
      _transactionPage = page;
    });
    try {
      final Map<String, dynamic> response = await _api.transactions(
        status: _statusFilter,
        type: _typeFilter,
        page: page,
      );
      final dynamic raw = response['data'];
      final Map<String, dynamic> data =
          raw is Map ? Map<String, dynamic>.from(raw) : response;
      if (!mounted) return;
      setState(() {
        _transactionRows = _rows(data['items']);
        _transactionTotal = (data['total'] as num?)?.toInt() ?? 0;
      });
    } catch (error) {
      if (mounted) setState(() => _transactionError = '$error');
    } finally {
      if (mounted) setState(() => _transactionsLoading = false);
    }
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  String _money(dynamic value) {
    final num amount = value is num ? value : num.tryParse('$value') ?? 0;
    return '₦${amount.toStringAsFixed(2)}';
  }

  Widget _panel(String title, List<Widget> children, {String? caption}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      )),
              if (caption != null) ...[
                const SizedBox(height: 4),
                Text(caption,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      );

  Widget _dataRows(List<Map<String, dynamic>> rows, String key, {bool amounts = false}) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text('No operational records to show.'),
      );
    }
    return Column(
      children: rows
          .map((row) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${row['_id'] ?? row['name'] ?? row['status'] ?? 'Record'}'),
                trailing: Text(amounts
                    ? '${row['count'] ?? 0} · ${_money(row['amount'])}'
                    : '${row['count'] ?? row['resolved'] ?? ''}'),
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Operations overview'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading && _data.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: List.generate(
                  5,
                  (_) => const Card(
                    child: SizedBox(height: 92, child: LinearProgressIndicator()),
                  ),
                ),
              )
            : _error.isNotEmpty && _data.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.lock_outline, size: 38),
                        const SizedBox(height: 12),
                        Text(_error, textAlign: TextAlign.center),
                        TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ]),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
                      children: [
                        if (_error.isNotEmpty)
                          MaterialBanner(
                            content: Text(_error),
                            actions: [
                              TextButton(onPressed: _load, child: const Text('Retry'))
                            ],
                          ),
                        _panel('Recorded ServicePay earnings', [
                          Text('NGN ${(_data['revenue'] as Map?)?['recordedServicepayProfit'] ?? 0}'),
                          const Text('Stored ServicePay profit on completed transactions today (UTC). Not gross turnover or a reconciled company income statement.'),
                        ]),
                        _panel(
                          'Daily transaction pulse',
                          [
                            _dataRows(
                              _rows(
                                (_data['transactions'] as Map?)?['today'],
                              ),
                              'today',
                              amounts: true,
                            ),
                          ],
                          caption: 'Operational gross amounts — not net profit.',
                        ),
                        _panel(
                          'Transaction outcomes',
                          [
                            _dataRows(
                              _rows(
                                (_data['transactions'] as Map?)?['byStatus'],
                              ),
                              'status',
                              amounts: true,
                            ),
                          ],
                          caption: 'Success, pending and failed counts and gross amounts.',
                        ),
                        _panel(
                          'Service activity',
                          [
                            _dataRows(
                              _rows(
                                (_data['transactions'] as Map?)?['services'],
                              ),
                              'services',
                              amounts: true,
                            ),
                          ],
                        ),
                        _panel(
                          'Ticket resolution performance',
                          _rows((_data['tickets'] as Map?)?['byAgent']).isEmpty
                              ? [const Text('No ticket resolution records are available.')]
                              : _rows((_data['tickets'] as Map?)?['byAgent'])
                                  .map((agent) => ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: Text('${agent['name'] ?? 'Support agent'}'),
                                        subtitle: Text('${agent['resolved'] ?? 0} resolved'),
                                        trailing: Text('${agent['count'] ?? 0} assigned'),
                                      ))
                                  .toList(),
                          caption: 'Assigned workload and resolved tickets by agent.',
                        ),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Transaction investigation',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                const Text('Read-only operational records. No balance or payment controls are available.'),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    SizedBox(
                                      width: 180,
                                      child: DropdownButtonFormField<String>(
                                        value: _statusFilter,
                                        isExpanded: true,
                                        decoration: const InputDecoration(labelText: 'Status'),
                                        items: const [
                                          ['', 'All statuses'],
                                          ['SUCCESSFUL', 'Success'],
                                          ['PENDING', 'Pending'],
                                          ['FAILED', 'Failed'],
                                        ]
                                            .map((item) => DropdownMenuItem(
                                                  value: item[0],
                                                  child: Text(item[1]),
                                                ))
                                            .toList(),
                                        onChanged: (value) {
                                          _statusFilter = value ?? '';
                                          _loadTransactions();
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      width: 180,
                                      child: DropdownButtonFormField<String>(
                                        value: _typeFilter,
                                        isExpanded: true,
                                        decoration: const InputDecoration(labelText: 'Service'),
                                        items: const [
                                          ['', 'All services'],
                                          ['DATA', 'Data'],
                                          ['AIRTIME', 'Airtime'],
                                          ['ELECTRICITY', 'Electricity'],
                                        ]
                                            .map((item) => DropdownMenuItem(
                                                  value: item[0],
                                                  child: Text(item[1]),
                                                ))
                                            .toList(),
                                        onChanged: (value) {
                                          _typeFilter = value ?? '';
                                          _loadTransactions();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                if (_transactionError.isNotEmpty)
                                  MaterialBanner(
                                    content: Text(_transactionError),
                                    actions: [
                                      TextButton(
                                        onPressed: () => _loadTransactions(page: _transactionPage),
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                if (_transactionsLoading && _transactionRows.isEmpty)
                                  const LinearProgressIndicator(),
                                if (!_transactionsLoading &&
                                    _transactionRows.isEmpty &&
                                    _transactionError.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text('No matching transactions.'),
                                  ),
                                ..._transactionRows.map((transaction) => ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.receipt_long_outlined),
                                      title: Text('${transaction['reference'] ?? transaction['id'] ?? 'Transaction'}'),
                                      subtitle: Text('${transaction['type'] ?? ''} · ${transaction['status'] ?? ''} · ${transaction['createdAt'] ?? ''}'),
                                      trailing: Text(_money(transaction['amount'])),
                                    )),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Page $_transactionPage · $_transactionTotal records'),
                                    Row(children: [
                                      IconButton(
                                        onPressed: _transactionPage > 1 && !_transactionsLoading
                                            ? () => _loadTransactions(page: _transactionPage - 1)
                                            : null,
                                        icon: const Icon(Icons.chevron_left),
                                      ),
                                      IconButton(
                                        onPressed: _transactionPage * 20 < _transactionTotal && !_transactionsLoading
                                            ? () => _loadTransactions(page: _transactionPage + 1)
                                            : null,
                                        icon: const Icon(Icons.chevron_right),
                                      ),
                                    ]),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        _panel('Open operational issues', [
                          Text('Virtual accounts · ${_rows((_data['issues'] as Map?)?['virtualAccounts']).length}'),
                          ..._rows((_data['issues'] as Map?)?['virtualAccounts']).take(5).map(
                            (e) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.account_balance_outlined),
                              title: Text('${e['id'] ?? 'Virtual account'}'),
                              trailing: Text('${e['status'] ?? 'Needs review'}'),
                              subtitle: Text('Updated ${e['updatedAt'] ?? 'date unavailable'}'),
                            ),
                          ),
                          const Divider(),
                          Text('Delivery · ${_rows((_data['issues'] as Map?)?['delivery']).length}'),
                          ..._rows((_data['issues'] as Map?)?['delivery']).take(5).map(
                            (e) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.local_shipping_outlined),
                              title: Text('${e['id'] ?? 'Delivery'}'),
                              trailing: Text('${e['status'] ?? 'Needs review'}'),
                              subtitle: Text('Created ${e['createdAt'] ?? 'date unavailable'}'),
                            ),
                          ),
                        ]),
                        _panel(
                          'Visible branches',
                          _rows(_data['branches']).isEmpty
                              ? [
                                  const Text(
                                    'No branches are assigned to this workspace.',
                                  ),
                                ]
                              : _rows(_data['branches'])
                                  .map(
                                    (branch) => ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        '${branch['name'] ?? 'Branch'}',
                                      ),
                                      subtitle: Text(
                                        'Today UTC · ${branch['count'] ?? 0} transactions · '
                                        '${branch['successful'] ?? 0} successful',
                                      ),
                                      trailing: Text(
                                        _money(branch['grossAmount']),
                                        textAlign: TextAlign.end,
                                      ),
                                    ),
                                  )
                                  .toList(),
                          caption:
                              'Today UTC gross transaction amount — not profit.',
                        ),
                        _panel('Support desk', [
                          const Text('Investigate cases and resolve complaints with the existing ticket workflow.'),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const AdminCustomerSupportScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.support_agent),
                            label: const Text('Open support tickets'),
                          ),
                        ]),
                      ],
                    ),
                  ),
      );
}

class CustomerSupportDashboard extends StatefulWidget {
  const CustomerSupportDashboard({super.key, this.api});
  final AdminStaffWorkspaceApi? api;
  @override
  State<CustomerSupportDashboard> createState() =>
      _CustomerSupportDashboardState();
}

class _CustomerSupportDashboardState extends State<CustomerSupportDashboard> {
  late final AdminStaffWorkspaceApi _api =
      widget.api ?? AdminStaffWorkspaceApi();
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _customers = [];
  Map<String, dynamic>? _selectedCustomer;
  Map<String, dynamic> _profile = {};
  int _page = 1, _total = 0;
  bool _loading = false;
  String _error = '';
  @override
  void dispose() {
    _search.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Map<String, dynamic> _nested(Map<String, dynamic> value) =>
      value['data'] is Map ? Map<String, dynamic>.from(value['data']) : value;

  Future<void> _find({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = '';
      _page = page;
    });
    try {
      final Map<String, dynamic> response =
          _nested(await _api.customers(query: _search.text, page: page));
      final List<Map<String, dynamic>> items = (response['items'] is List
              ? response['items'] as List
              : const <dynamic>[])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (mounted) {
        setState(() {
          _customers = items;
          _total = (response['total'] as num?)?.toInt() ?? items.length;
          _selectedCustomer = null;
          _profile = {};
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> customer) async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final response = _nested(await _api.customer('${customer['id']}'));
      if (mounted) {
        setState(() {
          _selectedCustomer = Map<String, dynamic>.from(
            response['customer'] is Map ? response['customer'] : customer,
          );
          _profile = response;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createTicket() async {
    final customer = _selectedCustomer;
    if (customer == null) return;
    final subject = TextEditingController();
    final description = TextEditingController();
    final transactionId = TextEditingController();
    String category = 'OTHER', priority = 'NORMAL';
    final Map<String, dynamic>? form =
        await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Create support case'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: subject, decoration: const InputDecoration(labelText: 'Subject')),
              TextField(controller: description, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Description')),
              TextField(controller: transactionId, decoration: const InputDecoration(labelText: 'Related transaction ID (optional)')),
              DropdownButtonFormField<String>(
                value: category,
                items: const ['TRANSACTION', 'TRANSFER', 'WITHDRAWAL', 'AIRTIME_DATA', 'BILLS', 'DELIVERY', 'OTHER']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v.replaceAll('_', ' ')))).toList(),
                onChanged: (v) => update(() => category = v ?? 'OTHER'),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              DropdownButtonFormField<String>(
                value: priority,
                items: const ['LOW', 'NORMAL', 'HIGH', 'URGENT']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => update(() => priority = v ?? 'NORMAL'),
                decoration: const InputDecoration(labelText: 'Priority'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (subject.text.trim().isEmpty || description.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'subject': subject.text.trim(),
                  'description': description.text.trim(),
                  'category': category,
                  'priority': priority,
                  'transactionId': transactionId.text.trim(),
                });
              },
              child: const Text('Create case'),
            ),
          ],
        ),
      ),
    );
    subject.dispose();
    description.dispose();
    transactionId.dispose();
    if (form == null) return;
    try {
      await _api.createTicket(
        customerId: '${customer['id']}',
        subject: '${form['subject']}',
        description: '${form['description']}',
        category: '${form['category']}',
        priority: '${form['priority']}',
        idempotencyKey: '${DateTime.now().microsecondsSinceEpoch}-${customer['id']}',
        transactionId: '${form['transactionId']}'.isEmpty
            ? null
            : '${form['transactionId']}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Support case created.')),
        );
        await _open(customer);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _escalate(Map<String, dynamic> ticket) async {
    final reason = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Escalate case'),
        content: TextField(controller: reason, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Reason')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => reason.text.trim().isEmpty ? null : Navigator.pop(context, reason.text.trim()),
            child: const Text('Escalate'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (value == null) return;
    try {
      await _api.escalateTicket('${ticket['id']}', value);
      if (mounted && _selectedCustomer != null) await _open(_selectedCustomer!);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  List<Map<String, dynamic>> _list(String key) {
    final dynamic raw = _profile[key];
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Customer support desk')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _find(),
              decoration: InputDecoration(
                labelText: 'Find by name, phone, email, ID or transaction reference',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(onPressed: _loading ? null : () => _find(), icon: const Icon(Icons.arrow_forward)),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error.isNotEmpty)
            MaterialBanner(content: Text(_error), actions: [TextButton(onPressed: () => _find(page: _page), child: const Text('Retry'))]),
          Expanded(
            child: _selectedCustomer == null
                ? _customers.isEmpty
                    ? Center(
                        child: Text(_error.isNotEmpty
                            ? 'Customer records could not be loaded.'
                            : _search.text.isEmpty
                                ? 'Search securely to investigate a customer.'
                                : 'No customer matches this search.'),
                      )
                    : ListView(
                        children: [
                          ..._customers.map((customer) => ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                                title: Text('${customer['fullName'] ?? 'Customer'}'),
                                subtitle: Text('${customer['phone'] ?? ''} · ${customer['email'] ?? ''}'),
                                trailing: Text('${customer['status'] ?? ''}'),
                                onTap: _loading ? null : () => _open(customer),
                              )),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Page $_page · $_total matches'),
                                Row(children: [
                                  IconButton(onPressed: _page > 1 && !_loading ? () => _find(page: _page - 1) : null, icon: const Icon(Icons.chevron_left)),
                                  IconButton(onPressed: _page * 20 < _total && !_loading ? () => _find(page: _page + 1) : null, icon: const Icon(Icons.chevron_right)),
                                ]),
                              ],
                            ),
                          ),
                        ],
                      )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(children: [
                        IconButton(onPressed: () => setState(() => _selectedCustomer = null), icon: const Icon(Icons.arrow_back)),
                        Expanded(child: Text('${_selectedCustomer!['fullName']}', style: Theme.of(context).textTheme.titleLarge)),
                        FilledButton.icon(onPressed: _createTicket, icon: const Icon(Icons.add), label: const Text('New case')),
                      ]),
                      ListTile(
                        leading: const Icon(Icons.verified_user_outlined),
                        title: Text('${_selectedCustomer!['phone'] ?? 'No phone'}'),
                        subtitle: Text('${_selectedCustomer!['email'] ?? 'No email'} · ${_selectedCustomer!['status'] ?? 'Status unavailable'}'),
                      ),
                      const Divider(),
                      Text('Recent transactions', style: Theme.of(context).textTheme.titleMedium),
                      ..._list('transactions').map((row) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.receipt_long_outlined),
                            title: Text('${row['reference'] ?? row['id'] ?? 'Transaction'}'),
                            subtitle: Text('${row['type'] ?? ''} · ${row['status'] ?? ''} · ${row['createdAt'] ?? ''}'),
                            trailing: Text('₦${row['amount'] ?? '—'}'),
                          )),
                      if (_list('transactions').isEmpty) const ListTile(title: Text('No transaction history is available.')),
                      const Divider(),
                      Text('Related support cases', style: Theme.of(context).textTheme.titleMedium),
                      ..._list('tickets').map((ticket) => ListTile(
                            leading: const Icon(Icons.support_agent_outlined),
                            title: Text('${ticket['caseReference'] ?? ticket['subject'] ?? 'Support case'}'),
                            subtitle: Text('${ticket['subject'] ?? ''} · ${ticket['status'] ?? ''} · ${ticket['priority'] ?? ''}'),
                            trailing: TextButton(onPressed: () => _escalate(ticket), child: const Text('Escalate')),
                          )),
                      if (_list('tickets').isEmpty) const ListTile(title: Text('No related support cases.')),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AdminCustomerSupportScreen())),
                        icon: const Icon(Icons.forum_outlined),
                        label: const Text('Open ticket queue and conversation tools'),
                      ),
                    ],
                  ),
          ),
        ]),
      );
}
