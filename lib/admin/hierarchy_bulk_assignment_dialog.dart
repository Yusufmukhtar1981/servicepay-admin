import 'dart:math';
import 'package:flutter/material.dart';
import 'phase1_operations_api.dart';

/// A reviewed batch is frozen while submitting or retrying an uncertain result.
/// Each item uses the existing server-side transactional assignment engine.
class HierarchyBulkAssignmentDialog extends StatefulWidget {
  const HierarchyBulkAssignmentDialog({
    super.key,
    required this.api,
    required this.customers,
    required this.parent,
  });
  final Phase1OperationsApi api;
  final List<Map<String, dynamic>> customers;
  final Map<String, dynamic> parent;

  @override
  State<HierarchyBulkAssignmentDialog> createState() =>
      _HierarchyBulkAssignmentDialogState();
}

class _HierarchyBulkAssignmentDialogState
    extends State<HierarchyBulkAssignmentDialog> {
  final _reason = TextEditingController();
  late final String _requestId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
  bool _busy = false;
  bool _submitted = false;
  bool _complete = false;
  String _frozenReason = '';
  String _error = '';
  List<Map<String, dynamic>> _results = [];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _complete) return;
    if (!_submitted && _reason.text.trim().length < 10) {
      setState(() => _error = 'Enter a reason of at least 10 characters.');
      return;
    }
    if (!_submitted) _frozenReason = _reason.text.trim();
    setState(() {
      _busy = true;
      _submitted = true;
      _error = '';
    });
    try {
      final response = await widget.api.assignCustomers(
        customers: widget.customers
            .map((customer) => <String, dynamic>{
                  'userId': customer['_id'],
                  'expectedParentId': customer['agentId'],
                })
            .toList(),
        parentId: '${widget.parent['_id']}',
        reason: _frozenReason,
        requestId: _requestId,
      );
      final raw = response['results'];
      if (raw is! List || raw.length != widget.customers.length) {
        throw Exception('Incomplete batch response. Retry this same batch.');
      }
      if (!mounted) return;
      setState(() {
        _results =
            raw.map((row) => Map<String, dynamic>.from(row as Map)).toList();
        _complete = _results.every((row) => row['success'] == true);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final c in widget.customers) '${c['_id']}': '${c['fullName']}'
    };
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Review customer assignments'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '${widget.customers.length} customers → ${widget.parent['fullName']}'),
              const SizedBox(height: 8),
              const Text('Each customer is checked and saved independently. '
                  'A blocked customer will not undo successful assignments. '
                  'Historical transactions and balances are never reassigned.'),
              const SizedBox(height: 8),
              ...widget.customers.map((customer) => Text(
                  '${customer['fullName']} · ${customer['phone'] ?? ''}\n'
                  'Reviewed Aggregator: ${customer['agentId'] ?? 'Unassigned'}')),
              const SizedBox(height: 16),
              TextField(
                controller: _reason,
                enabled: !_submitted,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration:
                    const InputDecoration(labelText: 'Batch assignment reason'),
              ),
              if (_error.isNotEmpty)
                Text(_error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_busy) const LinearProgressIndicator(),
              ..._results.map((row) => ListTile(
                    dense: true,
                    leading: Icon(row['success'] == true
                        ? Icons.check_circle_outline
                        : Icons.error_outline),
                    title:
                        Text(names['${row['userId']}'] ?? '${row['userId']}'),
                    subtitle: Text(row['success'] == true
                        ? (row['duplicate'] == true
                            ? 'Already applied; not duplicated.'
                            : 'Assignment saved and audited.')
                        : '${row['message'] ?? 'Assignment not completed.'}'),
                  )),
              if (_submitted && !_complete)
                const Text(
                    'Retry keeps the original reason, reviewed parents and request IDs. '
                    'Already saved items will not be duplicated. Close and refresh to review blocked items.'),
            ],
          )),
        ),
        actions: [
          TextButton(
              onPressed:
                  _busy ? null : () => Navigator.pop(context, _submitted),
              child: Text(_submitted ? 'Close and refresh' : 'Cancel')),
          if (!_complete)
            FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(
                    _submitted ? 'Retry same batch' : 'Confirm assignments')),
        ],
      ),
    );
  }
}
