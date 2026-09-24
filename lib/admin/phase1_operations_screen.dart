import 'package:flutter/material.dart';

import 'phase1_operations_api.dart';

class Phase1OperationsScreen extends StatefulWidget {
  const Phase1OperationsScreen({
    super.key,
    this.api,
    required this.role,
  });

  final Phase1OperationsApi? api;
  final String role;

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
  Map<String, dynamic>? _selectedCustomer;

  bool get _isHeadOffice => widget.role.trim().toUpperCase() == 'HEAD_OFFICE';
  bool get _isManager => const {
        'HEAD_OFFICE',
        'ZONAL_MANAGER',
        'STATE_MANAGER',
        'AGENT',
        'AGGREGATOR',
      }.contains(widget.role.trim().toUpperCase());

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
    if ([_name, _email, _phone, _password].any((c) => c.text.trim().isEmpty)) {
      setState(
          () => _message = 'Name, email, phone and password are required.');
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
    await _run(() async {
      await _api.adjustWallet(
        customerId: '${customer['_id'] ?? customer['id'] ?? ''}',
        action: action,
        amount: _amount.text,
        reason: _reason.text,
        reference: _reference.text,
        idempotencyKey: phase1IdempotencyKey(),
      );
      if (mounted) setState(() => _message = 'Wallet adjustment completed.');
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

  Widget _field(TextEditingController controller, String label) => TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
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
              _field(_zone, 'Zone (optional)'),
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
                  onTap: () => setState(
                    () => _selectedCustomer =
                        Map<String, dynamic>.from(row as Map),
                  ),
                ),
              ),
              if (_selectedCustomer != null) ...[
                _field(_amount, 'Amount'),
                _field(_reason, 'Mandatory reason'),
                _field(_reference, 'Mandatory reference'),
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
              ],
            ],
            if (_isManager)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await _api.hierarchySummary();
                          if (mounted) {
                            setState(() => _message =
                                'Downline summary loaded for your permitted scope.');
                          }
                        }),
                child: const Text('View permitted downline summary'),
              ),
          ],
        ),
      );
}
