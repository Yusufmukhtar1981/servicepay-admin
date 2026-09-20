import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'edupay_school_api.dart';
import 'student_activity_center_screen.dart';
import 'academic_operations_screen.dart';

List<String> schoolPortalNavigationTabsForRole(String role) {
  final normalized = role.trim().toUpperCase();
  if (const {'OWNER', 'ADMIN', 'SCHOOL_ADMIN'}.contains(normalized)) {
    return const [
      'Dashboard',
      'Students',
      'Teachers',
      'Classes',
      'Subjects',
      'Attendance',
      'Results / Report Cards',
      'Timetable',
      'Activities / Updates',
      'Parents',
      'Academic Sessions',
      'Fees / EduPay',
      'Notifications',
      'Settings',
      'Logout',
    ];
  }
  if (normalized == 'FINANCE') {
    return const [
      'Dashboard',
      'Students',
      'Expected School Fees',
      'Upcoming Settlements',
      'Completed Settlements',
      'Reconciliation',
      'Reports',
      'School Profile',
      'Settings',
      'Logout',
    ];
  }
  return const [
    'Dashboard',
    'My Classes',
    'My Students',
    'Attendance',
    'Results / Assessments',
    'Activities',
    'Announcements',
    'Logout',
  ];
}

class SchoolPortalScreen extends StatefulWidget {
  const SchoolPortalScreen({super.key, this.api});

  final EduPaySchoolApi? api;

  @override
  State<SchoolPortalScreen> createState() => _SchoolPortalScreenState();
}

class _SchoolPortalScreenState extends State<SchoolPortalScreen> {
  late final api = widget.api ?? EduPaySchoolApi();
  Map<String, dynamic>? data;
  String tab = 'Dashboard';
  bool loading = true;
  bool roleLoaded = false;
  String? error;
  String schoolRole = '';
  List<Map<String, dynamic>> sessions = [];
  List<Map<String, dynamic>> terms = [];
  List<Map<String, dynamic>> classes = [];
  List<Map<String, dynamic>> fees = [];
  Map<String, dynamic>? selectedSession, selectedTerm, selectedClass;
  final tabs = const [
    'Overview',
    'Academic workspace',
    'Students',
    'Academic Sessions',
    'Terms',
    'Classes',
    'Fee Structures',
    'EduPay Students',
    'Expected School Fees',
    'Student Activity Center',
    'Upcoming Settlements',
    'Completed Settlements',
    'Servicepay 5% Commission',
    'Reconciliation',
    'Reports',
    'School Profile',
    'Settings',
    'Logout',
  ];
  bool get managerRole =>
      const {'OWNER', 'ADMIN', 'SCHOOL_ADMIN'}.contains(schoolRole);
  bool get financeRole => schoolRole == 'FINANCE';
  bool get teacherRole => schoolRole == 'TEACHER';
  List<String> get navigationTabs =>
      schoolPortalNavigationTabsForRole(schoolRole);
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadRole();
    if (mounted) await _load();
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('school_role');
    if (mounted) {
      setState(() {
        schoolRole = value?.trim().toUpperCase() ?? '';
        roleLoaded = true;
        tab = 'Dashboard';
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final path = switch (tab) {
        'Dashboard' => managerRole || financeRole
            ? '/edupay/school/dashboard'
            : '/edupay/school/academic/dashboard',
        'Overview' => '/edupay/school/dashboard',
        'Academic workspace' => '/edupay/school/academic/dashboard',
        'Academic Sessions' => '/edupay/school/sessions',
        'Terms' => '/edupay/school/terms',
        'Classes' => '/edupay/school/classes',
        'Students' => '/edupay/school/students',
        'EduPay Students' => '/edupay/school/students',
        'Fee Structures' => '/edupay/school/fees',
        'Fees / EduPay' => '/edupay/school/fees',
        'Expected School Fees' => '/edupay/school/fees',
        'Upcoming Settlements' => '/edupay/school/settlements',
        'Completed Settlements' => '/edupay/school/settlements',
        'Servicepay 5% Commission' => '/edupay/school/settlements',
        'Settlements' => '/edupay/school/settlements',
        'Reconciliation' => '/edupay/school/reconciliation',
        'Reports' => '/edupay/school/reports',
        'Student Activity Center' =>
          '/edupay/activity-center/school/records?type=dashboard',
        'School Profile' => '/edupay/school/profile',
        'Profile' => '/edupay/school/profile',
        'Settings' => '/edupay/school/profile',
        'Logout' => '/edupay/school/dashboard',
        _ => managerRole || financeRole
            ? '/edupay/school/dashboard'
            : '/edupay/school/academic/dashboard',
      };
      data = await api.request('GET', path);
      if (tab == 'Academic Sessions') sessions = _list(data!, 'sessions');
      if (tab == 'Terms') terms = _list(data!, 'terms');
      if (tab == 'Classes') classes = _list(data!, 'classes');
      if (tab == 'Fee Structures' || tab == 'Expected School Fees') {
        fees = _list(data!, 'fees');
      }
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('school_auth_token');
    await p.remove('school_role');
    await p.remove('school_name');
    await p.remove('school_id');
    await p.remove('school_membership_status');
    await p.remove('school_status');
    await p.remove('school_authenticated_user');
    await p.remove('school_must_change_password');
    if (mounted) Navigator.of(context).pushReplacementNamed('/');
  }

  Future<void> _backToCustomer() async {
    final p = await SharedPreferences.getInstance();
    for (final key in const [
      'school_auth_token',
      'school_role',
      'school_name',
      'school_id',
      'school_membership_status',
      'school_status',
      'school_authenticated_user',
      'school_must_change_password',
    ]) {
      await p.remove(key);
    }
    await launchUrl(
      Uri.parse('https://servicepay.ng/'),
      webOnlyWindowName: '_self',
    );
  }

  Widget _profileCard() {
    final profile = data?['school'] is Map
        ? Map<String, dynamic>.from(data!['school'] as Map)
        : data ?? <String, dynamic>{};
    final visible = profile.entries
        .where(
          (entry) =>
              !entry.key.toLowerCase().contains('password') &&
              !entry.key.toLowerCase().contains('token'),
        )
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: visible
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('${entry.key}: ${entry.value ?? ''}'),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!roleLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      drawer: MediaQuery.sizeOf(context).width < 700
          ? Drawer(
              child: ListView(
                children: navigationTabs
                    .map(
                      (t) => ListTile(
                        title: Text(t),
                        selected: tab == t,
                        onTap: () {
                          Navigator.pop(context);
                          if (t == 'Logout') {
                            _logout();
                            return;
                          }
                          setState(() => tab = t);
                          _load();
                        },
                      ),
                    )
                    .toList(),
              ),
            )
          : null,
      appBar: AppBar(
        title: const Text('EduPay School Portal'),
        actions: [
          TextButton.icon(
            key: const Key('school-back-to-customer'),
            onPressed: _backToCustomer,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('ServicePay'),
          ),
          IconButton(
            onPressed: _logout,
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Row(
        children: [
          Visibility(
            visible: MediaQuery.sizeOf(context).width >= 700,
            child: SingleChildScrollView(
              child: NavigationRail(
                selectedIndex: navigationTabs.indexOf(tab),
                labelType: MediaQuery.sizeOf(context).width < 700
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                onDestinationSelected: (i) {
                  if (navigationTabs[i] == 'Logout') {
                    _logout();
                    return;
                  }
                  setState(() => tab = navigationTabs[i]);
                  _load();
                },
                destinations: navigationTabs
                    .map(
                      (t) => NavigationRailDestination(
                        icon: Icon(_icon(t)),
                        selectedIcon: Icon(_icon(t)),
                        label: Text(t),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _load,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text(
                            tab,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 20),
                          tab == 'Profile'
                              ? _profileCard()
                              : (teacherRole ||
                                      const {
                                        'Teachers',
                                        'Classes',
                                        'Subjects',
                                        'Attendance',
                                        'Results / Report Cards',
                                        'Timetable',
                                        'Activities / Updates',
                                        'Academic Sessions',
                                      }.contains(tab))
                                  ? AcademicOperationsScreen(
                                      api: api,
                                      manager: managerRole,
                                      initialSection: switch (tab) {
                                        'My Classes' => 'Classes & subjects',
                                        'My Students' => 'Students',
                                        'Teachers' => 'Teachers',
                                        'Classes' => 'Classes & subjects',
                                        'Subjects' => 'Classes & subjects',
                                        'Attendance' => 'Attendance',
                                        'Results / Report Cards' =>
                                          'Assessments',
                                        'Results / Assessments' =>
                                          'Assessments',
                                        'Timetable' => 'Timetable',
                                        'Activities / Updates' => 'Activities',
                                        'Activities' => 'Activities',
                                        'Academic Sessions' =>
                                          'Sessions & terms',
                                        'Announcements' => 'Activities',
                                        'Assignments' => 'Activities',
                                        _ => 'Dashboard',
                                      },
                                      allowedSections: managerRole
                                          ? null
                                          : const [
                                              'Dashboard',
                                              'Classes & subjects',
                                              'Students',
                                              'Attendance',
                                              'Assessments',
                                              'Timetable',
                                              'Activities',
                                            ],
                                    )
                                  : tab == 'Parents'
                                      ? StudentActivityCenterScreen(
                                          api: api,
                                          initialSection: 'Parents/Guardians',
                                          onOpenStudents: () {
                                            setState(() => tab = 'Students');
                                            _load();
                                          },
                                        )
                                      : tab == 'Notifications'
                                          ? StudentActivityCenterScreen(
                                              api: api,
                                              initialSection: 'Announcements',
                                            )
                                          : tab == 'Academic workspace'
                                              ? AcademicOperationsScreen(
                                                  api: api)
                                              : tab == 'Dashboard'
                                                  ? _dashboard()
                                                  : tab == 'Academic setup'
                                                      ? _academicSetup()
                                                      : const {
                                                          'Academic Sessions',
                                                          'Terms',
                                                          'Classes',
                                                          'Fee Structures',
                                                        }.contains(tab)
                                                          ? Column(
                                                              children: [
                                                                Align(
                                                                  alignment:
                                                                      Alignment
                                                                          .centerLeft,
                                                                  child:
                                                                      FilledButton
                                                                          .icon(
                                                                    onPressed: tab ==
                                                                            'Fee Structures'
                                                                        ? _createFee
                                                                        : () =>
                                                                            _academicDialog(
                                                                              tab == 'Academic Sessions'
                                                                                  ? 'session'
                                                                                  : tab == 'Terms'
                                                                                      ? 'term'
                                                                                      : 'class',
                                                                            ),
                                                                    icon: const Icon(
                                                                        Icons
                                                                            .add),
                                                                    label: Text(
                                                                        'Create $tab'),
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                    height: 12),
                                                                _records(),
                                                              ],
                                                            )
                                                          : tab == 'Draft fees'
                                                              ? Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    FilledButton
                                                                        .icon(
                                                                      onPressed:
                                                                          _createFee,
                                                                      icon: const Icon(
                                                                          Icons
                                                                              .add),
                                                                      label: const Text(
                                                                          'Create draft fee'),
                                                                    ),
                                                                    const SizedBox(
                                                                        height:
                                                                            18),
                                                                    const Card(
                                                                      child:
                                                                          Padding(
                                                                        padding:
                                                                            EdgeInsets.all(24),
                                                                        child:
                                                                            Text(
                                                                          'Draft fees are submitted to Head Office for approval.',
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                )
                                                              : tab ==
                                                                      'Settings'
                                                                  ? const Card(
                                                                      child:
                                                                          Padding(
                                                                        padding:
                                                                            EdgeInsets.all(24),
                                                                        child:
                                                                            Text(
                                                                          'School settings are managed by Head Office.',
                                                                        ),
                                                                      ),
                                                                    )
                                                                  : _records(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  IconData _icon(String t) => switch (t) {
        'Overview' => Icons.dashboard_outlined,
        'Academic workspace' => Icons.menu_book_outlined,
        'School Profile' => Icons.school_outlined,
        'Academic Sessions' => Icons.calendar_month_outlined,
        'Terms' => Icons.event_outlined,
        'Classes' => Icons.class_outlined,
        'Fee Structures' => Icons.request_quote_outlined,
        'Students' => Icons.groups_outlined,
        'Teachers' => Icons.co_present_outlined,
        'My Students' => Icons.groups_outlined,
        'Attendance' => Icons.fact_check_outlined,
        'Results / Report Cards' ||
        'Results / Assessments' =>
          Icons.assignment_turned_in_outlined,
        'Activities / Updates' || 'Activities' => Icons.campaign_outlined,
        'Parents' => Icons.family_restroom_outlined,
        'Fees / EduPay' => Icons.account_balance_wallet_outlined,
        'Notifications' || 'Announcements' => Icons.notifications_outlined,
        'Settlements' => Icons.payments_outlined,
        'Reconciliation' => Icons.compare_arrows_outlined,
        'Reports' => Icons.assessment_outlined,
        'Student Activity Center' => Icons.auto_stories_outlined,
        'Settings' => Icons.settings_outlined,
        'Logout' => Icons.logout,
        _ => Icons.payments_outlined,
      };
  List<Map<String, dynamic>> _list(Map<String, dynamic> value, String key) {
    final rows = value[key];
    return rows is List
        ? rows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
        : [];
  }

  Widget _dashboard() {
    final s = (data?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: s.entries
          .map(
            (e) => SizedBox(
              width: 220,
              height: 120,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.key.replaceAllMapped(
                          RegExp(r'([A-Z])'),
                          (m) => ' ${m[1]}',
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${e.value}',
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: Color(0xff08783e),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _records() {
    final key = switch (tab) {
      'Academic Sessions' => 'sessions',
      'Terms' => 'terms',
      'Classes' => 'classes',
      'Students' => 'students',
      'EduPay Students' => 'students',
      'Fee Structures' => 'fees',
      'Expected School Fees' => 'fees',
      'Upcoming Settlements' => 'settlements',
      'Completed Settlements' => 'settlements',
      'Servicepay 5% Commission' => 'settlements',
      'Settlements' => 'settlements',
      'Reconciliation' => 'reconciliation',
      'Reports' => 'report',
      _ => 'school',
    };
    final value = data?[key];
    if (value is Map) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(
            spacing: 24,
            runSpacing: 16,
            children: value.entries
                .map(
                  (entry) => SizedBox(
                    width: 220,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.key.toString()),
                      subtitle: Text('${entry.value}'),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      );
    }
    if (value is! List || value.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text('No records are available yet.'),
        ),
      );
    }
    final rows = value
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final filtered = switch (tab) {
      'Upcoming Settlements' => rows
          .where(
            (r) => !{
              'SETTLED',
              'COMPLETED',
              'REVERSED',
            }.contains(r['status']?.toString().toUpperCase()),
          )
          .toList(),
      'Completed Settlements' => rows
          .where(
            (r) => {
              'SETTLED',
              'COMPLETED',
            }.contains(r['status']?.toString().toUpperCase()),
          )
          .toList(),
      'Servicepay 5% Commission' => rows
          .map(
            (r) => {
              'schoolCommissionAmount': r['schoolCommissionAmount'],
              'grossAmount': r['grossAmount'],
              'netAmount': r['netAmount'],
              'reference': r['reference'],
            },
          )
          .toList(),
      _ => rows,
    };
    if (filtered.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text('No records are available yet.'),
        ),
      );
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: filtered.first.keys
              .take(5)
              .map((k) => DataColumn(label: Text(k)))
              .toList(),
          rows: filtered
              .map(
                (r) => DataRow(
                  cells: r.values
                      .take(5)
                      .map((v) => DataCell(Text('$v')))
                      .toList(),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _academicSetup() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create in order: academic session → term → class',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => _academicDialog('session'),
                icon: const Icon(Icons.calendar_today),
                label: const Text('Create session'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _academicDialog('term'),
                icon: const Icon(Icons.event),
                label: const Text('Create term'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _academicDialog('class'),
                icon: const Icon(Icons.class_outlined),
                label: const Text('Create class'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _records(),
        ],
      );

  Future<void> _academicDialog(String type) async {
    if (type == 'term' && sessions.isEmpty) {
      final response = await api.sessions();
      sessions = _list(response, 'sessions');
    }
    final name = TextEditingController();
    final parent = TextEditingController();
    String? selectedSession;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setDialogState) => AlertDialog(
          title: Text('Create academic $type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: '$type name'),
              ),
              if (type == 'term')
                DropdownButton<String>(
                  isExpanded: true,
                  value: selectedSession,
                  hint: const Text('Select academic session'),
                  items: sessions.map((row) {
                    final id = (row['_id'] ?? row['id']).toString();
                    return DropdownMenuItem(
                      value: id,
                      child: Text('${row['name']}'),
                    );
                  }).toList(),
                  onChanged: (value) => setDialogState(() {
                    selectedSession = value;
                    parent.text = value ?? '';
                  }),
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
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      final body = {
        'name': name.text.trim(),
        if (type == 'term' && parent.text.trim().isNotEmpty)
          'session': parent.text.trim(),
      };
      if (type == 'session') await api.createAcademicSession(body);
      if (type == 'term') await api.createTerm(body);
      if (type == 'class') await api.createClass(body);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Academic $type created.')));
        _load();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
    }
  }

  Future<void> _createFee() async {
    if (sessions.isEmpty) {
      final response = await api.sessions();
      sessions = _list(response, 'sessions');
    }
    if (terms.isEmpty) {
      final response = await api.terms();
      terms = _list(response, 'terms');
    }
    if (classes.isEmpty) {
      final response = await api.classes();
      classes = _list(response, 'classes');
    }
    final amount = TextEditingController();
    String? sessionId, termId, classId;
    String id(Map<String, dynamic> row) => (row['_id'] ?? row['id']).toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create draft fee'),
        content: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              children: [
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                DropdownButton<String>(
                  isExpanded: true,
                  value: sessionId,
                  hint: const Text('Select session'),
                  items: sessions
                      .map(
                        (row) => DropdownMenuItem(
                          value: id(row),
                          child: Text('${row['name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() {
                    sessionId = value;
                    termId = null;
                  }),
                ),
                DropdownButton<String>(
                  isExpanded: true,
                  value: termId,
                  hint: const Text('Select term'),
                  items: terms
                      .where(
                        (row) =>
                            (row['session'] is Map
                                    ? ((row['session'] as Map)['_id'] ??
                                            (row['session'] as Map)['id'])
                                        .toString()
                                    : row['session']?.toString()) ==
                                sessionId ||
                            row['sessionId']?.toString() == sessionId,
                      )
                      .map(
                        (row) => DropdownMenuItem(
                          value: id(row),
                          child: Text('${row['name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => termId = value),
                ),
                DropdownButton<String>(
                  isExpanded: true,
                  value: classId,
                  hint: const Text('Select class'),
                  items: classes
                      .map(
                        (row) => DropdownMenuItem(
                          value: id(row),
                          child: Text('${row['name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => classId = value),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: sessionId != null && termId != null && classId != null
                ? () => Navigator.pop(dialogContext, true)
                : null,
            child: const Text('Submit draft'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    try {
      await api.request('POST', '/edupay/school/fees', {
        'amount': double.tryParse(amount.text.trim()) ?? 0,
        'classLevel': classId,
        'session': sessionId,
        'term': termId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft fee submitted for approval.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }
}
