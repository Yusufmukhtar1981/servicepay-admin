import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api_configuration.dart';

/// API boundary for the canonical customer virtual-account resource.
///
/// The class is deliberately overridable so widget tests and host applications
/// can inject an implementation without changing the account-management UI.
class AdminCustomerVirtualAccountApi {
  AdminCustomerVirtualAccountApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        baseUrl = (baseUrl ?? AdminApiConfiguration.baseUrl)
            .replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final bool _ownsClient;
  final String baseUrl;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ??
        prefs.getString('token') ??
        prefs.getString('admin_token');
    if (token == null || token.trim().isEmpty) {
      throw StateError('Admin login token was not found. Please login again.');
    }
    return token;
  }

  Map<String, String> _headers(String token, {bool jsonBody = false}) => {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        if (jsonBody) 'Content-Type': 'application/json',
      };

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      return value is Map ? Map<String, dynamic>.from(value) : {};
    } catch (_) {
      return {};
    }
  }

  String _safeMessage(Map<String, dynamic> body, int statusCode) {
    final message = (body['message'] ?? '').toString().trim();
    final sensitive = RegExp(
      r'(secret|token|api.?key|password|credential|authorization|stack.?trace|https?://)',
      caseSensitive: false,
    );
    final safeVocabulary = RegExp(
      r'(not eligible|not permitted|not allowed|permission|configuration|configured|allowlist|whitelist|reconcil|already exists|already active|unsupported|invalid|required|failed|retry|account|request|temporarily unavailable|try again)',
      caseSensitive: false,
    );
    if (message.isNotEmpty &&
        message.length <= 240 &&
        !sensitive.hasMatch(message) &&
        safeVocabulary.hasMatch(message)) {
      return message;
    }
    if (statusCode == 401 || statusCode == 403) {
      return 'Your Head Office access could not be confirmed. Sign in again or contact an administrator.';
    }
    if (statusCode == 404) {
      return 'Virtual-account management is not available for this customer.';
    }
    if (statusCode == 409) {
      return 'The account state changed. Refresh the customer record before continuing.';
    }
    if (statusCode == 503) {
      return 'Virtual-account provider configuration is unavailable. No provider details were exposed.';
    }
    return 'Unable to complete the virtual-account request. Refresh the account status before continuing.';
  }

  Map<String, dynamic> _data(http.Response response) {
    final body = _decode(response);
    final data = body['data'];
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] != true ||
        data is! Map) {
      throw Exception(_safeMessage(body, response.statusCode));
    }
    return Map<String, dynamic>.from(data);
  }

  Uri _uri(String customerId, {String? before}) {
    final uri = Uri.parse(
        '$baseUrl/admin/users/${Uri.encodeComponent(customerId)}/virtual-account');
    return before == null || before.isEmpty
        ? uri
        : uri.replace(queryParameters: {'before': before});
  }

  Future<Map<String, dynamic>> load({
    required String customerId,
    String? before,
  }) async {
    final token = await _token();
    final response = await _client
        .get(_uri(customerId, before: before), headers: _headers(token))
        .timeout(const Duration(seconds: 30));
    return _data(response);
  }

  Future<Map<String, dynamic>> generate({
    required String customerId,
    required String reason,
    required String requestId,
  }) async {
    final token = await _token();
    final response = await _client
        .post(
          _uri(customerId),
          headers: _headers(token, jsonBody: true),
          body: jsonEncode({'reason': reason, 'requestId': requestId}),
        )
        .timeout(const Duration(seconds: 30));
    return _data(response);
  }
}

String _newRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class AdminCustomerVirtualAccountAdmin extends StatefulWidget {
  const AdminCustomerVirtualAccountAdmin({
    super.key,
    required this.customerId,
    this.api,
  });

  final String customerId;
  final AdminCustomerVirtualAccountApi? api;

  @override
  State<AdminCustomerVirtualAccountAdmin> createState() =>
      _AdminCustomerVirtualAccountAdminState();
}

class _AdminCustomerVirtualAccountAdminState
    extends State<AdminCustomerVirtualAccountAdmin> {
  static const _ink = Color(0xff173b40);
  static const _teal = Color(0xff087f78);
  static const _canvas = Color(0xfff3f7f5);
  late final AdminCustomerVirtualAccountApi _api =
      widget.api ?? AdminCustomerVirtualAccountApi();
  Map<String, dynamic>? _snapshot;
  List<Map<String, dynamic>> _history = [];
  String? _cursor;
  String? _error;
  String? _actionError;
  bool _loading = true;
  bool _loadingMore = false;
  bool _submitting = false;
  bool _uncertainIntent = false;
  String? _pendingReason;
  String? _pendingRequestId;

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  String _text(dynamic value, [String fallback = 'Not provided']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Map<String, dynamic> get _account =>
      _map(_map(_snapshot?['virtualAccount']));
  Map<String, dynamic> get _eligibility =>
      _map(_snapshot?['eligibility']);

  bool _isActiveAccount(Map<String, dynamic> snapshot) {
    final account = _map(snapshot['virtualAccount']);
    final number = account['accountNumber']?.toString().trim() ?? '';
    final status = account['status']?.toString().trim().toUpperCase() ?? '';
    return number.isNotEmpty && status == 'ACTIVE';
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool preserveIntent = true}) async {
    if (_loading && _snapshot != null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.load(customerId: widget.customerId);
      if (!mounted) return;
      setState(() {
        _snapshot = data;
        _history = _historyItems(data['history']);
        _cursor = data['nextCursor']?.toString();
        _loading = false;
        if (!preserveIntent || _isActiveAccount(data)) {
          _uncertainIntent = false;
          _pendingReason = null;
          _pendingRequestId = null;
          _actionError = null;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _cleanError(error);
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _historyItems(dynamic value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];

  String _cleanError(Object error) =>
      error.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (cursor == null || cursor.isEmpty || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final data = await _api.load(customerId: widget.customerId, before: cursor);
      if (!mounted) return;
      setState(() {
        final knownIds = _history
            .map((item) => item['id']?.toString())
            .whereType<String>()
            .toSet();
        _history.addAll(
          _historyItems(data['history']).where(
            (item) => item['id'] == null ||
                !knownIds.contains(item['id'].toString()),
          ),
        );
        _cursor = data['nextCursor']?.toString();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _beginAction({required bool retry}) async {
    if (_submitting || _uncertainIntent) return;
    var reasonText = '';
    final confirmed = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => PopScope<void>(
          canPop: !_submitting,
          child: AlertDialog(
            scrollable: true,
            title: Text(retry ? 'Retry failed generation?' : 'Generate virtual account?'),
            content: SizedBox(
              width: 460,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                  'This sends one request to the configured provider. If the result is uncertain, the request will not be submitted again automatically.',
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('virtual-account-reason'),
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (value) {
                    reasonText = value;
                    setDialogState(() {});
                  },
                  decoration: const InputDecoration(
                    labelText: 'Operational reason (5–500 characters)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (reasonText.trim().length < 5)
                  const Text('Enter a reason of at least 5 characters.',
                      style: TextStyle(color: Color(0xff9b3d32), fontSize: 12)),
              ]),
            ),
            actions: [
              TextButton(
                key: const Key('virtual-account-cancel'),
                onPressed: _submitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('virtual-account-confirm'),
                onPressed: reasonText.trim().length < 5 || _submitting
                    ? null
                    : () => Navigator.pop(dialogContext, reasonText.trim()),
                child: Text(retry ? 'Confirm retry' : 'Confirm generation'),
              ),
            ],
          ),
        ),
      ),
    );
    final reason = confirmed?.trim() ?? '';
    if (reason.length < 5 || reason.length > 500 || !mounted) return;

    final requestId = _newRequestId();
    setState(() {
      _submitting = true;
      _actionError = null;
      _pendingReason = reason;
      _pendingRequestId = requestId;
    });
    try {
      final data = await _api.generate(
        customerId: widget.customerId,
        reason: reason,
        requestId: requestId,
      );
      if (mounted) {
        setState(() {
          _snapshot = data;
          _history = _historyItems(data['history']);
          _cursor = data['nextCursor']?.toString();
          if (_isActiveAccount(data)) {
            _uncertainIntent = false;
            _pendingReason = null;
            _pendingRequestId = null;
            _actionError = null;
          } else {
            _uncertainIntent = true;
            _actionError =
                'The request was recorded, but an active account is not confirmed. Current status: ${_text(_map(data['virtualAccount'])['status'], 'unknown')}. Refresh and review history; do not submit again.';
          }
        });
      }
      if (!_isActiveAccount(data)) {
        // HTTP success can mean the intent was recorded while processing is
        // pending. Read canonical state once; never replay the provider POST.
        try {
          final refreshed = await _api.load(customerId: widget.customerId);
          if (mounted) {
            setState(() {
              _snapshot = refreshed;
              _history = _historyItems(refreshed['history']);
              _cursor = refreshed['nextCursor']?.toString();
              if (_isActiveAccount(refreshed)) {
                _uncertainIntent = false;
                _pendingReason = null;
                _pendingRequestId = null;
                _actionError = null;
              }
            });
          }
        } catch (_) {
          // Keep the response and its retained intent visible.
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uncertainIntent = true;
        _actionError = _cleanError(error);
      });
      // The write may have reached the provider. Refresh only; never replay it.
      try {
        final refreshed = await _api.load(customerId: widget.customerId);
        if (mounted) {
          setState(() {
            _snapshot = refreshed;
            _history = _historyItems(refreshed['history']);
            _cursor = refreshed['nextCursor']?.toString();
            if (_isActiveAccount(refreshed)) {
              _uncertainIntent = false;
              _pendingReason = null;
              _pendingRequestId = null;
            }
          });
        }
      } catch (_) {
        // Keep intent and original safe error visible when reconciliation is unavailable.
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _clearReviewedIntent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear uncertain request?'),
        content: const Text(
          'Only clear this intent after reviewing the refreshed account and provider outcome. Clearing it does not send another request.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep intent')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear intent')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _uncertainIntent = false;
        _pendingReason = null;
        _pendingRequestId = null;
      });
    }
  }

  Future<void> _copy(String label, String value) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label copied to clipboard')),
      );
    }
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(_text(value, ''));
    if (date == null) return 'Date unavailable';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  bool get _canGenerate => _eligibility['canGenerate'] == true;
  bool get _canRetry => _eligibility['canRetry'] == true;

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_submitting,
      child: Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: _canvas,
        foregroundColor: _ink,
        title: const Text('Customer virtual account'),
        actions: [
          IconButton(
            key: const Key('virtual-account-refresh'),
            tooltip: 'Refresh account status',
            onPressed: _loading || _submitting ? null : () => _refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading && _snapshot == null
          ? const _AccountSkeleton()
          : RefreshIndicator(
              onRefresh: () => _refresh(),
              child: ListView(
                key: const Key('virtual-account-scroll'),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                children: [
                  _heading(),
                  if (_error != null) _errorBanner(_error!),
                  if (_actionError != null) _errorBanner(_actionError!),
                  if (_uncertainIntent) _uncertainBanner(),
                  if (_snapshot != null) ...[
                    _customerCard(_map(_snapshot!['customer'])),
                    _accountCard(),
                    _eligibilityCard(),
                    _historyCard(),
                  ],
                  if (_snapshot == null && !_loading && _error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: OutlinedButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry loading account'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
      ),
    );
  }

  Widget _heading() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SERVICEPAY / HEAD OFFICE',
                style: TextStyle(
                    color: Color(0xff8fd2c5),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 1.3)),
            SizedBox(height: 10),
            Text('Bank details, plainly.',
                style: TextStyle(
                    color: Color(0xfff4faf7),
                    fontWeight: FontWeight.w800,
                    fontSize: 24)),
            SizedBox(height: 6),
            Text(
              'The account shown here is the backend record. Provider requests are never repeated automatically.',
              style: TextStyle(color: Color(0xffc0d8d3), height: 1.4),
            ),
          ],
        ),
      );

  Widget _customerCard(Map<String, dynamic> customer) => _Panel(
        title: 'Customer',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_text(customer['fullName']),
              key: const Key('virtual-account-customer-name'),
              style: const TextStyle(
                  color: _ink, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _copyLine('Phone', _text(customer['phone'], ''), Icons.call_outlined),
          _copyLine('Email', _text(customer['email'], ''), Icons.mail_outline),
        ]),
      );

  Widget _accountCard() {
    final account = _account;
    final hasAccount = account.isNotEmpty &&
        _text(account['accountNumber'], '').isNotEmpty;
    final status = _text(account['status'], hasAccount ? 'UNKNOWN' : 'NOT CREATED');
    final statusText = status.replaceAll('_', ' ');
    final failure = _text(account['failureReason'], '');
    return _Panel(
      title: 'Bank account',
      trailing: _StatusChip(status: statusText, known: hasAccount),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!hasAccount)
          const _Notice(
            text: 'No account number is recorded. A provider response is not treated as an account until it appears in this backend record.',
          )
        else ...[
          _accountDetail('Account name', _text(account['accountName']), copyable: true),
          _accountDetail('Account number', _text(account['accountNumber']), copyable: true, prominent: true),
          _accountDetail('Bank', _text(account['bankName'])),
          _accountDetail('Bank code', _text(account['bankCode']), copyable: true),
          _accountDetail('Provider', _text(account['provider'])),
          _accountDetail('Created', _date(account['createdAt'])),
          _accountDetail('Last updated', _date(account['updatedAt'])),
        ],
        if (failure.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Notice(text: 'Last failure: $failure', warning: true),
        ],
      ]),
    );
  }

  Widget _accountDetail(String label, String value,
      {bool copyable = false, bool prominent = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 122,
          child: Text(label,
              style: const TextStyle(color: Color(0xff6c817d), fontSize: 12)),
        ),
        Expanded(
          child: SelectableText(value,
              style: TextStyle(
                color: _ink,
                fontSize: prominent ? 20 : 14,
                fontWeight: prominent ? FontWeight.w900 : FontWeight.w700,
                letterSpacing: prominent ? 1.1 : 0,
              )),
        ),
        if (copyable)
          IconButton(
            key: Key('copy-${label.toLowerCase().replaceAll(' ', '-')}'),
            visualDensity: VisualDensity.compact,
            tooltip: 'Copy $label',
            onPressed: () => _copy(label, value),
            icon: const Icon(Icons.copy_rounded, size: 17),
          ),
      ]),
    );
  }

  Widget _copyLine(String label, String value, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(children: [
          Icon(icon, size: 16, color: const Color(0xff718782)),
          const SizedBox(width: 8),
          Expanded(child: Text('$label  $value', style: const TextStyle(color: Color(0xff526c67)))),
          if (value.isNotEmpty)
            IconButton(
              key: Key('copy-customer-${label.toLowerCase()}'),
              tooltip: 'Copy $label',
              visualDensity: VisualDensity.compact,
              onPressed: () => _copy(label, value),
              icon: const Icon(Icons.copy_rounded, size: 16),
            ),
        ]),
      );

  Widget _eligibilityCard() {
    final disabled = _submitting || _uncertainIntent || _loading;
    final actionAllowed = _canGenerate || _canRetry;
    final actionLabel = _canRetry ? 'Retry Failed Generation' : 'Generate virtual account';
    return _Panel(
      title: 'Provider request',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_eligibility['requiresReconciliation'] == true)
          const _Notice(
            text: 'Reconciliation is required before another provider request. Do not retry from this screen.',
            warning: true,
          ),
        if (_text(_eligibility['reason'], '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_text(_eligibility['reason']),
                style: const TextStyle(color: Color(0xff526c67), height: 1.4)),
          ),
        if (_uncertainIntent)
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              key: const Key('virtual-account-review-refresh'),
              onPressed: _loading ? null : () => _refresh(),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Refresh canonical status'),
            ),
            TextButton(
              key: const Key('virtual-account-clear-intent'),
              onPressed: _loading ? null : _clearReviewedIntent,
              child: const Text('Clear reviewed intent'),
            ),
          ])
        else
          FilledButton.icon(
            key: const Key('virtual-account-request'),
            onPressed: !actionAllowed || disabled
                ? null
                : () => _beginAction(retry: _canRetry),
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.account_balance_outlined),
            label: Text(_submitting ? 'Submitting once…' : actionLabel),
            style: FilledButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white),
          ),
        const SizedBox(height: 8),
        const Text(
          'Existing bank details remain unchanged. No manual account creation, activation, reset or account-number editing is available here.',
          style: TextStyle(color: Color(0xff708783), fontSize: 12, height: 1.4),
        ),
      ]),
    );
  }

  Widget _historyCard() => _Panel(
        title: 'Generation history',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_snapshot?['lookupSupported'] == false)
            const _Notice(
              text: 'Provider lookup is not supported. History and current account status reflect this service’s recorded state only.',
            ),
          if (_history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No generation history recorded.',
                  style: TextStyle(color: Color(0xff708783))),
            )
          else
            ..._history.map(_historyItem),
          if (_cursor != null && _cursor!.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const Key('virtual-account-load-more'),
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(_loadingMore ? 'Loading…' : 'Load more history'),
              ),
            ),
        ]),
      );

  Widget _historyItem(Map<String, dynamic> item) => Container(
        key: Key('virtual-account-history-${_text(item['id'], 'unknown')}'),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xfff4f8f6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_text(item['action'], 'Account event').replaceAll('_', ' '),
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${_text(item['outcome'])} · ${_date(item['createdAt'])}',
              style: const TextStyle(color: Color(0xff526c67), fontSize: 12)),
          const SizedBox(height: 4),
          Text('By ${_text(item['actorName'])} · ${_text(item['reason'])}',
              style: const TextStyle(color: Color(0xff526c67), fontSize: 12)),
          if (_text(item['requestId'], '').isNotEmpty)
            Text('Request ${_text(item['requestId'])}',
                style: const TextStyle(color: Color(0xff708783), fontSize: 11)),
        ]),
      );

  Widget _uncertainBanner() => Container(
        key: const Key('virtual-account-uncertain'),
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xfffff3dc),
          border: Border.all(color: const Color(0xffe6c77d)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Outcome uncertain — request not repeated',
              style: TextStyle(
                  color: Color(0xff73521a), fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text(
            'Reason retained: ${_pendingReason ?? 'Not available'}. Request ${_pendingRequestId ?? 'not available'}. Refresh the backend record and review history before clearing this intent. No automatic retry was sent.',
            style: const TextStyle(color: Color(0xff73521a), height: 1.4),
          ),
        ]),
      );

  Widget _errorBanner(String message) => Container(
        key: const Key('virtual-account-error'),
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xffffefed),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Color(0xffa84539), size: 19),
          const SizedBox(width: 9),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: Color(0xff8d3d33)))),
          TextButton(
              onPressed: _loading ? null : () => _refresh(),
              child: const Text('Refresh')),
        ]),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffdce9e5)),
          borderRadius: BorderRadius.circular(17),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final heading = Text(title,
              style: const TextStyle(
                  color: Color(0xff173b40),
                  fontSize: 15,
                  fontWeight: FontWeight.w800));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (trailing == null)
              heading
            else if (constraints.maxWidth < 390) ...[
              heading,
              Align(alignment: Alignment.centerRight, child: trailing!),
            ] else
              Row(children: [heading, const Spacer(), trailing!]),
            const SizedBox(height: 12),
            child,
          ]);
        }),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.known});
  final String status;
  final bool known;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: known ? const Color(0xffe4f2eb) : const Color(0xfff3eee3),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(status,
            style: TextStyle(
              color: known ? const Color(0xff236449) : const Color(0xff7a5b22),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .4,
            )),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.warning = false});
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: warning ? const Color(0xfffff3dc) : const Color(0xffedf5f2),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(text,
            style: TextStyle(
              color: warning ? const Color(0xff73521a) : const Color(0xff46635d),
              fontSize: 12,
              height: 1.45,
            )),
      );
}

class _AccountSkeleton extends StatelessWidget {
  const _AccountSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(
          4,
          (index) => Container(
            height: index == 0 ? 150 : 110,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xffe4eeea),
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      );
}
