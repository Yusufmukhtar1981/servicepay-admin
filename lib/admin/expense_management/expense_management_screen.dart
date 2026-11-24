import 'dart:async';

import 'package:flutter/material.dart';

import 'expense_api.dart';
import 'expense_approvals_section.dart';
import 'expense_audit_section.dart';
import 'expense_catalog_section.dart';
import 'expense_common.dart';
import 'expense_dashboard_section.dart';
import 'expense_form_section.dart';
import 'expense_list_section.dart';
import 'expense_policy_config_section.dart';
import 'expense_reports_section.dart';
import 'expense_requests_section.dart';

/// Server-derived context shared by every Financial Management section.
class ExpenseModuleContext {
  ExpenseModuleContext({
    required this.api,
    required this.access,
    required this.readiness,
    required this.references,
    required this.reloadReferences,
    required this.openExpense,
    required this.goTo,
    void Function(String id)? openRequest,
    this.requestReferences = const <String, dynamic>{},
    this.notifications = const <String, dynamic>{},
    this.notificationsTick = 0,
    this.refreshNotifications,
  }) : openRequest = openRequest ?? ((String _) {});
  final ExpenseManagementApi api;
  final ExpenseAccess access;
  final Map<String, dynamic> readiness;
  final Map<String, dynamic> references;
  final Future<void> Function() reloadReferences;
  final void Function(String id) openExpense;
  final void Function(String section) goTo;
  final void Function(String id) openRequest;
  final Map<String, dynamic> requestReferences;
  final Map<String, dynamic> notifications;
  final int notificationsTick;
  final Future<void> Function()? refreshNotifications;

  bool _flag(String k) => readiness[k] == true;
  /// Finance-wide records (totals, vendors, reports, global audit).
  bool get financeAccess =>
      readiness.containsKey('financeAccess') ? _flag('financeAccess') : access.has(ExpensePermissions.view);
  bool get canCreateRequests => _flag('canCreateRequests');
  bool get canViewDepartmentRequests => _flag('canViewDepartmentRequests');
  bool get canConfigurePolicies => _flag('canConfigurePolicies');
  bool get canReviewRequests => _flag('canReviewRequests');
  bool get canRecordPayments => _flag('canRecordPayments');
  bool get requestAccess => _flag('requestAccess') || canCreateRequests || canViewDepartmentRequests;
  String get department => text(readiness['department']);
  List<String> get requestDepartments {
    final List<dynamic> fromRefs = asList(requestReferences['departments']);
    return (fromRefs.isNotEmpty ? fromRefs : asList(readiness['departments'])).map((dynamic v) => '$v').toList();
  }
  List<Map<String, dynamic>> get requestCategories => asList(requestReferences['categories']).map(asMap).toList();
  List<Map<String, dynamic>> get requestVendors => asList(requestReferences['vendors']).map(asMap).toList();

  bool get workflowConfigured => readiness['workflowConfigured'] == true;
  int get maxDocumentBytes =>
      asInt(asMap(readiness['limits'])['maxDocumentBytes']) ?? ExpenseManagementApi.defaultMaxDocumentBytes;
  int get maxDocuments => asInt(asMap(readiness['limits'])['maxDocuments']) ?? 10;
  List<Map<String, dynamic>> get categories => asList(references['categories']).map(asMap).toList();
  List<Map<String, dynamic>> get vendors => asList(references['vendors']).map(asMap).toList();
}

class ExpenseSection {
  const ExpenseSection(this.id, this.label, this.icon, this.permissions, {this.anyOf = false});
  final String id;
  final String label;
  final IconData icon;
  final List<String> permissions;
  final bool anyOf;
}

/// Sections that expose finance-wide data. Hidden from request-only users.
const Set<String> financeOnlySections = <String>{'dashboard', 'new', 'expenses', 'categories', 'vendors', 'reports', 'audit'};

const List<ExpenseSection> expenseSections = <ExpenseSection>[
  ExpenseSection('my', 'My Expense Requests', Icons.assignment_ind_outlined, <String>[]),
  ExpenseSection('department', 'Department Requests', Icons.apartment_outlined, <String>[]),
  ExpenseSection('dashboard', 'Expense Dashboard', Icons.space_dashboard_outlined, <String>[ExpensePermissions.view]),
  ExpenseSection('new', 'Add New Expense', Icons.add_card_outlined, <String>[ExpensePermissions.create]),
  ExpenseSection('expenses', 'All Expenses', Icons.receipt_long_outlined, <String>[ExpensePermissions.view]),
  ExpenseSection('categories', 'Expense Categories', Icons.category_outlined, <String>[ExpensePermissions.view]),
  ExpenseSection('vendors', 'Vendors & Suppliers', Icons.storefront_outlined, <String>[ExpensePermissions.view]),
  ExpenseSection('approvals', 'Pending Approvals', Icons.fact_check_outlined,
      <String>[ExpensePermissions.approve, ExpensePermissions.policy], anyOf: true),
  ExpenseSection('approved', 'Approved Requests', Icons.task_alt_outlined, <String>[]),
  ExpenseSection('payments', 'Payment Records', Icons.receipt_outlined, <String>[]),
  ExpenseSection('policies', 'Approval Policy Configuration', Icons.rule_outlined, <String>[]),
  ExpenseSection('reports', 'Financial Reports', Icons.summarize_outlined, <String>[ExpensePermissions.export]),
  ExpenseSection('audit', 'Audit Logs', Icons.history_edu_outlined, <String>[ExpensePermissions.audit]),
];

class ExpenseManagementScreen extends StatefulWidget {
  const ExpenseManagementScreen({super.key, this.api, this.initialSection = 'dashboard', this.notificationInterval = const Duration(seconds: 30)});
  final Duration notificationInterval;
  final ExpenseManagementApi? api;
  final String initialSection;

  @override
  State<ExpenseManagementScreen> createState() => _ExpenseManagementScreenState();
}

class _ExpenseManagementScreenState extends State<ExpenseManagementScreen> {
  late final ExpenseManagementApi _api = widget.api ?? ExpenseManagementApi();
  late String _section = expenseSections.any((ExpenseSection s) => s.id == widget.initialSection)
      ? widget.initialSection
      : 'dashboard';
  Map<String, dynamic>? _readiness;
  Map<String, dynamic> _references = <String, dynamic>{};
  String? _error;
  String? _referenceError;
  bool _loading = true;
  String? _openExpenseId;
  String? _openRequestId;
  int _request = 0;
  Map<String, dynamic> _requestRefs = <String, dynamic>{};
  Map<String, dynamic> _notifications = <String, dynamic>{};
  int _notificationsTick = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  bool get _hasRequestFeatures {
    final Map<String, dynamic> r = _readiness ?? <String, dynamic>{};
    return <String>['requestAccess', 'canCreateRequests', 'canViewDepartmentRequests', 'canReviewRequests', 'canRecordPayments', 'canConfigurePolicies']
        .any((String k) => r[k] == true);
  }

  ExpenseModuleContext _baseCtx() => ExpenseModuleContext(
        api: _api,
        access: _access,
        readiness: _readiness ?? <String, dynamic>{},
        references: _references,
        reloadReferences: _loadReferences,
        openExpense: (_) {},
        goTo: (_) {},
      );

  bool _visible(ExpenseSection s) {
    if (_readiness == null) return false;
    final ExpenseModuleContext c = _baseCtx();
    if (financeOnlySections.contains(s.id)) return c.financeAccess;
    return switch (s.id) {
      'my' => c.requestAccess,
      'department' => c.canViewDepartmentRequests,
      'policies' => c.canConfigurePolicies,
      'approvals' => c.financeAccess || c.canReviewRequests,
      'approved' => c.canReviewRequests || c.canRecordPayments || c.financeAccess && _hasRequestFeatures,
      'payments' => c.canRecordPayments || c.financeAccess && _hasRequestFeatures,
      _ => true,
    };
  }

  List<ExpenseSection> get _sections => expenseSections.where(_visible).toList();

  Future<void> _loadRequestRefs() async {
    try {
      final Map<String, dynamic> refs = await _api.requestReferences();
      if (mounted) setState(() => _requestRefs = refs);
    } catch (e) {
      if (mounted) setState(() => _referenceError = errorText(e));
    }
  }

  Future<void> _loadNotifications() async {
    if (!_hasRequestFeatures) return;
    try {
      final Map<String, dynamic> n = await _api.requestNotifications();
      if (!mounted) return;
      final bool changed = n['pendingCount'] != _notifications['pendingCount'] ||
          asList(n['items']).map((dynamic i) => '${asMap(i)['id']}${asMap(i)['updatedAt']}').join() !=
              asList(_notifications['items']).map((dynamic i) => '${asMap(i)['id']}${asMap(i)['updatedAt']}').join();
      setState(() {
        final bool first = _notifications.isEmpty;
        _notifications = n;
        if (changed && !first) _notificationsTick++;
      });
    } catch (_) {
      // Notifications are advisory; lists show their own errors.
    }
  }

  void _startPolling() {
    _poll?.cancel();
    if (!_hasRequestFeatures) return;
    _poll = Timer.periodic(widget.notificationInterval, (_) {
      if (!mounted) return;
      if (!TickerMode.of(context)) return; // hidden behind another tab
      _loadNotifications();
    });
  }

  int get _pendingCount => asInt(_notifications['pendingCount']) ?? asInt(_readiness?['pendingRequestCount']) ?? 0;

  Future<void> _load() async {
    final int request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> readiness = await _api.readiness();
      if (!mounted || request != _request) return;
      setState(() {
        _readiness = readiness;
        _loading = false;
        final List<ExpenseSection> visible = _sections;
        if (visible.isNotEmpty && !visible.any((ExpenseSection s) => s.id == _section)) {
          _section = visible.any((ExpenseSection s) => s.id == 'my') ? 'my' : visible.first.id;
        }
      });
      if (readiness['ready'] == true) {
        if (_hasRequestFeatures) {
          _startPolling();
          unawaited(_loadNotifications());
          unawaited(_loadRequestRefs());
        }
        if (_baseCtx().financeAccess) await _loadReferences();
      }
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _readiness = null;
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _loadReferences() async {
    try {
      final Map<String, dynamic> refs = await _api.references();
      if (!mounted) return;
      setState(() {
        _references = refs;
        _referenceError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _referenceError = errorText(e));
    }
  }

  ExpenseAccess get _access => ExpenseAccess.fromReadiness(_readiness ?? <String, dynamic>{});

  List<String> _missingFor(ExpenseSection s) {
    final ExpenseAccess a = _access;
    if (s.permissions.isEmpty) return <String>[];
    if (s.id == 'approvals' && _baseCtx().canReviewRequests) return <String>[];
    if (s.anyOf) {
      return s.permissions.any(a.has) ? <String>[] : s.permissions;
    }
    return s.permissions.where((String p) => !a.has(p)).toList();
  }

  void _goTo(String id) {
    setState(() {
      _section = id;
      _openExpenseId = null;
      _openRequestId = null;
    });
    _loadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: expPaper,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
            final bool wide = c.maxWidth >= 980;
            final Widget content = _content(wide);
            if (!wide) return content;
            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              _sideNav(),
              const VerticalDivider(width: 1, color: expLine),
              Expanded(child: content),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _header(bool wide) {
    final ExpenseSection current = expenseSections.firstWhere((ExpenseSection s) => s.id == _section);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('SERVICEPAY  /  FINANCIAL MANAGEMENT  /  ${current.label.toUpperCase()}',
            style: const TextStyle(color: expGreen, letterSpacing: 1.3, fontWeight: FontWeight.w800, fontSize: 10)),
        const SizedBox(height: 7),
        Text(_openExpenseId != null ? 'Expense record' : _openRequestId != null ? 'Expense request' : current.label,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: expInk, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        const Text('Company operating expenses only. Customer wallets, funds and transactions are never read or changed here.',
            style: TextStyle(color: expMuted, fontSize: 12.5)),
        if (!wide && _readiness?['ready'] == true) ...<Widget>[
          const SizedBox(height: 12),
          _chipNav(),
        ],
      ]),
    );
  }

  Widget _sideNav() => SizedBox(
        width: 250,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text('FINANCIAL MANAGEMENT',
                  style: TextStyle(color: Color(0xff687b73), fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
            ),
            for (final ExpenseSection s in _sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: ListTile(
                  key: Key('expense-nav-${s.id}'),
                  dense: true,
                  selected: s.id == _section,
                  selectedTileColor: const Color(0xffdbe9e1),
                  selectedColor: expGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                  leading: Icon(s.icon, size: 19),
                  title: Text(s.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  trailing: _readiness != null && _missingFor(s).isNotEmpty
                      ? const Tooltip(message: 'Permission required', child: Icon(Icons.lock_outline, size: 15))
                      : _badge(s),
                  onTap: () => _goTo(s.id),
                ),
              ),
          ],
        ),
      );

  Widget _chipNav() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: <Widget>[
          for (final ExpenseSection s in _sections)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: Key('expense-nav-${s.id}'),
                avatar: Icon(_missingFor(s).isNotEmpty ? Icons.lock_outline : s.icon, size: 16),
                label: Text(_badgeCount(s) > 0 ? '${s.label} (${_badgeCount(s)})' : s.label),
                selected: s.id == _section,
                selectedColor: const Color(0xffcee1d6),
                onSelected: (_) => _goTo(s.id),
              ),
            ),
        ]),
      );

  int _badgeCount(ExpenseSection s) {
    final bool reviewer = _baseCtx().canReviewRequests;
    if (s.id == 'approvals' && reviewer) return _pendingCount;
    if (s.id == 'my' && !reviewer) return _pendingCount;
    return 0;
  }

  Widget? _badge(ExpenseSection s) {
    final int n = _badgeCount(s);
    if (n <= 0) return null;
    return Container(
      key: Key('expense-badge-${s.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: expAmber, borderRadius: BorderRadius.circular(10)),
      child: Text('$n', style: const TextStyle(color: Color(0xfffffbf2), fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }

  Widget _content(bool wide) {
    final Widget body;
    if (_loading) {
      body = const Padding(padding: EdgeInsets.all(20), child: ExpenseSkeleton(rows: 5));
    } else if (_readiness == null) {
      body = Padding(
        padding: const EdgeInsets.all(20),
        child: ExpenseErrorState(
          message: 'Expense management could not confirm readiness. No figures are shown until the server responds. ${_error ?? ''}',
          onRetry: _load,
        ),
      );
    } else if (_readiness!['ready'] != true) {
      final List<String> missing = asList(_readiness!['missing']).map((dynamic v) => '$v').toList();
      body = Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          ExpenseNotice(
            'Expense management is not ready on the server, so no records or metrics are displayed.'
            '${missing.isEmpty ? '' : '\nMissing: ${missing.join(', ')}'}',
            tone: 'warn',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Check readiness again')),
        ]),
      );
    } else {
      body = _sectionBody();
    }
    return CustomScrollView(slivers: <Widget>[
      SliverToBoxAdapter(child: _header(wide)),
      SliverToBoxAdapter(child: body),
    ]);
  }

  Widget _sectionBody() {
    final ExpenseSection s = expenseSections.firstWhere((ExpenseSection e) => e.id == _section);
    final ExpenseModuleContext ctx = ExpenseModuleContext(
      api: _api,
      access: _access,
      readiness: _readiness!,
      references: _references,
      reloadReferences: _loadReferences,
      openExpense: (String id) => setState(() => _openExpenseId = id),
      goTo: _goTo,
      openRequest: (String id) => setState(() => _openRequestId = id),
      requestReferences: _requestRefs,
      notifications: _notifications,
      notificationsTick: _notificationsTick,
      refreshNotifications: _loadNotifications,
    );
    final List<String> missing = _missingFor(s);
    Widget child;
    if (_openExpenseId != null) {
      child = ExpenseDetailView(
        key: ValueKey<String>('detail-$_openExpenseId'),
        ctx: ctx,
        expenseId: _openExpenseId!,
        onClose: () => setState(() => _openExpenseId = null),
      );
    } else if (_openRequestId != null) {
      child = ExpenseRequestDetailView(
        key: ValueKey<String>('request-$_openRequestId'),
        ctx: ctx,
        requestId: _openRequestId!,
        onClose: () => setState(() => _openRequestId = null),
      );
    } else if (missing.isNotEmpty) {
      child = ExpenseEmptyState(
        icon: Icons.lock_outline,
        title: 'Access not granted',
        message: '${s.label} requires ${s.anyOf ? 'one of' : ''} the explicit permission${missing.length > 1 ? 's' : ''}: '
            '${missing.map((String p) => '$p (${ExpensePermissions.labels[p]})').join(', ')}. '
            'Broad Head Office or wildcard access does not grant financial records. Ask a Head Office administrator to assign it.',
      );
    } else {
      child = switch (_section) {
        'dashboard' => ExpenseDashboardSection(ctx: ctx),
        'new' => ExpenseFormSection(key: const ValueKey<String>('new-expense'), ctx: ctx),
        'expenses' => ExpenseListSection(ctx: ctx),
        'categories' => ExpenseCatalogSection(key: const ValueKey<String>('categories'), ctx: ctx, kind: 'categories'),
        'vendors' => ExpenseCatalogSection(key: const ValueKey<String>('vendors'), ctx: ctx, kind: 'vendors'),
        'approvals' => ExpenseApprovalsSection(ctx: ctx),
        'my' => MyExpenseRequestsSection(ctx: ctx),
        'department' => RequestScopeSection(key: const ValueKey<String>('department'), ctx: ctx, scope: 'department'),
        'approved' => RequestScopeSection(key: const ValueKey<String>('approved'), ctx: ctx, scope: 'approved'),
        'payments' => RequestScopeSection(key: const ValueKey<String>('payments'), ctx: ctx, scope: 'payments'),
        'policies' => ApprovalPolicyConfigSection(ctx: ctx),
        'reports' => ExpenseReportsSection(ctx: ctx),
        _ => ExpenseAuditSection(ctx: ctx),
      };
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        if (_referenceError != null) ...<Widget>[
          ExpenseErrorState(
            message: 'Categories and vendors could not be loaded: $_referenceError',
            onRetry: () async {
              if (_baseCtx().financeAccess) await _loadReferences();
              if (_hasRequestFeatures) await _loadRequestRefs();
            },
            retryLabel: 'Reload references',
          ),
          const SizedBox(height: 12),
        ],
        child,
      ]),
    );
  }
}
