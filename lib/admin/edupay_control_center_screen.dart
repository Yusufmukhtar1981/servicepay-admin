import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'edupay_api.dart';
import 'private_asset_download.dart';

String? _reviewRowId(Map<String, dynamic> row) {
  final value = row['id'] ?? row['_id'] ?? row['feeId'];
  return value?.toString().trim().isNotEmpty == true ? value.toString() : null;
}

String _reviewType(Map<String, dynamic> row) =>
    (row['type'] ?? '').toString().trim().toUpperCase();

String _reviewStatus(Map<String, dynamic> row) =>
    (row['status'] ?? 'PENDING_REVIEW').toString().trim().toUpperCase();

bool _isSchoolRequestRow(Map<String, dynamic> row) =>
    _reviewType(row) == 'SCHOOL_REQUEST';

bool eduPayAdminRoleCanManage(String role) => const <String>{
  'HEAD_OFFICE',
}.contains(role.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_'));

bool eduPayAdminRoleCanReviewSchoolRequests(String role) => const <String>{
  'HEAD_OFFICE',
  'HEAD_OFFICE_ADMIN',
  'ADMIN',
  'SUPER_ADMIN',
  'SERVICEPAY_SUPER_ADMIN',
}.contains(role.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_'));

class _NavHeading extends StatelessWidget {
  const _NavHeading(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 12, 6),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
    ),
  );
}

class SchoolRequestActionControls extends StatelessWidget {
  const SchoolRequestActionControls({
    super.key,
    required this.row,
    required this.canManage,
    required this.onView,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> row;
  final bool canManage;
  final VoidCallback onView;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final pending = _reviewStatus(row) == 'PENDING_REVIEW';
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        TextButton.icon(
          onPressed: onView,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('View School'),
        ),
        if (pending && canManage) ...[
          TextButton.icon(
            onPressed: onApprove,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Approve'),
          ),
          TextButton.icon(
            onPressed: onReject,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Reject'),
          ),
        ],
      ],
    );
  }
}

class SchoolRequestDetailsActions extends StatelessWidget {
  const SchoolRequestDetailsActions({
    super.key,
    required this.pending,
    required this.canManage,
    required this.onApprove,
    required this.onReject,
    required this.onClose,
  });

  final bool pending;
  final bool canManage;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      if (pending && canManage) ...[
        TextButton(onPressed: onReject, child: const Text('Reject')),
        FilledButton(onPressed: onApprove, child: const Text('Approve')),
      ],
      TextButton(onPressed: onClose, child: const Text('Close')),
    ],
  );
}

String? _requestLinkedSchoolId(Map<String, dynamic> request) {
  final scalar = request['schoolId']?.toString().trim();
  if (scalar != null && scalar.isNotEmpty) return scalar;
  final linked =
      request['school'] ??
      request['linkedSchool'] ??
      request['convertedSchool'];
  if (linked is Map) {
    return _reviewRowId(Map<String, dynamic>.from(linked));
  }
  final value = linked?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

/// Combines full school rows with onboarding requests without showing an
/// approved request twice after it has been admitted as a school.
List<Map<String, dynamic>> eduPaySchoolReviewRows(
  List<Map<String, dynamic>> schools,
  List<Map<String, dynamic>> requests,
) {
  final schoolIds = schools.map(_reviewRowId).whereType<String>().toSet();
  final requestRows = requests
      .where((request) {
        final status = (request['status'] ?? 'PENDING_REVIEW')
            .toString()
            .toUpperCase();
        final linkedId = _requestLinkedSchoolId(request);
        return !(status == 'APPROVED' &&
            linkedId != null &&
            schoolIds.contains(linkedId));
      })
      .map(
        (request) => <String, dynamic>{
          'type': 'SCHOOL_REQUEST',
          'schoolName': request['schoolName'] ?? request['name'],
          'location': request['location'],
          'contactPhone': request['contactPhone'],
          'status': (request['status'] ?? 'PENDING_REVIEW')
              .toString()
              .trim()
              .toUpperCase(),
          'createdAt': request['createdAt'],
          '_requestId': request['_id'] ?? request['id'],
          '_request': request,
        },
      );
  return [...requestRows, ...schools];
}

class EduPayControlCenterScreen extends StatefulWidget {
  const EduPayControlCenterScreen({super.key});
  @override
  State<EduPayControlCenterScreen> createState() =>
      _EduPayControlCenterScreenState();
}

class _EduPayControlCenterScreenState extends State<EduPayControlCenterScreen> {
  final _api = EduPayApi();
  Map<String, dynamic>? data;
  Map<String, dynamic>? readiness;
  Set<String> permissions = <String>{};
  String adminRole = '';
  String section = 'Overview';
  bool loading = true;
  String? error;
  final schoolSearch = TextEditingController();
  String schoolStatus = 'ALL';
  final savingsSearch = TextEditingController();
  String savingsStatus = 'ALL';
  final savingsDateFrom = TextEditingController();
  final savingsDateTo = TextEditingController();
  final financeSections = const <String>[
    'Overview',
    'Schools & onboarding',
    'Fee approvals',
    'Parents & plans',
    'Savings & transactions',
    'Settlements',
    'Repayments',
    'Sponsors',
    'Reconciliation',
    'Reports',
    'Launch Readiness',
    'Settings',
    'Audit logs',
  ];
  final academicSections = const <String>[
    'Academic Overview',
    'Schools',
    'Students',
    'Teachers',
    'Classes',
    'Subjects',
    'Attendance',
    'Exams & Results',
    'Academic Sessions',
    'Timetable',
    'School Activities',
  ];
  List<String> get sections => [...financeSections, ...academicSections];
  bool get isHeadOffice => eduPayAdminRoleCanManage(adminRole);
  bool get canManageEduPay => isHeadOffice;
  bool get canReviewSchoolRequests =>
      isHeadOffice ||
      (eduPayAdminRoleCanReviewSchoolRequests(adminRole) &&
          permissions.contains('edupay.manage'));
  @override
  void initState() {
    super.initState();
    _loadAccess();
    _load();
    _loadReadiness();
  }

  Future<void> _loadAccess() async {
    final prefs = await SharedPreferences.getInstance();
    adminRole =
        (prefs.getString('user_role') ??
                prefs.getString('admin_role') ??
                prefs.getString('role') ??
                '')
            .trim()
            .toUpperCase()
            .replaceAll(RegExp(r'[\s-]+'), '_');
    permissions =
        (prefs.getStringList('staff_permissions') ??
                prefs.getStringList('admin_effective_permissions') ??
                <String>[])
            .map((value) => value.trim().toLowerCase())
            .toSet();
    if (mounted) setState(() {});
  }

  Future<void> _loadReadiness() async {
    try {
      readiness = await _api.readiness();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (academicSections.contains(section)) {
        if (section == 'Schools') {
          final responses = await Future.wait([
            _api.request('GET', '/admin/edupay/schools'),
            _api.academicOverview(),
          ]);
          data = <String, dynamic>{
            ...responses[0],
            'academicOverview': responses[1],
          };
        } else {
          data = await _api.academicOverview();
        }
        if (mounted) setState(() => loading = false);
        return;
      }
      if (section == 'Reports') {
        final responses = await Future.wait([
          _api.request('GET', '/admin/edupay/transactions'),
          _api.request('GET', '/admin/edupay/sponsors'),
          _api.request('GET', '/admin/edupay/audit'),
        ]);
        data = <String, dynamic>{
          'transactionContributions': responses[0]['contributions'],
          'transactionLedger': responses[0]['ledger'],
          'repaymentTransactions': responses[0]['repaymentTransactions'],
          'sponsorInvites': responses[1]['invites'],
          'sponsorContributions': responses[1]['contributions'],
          'audit': responses[2]['audit'],
        };
        if (mounted) setState(() => loading = false);
        return;
      }
      if (section == 'Parents & plans' || section == 'Savings & transactions') {
        final result = section == 'Parents & plans'
            ? await _api.adminPlans(
                search: savingsSearch.text,
                status: savingsStatus,
                dateFrom: savingsDateFrom.text,
                dateTo: savingsDateTo.text,
              )
            : await _api.adminTransactions(
                search: savingsSearch.text,
                status: savingsStatus,
                dateFrom: savingsDateFrom.text,
                dateTo: savingsDateTo.text,
              );
        data = result;
        if (mounted) setState(() => loading = false);
        return;
      }
      if (section == 'Launch Readiness') {
        await _loadReadiness();
        data = await _api.request('GET', '/admin/edupay/settings');
        if (mounted) setState(() => loading = false);
        return;
      }
      if (section == 'Overview') {
        final responses = await Future.wait([
          _api.request('GET', '/admin/edupay/overview'),
          _api.academicOverview(),
        ]);
        final overview = responses[0];
        final academic =
            (responses[1]['usage'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        data = <String, dynamic>{
          ...overview,
          'summary': <String, dynamic>{
            ...((overview['summary'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{}),
            ...academic.map((key, value) => MapEntry('academic_$key', value)),
          },
        };
        if (mounted) setState(() => loading = false);
        return;
      }
      final path = switch (section) {
        'Overview' => '/admin/edupay/overview',
        'Schools & onboarding' => '/admin/edupay/schools',
        'Fee approvals' => '/admin/edupay/fees',
        'Parents & plans' => '/admin/edupay/plans',
        'Savings & transactions' => '/admin/edupay/transactions',
        'Settlements' => '/admin/edupay/settlements',
        'Repayments' => '/admin/edupay/repayments',
        'Sponsors' => '/admin/edupay/sponsors',
        'Reconciliation' => '/admin/edupay/reconciliation',
        'Audit logs' => '/admin/edupay/audit',
        'Settings' => '/admin/edupay/settings',
        _ => '/admin/edupay/overview',
      };
      data = await _api.request('GET', path);
      if (section == 'Schools & onboarding' &&
          data?['onboardingRequests'] == null) {
        try {
          final requests = await _api.schoolRequests();
          data = <String, dynamic>{
            ...data!,
            'onboardingRequests':
                requests['requests'] ?? requests['onboardingRequests'] ?? [],
          };
        } catch (_) {
          // Keep school review usable on older backends without this endpoint.
        }
      }
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    schoolSearch.dispose();
    savingsSearch.dispose();
    savingsDateFrom.dispose();
    savingsDateTo.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows() {
    if (academicSections.contains(section)) {
      final academicKey = <String, String>{
        'Students': 'students',
        'Teachers': 'teachers',
        'Classes': 'classes',
        'Subjects': 'subjects',
        'Attendance': 'attendance',
        'Exams & Results': 'assessments',
        'Academic Sessions': 'sessions',
        'Timetable': 'timetable',
        'School Activities': 'activities',
      }[section];
      final sourceData = data;
      final source = section == 'Schools'
          ? (sourceData == null ? null : sourceData['schools'])
          : academicKey == null
          ? null
          : sourceData![academicKey];
      if (source is List) {
        return source
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      }
      final overview = data?['academicOverview'];
      if (overview is Map) {
        final value =
            overview[{
              'Students': 'students',
              'Teachers': 'teachers',
              'Classes': 'classes',
              'Subjects': 'subjects',
              'Attendance': 'attendance',
              'Exams & Results': 'assessments',
              'Academic Sessions': 'sessions',
              'Timetable': 'timetable',
              'School Activities': 'activities',
            }[section]];
        if (value is List) {
          return value
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
        }
      }
      if (section == 'Academic Overview') {
        final summary = (data?['usage'] ?? data?['summary']) as Map?;
        if (summary != null) {
          return summary.entries
              .map(
                (entry) => <String, dynamic>{entry.key.toString(): entry.value},
              )
              .toList();
        }
      }
      final profiles = data?['schoolProfiles'];
      final metricKey = <String, String>{
        'Students': 'students',
        'Teachers': 'teachers',
        'Classes': 'classes',
        'Subjects': 'subjects',
        'Attendance': 'attendanceRecords',
        'Exams & Results': 'publishedResults',
        'Academic Sessions': 'academicSessions',
        'Timetable': 'timetableEntries',
        'School Activities': 'schoolActivities',
      }[section];
      if (profiles is List && metricKey != null) {
        return profiles.whereType<Map>().map((profile) {
          final row = Map<String, dynamic>.from(profile);
          final activityKey = switch (section) {
            'Attendance' => 'lastAttendanceAt',
            'Exams & Results' => 'lastPublishedResultAt',
            'School Activities' => 'lastSchoolActivityAt',
            _ => null,
          };
          return <String, dynamic>{
            'school': row['name'] ?? 'School',
            metricKey: row[metricKey] ?? 0,
            if (activityKey != null) 'latestActivity': row[activityKey],
            'status': row['status'] ?? 'APPROVED',
          };
        }).toList();
      }
      return const [];
    }
    if (section == 'Savings & transactions' || section == 'Reconciliation') {
      final rows = <Map<String, dynamic>>[];
      for (final key in [
        'transactions',
        'contributions',
        'ledger',
        'repaymentTransactions',
      ]) {
        final value = data?[key];
        if (value is List) {
          rows.addAll(
            value.whereType<Map>().map(
              (row) => {...Map<String, dynamic>.from(row), '_source': key},
            ),
          );
        }
      }
      return rows
          .map(
            (row) => {
              if (row['targetAmount'] != null) ...{
                'parent': row['parentName'] ?? row['parent'],
                'student': row['studentName'] ?? row['student'],
                'targetAmount': row['targetAmount'],
                'amountSaved': row['amountSaved'] ?? row['saved'],
                'remaining': row['remaining'] ?? row['remainingAmount'],
                'status': row['status'],
                'history': row['history'],
              } else ...{
                'date': row['date'] ?? row['createdAt'] ?? row['occurredAt'],
                'reference': row['reference'] ?? row['transactionReference'],
                'parent': row['parentName'] ?? row['parent'],
                'student': row['studentName'] ?? row['student'],
                'school': row['schoolName'] ?? row['school'],
                'amount': row['amount'] ?? row['amountSaved'] ?? row['saved'],
                'status': row['status'],
                'type': row['type'] ?? row['transactionType'] ?? row['_source'],
              },
            },
          )
          .toList();
    }
    if (section == 'Sponsors') {
      final rows = <Map<String, dynamic>>[];
      for (final key in ['invites', 'contributions']) {
        final value = data?[key];
        if (value is List) {
          rows.addAll(
            value.whereType<Map>().map(
              (row) => {...Map<String, dynamic>.from(row), '_source': key},
            ),
          );
        }
      }
      return rows;
    }
    if (section == 'Audit logs') {
      final value = data?['audit'];
      return value is List
          ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : <Map<String, dynamic>>[];
    }
    final value =
        data?[{
          'Schools & onboarding': 'schools',
          'Fee approvals': 'fees',
          'Parents & plans': 'plans',
          'Savings & transactions': 'transactions',
          'Settlements': 'settlements',
          'Repayments': 'repayments',
          'Sponsors': 'sponsors',
          'Reconciliation': 'transactions',
          'Audit logs': 'logs',
        }[section]];
    final rows = value is List
        ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    if (section == 'Parents & plans') {
      return rows
          .map(
            (row) => {
              'parent': row['parentName'] ?? row['parent'],
              'student': row['studentName'] ?? row['student'],
              'school': row['schoolName'] ?? row['school'],
              'targetAmount': row['targetAmount'] ?? row['target'],
              'amountSaved': row['amountSaved'] ?? row['saved'],
              'remaining': row['remaining'] ?? row['remainingAmount'],
              'status': row['status'],
            },
          )
          .toList();
    }
    if (section == 'Schools & onboarding' &&
        data?['onboardingRequests'] is List) {
      final requests = (data!['onboardingRequests'] as List)
          .whereType<Map>()
          .map((request) => Map<String, dynamic>.from(request))
          .toList();
      return eduPaySchoolReviewRows(rows, requests);
    }
    return rows;
  }

  String _display(dynamic v) => v == null ? '—' : v.toString();
  Widget _reportsView() {
    final contributionRows = (data?['transactionContributions'] is List)
        ? (data!['transactionContributions'] as List).length
        : 0;
    final ledgerRows = (data?['transactionLedger'] is List)
        ? (data!['transactionLedger'] as List).length
        : 0;
    final repaymentRows = (data?['repaymentTransactions'] is List)
        ? (data!['repaymentTransactions'] as List).length
        : 0;
    final values = <String, dynamic>{
      'Contributions': contributionRows,
      'Ledger': ledgerRows,
      'Repayment transactions': repaymentRows,
      'Sponsor invites': data?['sponsorInvites'] is List
          ? (data!['sponsorInvites'] as List).length
          : 0,
      'Sponsor contributions': data?['sponsorContributions'] is List
          ? (data!['sponsorContributions'] as List).length
          : 0,
      'Audit events': data?['audit'] is List
          ? (data!['audit'] as List).length
          : 0,
    };
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: MediaQuery.sizeOf(context).width < 700 ? 1 : 3,
      children: values.entries
          .map(
            (e) => Card(
              child: ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: Text(e.key),
                subtitle: Text(_display(e.value)),
              ),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = (data?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    return Scaffold(
      backgroundColor: const Color(0xfff4f7f5),
      drawer: MediaQuery.sizeOf(context).width < 700
          ? Drawer(
              child: ListView(
                children: [
                  const _NavHeading('EDUPAY FINANCE'),
                  ...financeSections.map(
                    (s) => ListTile(
                      title: Text(s),
                      selected: section == s,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => section = s);
                        _load();
                      },
                    ),
                  ),
                  const _NavHeading('ACADEMIC MANAGEMENT'),
                  ...academicSections.map(
                    (s) => ListTile(
                      title: Text(s),
                      selected: section == s,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => section = s);
                        _load();
                      },
                    ),
                  ),
                ],
              ),
            )
          : null,
      appBar: AppBar(
        title: const Text('EduPay Control Center'),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Row(
        children: [
          Visibility(
            visible: MediaQuery.sizeOf(context).width >= 700,
            child: SizedBox(
              width: 220,
              child: ListView(
                children: [
                  const _NavHeading('EDUPAY FINANCE'),
                  ...financeSections.map(_desktopNav),
                  const _NavHeading('ACADEMIC MANAGEMENT'),
                  ...academicSections.map(_desktopNav),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: loading
                ? const _Loading()
                : error != null
                ? _Error(message: error!, retry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          section,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _subtitle(section),
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 22),
                        if (readiness != null &&
                            (section == 'Overview' ||
                                section == 'Launch Readiness'))
                          _readinessCard(),
                        if (section == 'Overview')
                          _summary(summary)
                        else if (section == 'Reports')
                          _reportsView()
                        else if (section == 'Launch Readiness')
                          _readinessView()
                        else if (section == 'Settings')
                          _settingsView()
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (section == 'Parents & plans' ||
                                  section == 'Savings & transactions') ...[
                                _savingsSummary(),
                                const SizedBox(height: 14),
                                _savingsFilters(),
                                const SizedBox(height: 14),
                              ],
                              section == 'Parents & plans' ||
                                      section == 'Savings & transactions'
                                  ? _savingsTable(_rows())
                                  : _table(_rows()),
                            ],
                          ),
                        if (section == 'Settlements') _settlementTools(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _desktopNav(String value) => ListTile(
    leading: Icon(_icon(value)),
    title: Text(value),
    selected: section == value,
    onTap: () {
      setState(() => section = value);
      _load();
    },
  );

  IconData _icon(String s) => switch (s) {
    'Overview' => Icons.dashboard_outlined,
    'Schools & onboarding' => Icons.school_outlined,
    'Fee approvals' => Icons.fact_check_outlined,
    'Parents & plans' => Icons.family_restroom_outlined,
    'Savings & transactions' => Icons.account_balance_wallet_outlined,
    'Settlements' => Icons.payments_outlined,
    'Repayments' => Icons.replay_outlined,
    'Sponsors' => Icons.handshake_outlined,
    'Reconciliation' => Icons.compare_arrows_outlined,
    'Reports' => Icons.assessment_outlined,
    'Launch Readiness' => Icons.verified_outlined,
    'Settings' => Icons.tune_outlined,
    _ => Icons.history_outlined,
  };
  String _subtitle(String s) => s == 'Overview'
      ? 'A precise view of EduPay money movement and partner health.'
      : 'Traceable records from the EduPay API.';
  Widget _settingsView() {
    final settings = (data?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    return Card(
      child: Column(
        children: settings.entries
            .map(
              (entry) => ListTile(
                title: Text(entry.key),
                subtitle: Text('${entry.value}'),
                trailing: canManageEduPay && entry.key != 'enabled'
                    ? IconButton(
                        tooltip: 'Edit operating settings',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: _editSettings,
                      )
                    : null,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _savingsSummary() {
    final summary = (data?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final keys = <String, String>{
      'activePlans': 'Active plans',
      'totalSaved': 'Total saved',
      'completedPlans': 'Completed plans',
    };
    final values = keys.entries
        .map((entry) => MapEntry(entry.value, summary[entry.key] ?? 0))
        .toList();
    if (values.every((entry) => entry.value == 0) && summary.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: values
          .map(
            (entry) => SizedBox(
              width: 190,
              child: Card(
                child: ListTile(
                  title: Text(entry.key),
                  subtitle: Text(_display(entry.value)),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _savingsFilters() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: savingsSearch,
              decoration: const InputDecoration(
                labelText: 'Parent, student or school',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              value: savingsStatus,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('All statuses')),
                DropdownMenuItem(value: 'ACTIVE', child: Text('ACTIVE')),
                DropdownMenuItem(value: 'COMPLETED', child: Text('COMPLETED')),
                DropdownMenuItem(value: 'PAUSED', child: Text('PAUSED')),
                DropdownMenuItem(value: 'CANCELLED', child: Text('CANCELLED')),
                DropdownMenuItem(value: 'SETTLED', child: Text('SETTLED')),
              ],
              onChanged: (value) {
                setState(() => savingsStatus = value ?? 'ALL');
                _load();
              },
            ),
          ),
          SizedBox(
            width: 145,
            child: TextField(
              controller: savingsDateFrom,
              decoration: const InputDecoration(labelText: 'From (YYYY-MM-DD)'),
              onSubmitted: (_) => _load(),
            ),
          ),
          SizedBox(
            width: 145,
            child: TextField(
              controller: savingsDateTo,
              decoration: const InputDecoration(labelText: 'To (YYYY-MM-DD)'),
              onSubmitted: (_) => _load(),
            ),
          ),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.filter_alt_outlined),
            label: const Text('Apply filters'),
          ),
        ],
      ),
    ),
  );

  String _savingsText(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return '—';
    return value.toString();
  }

  Widget _savingsTable(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const _Empty();
    final plans = section == 'Parents & plans';
    final columns = plans
        ? const [
            'Parent',
            'Student',
            'School',
            'Target',
            'Saved',
            'Remaining',
            'Status',
            'History',
          ]
        : const [
            'Date',
            'Reference',
            'Parent',
            'Student',
            'School',
            'Amount',
            'Status',
            'Type',
          ];
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: columns
              .map((label) => DataColumn(label: Text(label)))
              .toList(),
          rows: rows.map((row) {
            final cells = plans
                ? <DataCell>[
                    DataCell(Text(_savingsText(row, 'parent'))),
                    DataCell(Text(_savingsText(row, 'student'))),
                    DataCell(Text(_savingsText(row, 'school'))),
                    DataCell(Text(_savingsText(row, 'targetAmount'))),
                    DataCell(Text(_savingsText(row, 'amountSaved'))),
                    DataCell(Text(_savingsText(row, 'remaining'))),
                    DataCell(Text(_savingsText(row, 'status'))),
                    DataCell(
                      TextButton(
                        onPressed: () => _showSavingsHistory(row),
                        child: const Text('View history'),
                      ),
                    ),
                  ]
                : <DataCell>[
                    DataCell(
                      Text(
                        _savingsText(row, 'date') == '—'
                            ? (_savingsText(row, 'createdAt') == '—'
                                  ? '—'
                                  : _savingsText(row, 'createdAt'))
                            : _savingsText(row, 'date'),
                      ),
                    ),
                    DataCell(Text(_savingsText(row, 'reference'))),
                    DataCell(Text(_savingsText(row, 'parent'))),
                    DataCell(Text(_savingsText(row, 'student'))),
                    DataCell(Text(_savingsText(row, 'school'))),
                    DataCell(Text(_savingsText(row, 'amount'))),
                    DataCell(Text(_savingsText(row, 'status'))),
                    DataCell(Text(_savingsText(row, 'type'))),
                  ];
            return DataRow(cells: cells);
          }).toList(),
        ),
      ),
    );
  }

  void _showSavingsHistory(Map<String, dynamic> row) {
    final history = row['history'];
    final entries = history is List
        ? history.whereType<Map>().toList()
        : const [];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Savings history'),
        content: entries.isEmpty
            ? const Text('No savings history is available for this plan.')
            : SizedBox(
                width: 520,
                child: ListView(
                  shrinkWrap: true,
                  children: entries.map((entry) {
                    final item = Map<String, dynamic>.from(entry);
                    return ListTile(
                      title: Text(
                        '${item['amount'] ?? item['amountSaved'] ?? '—'} · ${item['status'] ?? '—'}',
                      ),
                      subtitle: Text(
                        '${item['date'] ?? item['createdAt'] ?? '—'} · ${item['reference'] ?? '—'}',
                      ),
                    );
                  }).toList(),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _readinessView() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _readinessCard(),
      const SizedBox(height: 14),
      Card(
        child: ListTile(
          leading: Icon(
            _eduPayActive ? Icons.check_circle : Icons.pause_circle_outline,
          ),
          title: Text(
            'EduPay Status ${_eduPayActive ? 'ACTIVE' : 'NOT ACTIVE'}',
          ),
          subtitle: Text(
            _eduPayActive
                ? 'Automatically enabled'
                : 'Not automatically enabled',
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Provider credentials and account encryption are deployment-controlled. '
            'They cannot be entered or exposed in this dashboard.',
          ),
        ),
      ),
    ],
  );

  Future<void> _editSettings() async {
    if (!canManageEduPay) return;
    final source = (data?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final fields = <String>[
      'schoolCommissionRate',
      'parentShortfallChargeRate',
      'minimumSavingsRequirement',
      'maximumEduPayCover',
      'maximumCoverPercentage',
      'defaultRepaymentPeriodDays',
      'settlementLeadDays',
      'gracePeriodDays',
    ];
    final controllers = <String, TextEditingController>{
      for (final key in fields)
        key: TextEditingController(text: '${source[key] ?? ''}'),
    };
    var settlementMethod =
        '${source['settlementMethod'] ?? 'DEDUCT_COMMISSION'}';
    var autosave = source['autosaveEnabled'] == true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('EduPay operating settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final key in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: controllers[key],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: key,
                        helperText:
                            key.contains('Rate') ||
                                key == 'maximumCoverPercentage'
                            ? 'Enter a percentage from 0 to 100'
                            : null,
                      ),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  value: settlementMethod,
                  decoration: const InputDecoration(
                    labelText: 'settlementMethod',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'DEDUCT_COMMISSION',
                      child: Text('Deduct commission'),
                    ),
                    DropdownMenuItem(
                      value: 'GROSS_AND_RECEIVABLE',
                      child: Text('Gross and receivable'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => settlementMethod = value ?? settlementMethod,
                  ),
                ),
                SwitchListTile(
                  value: autosave,
                  title: const Text('autosaveEnabled'),
                  onChanged: (value) => setDialogState(() => autosave = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Validate and save'),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    final payload = <String, dynamic>{};
    for (final key in fields) {
      final value = double.tryParse(controllers[key]!.text.trim());
      final isPercentage =
          key.contains('Rate') || key == 'maximumCoverPercentage';
      if (value == null || value < 0 || (isPercentage && value > 100)) {
        _showError(
          'Enter valid non-negative settings; percentages must be 0–100.',
        );
        return;
      }
      payload[key] = value;
    }
    payload['settlementMethod'] = settlementMethod;
    payload['autosaveEnabled'] = autosave;
    try {
      await _api.saveSettings(payload);
      await _load();
      await _loadReadiness();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('EduPay settings saved and audited.')),
        );
      }
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _summary(Map<String, dynamic> s) => GridView.count(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: MediaQuery.sizeOf(context).width < 700 ? 1 : 4,
    childAspectRatio: 1.8,
    crossAxisSpacing: 14,
    mainAxisSpacing: 14,
    children: s.entries
        .map(
          (e) => Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.key
                        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}')
                        .trim(),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const Spacer(),
                  Text(
                    _display(e.value),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xff08783e),
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
        .toList(),
  );

  bool get _eduPayActive =>
      readiness?['ready'] == true &&
      readiness?['eduPayActive'] == true &&
      readiness?['customerInitiationEnabled'] == true;

  Widget _readinessRow({
    required String title,
    required bool ready,
    String? detail,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ready ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          color: ready ? const Color(0xff08783e) : Colors.orange.shade800,
          size: 21,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        Text(
          ready ? 'READY' : 'NOT READY',
          style: TextStyle(
            color: ready ? const Color(0xff08783e) : Colors.orange.shade900,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  Widget _readinessCard() {
    final payout =
        (readiness?['payoutConfig'] as Map?)?.cast<String, dynamic>() ?? {};
    final missing =
        (payout['missingEnvironment'] as List?)
            ?.map((value) => value.toString())
            .toList() ??
        <String>[];
    return Card(
      color: _eduPayActive ? const Color(0xffe9f6ee) : const Color(0xfffff4df),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EDUPAY LAUNCH READINESS',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xff10231a),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _eduPayActive
                  ? 'EduPay is automatically enabled for customer initiation.'
                  : 'EduPay is not automatically enabled.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),
            const Text(
              'Financial Infrastructure',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            _readinessRow(
              title: 'Payout Provider',
              ready: payout['provider'] == true,
              detail:
                  '${payout['providerName'] ?? 'SQUAD'} · ${payout['configurationStatus'] ?? 'NOT READY'} · ${payout['connectionStatus'] ?? 'NOT READY'}',
            ),
            _readinessRow(
              title: 'Account Encryption',
              ready: payout['accountEncryption'] == true,
              detail: payout['accountEncryption'] == true
                  ? 'Deployment encryption key is configured.'
                  : 'Deployment encryption key is required.',
            ),
            _readinessRow(
              title: 'Settlement Method',
              ready: payout['settlementMethod'] == true,
            ),
            _readinessRow(title: 'Rates', ready: payout['rates'] == true),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Missing production environment configuration',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: missing
                    .map(
                      (key) => Chip(
                        avatar: const Icon(Icons.key_outlined, size: 16),
                        label: Text(key),
                      ),
                    )
                    .toList(),
              ),
            ],
            const Divider(height: 32),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _eduPayActive
                    ? const Color(0xffd8f0e2)
                    : Colors.orange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'EduPay Status: ${_eduPayActive ? 'ACTIVE' : 'NOT ACTIVE'}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: _eduPayActive
                      ? const Color(0xff08783e)
                      : Colors.orange.shade900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settlementTools() {
    final canManage = permissions.contains('edupay.manage');
    final canProcess =
        permissions.contains('edupay.settlement.process') &&
        readiness?['ready'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settlement lifecycle',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Approve under Manage, then use explicit Squad process and requery routes. Legacy PATCH PROCESS and CONFIRM are never used.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                FilledButton.tonal(
                  onPressed: canManage
                      ? () => _settlementAction('APPROVE')
                      : null,
                  child: const Text('Approve settlement'),
                ),
                FilledButton(
                  onPressed: canProcess
                      ? () => _settlementAction('PROCESS')
                      : null,
                  child: const Text('Process payout'),
                ),
                OutlinedButton(
                  onPressed: canProcess
                      ? () => _settlementAction('REQUERY')
                      : null,
                  child: const Text('Requery payout'),
                ),
              ],
            ),
            if (!canProcess)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Process and requery stay disabled until permission and viable duty separation are confirmed.',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _settlementAction(String action) async {
    final id = await _promptForId('settlement ID');
    if (id == null || id.isEmpty) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$action settlement?'),
        content: const Text(
          'This sensitive financial action will be recorded in the audit log.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (action == 'APPROVE') {
        await _api.request(
          'PATCH',
          '/admin/edupay/settlements/$id',
          body: {'action': 'APPROVE'},
        );
      } else if (action == 'PROCESS') {
        await _api.processSettlement(id);
      } else {
        await _api.requerySettlement(id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server action completed and audited.')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<String?> _promptForId(String label) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Enter $label'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _table(List<Map<String, dynamic>> rows) {
    if (section == 'Fee approvals') return _feeApprovalsTable(rows);
    if (section == 'Parents & plans' || section == 'Savings & transactions') {
      rows = rows
          .map(
            (row) => Map<String, dynamic>.fromEntries(
              row.entries.where(
                (entry) =>
                    !entry.key.startsWith('_') &&
                    entry.key != '_id' &&
                    entry.key != 'id' &&
                    !entry.key.toLowerCase().contains('token'),
              ),
            ),
          )
          .toList();
    }
    if (section == 'Schools & onboarding') {
      rows = rows.where((r) {
        final q = schoolSearch.text.trim().toLowerCase();
        final status = _reviewStatus(r);
        return (q.isEmpty ||
                r.values.any((v) => '$v'.toLowerCase().contains(q))) &&
            (schoolStatus == 'ALL' ||
                status == schoolStatus.trim().toUpperCase());
      }).toList();
    }
    final table = rows.isEmpty
        ? const _Empty()
        : LayoutBuilder(
            builder: (context, constraints) {
              if ((section == 'Schools' || section == 'Schools & onboarding') &&
                  constraints.maxWidth < 700) {
                return section == 'Schools'
                    ? _mobileAcademicSchoolCards(rows)
                    : _mobileSchoolReviewCards(rows);
              }
              return Card(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns:
                        (rows.first.keys.take(
                            6,
                          )).map((k) => DataColumn(label: Text(k))).toList()
                          ..add(const DataColumn(label: Text('Actions'))),
                    rows: rows
                        .map(
                          (r) => DataRow(
                            cells:
                                r.entries
                                    .take(6)
                                    .map(
                                      (entry) => DataCell(
                                        Text(
                                          entry.key == 'status'
                                              ? _schoolStatusLabel(entry.value)
                                              : _display(entry.value),
                                        ),
                                      ),
                                    )
                                    .toList()
                                  ..add(
                                    DataCell(
                                      Wrap(
                                        spacing: 4,
                                        children: [
                                          if (section ==
                                                  'Schools & onboarding' &&
                                              _isSchoolRequestRow(r))
                                            SchoolRequestActionControls(
                                              row: r,
                                              canManage:
                                                  canReviewSchoolRequests,
                                              onView: () => _schoolDetails(r),
                                              onApprove: () =>
                                                  _schoolRequestAction(
                                                    r,
                                                    'APPROVE',
                                                  ),
                                              onReject: () =>
                                                  _schoolRequestAction(
                                                    r,
                                                    'REJECT',
                                                  ),
                                            ),
                                          if (section == 'Schools' &&
                                              !_isSchoolRequestRow(r)) ...[
                                            TextButton(
                                              onPressed: () =>
                                                  _openAcademicProfile(r),
                                              child: const Text(
                                                'Open Academic Profile',
                                              ),
                                            ),
                                            if (canManageEduPay)
                                              IconButton(
                                                tooltip: 'Edit school metadata',
                                                onPressed: () => _editSchool(r),
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                ),
                                              ),
                                            if (canManageEduPay)
                                              IconButton(
                                                tooltip:
                                                    'Reset administrator password',
                                                onPressed: () =>
                                                    _resetSchoolPassword(r),
                                                icon: const Icon(
                                                  Icons.lock_reset_outlined,
                                                ),
                                              ),
                                          ],
                                          if (section ==
                                                  'Schools & onboarding' &&
                                              !_isSchoolRequestRow(r)) ...[
                                            IconButton(
                                              tooltip: 'View details',
                                              icon: const Icon(
                                                Icons.visibility_outlined,
                                              ),
                                              onPressed: () =>
                                                  _schoolDetails(r),
                                            ),
                                            ..._schoolActionButtons(r),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              );
            },
          );
    if (section == 'Schools') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canManageEduPay)
            FilledButton.icon(
              onPressed: _createSchool,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Create School'),
            ),
          const SizedBox(height: 12),
          table,
        ],
      );
    }
    if (section != 'Schools & onboarding') return table;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: schoolSearch,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search schools',
                ),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: schoolStatus,
              items: const [
                'ALL',
                'PENDING_REVIEW',
                'APPROVED',
                'REJECTED',
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => schoolStatus = v ?? 'All'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        table,
      ],
    );
  }

  Widget _feeApprovalsTable(List<Map<String, dynamic>> rows) {
    final pending = rows
        .where((r) => _reviewStatus(r) == 'PENDING_APPROVAL')
        .toList();
    if (pending.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No pending school fees. Submitted fees appear here for review.',
          ),
        ),
      );
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('School')),
            DataColumn(label: Text('Session')),
            DataColumn(label: Text('Term')),
            DataColumn(label: Text('Class')),
            DataColumn(label: Text('Amount')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: pending.map((row) {
            final id = _reviewRowId(row);
            return DataRow(
              cells: [
                DataCell(Text(_display(row['schoolName'] ?? row['school']))),
                DataCell(Text(_display(row['sessionName'] ?? row['session']))),
                DataCell(Text(_display(row['termName'] ?? row['term']))),
                DataCell(Text(_display(row['className'] ?? row['classLevel']))),
                DataCell(Text(_display(row['amount']))),
                DataCell(Text(_reviewStatus(row))),
                DataCell(
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: id == null
                            ? null
                            : () => _showFeeDetails(row),
                        child: const Text('Review'),
                      ),
                      FilledButton.tonal(
                        onPressed: !canManageEduPay || id == null
                            ? null
                            : () => _feeAction(row, 'APPROVE'),
                        child: const Text('Approve'),
                      ),
                      TextButton(
                        onPressed: !canManageEduPay || id == null
                            ? null
                            : () => _feeAction(row, 'REJECT'),
                        child: const Text('Reject'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _showFeeDetails(Map<String, dynamic> row) async {
    final visible = row.entries.where((entry) {
      final key = entry.key.toLowerCase();
      return !key.contains('token') &&
          key != '_id' &&
          key != 'id' &&
          entry.value is! Map &&
          entry.value is! List;
    }).toList();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pending school fee review'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: visible
                .map(
                  (entry) => ListTile(
                    dense: true,
                    title: Text(entry.key),
                    subtitle: Text(_display(entry.value)),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _feeAction(Map<String, dynamic> row, String action) async {
    final id = _reviewRowId(row);
    if (id == null || !canManageEduPay) return;
    String? note;
    if (action == 'REJECT') {
      final controller = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reject school fee'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Rejection reason',
              hintText: 'Explain what the school must correct.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, controller.text.trim());
              },
              child: const Text('Reject fee'),
            ),
          ],
        ),
      );
      if (note == null || note.trim().isEmpty) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Approve school fee?'),
          content: const Text(
            'Approval publishes this official fee to eligible parent plans.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Approve fee'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      if (action == 'APPROVE') {
        await _api.approveFee(id);
      } else {
        await _api.rejectFee(id, note!);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'APPROVE'
                  ? 'Fee approved and published.'
                  : 'Fee rejected with feedback.',
            ),
          ),
        );
      }
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Widget _mobileSchoolReviewCards(List<Map<String, dynamic>> rows) {
    return Column(
      children: rows.map((row) {
        final request = _isSchoolRequestRow(row);
        final name = row['schoolName'] ?? row['name'] ?? 'School';
        final location = row['location'] ?? row['address'];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (location != null && '$location'.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('$location'),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_schoolStatusLabel(_reviewStatus(row))),
                ),
                const SizedBox(height: 8),
                request
                    ? SchoolRequestActionControls(
                        row: row,
                        canManage: canReviewSchoolRequests,
                        onView: () => _schoolDetails(row),
                        onApprove: () => _schoolRequestAction(row, 'APPROVE'),
                        onReject: () => _schoolRequestAction(row, 'REJECT'),
                      )
                    : Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: () => _schoolDetails(row),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('View'),
                          ),
                          ..._schoolActionButtons(row),
                        ],
                      ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _mobileAcademicSchoolCards(List<Map<String, dynamic>> rows) => Column(
    children: rows
        .map(
          (row) => Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text('${row['name'] ?? row['schoolName'] ?? 'School'}'),
              subtitle: Text('${row['location'] ?? row['address'] ?? ''}'),
              trailing: TextButton(
                onPressed: () => _openAcademicProfile(row),
                child: const Text('Open Academic Profile'),
              ),
            ),
          ),
        )
        .toList(),
  );

  Future<void> _openAcademicProfile(Map<String, dynamic> row) async {
    final id = (row['id'] ?? row['_id'])?.toString();
    if (id == null || id.isEmpty) {
      _showError('This school has no profile identifier.');
      return;
    }
    try {
      final response = await _api.academicOverview(id);
      if (!mounted) return;
      final profiles = response['schoolProfiles'];
      final overview = profiles is List && profiles.isNotEmpty
          ? profiles.first
          : response['usage'] ?? response['summary'] ?? response;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            '${row['name'] ?? row['schoolName'] ?? 'School'} · Academic Profile',
          ),
          content: SingleChildScrollView(child: Text('$overview')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _schoolDetails(Map<String, dynamic> row) async {
    if (!mounted) return;
    if (_isSchoolRequestRow(row)) {
      await _schoolRequestDetails(row);
      return;
    }
    final id = row['id']?.toString() ?? row['_id']?.toString();
    Map<String, dynamic> details = row;
    if (id != null && id.isNotEmpty) {
      try {
        final response = await _api.schoolDetail(id);
        final value = response['school'] ?? response['data'];
        if (value is Map) details = Map<String, dynamic>.from(value);
        if (permissions.contains('edupay.school.private_assets.view')) {
          final privateData = await _api.privateSchoolDocuments(id);
          final assets = privateData['assets'];
          details = {
            ...details,
            'privateAssets': assets is Map
                ? [
                    if (assets['logo'] is Map) assets['logo'],
                    ...((assets['supportingDocuments'] as List?) ?? const []),
                  ]
                : (assets ?? privateData['documents'] ?? privateData['data']),
          };
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', '')),
            ),
          );
      }
    }
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(details['name']?.toString() ?? 'School details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                details.entries
                    .where((e) => e.key != 'privateAssets')
                    .map((e) => '${e.key}: ${e.value}')
                    .join('\n'),
              ),
              if (permissions.contains('edupay.school.private_assets.view') &&
                  details['privateAssets'] is List) ...[
                const Divider(),
                const Text(
                  'Private assets',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...(details['privateAssets'] as List).whereType<Map>().map((
                  asset,
                ) {
                  final id = (asset['fileId'] ?? asset['id'] ?? asset['_id'])
                      .toString();
                  return ListTile(
                    title: Text(
                      asset['originalName']?.toString() ?? 'Document',
                    ),
                    subtitle: Text(
                      asset['mimeType']?.toString() ?? 'Private file',
                    ),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Preview',
                          icon: const Icon(Icons.visibility_outlined),
                          onPressed: () => _downloadAsset(
                            (details['id'] ?? details['_id']).toString(),
                            id,
                            mimeType: asset['mimeType']?.toString(),
                            assetName: asset['originalName']?.toString(),
                            preview: true,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Download',
                          icon: const Icon(Icons.download_outlined),
                          onPressed: () => _downloadAsset(
                            (details['id'] ?? details['_id']).toString(),
                            id,
                            mimeType: asset['mimeType']?.toString(),
                            assetName: asset['originalName']?.toString(),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
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

  Future<void> _schoolRequestDetails(Map<String, dynamic> row) async {
    final id = row['_requestId']?.toString() ?? row['id']?.toString();
    if (id == null || id.isEmpty) return;
    Map<String, dynamic> details =
        (row['_request'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{...row};
    try {
      final response = await _api.schoolRequestDetail(id);
      final value =
          response['request'] ?? response['schoolRequest'] ?? response['data'];
      if (value is Map) details = Map<String, dynamic>.from(value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
    if (!mounted) return;
    final fields = <String, dynamic>{
      'School Name': details['schoolName'] ?? details['name'],
      'School Type': details['schoolType'] ?? details['category'],
      'Address / Location': details['location'] ?? details['address'],
      'Requester Name': details['requesterName'],
      'Requester Email': details['requesterEmail'],
      'Requester Phone': details['requesterPhone'],
      'School Contact Phone': details['contactPhone'],
      'Registration Information':
          details['registrationNumber'] ?? details['registration'],
      'Submission Date': details['createdAt'] ?? details['submittedAt'],
      'Current Status': details['status'] ?? 'PENDING_REVIEW',
      'Request ID': details['id'] ?? details['_id'] ?? id,
    }..removeWhere((_, value) => value == null || '$value'.trim().isEmpty);
    final selectedAction = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          details['schoolName']?.toString() ??
              details['name']?.toString() ??
              'School Application Details',
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: fields.entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText('${entry.key}: ${entry.value}'),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          SchoolRequestDetailsActions(
            pending: _reviewStatus(details) == 'PENDING_REVIEW',
            canManage: canReviewSchoolRequests,
            onReject: () => Navigator.pop(dialogContext, 'REJECT'),
            onApprove: () => Navigator.pop(dialogContext, 'APPROVE'),
            onClose: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
    if (selectedAction != null) {
      await _schoolRequestAction(row, selectedAction);
    }
  }

  Future<void> _downloadAsset(
    String schoolId,
    String fileId, {
    String? mimeType,
    String? assetName,
    bool preview = false,
  }) async {
    // The authenticated response is intentionally kept in memory; no private
    // URL or document reference is rendered into the public UI.
    if (schoolId.isEmpty) return;
    try {
      final response = await _api.privateAssetBytes(schoolId, fileId);
      if (!mounted) return;
      if (preview) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Private asset preview'),
            content: mimeType?.startsWith('image/') == true
                ? Image.memory(response.bodyBytes, fit: BoxFit.contain)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.picture_as_pdf, size: 48),
                      Text(
                        'Authenticated PDF loaded (${response.bodyBytes.length} bytes).',
                      ),
                    ],
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      } else {
        await savePrivateAsset(
          response.bodyBytes,
          assetName ?? 'private-asset',
          mimeType ?? 'application/octet-stream',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authenticated private asset downloaded.'),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
    }
  }

  Future<void> _createSchool() async {
    if (!canManageEduPay) return;
    final fields = <String>[
      'schoolName',
      'schoolType',
      'proprietorName',
      'email',
      'phone',
      'address',
      'state',
      'lga',
      'temporaryPassword',
    ];
    final controllers = {for (final f in fields) f: TextEditingController()};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Create School'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
          child: SingleChildScrollView(
            child: Column(
              children: fields
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: controllers[f],
                        obscureText: f == 'temporaryPassword',
                        keyboardType: f == 'email'
                            ? TextInputType.emailAddress
                            : null,
                        decoration: InputDecoration(labelText: f),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final body = <String, dynamic>{
      for (final f in fields)
        if (controllers[f]!.text.trim().isNotEmpty)
          f: controllers[f]!.text.trim(),
    };
    if ((body['schoolName'] ?? '').toString().isEmpty ||
        (body['email'] ?? '').toString().isEmpty ||
        (body['temporaryPassword'] ?? '').toString().length < 8) {
      _showError(
        'School name, email and a temporary password of at least 8 characters are required.',
      );
      return;
    }
    try {
      await _api.createSchool(body);
      _showSuccess('School created. The password is not displayed.');
      _load();
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _editSchool(Map<String, dynamic> row) async {
    final id = _reviewRowId(row);
    if (id == null || !canManageEduPay) return;
    final fields = [
      'schoolName',
      'schoolType',
      'proprietorName',
      'email',
      'phone',
      'address',
      'state',
      'lga',
    ];
    final controllers = {
      for (final f in fields)
        f: TextEditingController(
          text: '${row[f] ?? row[_schoolAlias(f)] ?? ''}',
        ),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Edit school metadata'),
        content: SingleChildScrollView(
          child: Column(
            children: fields
                .map(
                  (f) => TextField(
                    controller: controllers[f],
                    decoration: InputDecoration(labelText: f),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.updateSchool(id, {
        for (final f in fields) f: controllers[f]!.text.trim(),
        // Backend persistence currently uses `name`; keep schoolName in the
        // contract and provide the compatibility alias until it is mapped.
        'name': controllers['schoolName']!.text.trim(),
      });
      _showSuccess('School metadata updated.');
      _load();
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _schoolAlias(String field) => switch (field) {
    'schoolName' => 'name',
    'phone' => 'contactPhone',
    _ => field,
  };

  Future<void> _resetSchoolPassword(Map<String, dynamic> row) async {
    final id = _reviewRowId(row);
    if (id == null || !canManageEduPay) return;
    final password = TextEditingController(), confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Reset administrator password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Strong temporary password',
              ),
            ),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm temporary password',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Reset password'),
          ),
        ],
      ),
    );
    if (ok != true ||
        password.text.length < 8 ||
        password.text != confirm.text) {
      _showError('Passwords must match and contain at least 8 characters.');
      return;
    }
    try {
      await _api.resetSchoolPassword(id, password.text);
      _showSuccess('Administrator password reset. It is not displayed.');
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showSuccess(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
  Future<void> _schoolAction(Map<String, dynamic> row, String action) async {
    final id = row['id']?.toString() ?? row['_id']?.toString();
    if (id == null || id.isEmpty) return;
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('$action school'),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Review note (required)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, note.text.trim().isNotEmpty),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.schoolAction(id, action, note: note.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('School $action completed and audited.')),
        );
        _load();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
    }
  }

  Future<void> _schoolRequestAction(
    Map<String, dynamic> row,
    String action,
  ) async {
    final id = row['_requestId']?.toString() ?? row['id']?.toString();
    if (id == null || id.isEmpty) return;
    String? rejectionReason;
    if (action == 'REJECT') {
      final controller = TextEditingController();
      rejectionReason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reject School Application'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(dialogContext, value);
              },
              child: const Text('Reject Application'),
            ),
          ],
        ),
      );
      if (rejectionReason == null || rejectionReason.isEmpty) return;
    } else {
      Map<String, dynamic> details =
          (row['_request'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{...row};
      try {
        final response = await _api.schoolRequestDetail(id);
        final value =
            response['request'] ??
            response['schoolRequest'] ??
            response['data'];
        if (value is Map) details = Map<String, dynamic>.from(value);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', '')),
            ),
          );
        }
        return;
      }
      final representativeFields = <String, dynamic>{
        'Requester Name': details['requesterName'],
        'Requester Email': details['requesterEmail'],
        'Requester Phone': details['requesterPhone'],
        'School Contact Phone': details['contactPhone'],
      }..removeWhere((_, value) => value == null || '$value'.trim().isEmpty);
      var authorityConfirmed = false;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Approve School'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Approve this school for Servicepay EduPay?'),
                  if (representativeFields.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...representativeFields.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('${entry.key}: ${entry.value}'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: authorityConfirmed,
                    onChanged: (value) => setDialogState(
                      () => authorityConfirmed = value ?? false,
                    ),
                    title: const Text(
                      'I verified this requester is authorized to represent the school.',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: authorityConfirmed
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: const Text('Approve School'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
      try {
        await _api.schoolRequestAction(
          id,
          action,
          representativeAuthorityConfirmed: true,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', '')),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('School approved and admitted to EduPay.'),
        ),
      );
      await _load();
      return;
    }
    try {
      await _api.schoolRequestAction(
        id,
        action,
        rejectionReason: rejectionReason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'APPROVE'
                ? 'School approved and admitted to EduPay.'
                : 'School application rejected and audited.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  String _schoolStatusLabel(dynamic value) {
    switch (value?.toString().toUpperCase()) {
      case 'PENDING_REVIEW':
        return 'Pending review';
      case 'APPROVED':
        return 'Approved';
      case 'REJECTED':
        return 'Rejected';
      case 'CONTACTED':
        return 'Contacted';
      case 'CLOSED':
        return 'Closed';
      default:
        return _display(value);
    }
  }

  List<Widget> _schoolActionButtons(Map<String, dynamic> row) {
    if (_isSchoolRequestRow(row)) return const <Widget>[];
    final state = _reviewStatus(row);
    final actions = switch (state) {
      'PENDING_REVIEW' => ['APPROVE', 'REJECT', 'REQUEST_UPDATE'],
      'UNDER_REVIEW' => ['APPROVE', 'REJECT', 'REQUEST_UPDATE'],
      'APPROVED' => ['SUSPEND'],
      'SUSPENDED' => ['REACTIVATE'],
      _ => <String>[],
    };
    final icons = <String, IconData>{
      'APPROVE': Icons.check_circle_outline,
      'REJECT': Icons.cancel_outlined,
      'REQUEST_UPDATE': Icons.edit_note,
      'SUSPEND': Icons.pause_circle_outline,
      'REACTIVATE': Icons.play_circle_outline,
    };
    return actions
        .map(
          (action) => IconButton(
            tooltip: action,
            icon: Icon(icons[action]),
            onPressed: () => _schoolAction(row, action),
          ),
        )
        .toList();
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext c) =>
      const Center(child: CircularProgressIndicator());
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext c) => const Card(
    child: Padding(
      padding: EdgeInsets.all(40),
      child: Center(child: Text('No records returned by the server.')),
    ),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext c) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: retry, child: const Text('Try again')),
      ],
    ),
  );
}
