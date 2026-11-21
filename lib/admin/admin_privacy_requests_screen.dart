import 'package:flutter/material.dart';

import 'admin_permissions.dart';
import 'admin_privacy_requests_api.dart';

const _privacyGreen = Color(0xFF08783E);
const _privacyInk = Color(0xFF17352B);
const _privacyPaper = Color(0xFFF5F8F6);

class AdminPrivacyRequestsScreen extends StatefulWidget {
  const AdminPrivacyRequestsScreen({super.key, this.api});
  final AdminPrivacyRequestsApi? api;

  @override
  State<AdminPrivacyRequestsScreen> createState() =>
      _AdminPrivacyRequestsScreenState();
}

class _AdminPrivacyRequestsScreenState
    extends State<AdminPrivacyRequestsScreen> {
  late final AdminPrivacyRequestsApi _api;
  final _search = TextEditingController();
  bool _loading = true;
  String _error = '';
  String _status = '';
  String _kind = '';
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  AdminAccess? _access;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? AdminPrivacyRequestsApi();
    _initialize();
  }

  @override
  void dispose() {
    _search.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _initialize() async {
    final access = await AdminSessionStore.loadAccess();
    if (!mounted) return;
    setState(() => _access = access);
    if (!access.has(AdminPermissions.privacyView)) {
      setState(() {
        _loading = false;
        _error = 'You do not have permission to view privacy requests.';
      });
      return;
    }
    await _load();
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  List<Map<String, dynamic>> _list(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((Map value) => Map<String, dynamic>.from(value))
          .toList()
      : <Map<String, dynamic>>[];
  String _text(dynamic value, [String fallback = '—']) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  bool get _canManage => _access?.has(AdminPermissions.privacyManage) ?? false;

  Future<void> _load() async {
    if (_access == null || !_access!.has(AdminPermissions.privacyView)) {
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final response = await _api.list(
        search: _search.text,
        status: _status,
        kind: _kind,
      );
      final data = _map(response['data']);
      if (!mounted) return;
      setState(() {
        _items = _list(data['items'] ?? response['items']);
        _loading = false;
      });
    } on AdminPrivacyRequestsException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load privacy requests.';
        _loading = false;
      });
    }
  }

  void _notice(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? const Color(0xFFB42318) : _privacyGreen,
        ),
      );
  }

  Color _statusColor(String status) => switch (status) {
        'PENDING' => const Color(0xFFB54708),
        'UNDER_REVIEW' => const Color(0xFF175CD3),
        'APPROVED' => const Color(0xFF027A48),
        'COMPLETED' => _privacyGreen,
        'REJECTED' => const Color(0xFFB42318),
        _ => Colors.blueGrey,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _privacyPaper,
        appBar: AppBar(
          title: const Text(
            'Account & Data Requests',
            style: TextStyle(fontWeight: FontWeight.w800, color: _privacyInk),
          ),
          backgroundColor: _privacyPaper,
          foregroundColor: _privacyInk,
          elevation: 0,
          actions: <Widget>[
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
                ? _errorView()
                : RefreshIndicator(onRefresh: _load, child: _body()),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.privacy_tip_outlined,
                size: 46,
                color: Colors.blueGrey,
              ),
              const SizedBox(height: 12),
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );

  Widget _body() => ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Text(
            'Privacy request review',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _privacyInk,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Review public account-deletion and specific-data requests. Completing account deletion disables sessions and anonymizes eligible account details while retained evidence remains intact.',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _search,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    hintText: 'Name, email, phone or reference',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      onPressed: _load,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              _filter(
                value: _status,
                hint: 'All statuses',
                values: const <String>[
                  'PENDING',
                  'UNDER_REVIEW',
                  'APPROVED',
                  'COMPLETED',
                  'REJECTED',
                ],
                onChanged: (value) {
                  setState(() => _status = value ?? '');
                  _load();
                },
              ),
              _filter(
                value: _kind,
                hint: 'All request types',
                values: const <String>['ACCOUNT_DELETION', 'DATA_REQUEST'],
                onChanged: (value) {
                  setState(() => _kind = value ?? '');
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_items.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Column(
                  children: <Widget>[
                    Icon(Icons.inbox_outlined,
                        size: 42, color: Colors.blueGrey),
                    SizedBox(height: 10),
                    Text('No privacy requests match these filters.'),
                  ],
                ),
              ),
            )
          else
            ..._items.map(_requestCard),
        ],
      );

  Widget _filter({
    required String value,
    required String hint,
    required List<String> values,
    required ValueChanged<String?> onChanged,
  }) =>
      SizedBox(
        width: 200,
        child: DropdownButtonFormField<String>(
          value: value.isEmpty ? null : value,
          decoration: InputDecoration(
            labelText: hint,
            filled: true,
            fillColor: Colors.white,
            border: const OutlineInputBorder(),
          ),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(value: '', child: Text('All')),
            ...values.map(
              (item) => DropdownMenuItem<String>(
                value: item,
                child: Text(item.replaceAll('_', ' ')),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      );

  Widget _requestCard(Map<String, dynamic> request) {
    final requester = _map(request['requester']);
    final status = _text(request['status'], 'PENDING').toUpperCase();
    final color = _statusColor(status);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          foregroundColor: color,
          child: Icon(
            request['requestKind'] == 'ACCOUNT_DELETION'
                ? Icons.person_remove_outlined
                : Icons.data_object_outlined,
          ),
        ),
        title: Text(
          _text(requester['fullName'], 'Unknown requester'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_text(request['referenceId'])}  •  ${_text(request['requestKind']).replaceAll('_', ' ')}\n${_text(requester['email'])}  •  ${_text(request['submittedAt'] ?? request['createdAt'])}',
        ),
        isThreeLine: true,
        trailing: Chip(
          label: Text(status.replaceAll('_', ' ')),
          labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
          backgroundColor: color.withValues(alpha: .10),
          side: BorderSide.none,
        ),
        onTap: () => _openDetail(request),
      ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> summary) async {
    Map<String, dynamic> request = summary;
    try {
      final response = await _api.detail(_text(summary['_id'], ''));
      request = _map(response['data']);
    } on AdminPrivacyRequestsException catch (error) {
      _notice(error.message, error: true);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _PrivacyRequestDialog(
        request: request,
        canManage: _canManage,
        onTransition: (status, note, password, evidence) async {
          await _api.update(
            _text(request['_id'], ''),
            status: status,
            note: note,
            currentPassword: password,
            completionEvidence: evidence,
          );
          _notice('Privacy request marked ${status.replaceAll('_', ' ')}.');
          await _load();
        },
      ),
    );
  }
}

class _PrivacyRequestDialog extends StatelessWidget {
  const _PrivacyRequestDialog({
    required this.request,
    required this.canManage,
    required this.onTransition,
  });

  final Map<String, dynamic> request;
  final bool canManage;
  final Future<void> Function(
    String status,
    String note,
    String? currentPassword,
    Map<String, dynamic>? completionEvidence,
  ) onTransition;

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  String _text(dynamic value, [String fallback = '—']) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  bool get _ownerVerified {
    final proof = _map(request['ownershipVerification']);
    return proof['verifiedAt'] != null &&
        const ['EMAIL_OTP', 'PASSWORD'].contains(proof['method']);
  }

  List<String> _actions(String status) => switch (status) {
        'PENDING' => <String>['UNDER_REVIEW', 'REJECTED'],
        'UNDER_REVIEW' => <String>[
            if (request['requestKind'] != 'ACCOUNT_DELETION' || _ownerVerified)
              'APPROVED',
            'REJECTED',
            'PENDING',
          ],
        'APPROVED' => <String>[
            if (request['requestKind'] != 'ACCOUNT_DELETION' || _ownerVerified)
              'COMPLETED',
            'REJECTED',
          ],
        _ => <String>[],
      };

  @override
  Widget build(BuildContext context) {
    final requester = _map(request['requester']);
    final subject = _map(request['subjectUser']);
    final status = _text(request['status'], 'PENDING').toUpperCase();
    final history = request['history'] is List
        ? (request['history'] as List)
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .toList()
        : <Map<String, dynamic>>[];
    return AlertDialog(
      title: Text(_text(request['referenceId'], 'Privacy request')),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _fields(<String, dynamic>{
                'Status': status.replaceAll('_', ' '),
                'Request': _text(request['requestKind']).replaceAll('_', ' '),
                'Data request type': request['dataRequestType'],
                'Submitted': request['submittedAt'] ?? request['createdAt'],
                'Processing deadline': request['processingDeadlineAt'],
                'Full name': requester['fullName'],
                'Registered phone': requester['phone'],
                'Registered email': requester['email'],
                'Matched customer': subject.isEmpty
                    ? 'Pending verification'
                    : '${_text(subject['fullName'])} (${_text(subject['status'])})',
                'Description / reason': request['description'],
                'Ownership verification': _map(
                        request['ownershipVerification'])['method'] ??
                    'Not verified — customer must use the secure deletion form.',
                'Ownership verified at':
                    _map(request['ownershipVerification'])['verifiedAt'],
                'Processing evidence': _map(request['completionEvidence'])[
                    'associatedDataReviewReference'],
                'Processor evidence': _map(request['completionEvidence'])[
                    'processorRequestsReference'],
                'Retention policy': _map(
                    request['completionEvidence'])['retentionPolicyReference'],
                'Retained categories':
                    _map(request['completionEvidence'])['retentionScope'],
                'Retention review date':
                    _map(request['completionEvidence'])['retentionReviewBy'],
              }),
              const SizedBox(height: 18),
              const Text(
                'Immutable request history',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (history.isEmpty)
                const Text('No history entries.')
              else
                ...history.map(
                  (entry) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history, size: 20),
                    title: Text(_text(entry['status']).replaceAll('_', ' ')),
                    subtitle: Text(
                      '${_text(entry['changedAt'])}\n${_text(entry['note'], 'No note')}',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (canManage)
          ..._actions(status).map(
            (next) => FilledButton(
              onPressed: () => _transition(context, next),
              style: next == 'REJECTED'
                  ? FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB42318),
                    )
                  : null,
              child: Text(next.replaceAll('_', ' ')),
            ),
          ),
      ],
    );
  }

  Widget _fields(Map<String, dynamic> fields) => Column(
        children: fields.entries
            .where((entry) => _text(entry.value, '').isNotEmpty)
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 150,
                      child: Text(
                        entry.key,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(child: SelectableText(_text(entry.value))),
                  ],
                ),
              ),
            )
            .toList(),
      );

  Future<void> _transition(BuildContext context, String status) async {
    final note = TextEditingController();
    final password = TextEditingController();
    final confirmation = TextEditingController();
    final associated = TextEditingController();
    final processors = TextEditingController();
    final policy = TextEditingController();
    final scope = TextEditingController();
    final reviewDate = TextEditingController();
    final completing =
        status == 'COMPLETED' && request['requestKind'] == 'ACCOUNT_DELETION';
    bool associatedReviewed = false;
    bool processorsReviewed = false;
    bool financialReviewed = false;
    bool busy = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _PrivacyDialogBuilder(
        onDispose: () {
          note.dispose();
          password.dispose();
          confirmation.dispose();
          associated.dispose();
          processors.dispose();
          policy.dispose();
          scope.dispose();
          reviewDate.dispose();
        },
        builder: (context, setState) => AlertDialog(
          title: Text('Mark ${status.replaceAll('_', ' ')}?'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (completing)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Irreversible: eligible profile/authentication data and saved contacts will be erased and sessions revoked. This does not move money. Resolve outstanding balances and transactions first. Record actual actions for all other personal data and processors; do not claim unperformed erasure. Retain financial/security records only under the applicable documented legal policy.',
                      ),
                    ),
                  TextField(
                    controller: note,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Review note / reason',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (completing) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: associated,
                      minLines: 2,
                      maxLines: 3,
                      maxLength: 1500,
                      decoration: const InputDecoration(
                        labelText: 'Associated-data erasure evidence',
                        helperText:
                            'Case/ticket references for all other associated personal data.',
                        helperMaxLines: 3,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextField(
                      controller: processors,
                      minLines: 2,
                      maxLines: 3,
                      maxLength: 1500,
                      decoration: const InputDecoration(
                        labelText: 'Processor deletion/retention evidence',
                        helperText:
                            'Identify relevant processors and request references or lawful retention basis. No secrets.',
                        helperMaxLines: 3,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextField(
                      controller: policy,
                      minLines: 2,
                      maxLines: 3,
                      maxLength: 1500,
                      decoration: const InputDecoration(
                        labelText:
                            'Applicable retention policy and legal basis',
                        helperText:
                            'Use the approved policy, not an invented retention duration.',
                        helperMaxLines: 3,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextField(
                      controller: scope,
                      minLines: 2,
                      maxLines: 3,
                      maxLength: 1500,
                      decoration: const InputDecoration(
                        labelText: 'Retained categories and retention schedule',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextField(
                      controller: reviewDate,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Next policy-based retention review',
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                        border: OutlineInputBorder(),
                      ),
                      onTap: () async {
                        final today = DateTime.now();
                        final date = await showDatePicker(
                          context: dialogContext,
                          initialDate: today.add(const Duration(days: 1)),
                          firstDate: today.add(const Duration(days: 1)),
                          lastDate: DateTime(today.year + 20),
                        );
                        if (date != null && dialogContext.mounted) {
                          reviewDate.text = date.toIso8601String();
                        }
                      },
                    ),
                    CheckboxListTile(
                      value: financialReviewed,
                      onChanged: busy
                          ? null
                          : (value) => setState(
                              () => financialReviewed = value ?? false),
                      title: const Text(
                          'All open financial and business obligations were reviewed and resolved. No balances were forfeited.'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: associatedReviewed,
                      onChanged: busy
                          ? null
                          : (value) => setState(
                              () => associatedReviewed = value ?? false),
                      title: const Text(
                          'Associated-data actions were actually completed and documented.'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: processorsReviewed,
                      onChanged: busy
                          ? null
                          : (value) => setState(
                              () => processorsReviewed = value ?? false),
                      title: const Text(
                          'All relevant processor requests or lawful retention were documented.'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    TextField(
                      controller: confirmation,
                      decoration: InputDecoration(
                        labelText:
                            'Type DELETE ${_text(request['referenceId'])}',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Your current Head Office password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed:
                  busy ? null : () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await onTransition(
                          status,
                          note.text,
                          completing ? password.text : null,
                          completing
                              ? <String, dynamic>{
                                  'confirmation': confirmation.text.trim(),
                                  'associatedDataReviewReference':
                                      associated.text.trim(),
                                  'processorRequestsReference':
                                      processors.text.trim(),
                                  'retentionPolicyReference':
                                      policy.text.trim(),
                                  'retentionScope': scope.text.trim(),
                                  'retentionReviewBy': reviewDate.text,
                                  'otherSystemsReviewed': associatedReviewed,
                                  'processorsReviewed': processorsReviewed,
                                  'financialObligationsReviewed':
                                      financialReviewed,
                                }
                              : null,
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } on AdminPrivacyRequestsException catch (error) {
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(
                          dialogContext,
                        ).showSnackBar(SnackBar(content: Text(error.message)));
                        setState(() => busy = false);
                      } catch (_) {
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Unable to update this request. Please try again.')),
                        );
                        setState(() => busy = false);
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && context.mounted) Navigator.of(context).pop();
  }
}

// Dispose sensitive field controllers only when the route has actually
// unmounted, not when showDialog resolves before its exit animation completes.
class _PrivacyDialogBuilder extends StatefulWidget {
  const _PrivacyDialogBuilder({
    required this.builder,
    required this.onDispose,
  });
  final StatefulWidgetBuilder builder;
  final VoidCallback onDispose;

  @override
  State<_PrivacyDialogBuilder> createState() => _PrivacyDialogBuilderState();
}

class _PrivacyDialogBuilderState extends State<_PrivacyDialogBuilder> {
  @override
  Widget build(BuildContext context) => widget.builder(context, setState);

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}
