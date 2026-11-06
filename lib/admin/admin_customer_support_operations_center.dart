import 'package:flutter/material.dart';

import 'admin_control_center_download.dart';
import 'admin_customer_support_screen.dart';
import 'admin_staff_workspace_api.dart';

/// Read-only customer and payment investigation paired with the established
/// ticket workflow. This workspace intentionally exposes no money controls.
class CustomerSupportOperationsCenter extends StatefulWidget {
  const CustomerSupportOperationsCenter({super.key, this.api});
  final AdminStaffWorkspaceApi? api;

  @override
  State<CustomerSupportOperationsCenter> createState() =>
      _CustomerSupportOperationsCenterState();
}

class _CustomerSupportOperationsCenterState
    extends State<CustomerSupportOperationsCenter> {
  late final AdminStaffWorkspaceApi _api = widget.api ?? AdminStaffWorkspaceApi();
  final TextEditingController _search = TextEditingController();
  final TextEditingController _transactionSearch = TextEditingController();
  final TextEditingController _accountSearch = TextEditingController();
  final Map<String, String> _ticketIntentKeys = <String, String>{};
  Map<String, dynamic>? _ticketRetryCustomer;
  Map<String, String>? _ticketRetryForm;
  String? _ticketRetryKey;
  String? _ticketRetryIntent;
  String? _escalationRetryId;
  String? _escalationRetryReason;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _accounts = [];
  Map<String, dynamic>? _customer;
  Map<String, dynamic>? _customerTarget;
  Map<String, dynamic> _profile = {};
  String _view = 'Customers';
  String _accountStatus = '';
  String _transactionStatus = '';
  String _error = '';
  bool _loading = false;
  bool _summaryLoading = true;
  bool _accountsLoading = false;
  String _retryAction = 'summary';
  int _customerPage = 1;
  int _customerTotal = 0;
  int _transactionPage = 1;
  int _transactionTotal = 0;
  int _accountPage = 1;
  int _accountTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void dispose() {
    _search.dispose();
    _transactionSearch.dispose();
    _accountSearch.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Map<String, dynamic> _data(dynamic value) {
    if (value is Map && value['data'] is Map) {
      return Map<String, dynamic>.from(value['data'] as Map);
    }
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  List<Map<String, dynamic>> _activityRows() {
    final dynamic activity = _summary['todaySupportActivity'];
    if (activity is num) {
      return <Map<String, dynamic>>[
        {'label': 'Support activity', 'count': activity},
      ];
    }
    return _rows(activity);
  }

  Future<void> _loadSummary() async {
    setState(() {
      _summaryLoading = true;
      _error = '';
      _retryAction = 'summary';
    });
    try {
      final value = _data(await _api.supportSummary());
      if (mounted) {
        setState(() {
          _summary = value;
          if (_summary['canManageTeam'] != true && _view == 'Team & reports') {
            _view = 'Customers';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _summaryLoading = false);
    }
  }

  String _friendlyError(Object error) {
    final text = '$error'.replaceFirst('Exception: ', '').trim();
    return text.isEmpty
        ? 'We could not load this information. Try again.'
        : text;
  }

  Future<void> _findCustomers({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = '';
      _retryAction = 'customers';
      _customerPage = page;
    });
    try {
      final data = _data(await _api.customers(
        query: _search.text.trim(),
        page: page,
        limit: 20,
      ));
      if (!mounted) return;
      setState(() {
        _customers = _rows(data['items']);
        _customerTotal = (data['total'] as num?)?.toInt() ?? _customers.length;
        _customer = null;
        _profile = {};
      });
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCustomer(Map<String, dynamic> customer) async {
    _customerTarget = customer;
    setState(() {
      _loading = true;
      _error = '';
      _retryAction = 'customer';
    });
    try {
      final data = _data(await _api.customer('${customer['id']}'));
      if (!mounted) return;
      setState(() {
        _profile = data;
        _customer = data['customer'] is Map
            ? Map<String, dynamic>.from(data['customer'] as Map)
            : customer;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _findTransactions({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = '';
      _retryAction = 'transactions';
      _transactionPage = page;
    });
    try {
      final data = _data(await _api.transactions(
        query: _transactionSearch.text.trim(),
        status: _transactionStatus,
        page: page,
        limit: 20,
      ));
      if (!mounted) return;
      setState(() {
        _transactions = _rows(data['items']);
        _transactionTotal =
            (data['total'] as num?)?.toInt() ?? _transactions.length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _findAccounts({int page = 1}) async {
    setState(() {
      _accountsLoading = true;
      _error = '';
      _retryAction = 'accounts';
      _accountPage = page;
    });
    try {
      final data = _data(await _api.virtualAccounts(
        query: _accountSearch.text.trim(),
        status: _accountStatus,
        page: page,
        limit: 20,
      ));
      if (!mounted) return;
      setState(() {
        _accounts = _rows(data['items']);
        _accountTotal = (data['total'] as num?)?.toInt() ?? _accounts.length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _accountsLoading = false);
    }
  }

  Future<void> _retry() async {
    switch (_retryAction) {
      case 'customers':
        return _findCustomers(page: _customerPage);
      case 'customer':
        if (_customerTarget != null) return _openCustomer(_customerTarget!);
        return;
      case 'transactions':
        return _findTransactions(page: _transactionPage);
      case 'accounts':
        return _findAccounts(page: _accountPage);
      case 'ticket':
        return _submitTicket();
      case 'escalation':
        return _submitEscalation();
      default:
        return _loadSummary();
    }
  }

  Future<void> _createTicket({Map<String, dynamic>? transaction}) async {
    final customer = _customer;
    if (customer == null) return;
    String subject = transaction == null
        ? ''
        : 'Investigate ${transaction['reference'] ?? 'transaction'}';
    String description = '';
    String transactionId = '${transaction?['id'] ?? ''}';
    String category = transaction == null ? 'OTHER' : 'TRANSACTION';
    String priority = 'NORMAL';
    final form = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Open a support case'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('For ${customer['fullName'] ?? 'selected customer'}',
                    style: Theme.of(context).textTheme.bodySmall),
                TextFormField(
                  initialValue: subject,
                  onChanged: (value) => update(() => subject = value),
                  decoration: const InputDecoration(labelText: 'Subject'),
                ),
                TextFormField(
                  initialValue: description,
                  onChanged: (value) => update(() => description = value),
                  minLines: 3,
                  maxLines: 5,
                  decoration:
                      const InputDecoration(labelText: 'What happened?'),
                ),
                TextFormField(
                  initialValue: transactionId,
                  onChanged: (value) => transactionId = value,
                  decoration: const InputDecoration(
                    labelText: 'Related transaction ID (optional)',
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const [
                    'TRANSACTION',
                    'TRANSFER',
                    'WITHDRAWAL',
                    'AIRTIME_DATA',
                    'BILLS',
                    'ACCOUNT_KYC',
                    'OTHER'
                  ]
                      .map((v) => DropdownMenuItem(
                          value: v, child: Text(v.replaceAll('_', ' '))))
                      .toList(),
                  onChanged: (v) => update(() => category = v ?? 'OTHER'),
                ),
                DropdownButtonFormField<String>(
                  value: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const ['LOW', 'NORMAL', 'HIGH', 'URGENT']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => update(() => priority = v ?? 'NORMAL'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: subject.trim().isEmpty || description.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, {
                        'subject': subject.trim(),
                        'description': description.trim(),
                        'transactionId': transactionId.trim(),
                        'category': category,
                        'priority': priority,
                      }),
              child: const Text('Create case'),
            ),
          ],
        ),
      ),
    );
    if (form == null) return;
    final intent = [
      customer['id'],
      form['subject'],
      form['description'],
      form['transactionId'],
      form['category'],
      form['priority'],
    ].join('|');
    final intentKey = _ticketIntentKeys.putIfAbsent(
      intent,
      () =>
          'support-${customer['id']}-${DateTime.now().microsecondsSinceEpoch}',
    );
    _ticketRetryCustomer = customer;
    _ticketRetryForm = form;
    _ticketRetryKey = intentKey;
    _ticketRetryIntent = intent;
    await _submitTicket();
  }

  Future<void> _submitTicket() async {
    final customer = _ticketRetryCustomer;
    final form = _ticketRetryForm;
    final intentKey = _ticketRetryKey;
    if (customer == null || form == null || intentKey == null) return;
    setState(() {
      _loading = true;
      _error = '';
      _retryAction = 'ticket';
    });
    try {
      await _api.createTicket(
        customerId: '${customer['id']}',
        subject: form['subject']!,
        description: form['description']!,
        category: form['category']!,
        priority: form['priority']!,
        idempotencyKey: intentKey,
        transactionId:
            form['transactionId']!.isEmpty ? null : form['transactionId'],
      );
      _ticketRetryCustomer = null;
      _ticketRetryForm = null;
      _ticketRetryKey = null;
      if (_ticketRetryIntent != null) {
        _ticketIntentKeys.remove(_ticketRetryIntent);
      }
      _ticketRetryIntent = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Support case created.')),
        );
        await _openCustomer(customer);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generateReport() async {
    final team = _rows(_summary['team']);
    final activity = _activityRows();
    final lines = <List<String>>[
      ['ServicePay Support Operations Report'],
      ['Generated', DateTime.now().toLocal().toIso8601String()],
      ['Total customers', '${_summary['totalCustomers'] ?? 0}'],
      ['Pending transactions', '${_summary['pendingTransactions'] ?? 0}'],
      ['Failed transactions', '${_summary['failedTransactions'] ?? 0}'],
      ['Open complaints', '${_summary['openComplaints'] ?? 0}'],
      ['Resolved tickets', '${_summary['resolvedTickets'] ?? 0}'],
      [
        'Average resolution seconds',
        '${_summary['averageResolutionSeconds'] ?? 'Unavailable'}'
      ],
      [
        'Average first response seconds',
        '${_summary['averageFirstResponseSeconds'] ?? 'Unavailable'}'
      ],
      [],
      [
        'Support team',
        'Assigned',
        'Resolved',
        'Avg resolution (sec)',
        'Avg first response (sec)'
      ],
      ...team.map((row) => [
            '${row['name'] ?? 'Support agent'}',
            '${row['assigned'] ?? 0}',
            '${row['resolved'] ?? 0}',
            '${row['averageResolutionSeconds'] ?? 'Unavailable'}',
            '${row['averageFirstResponseSeconds'] ?? 'Unavailable'}',
          ]),
      [],
      ['Today activity', 'Count'],
      ...activity.map((row) => [
            '${row['label'] ?? row['type'] ?? row['name'] ?? 'Activity'}',
            '${row['count'] ?? row['value'] ?? 0}',
          ]),
    ];
    String quote(String value) {
      final safe = RegExp(r'^[\s]*[=+\-@\t\r]').hasMatch(value) ? "'$value" : value;
      return '"${safe.replaceAll('"', '""')}"';
    }
    final csv = lines.map((row) => row.map(quote).join(',')).join('\n');
    try {
      await downloadControlCenterCsv(csv, 'servicepay-support-report.csv');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Support report downloaded.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Support operations report'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: SelectableText(csv, style: const TextStyle(fontSize: 12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Widget _metric(String label, dynamic value, IconData icon,
      {bool loading = false}) {
    final text = value is num ? _groupNumber(value) : '$value';
    return SizedBox(
      width: 174,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(icon, color: const Color(0xff087b55)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 4),
                  loading
                      ? const SizedBox(
                          width: 58,
                          height: 13,
                          child: LinearProgressIndicator(minHeight: 5))
                      : Text(text,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xff155b45),
                                  )),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  String _groupNumber(num value) {
    final source = value.toInt().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < source.length; index++) {
      if (index > 0 && (source.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(source[index]);
    }
    return buffer.toString();
  }

  Widget _searchField(
      TextEditingController controller, String label, VoidCallback search,
      {String hint = ''}) {
    return TextField(
      controller: controller,
      onSubmitted: (_) => search(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint.isEmpty ? null : hint,
        prefixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: 'Search',
          onPressed: _loading || _accountsLoading ? null : search,
          icon: const Icon(Icons.arrow_forward),
        ),
      ),
    );
  }

  Widget _errorBanner() => _error.isEmpty
      ? const SizedBox.shrink()
      : MaterialBanner(
          leading: const Icon(Icons.info_outline),
          content: Text(_error),
          actions: [
            TextButton(onPressed: _retry, child: const Text('Retry')),
          ],
        );

  Widget _empty(String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.manage_search_outlined,
                size: 26, color: Color(0xff568574)),
            const SizedBox(width: 10),
            Expanded(child: Text(message, textAlign: TextAlign.start)),
          ],
        ),
      );

  Widget _customerPane() {
    if (_customer != null) {
      final customer = _customer!;
      final virtual = _profile['virtualAccount'] is Map
          ? Map<String, dynamic>.from(_profile['virtualAccount'] as Map)
          : <String, dynamic>{};
      return ListView(
        key: const ValueKey('customer-detail'),
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _customer = null),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Customer results'),
                ),
                FilledButton.icon(
                  onPressed: _createTicket,
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('Create support case'),
                ),
              ]),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${customer['fullName'] ?? 'Customer'}',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: const Color(0xff155b45),
                                  fontWeight: FontWeight.w800,
                                )),
                    const SizedBox(height: 12),
                    Wrap(spacing: 22, runSpacing: 10, children: [
                      _detail('Phone', customer['phone']),
                      _detail('Email', customer['email']),
                      _detail('Account status', customer['status']),
                      _detail('KYC status', customer['kycStatus']),
                      _detail(
                        'Wallet balance · view only',
                        _money(customer['walletBalance']),
                      ),
                    ]),
                  ]),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('Virtual account · read only'),
              subtitle: Text([
                '${virtual['bankName'] ?? 'Bank unavailable'}',
                '${virtual['maskedAccountNumber'] ?? 'Account number unavailable'}',
                '${virtual['status'] ?? 'Status unavailable'}',
                if ('${virtual['message'] ?? ''}'.isNotEmpty)
                  '${virtual['message']}',
                if ('${virtual['errorCode'] ?? ''}'.isNotEmpty)
                  'Code: ${virtual['errorCode']}',
              ].join(' · ')),
            ),
          ),
          const SizedBox(height: 6),
          Text('Recent transactions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  )),
          ..._rows(_profile['transactions']).map(_transactionTile),
          if (_rows(_profile['transactions']).isEmpty)
            _empty('No transaction history is available for this customer.'),
          const SizedBox(height: 8),
          Text('Related support cases',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  )),
          ..._rows(_profile['tickets']).map((ticket) => Card(
                child: ListTile(
                  leading: const Icon(Icons.support_agent_outlined),
                  title: Text(
                      '${ticket['caseReference'] ?? ticket['subject'] ?? 'Support case'}'),
                  subtitle: Text(
                      '${ticket['subject'] ?? ''} · ${ticket['status'] ?? 'OPEN'} · ${ticket['priority'] ?? 'NORMAL'}'),
                  trailing: TextButton(
                    onPressed: () => _escalate(ticket),
                    child: const Text('Escalate'),
                  ),
                ),
              )),
          if (_rows(_profile['tickets']).isEmpty)
            _empty('No support cases are linked to this customer.'),
        ],
      );
    }
    if (_customers.isEmpty && !_loading) {
      return _empty(_search.text.isEmpty
          ? 'Search a customer to begin a secure investigation.'
          : 'No customer matched that search. Try a phone, email, ID or reference.');
    }
    return ListView(
      key: const ValueKey('customer-results'),
      padding: const EdgeInsets.all(16),
      children: [
        if (_loading) const LinearProgressIndicator(),
        ..._customers.map((customer) => Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xffe1f1e9),
                  child: Icon(Icons.person_outline, color: Color(0xff17664d)),
                ),
                title: Text('${customer['fullName'] ?? 'Customer'}'),
                subtitle: Text(
                    '${customer['phone'] ?? 'No phone'} · ${customer['email'] ?? 'No email'}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _loading ? null : () => _openCustomer(customer),
              ),
            )),
        if (_customers.isNotEmpty)
          _pager(_customerPage, _customerTotal, _loading, _findCustomers),
      ],
    );
  }

  Widget _detail(String label, dynamic value) => SizedBox(
        width: 210,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text('${value ?? 'Unavailable'}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  String _money(dynamic value) {
    final amount = value is num ? value : num.tryParse('$value');
    if (amount == null) return 'Unavailable';
    final fixed = amount.toStringAsFixed(2).split('.');
    return '₦${_groupNumber(int.parse(fixed[0]))}.${fixed[1]}';
  }

  Widget _transactionTile(Map<String, dynamic> row) => Card(
        child: ListTile(
          onTap: _loading ? null : () => _investigateTransaction(row),
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text('${row['reference'] ?? row['id'] ?? 'Transaction'}'),
          subtitle: Text(
              '${row['type'] ?? 'Payment'} · ${row['status'] ?? 'Unknown'} · ${row['createdAt'] ?? 'Date unavailable'}'
              '${row['providerStatus'] == null ? '' : ' · Provider: ${row['providerStatus']}'}'
              '${row['errorCode'] == null ? '' : ' · Code ${row['errorCode']}'}'
              '${row['diagnostic'] == null ? '' : '\n${row['diagnostic']}'}'),
          isThreeLine: row['diagnostic'] != null,
          trailing: Text('₦${row['amount'] ?? '—'}'),
        ),
      );

  Future<void> _investigateTransaction(Map<String, dynamic> row) async {
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transaction investigation'),
        content: SingleChildScrollView(
          child: SelectableText([
            'Reference: ${row['reference'] ?? 'Unavailable'}',
            'Transaction ID: ${row['id'] ?? 'Unavailable'}',
            'Status: ${row['status'] ?? 'Unavailable'}',
            'Amount: ${_money(row['amount'])}',
            'Created: ${row['createdAt'] ?? 'Unavailable'}',
            'Updated: ${row['updatedAt'] ?? 'Unavailable'}',
            'Provider status: ${row['providerStatus'] ?? 'Unavailable'}',
            'Safe diagnostic: ${row['diagnostic'] ?? 'No provider evidence available.'}',
          ].join('\n\n')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Close')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Create linked complaint')),
        ],
      ),
    );
    if (create != true || !mounted) return;
    final customerId = '${row['customerId'] ?? _customer?['id'] ?? ''}';
    if (customerId.isEmpty) {
      setState(() => _error = 'Select the transaction customer before creating a complaint.');
      return;
    }
    await _openCustomer({'id': customerId});
    if (!mounted || _customer?['id'] != customerId) return;
    setState(() => _view = 'Customers');
    await _createTicket(transaction: row);
  }

  Widget _pager(int page, int total, bool busy,
          Future<void> Function({int page}) load) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Page $page · $total records'),
        Row(children: [
          IconButton(
            tooltip: 'Previous page',
            onPressed: page > 1 && !busy ? () => load(page: page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed:
                page * 20 < total && !busy ? () => load(page: page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
      ]);

  Widget _transactionsPane() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
              'Investigation only. No payment, refund or balance controls.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _transactionStatus,
            decoration: const InputDecoration(labelText: 'Transaction status'),
            items: const [
              ['', 'All statuses'], ['SUCCESSFUL', 'Successful'],
              ['PENDING', 'Pending'], ['FAILED', 'Failed'], ['REFUNDED', 'Refunded'],
            ].map((v) => DropdownMenuItem(value: v[0], child: Text(v[1]))).toList(),
            onChanged: _loading ? null : (value) {
              setState(() => _transactionStatus = value ?? '');
              _findTransactions();
            },
          ),
          if (_loading) const LinearProgressIndicator(),
          ..._transactions.map(_transactionTile),
          if (_transactions.isEmpty && !_loading)
            _empty(
                'Search by reference or customer details to inspect transactions.'),
          if (_transactions.isNotEmpty)
            _pager(_transactionPage, _transactionTotal, _loading,
                _findTransactions),
        ],
      );

  Widget _accountsPane() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _accountStatus,
            decoration: const InputDecoration(
                labelText: 'Account status', border: OutlineInputBorder()),
            items: const [
              ['', 'All statuses'],
              ['ACTIVE', 'Active'],
              ['PENDING', 'Pending'],
              ['FAILED', 'Failed'],
              ['DISABLED', 'Disabled'],
              ['NOT_CREATED', 'Not created'],
              ['UNKNOWN', 'Unknown'],
            ]
                .map((item) =>
                    DropdownMenuItem(value: item[0], child: Text(item[1])))
                .toList(),
            onChanged: _accountsLoading
                ? null
                : (value) {
                    setState(() => _accountStatus = value ?? '');
                    _findAccounts();
                  },
          ),
          if (_accountsLoading) const LinearProgressIndicator(),
          ..._accounts.map((row) => Card(
                child: ListTile(
                  onTap: () async {
                    await _openCustomer({'id': row['id']});
                    if (mounted && _customer?['id'] == row['id']) {
                      setState(() => _view = 'Customers');
                    }
                  },
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text('${row['fullName'] ?? 'Customer'}'),
                  subtitle: Text(
                      '${row['bankName'] ?? 'Bank unavailable'} · ${row['maskedAccountNumber'] ?? 'Account unavailable'}'
                      '${row['message'] == null ? '' : '\n${row['message']}'}'
                      '${row['errorCode'] == null ? '' : ' · Code ${row['errorCode']}'}'),
                  isThreeLine: row['message'] != null,
                  trailing: Text('${row['status'] ?? 'Unknown'}'),
                ),
              )),
          if (_accounts.isEmpty && !_accountsLoading)
            _empty('No virtual account records match these filters.'),
          if (_accounts.isNotEmpty)
            _pager(
                _accountPage, _accountTotal, _accountsLoading, _findAccounts),
        ],
      );

  Widget _teamPane() {
    final team = _rows(_summary['team']);
    final activity = _activityRows();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: Text('Support team performance',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        )),
              ),
              OutlinedButton.icon(
                onPressed: _generateReport,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Generate report'),
              ),
            ]),
        const SizedBox(height: 6),
        const Text(
            'Live figures from the support workspace. Team actions remain permission-gated by the service.'),
        if ('${_summary['dayTimezone'] ?? ''}'.isNotEmpty)
          Text('Reporting day: ${_summary['dayTimezone']}'),
        if ('${_summary['timingNotice'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${_summary['timingNotice']}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        const SizedBox(height: 12),
        ...team.map((agent) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 22,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 190,
                      child: Text('${agent['name'] ?? 'Support agent'}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text('Assigned  ${agent['assigned'] ?? 0}'),
                    Text('Resolved  ${agent['resolved'] ?? 0}'),
                    Text(
                        'Avg resolution  ${_duration(agent['averageResolutionSeconds'])}'),
                    Text(
                        'First response  ${_duration(agent['averageFirstResponseSeconds'])}'),
                  ],
                ),
              ),
            )),
        if (team.isEmpty && !_summaryLoading)
          _empty('Team performance is not available yet.'),
        const SizedBox(height: 12),
        Text('Today’s support activity',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                )),
        ...activity.map((row) => ListTile(
              dense: true,
              leading: const Icon(Icons.query_stats_outlined),
              title: Text(
                  '${row['label'] ?? row['type'] ?? row['name'] ?? 'Activity'}'),
              trailing: Text('${row['count'] ?? row['value'] ?? 0}'),
            )),
        if (activity.isEmpty && !_summaryLoading)
          const ListTile(title: Text('No activity has been reported today.')),
      ],
    );
  }

  String _duration(dynamic raw) {
    final seconds = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    if (seconds <= 0) return '—';
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  Future<void> _escalate(Map<String, dynamic> ticket) async {
    String reason = '';
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Escalate support case'),
          content: TextField(
            onChanged: (value) => update(() => reason = value),
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Escalation reason'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: reason.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, reason.trim()),
              child: const Text('Escalate'),
            ),
          ],
        ),
      ),
    );
    if (value == null) return;
    _escalationRetryId = '${ticket['id'] ?? ticket['_id']}';
    _escalationRetryReason = value;
    await _submitEscalation();
  }

  Future<void> _submitEscalation() async {
    final id = _escalationRetryId;
    final reason = _escalationRetryReason;
    if (id == null || reason == null) return;
    setState(() {
      _loading = true;
      _error = '';
      _retryAction = 'escalation';
    });
    try {
      await _api.escalateTicket(id, reason);
      _escalationRetryId = null;
      _escalationRetryReason = null;
      if (_customer != null) await _openCustomer(_customer!);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <String>[
      'Customers',
      'Transactions',
      'Virtual accounts',
      if (_summary['canManageTeam'] == true) 'Team & reports',
    ];
    final Widget content;
    if (_view == 'Transactions') {
      content = _transactionsPane();
    } else if (_view == 'Virtual accounts') {
      content = _accountsPane();
    } else if (_view == 'Team & reports' && _summary['canManageTeam'] == true) {
      content = _teamPane();
    } else {
      content = _customerPane();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support operations'),
        actions: [
          IconButton(
            tooltip: 'Refresh metrics',
            onPressed: _summaryLoading ? null : _loadSummary,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity,
            color: const Color(0xffe8f3ed),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Support Operations Center',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xff155b45),
                        fontWeight: FontWeight.w800,
                      )),
              const SizedBox(height: 4),
              const Text(
                  'Investigate carefully. Customer funds are never in scope.'),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _metric('Customers', _summary['totalCustomers'] ?? 0,
                      Icons.people_outline,
                      loading: _summaryLoading),
                  _metric(
                      'Pending payments',
                      _summary['pendingTransactions'] ?? 0,
                      Icons.hourglass_top_outlined,
                      loading: _summaryLoading),
                  _metric('Failed payments',
                      _summary['failedTransactions'] ?? 0, Icons.error_outline,
                      loading: _summaryLoading),
                  _metric('Open complaints', _summary['openComplaints'] ?? 0,
                      Icons.forum_outlined,
                      loading: _summaryLoading),
                  _metric('Resolved', _summary['resolvedTickets'] ?? 0,
                      Icons.task_alt_outlined,
                      loading: _summaryLoading),
                  _metric('Active agents', _summary['activeSupportAgents'] ?? 0,
                      Icons.support_agent_outlined,
                      loading: _summaryLoading),
                ]),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 16, children: [
                Text(
                    'Avg. resolution  ${_duration(_summary['averageResolutionSeconds'])}'),
                Text(
                    'First response  ${_duration(_summary['averageFirstResponseSeconds'])}'),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AdminCustomerSupportScreen(
                        canManageAssignments: _summary['canManageTeam'] == true,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.forum_outlined, size: 18),
                  label: const Text('Tickets & conversations'),
                ),
              ]),
            ]),
          ),
          _errorBanner(),
          if (_view == 'Customers' && _customer == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _searchField(
                _search,
                'Find customer',
                _findCustomers,
                hint:
                    'Name, phone, email, customer ID or transaction reference',
              ),
            ),
          if (_view == 'Transactions')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _searchField(
                _transactionSearch,
                'Search transactions',
                _findTransactions,
                hint: 'Reference or customer details',
              ),
            ),
          if (_view == 'Virtual accounts')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _searchField(
                _accountSearch,
                'Search virtual accounts',
                _findAccounts,
                hint: 'Customer or masked account number',
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: tabs
                      .map((tab) => ButtonSegment<String>(
                            value: tab,
                            label: Text(tab),
                            icon: Icon(switch (tab) {
                              'Customers' => Icons.person_search_outlined,
                              'Transactions' => Icons.receipt_long_outlined,
                              'Virtual accounts' =>
                                Icons.account_balance_outlined,
                              _ => Icons.groups_outlined,
                            }),
                          ))
                      .toList(),
                  selected: {_view},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => setState(() {
                    _view = value.first;
                    _error = '';
                  }),
                ),
              ),
            ),
          ),
          if ((_loading || _accountsLoading) && !_summaryLoading)
            const LinearProgressIndicator(),
          Expanded(child: content),
        ]),
      ),
    );
  }
}
