import 'package:flutter/material.dart';

import 'admin_customer_withdrawals_api.dart';
import 'admin_permissions.dart';

class AdminCustomerWithdrawalsScreen extends StatefulWidget {
  const AdminCustomerWithdrawalsScreen({
    super.key,
    this.api,
    this.initialAccess,
  });

  final AdminCustomerWithdrawalsApi? api;
  final AdminAccess? initialAccess;

  @override
  State<AdminCustomerWithdrawalsScreen> createState() =>
      _AdminCustomerWithdrawalsScreenState();
}

class _AdminCustomerWithdrawalsScreenState
    extends State<AdminCustomerWithdrawalsScreen> {
  late final AdminCustomerWithdrawalsApi _api =
      widget.api ?? AdminCustomerWithdrawalsApi();
  late final bool _ownsApi = widget.api == null;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _withdrawals = <Map<String, dynamic>>[];
  String _status = 'PENDING';
  String _search = '';
  String _error = '';
  bool _loading = true;
  bool _acting = false;
  int _loadVersion = 0;

  bool get _authorized {
    final AdminAccess? access = widget.initialAccess;
    return access != null &&
        AdminAccess.normalizeRole(access.role) == 'HEAD_OFFICE' &&
        access.has(AdminPermissions.withdrawalsView);
  }

  @override
  void initState() {
    super.initState();
    if (_authorized) _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_ownsApi) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_authorized) return;
    final int requestVersion = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final List<Map<String, dynamic>> withdrawals = await _api.list(
        status: _status == 'ALL' ? '' : _status,
      );
      if (!mounted || requestVersion != _loadVersion) return;
      setState(() => _withdrawals = withdrawals);
    } catch (error) {
      if (!mounted || requestVersion != _loadVersion) return;
      setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted && requestVersion == _loadVersion) {
        setState(() => _loading = false);
      }
    }
  }

  String _errorMessage(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Future<String?> _askForRejectionReason() async {
    String reason = '';
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
          title: const Text('Reject customer withdrawal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'The existing rejection flow returns the held withdrawal amount '
                'to the customer’s wallet.',
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                maxLength: 180,
                onChanged: (String value) =>
                    setDialogState(() => reason = value),
                decoration: const InputDecoration(
                  labelText: 'Reason for rejection',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: reason.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, reason.trim()),
              child: const Text('Reject request'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    final String id = item['_id']?.toString() ?? '';
    if (id.isEmpty) {
      _showMessage('This withdrawal has no valid request ID.', error: true);
      return;
    }
    final String? reason = await _askForRejectionReason();
    if (reason == null || !mounted) return;
    await _runAction(() => _api.reject(id, reason: reason));
  }

  Future<void> _markPaid(Map<String, dynamic> item) async {
    final String id = item['_id']?.toString() ?? '';
    if (id.isEmpty) {
      _showMessage('This withdrawal has no valid request ID.', error: true);
      return;
    }
    final num? amount = _number(item['amount']);
    final String accountNumber = item['accountNumber']?.toString() ?? '';
    if (amount == null || amount <= 0 || accountNumber.trim().isEmpty) {
      _showMessage(
        'The request is missing a valid amount or beneficiary account.',
        error: true,
      );
      return;
    }
    final (String, String)? details = await _paymentDetails(item);
    if (details == null || !mounted) return;
    await _runAction(
      () => _api.markPaid(
        id,
        payoutReference: details.$1,
        adminNote: details.$2,
        manualPaymentConfirmed: true,
        expectedAmount: amount,
        expectedAccountNumber: accountNumber,
      ),
    );
  }

  Future<(String, String)?> _paymentDetails(
    Map<String, dynamic> item,
  ) async {
    String payoutReference = '';
    String adminNote = '';
    bool manualPaymentConfirmed = false;
    final (String, String)? result = await showDialog<(String, String)>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          final bool canConfirm =
              payoutReference.trim().isNotEmpty && manualPaymentConfirmed;
          return AlertDialog(
            title: const Text('Confirm manual bank transfer'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'First transfer the funds manually from the company bank '
                    'account to this beneficiary. This action only records your '
                    'attestation; ServicePay does not initiate or verify a bank '
                    'payment through an API. If the transfer is uncertain, '
                    'cancel and leave this request pending.',
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Transfer amount: ${_money(item['amount'])}\n'
                    'Bank: ${_text(item['bankName'])}\n'
                    'Beneficiary account: ${_text(item['accountNumber'])}\n'
                    'Beneficiary name: ${_text(item['accountName'])}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    maxLength: 120,
                    onChanged: (String value) => setDialogState(
                      () => payoutReference = value,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Payout / bank transfer reference',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextField(
                    maxLines: 2,
                    onChanged: (String value) => adminNote = value,
                    decoration: const InputDecoration(
                      labelText: 'Admin note (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: manualPaymentConfirmed,
                    onChanged: (bool? value) => setDialogState(
                      () => manualPaymentConfirmed = value ?? false,
                    ),
                    title: const Text(
                      'I attest that the company has actually completed this '
                      'transfer to the beneficiary and account shown above.',
                    ),
                    subtitle: const Text(
                      'Do not check this for a pending, uncertain, or failed transfer.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canConfirm
                    ? () => Navigator.pop(
                          dialogContext,
                          (payoutReference.trim(), adminNote.trim()),
                        )
                    : null,
                child: const Text('Confirm transfer already completed'),
              ),
            ],
          );
        },
      ),
    );
    return result;
  }

  Future<void> _runAction(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    setState(() {
      _acting = true;
      _error = '';
    });
    try {
      await action();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      if (_error.isEmpty) {
        _showMessage(
          'Action submitted. The queue shows the current server-recorded status.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _errorMessage(error);
        _loading = false;
      });
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  num? _number(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }

  String _money(dynamic value) {
    final num? amount = _number(value);
    return amount == null
        ? 'Amount unavailable'
        : '₦${amount.toStringAsFixed(2)}';
  }

  String _text(dynamic value, [String fallback = '-']) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  List<Map<String, dynamic>> get _filteredWithdrawals {
    final String query = _search.trim().toLowerCase();
    if (query.isEmpty) return _withdrawals;
    return _withdrawals.where((Map<String, dynamic> item) {
      final Map<String, dynamic> user = item['user'] is Map
          ? Map<String, dynamic>.from(item['user'] as Map)
          : <String, dynamic>{};
      final List<dynamic> searchValues = <dynamic>[
        user['fullName'],
        user['phone'],
        user['email'],
        item['reference'],
        item['bankName'],
        item['accountNumber'],
        item['accountName'],
        item['payoutReference'],
      ];
      return searchValues.any(
        (dynamic value) =>
            value?.toString().toLowerCase().contains(query) ?? false,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!_authorized) {
      return const Scaffold(
        body: Center(
          child: Text(
            'You do not have permission to view customer withdrawals.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Withdrawals'),
        actions: <Widget>[
          IconButton(
            onPressed: _loading || _acting ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh queue',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: <Widget>[
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(
                    labelText: 'Queue status',
                    border: OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
                    DropdownMenuItem(
                      value: 'APPROVED',
                      child: Text('Approved'),
                    ),
                    DropdownMenuItem(
                      value: 'REJECTED',
                      child: Text('Rejected'),
                    ),
                    DropdownMenuItem(value: 'ALL', child: Text('All')),
                  ],
                  onChanged: _loading || _acting
                      ? null
                      : (String? value) {
                          if (value == null) return;
                          setState(() => _status = value);
                          _load();
                        },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search customer, bank or reference',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (String value) => setState(() => _search = value),
                ),
              ],
            ),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MaterialBanner(
                content: Text(_error),
                actions: <Widget>[
                  TextButton(
                    onPressed: _loading || _acting ? null : _load,
                    child: const Text('Retry refresh'),
                  ),
                ],
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _filteredWithdrawals.isEmpty && !_loading
                  ? ListView(
                      children: <Widget>[
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            _error.isEmpty
                                ? 'No withdrawal requests found.'
                                : 'Unable to load the queue. Retry refresh.',
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredWithdrawals.length,
                      itemBuilder: (BuildContext context, int index) {
                        final Map<String, dynamic> item =
                            _filteredWithdrawals[index];
                        final Map<String, dynamic> user = item['user'] is Map
                            ? Map<String, dynamic>.from(item['user'] as Map)
                            : <String, dynamic>{};
                        final String status =
                            _text(item['status'], 'UNKNOWN').toUpperCase();
                        final bool pending = status == 'PENDING';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '${_text(user['fullName'], 'Customer')} • ${_money(item['amount'])}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${_text(user['phone'])} • ${_text(user['email'])}\n'
                                  '${_text(item['bankName'])} • ${_text(item['accountNumber'])}\n'
                                  '${_text(item['accountName'])}\n'
                                  'Request ref: ${_text(item['reference'])}\n'
                                  'Payout ref: ${_text(item['payoutReference'])}',
                                ),
                                const SizedBox(height: 8),
                                Chip(label: Text(status)),
                                if (pending)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Wrap(
                                      spacing: 8,
                                      children: <Widget>[
                                        OutlinedButton(
                                          onPressed: _acting
                                              ? null
                                              : () => _reject(item),
                                          child: const Text('Reject'),
                                        ),
                                        FilledButton(
                                          onPressed: _acting
                                              ? null
                                              : () => _markPaid(item),
                                          child: const Text('Mark paid'),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
