import 'dart:async';

import 'package:flutter/material.dart';

import 'admin_control_center_download.dart';
import 'admin_customer_360_api.dart';
import 'admin_permissions.dart';
import 'admin_virtual_account_management_api.dart';
import 'customer_360_directory.dart';
import 'customer_virtual_account_admin.dart';

typedef VirtualAccountReportDownloader = Future<void> Function(
    List<int> bytes, String contentType, String filename);

/// A write that was sent but whose outcome is not proven. The same requestId
/// is kept so an explicit resubmission stays idempotent server-side.
class _Intent {
  _Intent({
    required this.kind,
    required this.requestId,
    required this.reason,
    this.mode = 'ALL',
    this.customerIds = const [],
    this.jobId,
  });
  final String kind; // create | retry
  final String requestId, reason, mode;
  final List<String> customerIds;
  final String? jobId;
}

class AdminVirtualAccountManagementScreen extends StatefulWidget {
  const AdminVirtualAccountManagementScreen({
    super.key,
    this.api,
    this.directoryApi,
    this.virtualAccountApi,
    this.access,
    this.downloader,
    this.pollInterval = const Duration(seconds: 5),
  });

  final AdminVirtualAccountManagementApi? api;
  final AdminCustomer360Api? directoryApi;
  final AdminCustomerVirtualAccountApi? virtualAccountApi;
  final AdminAccess? access;
  final VirtualAccountReportDownloader? downloader;
  final Duration pollInterval;

  @override
  State<AdminVirtualAccountManagementScreen> createState() =>
      _AdminVirtualAccountManagementScreenState();
}

class _AdminVirtualAccountManagementScreenState
    extends State<AdminVirtualAccountManagementScreen>
    with WidgetsBindingObserver {
  static const _ink = Color(0xff173b40);
  static const _teal = Color(0xff087f78);
  static const _mint = Color(0xffe7f4ef);
  static const _canvas = Color(0xfff3f7f5);
  static const _muted = Color(0xff708783);

  late final AdminVirtualAccountManagementApi _api =
      widget.api ?? AdminVirtualAccountManagementApi();
  late final AdminCustomer360Api _directoryApi =
      widget.directoryApi ?? AdminCustomer360Api();
  late final AdminCustomerVirtualAccountApi _vaApi =
      widget.virtualAccountApi ?? AdminCustomerVirtualAccountApi();

  VirtualAccountSummary? _summary;
  String? _summaryError;
  bool _loadingSummary = true;

  List<VirtualAccountJob> _jobs = [];
  VirtualAccountPagination _jobsPagination = const VirtualAccountPagination();
  String? _jobsError;
  bool _loadingJobs = true;

  VirtualAccountJobDetail? _detail;
  String? _detailError;
  bool _loadingDetail = false;
  int _detailPage = 1;

  final Map<String, String> _selected = {};
  _Intent? _intent;
  String? _actionError;
  String? _notice;
  bool _submitting = false;
  bool _downloading = false;

  Timer? _poll;
  bool _resumed = true;
  bool _visible = true;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pages hidden in the navigation stack run with tickers disabled.
    _visible = TickerMode.of(context);
    _syncPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _syncPolling();
    if (_resumed && _hasActiveJob) _pollTick();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _poll = null;
    WidgetsBinding.instance.removeObserver(this);
    if (widget.api == null) _api.dispose();
    if (widget.directoryApi == null) _directoryApi.close();
    if (widget.virtualAccountApi == null) _vaApi.dispose();
    super.dispose();
  }

  bool get _hasActiveJob =>
      _jobs.any((j) => j.isActive) || (_detail?.job.isActive ?? false);

  void _syncPolling() {
    final shouldPoll = !_disposed && _resumed && _visible && _hasActiveJob;
    if (shouldPoll && _poll == null) {
      _poll = Timer.periodic(widget.pollInterval, (_) => _pollTick());
    } else if (!shouldPoll && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  bool _polling = false;
  Future<void> _pollTick() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      await _loadJobs(_jobsPagination.page, quiet: true);
      if (_detail != null) await _loadDetail(_detail!.job.id, _detailPage, quiet: true);
    } finally {
      _polling = false;
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _refreshAll() async {
    await Future.wait([_loadSummary(), _loadJobs(1)]);
  }

  Future<void> _loadSummary() async {
    if (mounted) {
      setState(() {
        _loadingSummary = true;
        _summaryError = null;
      });
    }
    try {
      final s = await _api.summary();
      if (mounted) setState(() => _summary = s);
    } catch (e) {
      if (mounted) setState(() => _summaryError = _clean(e));
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  Future<void> _loadJobs(int page, {bool quiet = false}) async {
    if (!quiet && mounted) {
      setState(() {
        _loadingJobs = true;
        _jobsError = null;
      });
    }
    try {
      final result = await _api.jobs(page: page);
      if (!mounted) return;
      setState(() {
        _jobs = result.items;
        _jobsPagination = result.pagination;
        _jobsError = null;
      });
    } catch (e) {
      if (mounted && !quiet) setState(() => _jobsError = _clean(e));
    } finally {
      if (mounted) {
        setState(() => _loadingJobs = false);
        _syncPolling();
      }
    }
  }

  Future<void> _loadDetail(String id, int page, {bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loadingDetail = true;
        _detailError = null;
      });
    }
    try {
      final d = await _api.job(id, page: page);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _detailPage = page;
        _detailError = null;
      });
    } catch (e) {
      if (mounted && !quiet) setState(() => _detailError = _clean(e));
    } finally {
      if (mounted) {
        setState(() => _loadingDetail = false);
        _syncPolling();
      }
    }
  }

  bool get _storageReady => _summary?.storageReady == true;
  bool get _canGenerate => _summary?.permissions.generate == true;
  bool get _canBulk => _summary?.permissions.bulk == true;
  /// Every background job (ALL or SELECTED) needs both permissions.
  bool get _canCreateJobs => _canGenerate && _canBulk;

  // ---------------------------------------------------------------- writes

  Future<({String reason, String mode})?> _confirm({
    required bool retry,
    VirtualAccountJob? job,
  }) {
    var reason = '';
    var mode = _selected.isNotEmpty ? 'SELECTED' : 'ALL';
    var acknowledged = false;
    return showDialog<({String reason, String mode})>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final count = mode == 'ALL'
            ? 'all existing customers (${_summary?.withoutAccounts ?? 0} currently without accounts)'
            : '${_selected.length} selected customers';
        final modeOk = retry ||
            (_canCreateJobs && (mode == 'ALL' || _selected.isNotEmpty));
        final valid = reason.trim().length >= 5 &&
            reason.trim().length <= 500 &&
            acknowledged &&
            modeOk;
        return AlertDialog(
          scrollable: true,
          title: Text(retry ? 'Retry failed customers?' : 'Generate missing accounts?'),
          content: SizedBox(
            width: 480,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!retry) ...[
                    RadioListTile<String>(
                      key: const Key('va-mode-all'),
                      contentPadding: EdgeInsets.zero,
                      value: 'ALL',
                      groupValue: mode,
                      onChanged: _canCreateJobs ? (v) => setD(() => mode = v!) : null,
                      title: const Text('All eligible customers'),
                      subtitle: const Text(
                          'Existing customers up to a fixed cutoff are evaluated. Existing accounts are kept without provider calls; only eligible customers are generated.'),
                    ),
                    RadioListTile<String>(
                      key: const Key('va-mode-selected'),
                      contentPadding: EdgeInsets.zero,
                      value: 'SELECTED',
                      groupValue: mode,
                      onChanged: _canCreateJobs && _selected.isNotEmpty
                          ? (v) => setD(() => mode = v!)
                          : null,
                      title: Text('Selected customers (${_selected.length})'),
                    ),
                    const SizedBox(height: 6),
                    Text('Scope: $count',
                        key: const Key('va-confirm-scope'),
                        style: const TextStyle(
                            color: _ink, fontWeight: FontWeight.w700)),
                  ] else
                    Text(
                        'Only failed customers the server marks as safe are retried for job ${job?.id}. Pending or uncertain customers are excluded.',
                        style: const TextStyle(height: 1.4)),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('va-reason'),
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (v) => setD(() => reason = v),
                    decoration: const InputDecoration(
                        labelText: 'Operational reason (5–500 characters)',
                        border: OutlineInputBorder()),
                  ),
                  CheckboxListTile(
                    key: const Key('va-acknowledge'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: acknowledged,
                    onChanged: (v) => setD(() => acknowledged = v == true),
                    title: const Text(
                        'I confirm this sends provider requests once. Uncertain results are not resent automatically.',
                        style: TextStyle(fontSize: 13)),
                  ),
                ]),
          ),
          actions: [
            TextButton(
                key: const Key('va-cancel'),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              key: const Key('va-confirm'),
              style: FilledButton.styleFrom(backgroundColor: _teal),
              onPressed: valid
                  ? () => Navigator.pop(ctx, (reason: reason.trim(), mode: mode))
                  : null,
              child: Text(retry ? 'Confirm retry' : 'Confirm generation'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _startGenerate() async {
    if (_submitting || _intent != null || !_storageReady || !_canCreateJobs) {
      return;
    }
    final result = await _confirm(retry: false);
    if (result == null || !mounted) return;
    await _submit(_Intent(
      kind: 'create',
      requestId: newVirtualAccountJobRequestId(),
      reason: result.reason,
      mode: result.mode,
      customerIds: result.mode == 'ALL' ? const [] : _selected.keys.toList(),
    ));
  }

  Future<void> _startRetry(VirtualAccountJob job) async {
    if (_submitting || _intent != null || !_storageReady || !_canCreateJobs) {
      return;
    }
    final result = await _confirm(retry: true, job: job);
    if (result == null || !mounted) return;
    await _submit(_Intent(
      kind: 'retry',
      requestId: newVirtualAccountJobRequestId(),
      reason: result.reason,
      jobId: job.id,
    ));
  }

  /// Sends exactly one POST. Ambiguous outcomes keep the intent (same
  /// requestId) and only refresh; they never re-POST.
  Future<void> _submit(_Intent intent) async {
    setState(() {
      _submitting = true;
      _intent = intent;
      _actionError = null;
      _notice = null;
    });
    try {
      final job = intent.kind == 'create'
          ? await _api.createJob(
              requestId: intent.requestId,
              reason: intent.reason,
              mode: intent.mode,
              customerIds: intent.customerIds)
          : await _api.retryJob(
              jobId: intent.jobId!,
              requestId: intent.requestId,
              reason: intent.reason);
      if (!mounted) return;
      setState(() {
        _intent = null;
        if (intent.kind == 'create') _selected.clear();
        _notice = 'Job ${job.id} recorded with status ${job.status}.';
      });
      await Future.wait([_loadSummary(), _loadJobs(1)]);
      if (mounted && job.id.isNotEmpty) await _loadDetail(job.id, 1);
    } on VirtualAccountManagementException catch (e) {
      if (!mounted) return;
      setState(() {
        _actionError = e.message;
        if (!e.ambiguous) _intent = null;
      });
      if (e.ambiguous) await _loadJobs(1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = _clean(e));
      await _loadJobs(1);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resubmitSameRequest() async {
    final intent = _intent;
    if (intent == null || _submitting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resubmit with the same request ID?'),
        content: Text(
            'Request ${intent.requestId} is sent again unchanged. The server treats it as the same request, so a job that was already recorded is not duplicated. Check the job list first.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('va-resubmit-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Resubmit')),
        ],
      ),
    );
    if (ok == true && mounted) await _submit(intent);
  }

  Future<void> _discardIntent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear uncertain request?'),
        content: const Text(
            'Only clear this after confirming the job list. Clearing does not send anything.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          FilledButton(
              key: const Key('va-discard-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        _intent = null;
        _actionError = null;
      });
    }
  }

  Future<void> _download(VirtualAccountJob job) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final report = await _api.report(job.id);
      final downloader = widget.downloader ?? downloadControlCenterBytes;
      await downloader(report.bytes, 'text/csv;charset=utf-8', report.filename);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloaded ${report.filename}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is UnsupportedError
                ? 'Report download is available in the web Admin only.'
                : _clean(e))));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _openIndividual(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || !_canGenerate) return;
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        child: AdminCustomerVirtualAccountAdmin(customerId: id, api: _vaApi),
      ),
    );
    if (mounted) _loadSummary();
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: _canvas,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text('Virtual Account Management',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            key: const Key('va-refresh'),
            tooltip: 'Refresh',
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          key: const Key('va-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            _intro(),
            const SizedBox(height: 14),
            _summarySection(),
            if (_intent != null && !_submitting && _actionError != null)
              _uncertainBanner()
            else if (_actionError != null)
              _banner(_actionError!, key: const Key('va-action-error')),
            if (_notice != null)
              _banner(_notice!, ok: true, key: const Key('va-notice')),
            _generateSection(),
            _jobsSection(),
            if (_detail != null || _loadingDetail || _detailError != null)
              _detailSection(),
            if (_summary != null && (_canGenerate || _canBulk))
              AdminCustomer360Directory(
                api: _directoryApi,
                title: 'Select customers',
                initialAccount: 'WITHOUT',
                selectedIds: _selected.keys.toSet(),
                onToggleSelected: _canCreateJobs
                    ? (item, on) => setState(() {
                          final id = item['id'].toString();
                          on
                              ? _selected[id] = '${item['fullName'] ?? id}'
                              : _selected.remove(id);
                        })
                    : null,
                onOpenVirtualAccount: _canGenerate ? _openIndividual : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _intro() => Container(
        padding: const EdgeInsets.all(22),
        decoration:
            BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(22)),
        child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SERVICEPAY / OPERATIONS',
                  style: TextStyle(
                      color: Color(0xff8fd2c5),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5)),
              SizedBox(height: 12),
              Text('Every customer, one bank account.',
                  style: TextStyle(
                      color: Color(0xfff4faf7),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.1)),
              SizedBox(height: 8),
              Text(
                  'Figures come from the backend record. Requests are sent once and never repeated automatically.',
                  style: TextStyle(color: Color(0xffc0d8d3), height: 1.4)),
            ]),
      );

  Widget _summarySection() {
    if (_loadingSummary && _summary == null) return _skeleton(96);
    if (_summaryError != null && _summary == null) {
      return _banner(_summaryError!,
          key: const Key('va-summary-error'), retry: _loadSummary);
    }
    final s = _summary!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!s.storageReady)
        _banner(
          'Job storage is not ready. Generation is disabled until the backend reports storage as ready. No requests have been sent.',
          key: const Key('va-storage-missing'),
        ),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _metric('Customers', '${s.totalCustomers}'),
        _metric('With accounts', '${s.withAccounts}'),
        _metric('Without accounts', '${s.withoutAccounts}', strong: true),
      ]),
    ]);
  }

  Widget _generateSection() {
    if (_summary == null) return const SizedBox.shrink();
    final allowed = _canCreateJobs && _storageReady;
    final blocked = _submitting || _intent != null;
    return _card(
      title: 'Generate missing accounts',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          !_canCreateJobs
              ? (_canGenerate
                  ? 'Background jobs require both generate and bulk permissions. Use Virtual account on a customer below for individual generation.'
                  : 'Your access is view-only. Generation requires operations permissions.')
              : _selected.isEmpty
                  ? 'Run for all eligible customers, or select customers below.'
                  : '${_selected.length} customers selected.',
          style: const TextStyle(color: _muted, height: 1.4),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('va-generate'),
            style: FilledButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: allowed && !blocked ? _startGenerate : null,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.account_balance_outlined),
            label: Text(_submitting
                ? 'Submitting once…'
                : 'Generate Missing Accounts'),
          ),
        ),
        if (_selected.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('va-clear-selection'),
              onPressed: blocked ? null : () => setState(_selected.clear),
              child: const Text('Clear selection'),
            ),
          ),
      ]),
    );
  }

  Widget _jobsSection() => _card(
        title: 'Jobs',
        child: _loadingJobs && _jobs.isEmpty
            ? _skeleton(80)
            : _jobsError != null
                ? _banner(_jobsError!,
                    key: const Key('va-jobs-error'),
                    retry: () => _loadJobs(_jobsPagination.page))
                : _jobs.isEmpty
                    ? const Padding(
                        key: Key('va-jobs-empty'),
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('No jobs have been run yet.',
                            style: TextStyle(color: _muted)))
                    : Column(children: [
                        ..._jobs.map(_jobTile),
                        _pager(_jobsPagination, (p) => _loadJobs(p)),
                      ]),
      );

  Widget _jobTile(VirtualAccountJob job) => InkWell(
        key: Key('va-job-${job.id}'),
        onTap: () => _loadDetail(job.id, 1),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _detail?.job.id == job.id ? _mint : const Color(0xfff7faf8),
              borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text('Job ${job.id}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _ink, fontWeight: FontWeight.w800))),
              _status(job.status),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: job.progress,
                color: _teal,
                backgroundColor: const Color(0xffdce9e5)),
            const SizedBox(height: 6),
            Text(
                '${job.processed}/${job.total} evaluated · ${job.successful} with account · ${job.failed} failed · ${job.pending} pending · ${job.skipped} skipped',
                style: const TextStyle(color: _muted, fontSize: 12)),
            if (job.pauseReason != null)
              Text('Paused: ${job.pauseReason}',
                  style:
                      const TextStyle(color: Color(0xff73521a), fontSize: 12)),
          ]),
        ),
      );

  Widget _detailSection() {
    final d = _detail;
    return _card(
      title: d == null ? 'Job detail' : 'Job ${d.job.id}',
      child: _loadingDetail && d == null
          ? _skeleton(80)
          : _detailError != null && d == null
              ? _banner(_detailError!, key: const Key('va-detail-error'))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _status(d!.job.status),
                    if (d.job.isActive)
                      const Text('Updating while this page is open',
                          style: TextStyle(color: _muted, fontSize: 12)),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      key: const Key('va-download'),
                      onPressed: _downloading ? null : () => _download(d.job),
                      icon: const Icon(Icons.download_outlined, size: 17),
                      label: Text(_downloading ? 'Preparing…' : 'Download CSV'),
                    ),
                    if (_canCreateJobs)
                      OutlinedButton.icon(
                        key: const Key('va-retry'),
                        onPressed: d.job.canRetryFailed &&
                                _storageReady &&
                                !_submitting &&
                                _intent == null
                            ? () => _startRetry(d.job)
                            : null,
                        icon: const Icon(Icons.replay_rounded, size: 17),
                        label: Text('Retry failed (${d.job.failed})'),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  if (d.items.isEmpty)
                    const Text('No customer results recorded yet.',
                        style: TextStyle(color: _muted))
                  else
                    ...d.items.map(_itemRow),
                  _pager(d.pagination, (p) => _loadDetail(d.job.id, p)),
                ]),
    );
  }

  Widget _itemRow(VirtualAccountJobItem i) => Padding(
        key: Key('va-item-${i.customerId}'),
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.fullName.isEmpty ? i.customerId : i.fullName,
                  style:
                      const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
              Text(
                  [i.phone, i.reason].where((e) => e.isNotEmpty).join(' · '),
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ]),
          ),
          _status(i.status),
        ]),
      );

  Widget _uncertainBanner() {
    final i = _intent!;
    return Container(
      key: const Key('va-uncertain'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xfffff3dc),
          border: Border.all(color: const Color(0xffe6c77d)),
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Outcome uncertain. Nothing was resent.',
            style: TextStyle(
                color: Color(0xff73521a), fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        Text(
            '${_actionError ?? ''} Request ${i.requestId} is retained. Check the job list before resubmitting.',
            style: const TextStyle(color: Color(0xff73521a), height: 1.4)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          OutlinedButton(
              key: const Key('va-uncertain-refresh'),
              onPressed: () => _loadJobs(1),
              child: const Text('Refresh jobs')),
          OutlinedButton(
              key: const Key('va-resubmit'),
              onPressed: _resubmitSameRequest,
              child: const Text('Resubmit same request')),
          TextButton(
              key: const Key('va-discard'),
              onPressed: _discardIntent,
              child: const Text('Clear after review')),
        ]),
      ]),
    );
  }

  Widget _pager(VirtualAccountPagination p, void Function(int) load) =>
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text(p.pages > 0 ? 'Page ${p.page} of ${p.pages}' : 'Page ${p.page}',
            style: const TextStyle(color: _muted, fontSize: 12)),
        IconButton(
            tooltip: 'Previous page',
            onPressed: p.hasPrevious ? () => load(p.page - 1) : null,
            icon: const Icon(Icons.chevron_left)),
        IconButton(
            tooltip: 'Next page',
            onPressed: p.hasNext ? () => load(p.page + 1) : null,
            icon: const Icon(Icons.chevron_right)),
      ]);

  Widget _status(String s) {
    final warn = {'FAILED', 'PAUSED'}.contains(s);
    final pending = {'PENDING', 'QUEUED', 'RUNNING'}.contains(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: warn
            ? const Color(0xfffff1ef)
            : pending
                ? const Color(0xfffff3dc)
                : _mint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(s.isEmpty ? 'UNKNOWN' : s,
          style: TextStyle(
              color: warn
                  ? const Color(0xff8d3d33)
                  : pending
                      ? const Color(0xff73521a)
                      : _teal,
              fontSize: 11,
              fontWeight: FontWeight.w800)),
    );
  }

  Widget _metric(String label, String value, {bool strong = false}) =>
      Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xffdce9e5)),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(
                  color: _ink,
                  fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                  fontSize: strong ? 18 : 15)),
        ]),
      );

  Widget _card({required String title, required Widget child}) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xffdce9e5))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _ink, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _banner(String text,
          {Key? key, bool ok = false, Future<void> Function()? retry}) =>
      Container(
        key: key,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: ok ? _mint : const Color(0xfffff1ef),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
              color: ok ? _teal : const Color(0xffbb4a3b)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: ok ? _ink : const Color(0xff8d3d33)))),
          if (retry != null)
            TextButton(onPressed: retry, child: const Text('Retry')),
        ]),
      );

  Widget _skeleton(double h) => Container(
        height: h,
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
            color: const Color(0xffe4eeea),
            borderRadius: BorderRadius.circular(16)),
      );
}
