import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'edupay_school_api.dart';

class SchoolPortalScreen extends StatefulWidget {
  const SchoolPortalScreen({super.key});
  @override
  State<SchoolPortalScreen> createState() => _SchoolPortalScreenState();
}

class _SchoolPortalScreenState extends State<SchoolPortalScreen> {
  final api = EduPaySchoolApi();
  Map<String, dynamic>? data;
  String tab = 'Dashboard';
  bool loading = true;
  String? error;
  final tabs = const [
    'Dashboard',
    'Profile',
    'Sessions & classes',
    'Draft fees',
    'Students',
    'Settlements',
    'Reconciliation',
    'Reports',
  ];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final path = switch (tab) {
        'Dashboard' => '/edupay/school/dashboard',
        'Profile' => '/edupay/school/profile',
        'Sessions & classes' => '/edupay/school/sessions',
        'Students' => '/edupay/school/students',
        'Settlements' => '/edupay/school/settlements',
        'Reconciliation' => '/edupay/school/reconciliation',
        'Reports' => '/edupay/school/reports',
        _ => '/edupay/school/dashboard',
      };
      data = await api.request('GET', path);
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('school_auth_token');
    if (mounted) Navigator.of(context).pushReplacementNamed('/');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('EduPay School Portal'),
          actions: [
            IconButton(
              onPressed: _logout,
              tooltip: 'Log out',
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: tabs.indexOf(tab),
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) {
                setState(() => tab = tabs[i]);
                _load();
              },
              destinations: tabs
                  .map(
                    (t) => NavigationRailDestination(
                      icon: Icon(_icon(t)),
                      selectedIcon: Icon(_icon(t)),
                      label: Text(t),
                    ),
                  )
                  .toList(),
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
                            tab == 'Dashboard'
                                ? _dashboard()
                                : tab == 'Draft fees'
                                    ? Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          FilledButton.icon(
                                            onPressed: _createFee,
                                            icon: const Icon(Icons.add),
                                            label:
                                                const Text('Create draft fee'),
                                          ),
                                          const SizedBox(height: 18),
                                          const Card(
                                            child: Padding(
                                              padding: EdgeInsets.all(24),
                                              child: Text(
                                                'Draft fees are submitted to Head Office for approval.',
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : _records(),
                          ],
                        ),
            ),
          ],
        ),
      );
  IconData _icon(String t) => switch (t) {
        'Dashboard' => Icons.dashboard_outlined,
        'Profile' => Icons.school_outlined,
        'Sessions & classes' => Icons.calendar_month_outlined,
        'Draft fees' => Icons.request_quote_outlined,
        'Students' => Icons.groups_outlined,
        'Settlements' => Icons.payments_outlined,
        'Reconciliation' => Icons.compare_arrows_outlined,
        'Reports' => Icons.assessment_outlined,
        _ => Icons.payments_outlined,
      };
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
      'Sessions & classes' => 'sessions',
      'Students' => 'students',
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
                .map((entry) => SizedBox(
                      width: 220,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(entry.key.toString()),
                        subtitle: Text('${entry.value}'),
                      ),
                    ))
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
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: rows.first.keys
              .take(5)
              .map((k) => DataColumn(label: Text(k)))
              .toList(),
          rows: rows
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

  Future<void> _createFee() async {
    final amount = TextEditingController();
    final classLevel = TextEditingController();
    final session = TextEditingController();
    final term = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create draft fee'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount')),
              TextField(
                  controller: classLevel,
                  decoration: const InputDecoration(labelText: 'Class')),
              TextField(
                  controller: session,
                  decoration:
                      const InputDecoration(labelText: 'Academic session ID')),
              TextField(
                  controller: term,
                  decoration: const InputDecoration(labelText: 'Term ID')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Submit draft')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    try {
      await api.request('POST', '/edupay/school/fees', {
        'amount': double.tryParse(amount.text.trim()) ?? 0,
        'classLevel': classLevel.text.trim(),
        'session': session.text.trim(),
        'term': term.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Draft fee submitted for approval.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }
}
