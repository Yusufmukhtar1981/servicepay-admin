import 'package:flutter/material.dart';

import 'phase1_operations_api.dart';

class Phase1OperationsScreen extends StatefulWidget {
  const Phase1OperationsScreen({
    super.key,
    this.api,
    required this.role,
    this.permissions = const <String>{},
  });

  final Phase1OperationsApi? api;
  final String role;
  final Set<String> permissions;

  @override
  State<Phase1OperationsScreen> createState() => _Phase1OperationsScreenState();
}

class _Phase1OperationsScreenState extends State<Phase1OperationsScreen> {
  late final Phase1OperationsApi _api = widget.api ?? Phase1OperationsApi();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _zone = TextEditingController();
  final _state = TextEditingController();
  final _customerSearch = TextEditingController();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _reference = TextEditingController();
  bool _busy = false;
  String? _message;
  List<dynamic> _customers = <dynamic>[];
  Map<String, dynamic> _summary = <String, dynamic>{};
  List<dynamic> _transactions = <dynamic>[];
  List<dynamic> _recentTransactions = <dynamic>[];
  int _transactionPage = 1;
  String? _walletIntentKey;
  Map<String, dynamic>? _selectedCustomer;

  bool get _isHeadOffice => widget.role.trim().toUpperCase() == 'HEAD_OFFICE';
  bool get _isManager => const {
        'HEAD_OFFICE',
        'ZONAL_MANAGER',
        'STATE_MANAGER',
        'AGENT',
        'AGGREGATOR',
      }.contains(widget.role.trim().toUpperCase());
  bool get _canAdjustWallet =>
      widget.permissions.map((value) => value.trim().toLowerCase()).contains(
            'wallets.adjust',
          );

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _phone,
      _password,
      _zone,
      _state,
      _customerSearch,
      _amount,
      _reason,
      _reference,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on Phase1OperationsException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'Unable to reach Servicepay.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createZonal() async {
    if ([_name, _email, _phone, _password, _zone]
        .any((c) => c.text.trim().isEmpty)) {
      setState(() =>
          _message = 'Name, email, phone, password and zone are required.');
      return;
    }
    await _run(() async {
      await _api.createZonalManager(
        fullName: _name.text,
        email: _email.text,
        phone: _phone.text,
        password: _password.text,
        zone: _zone.text,
        state: _state.text,
      );
      if (mounted) {
        setState(() => _message = 'Zonal Manager created successfully.');
      }
    });
  }

  Future<void> _promote() async {
    final id = await _ask('Existing user ID');
    if (id == null || id.trim().isEmpty) return;
    final target = await _ask('Target role (STATE_MANAGER or ZONAL_MANAGER)');
    if (target == null || target.trim().isEmpty) return;
    final confirmed = await _confirm(
      'Promote this existing account to ${target.trim().toUpperCase()}? '
      'Wallet, profile and transaction history remain on the account.',
    );
    if (!confirmed) return;
    await _run(() async {
      await _api.promoteUser(
        userId: id.trim(),
        targetRole: target.trim().toUpperCase(),
      );
      if (mounted) setState(() => _message = 'Promotion completed.');
    });
  }

  Future<void> _searchCustomers() async {
    await _run(() async {
      final data = await _api.searchCustomers(_customerSearch.text);
      final rows = data['customers'] ?? data['users'] ?? <dynamic>[];
      if (mounted) {
        setState(() => _customers = rows is List ? rows : <dynamic>[]);
      }
    });
  }

  Future<void> _adjust(String action) async {
    final customer = _selectedCustomer;
    if (customer == null) {
      setState(() => _message = 'Select a customer first.');
      return;
    }
    if ([_amount, _reason, _reference].any((c) => c.text.trim().isEmpty)) {
      setState(() => _message = 'Amount, reason and reference are required.');
      return;
    }
    if (!await _confirm(
      'Confirm $action of ₦${_amount.text.trim()} for '
      '${customer['fullName'] ?? customer['name'] ?? 'this customer'}?',
    )) {
      return;
    }
    final intentKey = _walletIntentKey ??= phase1IdempotencyKey();
    await _run(() async {
      await _api.adjustWallet(
        identifier:
            '${customer['_id'] ?? customer['id'] ?? customer['phone'] ?? ''}',
        action: action,
        amount: _amount.text,
        reason: _reason.text,
        reference: _reference.text,
        idempotencyKey: intentKey,
      );
      if (mounted) {
        setState(() {
          _message = 'Wallet adjustment completed.';
          _walletIntentKey = null;
        });
      }
    });
  }

  Future<void> _loadDownline() async {
    await _run(() async {
      final summary = await _api.hierarchySummary();
      final transactions = await _api.downlineTransactions(
        page: _transactionPage,
        limit: 25,
      );
      if (mounted) {
        setState(() {
          _summary = Map<String, dynamic>.from(
            (summary['summary'] is Map ? summary['summary'] : summary),
          );
          final recent = _summary['recentTransactions'];
          _recentTransactions = recent is List ? recent : <dynamic>[];
          final rows = transactions['transactions'] ?? transactions['items'];
          _transactions = rows is List ? rows : <dynamic>[];
        });
      }
    });
  }

  void _cancelWalletIntent() {
    setState(() {
      _walletIntentKey = null;
      _selectedCustomer = null;
      _amount.clear();
      _reason.clear();
      _reference.clear();
    });
  }

  Future<String?> _ask(String label) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;

  Widget _field(
    TextEditingController controller,
    String label, {
    bool resetsWalletIntent = false,
  }) =>
      TextField(
        controller: controller,
        onChanged: resetsWalletIntent ? (_) => _walletIntentKey = null : null,
        decoration: InputDecoration(labelText: label),
      );

  Widget _transactionTile(dynamic row) => ListTile(
        dense: true,
        title: Text('${row['type'] ?? row['serviceType'] ?? 'Transaction'}'),
        subtitle: Text('${row['status'] ?? ''}  ${row['amount'] ?? ''}'),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phase 1 Operations')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_message != null)
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_message!),
              ),
            ),
          if (_isHeadOffice) ...[
            const Text('Create Zonal Manager',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            _field(_name, 'Full name'),
            _field(_email, 'Email'),
            _field(_phone, 'Phone'),
            _field(_password, 'Temporary password'),
            _field(_zone, 'Zone (required)'),
            _field(_state, 'State (optional)'),
            FilledButton(
              onPressed: _busy ? null : _createZonal,
              child: const Text('Create Zonal Manager'),
            ),
            const Divider(height: 32),
            const Text('Promote existing account',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            FilledButton.tonal(
              onPressed: _busy ? null : _promote,
              child: const Text('Choose account and target role'),
            ),
            if (_canAdjustWallet) ...<Widget>[
              const Divider(height: 32),
              const Text('Manual customer wallet adjustment',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              _field(_customerSearch, 'Search customer'),
              OutlinedButton(
                onPressed: _busy ? null : _searchCustomers,
                child: const Text('Search customers'),
              ),
              ..._customers.map(
                (row) => ListTile(
                  title:
                      Text('${row['fullName'] ?? row['name'] ?? 'Customer'}'),
                  subtitle: Text(
                    'Balance: ₦${row['walletBalance'] ?? row['balance'] ?? 0}',
                  ),
                  selected: identical(_selectedCustomer, row),
                  onTap: () => setState(() {
                    _selectedCustomer = Map<String, dynamic>.from(row as Map);
                    _walletIntentKey = null;
                  }),
                ),
              ),
              if (_selectedCustomer != null) ...[
                _field(_amount, 'Amount', resetsWalletIntent: true),
                _field(_reason, 'Mandatory reason', resetsWalletIntent: true),
                _field(_reference, 'Mandatory reference',
                    resetsWalletIntent: true),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : () => _adjust('CREDIT'),
                        child: const Text('Credit'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _busy ? null : () => _adjust('DEBIT'),
                        child: const Text('Debit'),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _busy ? null : _cancelWalletIntent,
                  child: const Text('Cancel adjustment'),
                ),
              ],
            ],
          ],
          if (_isManager)
            OutlinedButton(
              onPressed: _busy ? null : _loadDownline,
              child: const Text('View permitted downline summary'),
            ),
          if (_summary.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Permitted downline summary',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Wrap(spacing: 8, children: [
              Chip(
                label: Text(
                  'Total downline: ${_summary['totalDownline'] ?? 0}',
                ),
              ),
              Chip(
                label: Text('Customers: ${_summary['customers'] ?? 0}'),
              ),
              Chip(
                label: Text(
                  'Transactions: ${_summary['transactionCount'] ?? 0}',
                ),
              ),
              Chip(
                label: Text(
                  'Value: ${_summary['transactionValue'] ?? 0}',
                ),
              ),
            ]),
            if (_recentTransactions.isNotEmpty) ...[
              const Text(
                'Recent transactions',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ..._recentTransactions.map(_transactionTile),
            ],
            const SizedBox(height: 8),
            Text('Transactions (page $_transactionPage)'),
            ..._transactions.map(_transactionTile),
            Row(
              children: [
                TextButton(
                  onPressed: _transactionPage <= 1 || _busy
                      ? null
                      : () {
                          setState(() => _transactionPage--);
                          _loadDownline();
                        },
                  child: const Text('Previous'),
                ),
                TextButton(
                  onPressed: _transactions.length < 25 || _busy
                      ? null
                      : () {
                          setState(() => _transactionPage++);
                          _loadDownline();
                        },
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
