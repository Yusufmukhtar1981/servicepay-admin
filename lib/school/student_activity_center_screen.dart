import 'package:flutter/material.dart';
import 'edupay_school_api.dart';

/// School-side Student Activity Center.  The backend remains the source of
/// truth for role permissions, publication state, and school tenancy.
class StudentActivityCenterScreen extends StatefulWidget {
  const StudentActivityCenterScreen({
    super.key,
    required this.api,
    this.onOpenStudents,
    this.initialSection = 'Overview',
  });
  final EduPaySchoolApi api;
  final VoidCallback? onOpenStudents;
  final String initialSection;

  @override
  State<StudentActivityCenterScreen> createState() =>
      _StudentActivityCenterScreenState();
}

class _StudentActivityCenterScreenState
    extends State<StudentActivityCenterScreen> {
  static const sections = <String>[
    'Overview',
    'Student Management',
    'Attendance',
    'Results',
    'Assignments',
    'Activities',
    'Announcements',
    'Parents/Guardians',
    'Conduct/Achievements',
    'Reports',
  ];
  String section = 'Overview';
  bool loading = true;
  String? error;
  Map<String, dynamic> response = {};

  EduPaySchoolApi get api => widget.api;

  @override
  void initState() {
    super.initState();
    section =
        sections.contains(widget.initialSection) ? widget.initialSection : 'Overview';
    _load();
  }

  String? get resource => switch (section) {
        'Overview' => 'dashboard',
        'Attendance' => 'attendance',
        'Results' => 'results',
        'Assignments' => 'assignments',
        'Activities' => 'activities',
        'Announcements' => 'announcements',
        'Conduct/Achievements' => 'conduct',
        'Reports' => 'reports',
        _ => null,
      };

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    if (resource == null) {
      response = {};
      if (mounted) setState(() => loading = false);
      return;
    }
    try {
      response = await api.activityCenter(resource!);
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => loading = false);
  }

  List<Map<String, dynamic>> get rows {
    final body = response['data'] is Map
        ? Map<String, dynamic>.from(response['data'] as Map)
        : response;
    final value =
        body[resource] ?? body['records'] ?? body['items'] ?? body['data'];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  void _select(String value) {
    setState(() => section = value);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sections
                  .map(
                    (item) => ChoiceChip(
                      label: Text(item),
                      selected: item == section,
                      onSelected: (_) => _select(item),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            ),
          )
        else if (error != null)
          _error()
        else ...[
          if (section == 'Overview') _overview(compact),
          if (section != 'Overview') _records(compact),
        ],
      ],
    );
  }

  Widget _error() => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(error!),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );

  Widget _overview(bool compact) {
    final body = response['data'] is Map
        ? Map<String, dynamic>.from(response['data'] as Map)
        : response;
    final summary = (body['summary'] as Map?)?.cast<String, dynamic>() ?? body;
    final cards = summary.entries
        .where((e) => e.value is num || e.value is String || e.value is bool)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Keep families informed with verified school updates.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .take(8)
              .map(
                (entry) => SizedBox(
                  width: compact ? 150 : 205,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_label(entry.key)),
                          const SizedBox(height: 10),
                          Text(
                            '${entry.value}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        _timeline(),
      ],
    );
  }

  Widget _timeline() {
    final body = response['data'] is Map
        ? Map<String, dynamic>.from(response['data'] as Map)
        : response;
    final timeline =
        (body['timeline'] as List?)?.whereType<Map>().toList() ?? const [];
    if (timeline.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Recent student updates will appear here.'),
        ),
      );
    }
    return Card(
      child: Column(
        children: timeline.take(10).map((item) {
          final row = Map<String, dynamic>.from(item);
          return ListTile(
            leading: const Icon(Icons.timeline),
            title: Text('${row['title'] ?? row['type'] ?? 'Student update'}'),
            subtitle: Text('${row['createdAt'] ?? row['date'] ?? ''}'),
            trailing: Text('${row['studentName'] ?? ''}'),
          );
        }).toList(),
      ),
    );
  }

  Widget _records(bool compact) {
    if (section == 'Student Management') {
      return _studentManagement();
    }
    if (section == 'Parents/Guardians') {
      return _guardianManagement();
    }
    final canCreate = section != 'Reports' && section != 'Parents/Guardians';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (canCreate)
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: Text(_createLabel),
              ),
            if (section == 'Attendance')
              OutlinedButton.icon(
                onPressed: _bulkAttendance,
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('Bulk attendance'),
              ),
            if (section == 'Reports')
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Refresh reports'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No records are available yet.'),
            ),
          )
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  ...rows.first.keys
                      .take(compact ? 3 : 5)
                      .map((key) => DataColumn(label: Text(_label(key)))),
                  if (_canEdit) const DataColumn(label: Text('Actions')),
                ],
                rows: rows
                    .map(
                      (row) => DataRow(
                        cells: [
                          ...row.entries.take(compact ? 3 : 5).map((entry) =>
                              DataCell(_cell(entry.key, entry.value))),
                          if (_canEdit)
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit record',
                                  onPressed: () => _editRecord(row),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                if (section == 'Results' && !_isPublished(row))
                                  IconButton(
                                    tooltip: 'Publish result',
                                    onPressed: () => _publish(row),
                                    icon: const Icon(Icons.publish_outlined),
                                  ),
                              ],
                            )),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _studentManagement() => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Student records use the existing Students workflow.',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Create or update students there, then use this '
                  'center for attendance, results, assignments, and updates.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: widget.onOpenStudents,
                icon: const Icon(Icons.groups_outlined),
                label: const Text('Open Students'),
              ),
            ],
          ),
        ),
      );

  Widget _guardianManagement() => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Invite a verified parent or guardian',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Guardian lists are not exposed by this contract. '
                  'Create an invite using an existing child ID.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _createGuardianInvite,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Create guardian invite'),
              ),
            ],
          ),
        ),
      );

  bool get _canEdit =>
      section != 'Reports' &&
      section != 'Student Management' &&
      section != 'Parents/Guardians';

  bool _isPublished(Map<String, dynamic> row) {
    final status =
        '${row['status'] ?? row['publicationStatus'] ?? ''}'.toUpperCase();
    return row['published'] == true ||
        {'PUBLISHED', 'PUBLIC', 'LIVE'}.contains(status);
  }

  Widget _cell(String key, Object? value) {
    if (key.toLowerCase().contains('status') ||
        key.toLowerCase() == 'published') {
      final published = value == true ||
          {'PUBLISHED', 'PUBLIC', 'LIVE'}.contains('$value'.toUpperCase());
      return Chip(
        label: Text(published ? 'Published' : '${value ?? 'Draft'}'),
        visualDensity: VisualDensity.compact,
        backgroundColor:
            published ? Colors.green.shade50 : Colors.orange.shade50,
      );
    }
    return Text(_display(value));
  }

  String? _recordId(Map<String, dynamic> row) =>
      (row['recordId'] ?? row['_id'] ?? row['id'])?.toString();

  Future<void> _editRecord(Map<String, dynamic> row) async {
    final id = _recordId(row);
    if (id == null || id.isEmpty) return;
    final editable = row.entries
        .where((entry) =>
            entry.value is String || entry.value is num || entry.value is bool)
        .where((entry) => !{
              'id',
              '_id',
              'recordId',
              'createdAt',
              'updatedAt',
              'createdBy',
              'updatedBy',
              'schoolId',
              'studentId',
            }.contains(entry.key))
        .take(5);
    final fields = <String, TextEditingController>{
      for (final entry in editable)
        entry.key: TextEditingController(text: '${entry.value}'),
    };
    if (fields.isEmpty) return;
    final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Edit record'),
              content: SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                children: fields.entries
                    .map((entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                              controller: entry.value,
                              decoration: InputDecoration(
                                  labelText: _label(entry.key))),
                        ))
                    .toList(),
              )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Save')),
              ],
            ));
    if (ok != true) return;
    try {
      await api.updateActivity(
          id, fields.map((key, value) => MapEntry(key, value.text.trim())));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Record updated.')));
      _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _publish(Map<String, dynamic> row) async {
    final id = _recordId(row);
    if (id == null || id.isEmpty) return;
    try {
      await api.publishResult(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Result published.')));
      _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _createGuardianInvite() async {
    final childId = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Create guardian invite'),
              content: TextField(
                  controller: childId,
                  decoration:
                      const InputDecoration(labelText: 'Existing child ID')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Create invite')),
              ],
            ));
    if (ok != true || childId.text.trim().isEmpty) return;
    try {
      final result = await api.createGuardianInvite(childId.text.trim());
      final body = result['data'] is Map
          ? Map<String, dynamic>.from(result['data'] as Map)
          : result;
      final code = body['code'] ??
          body['inviteCode'] ??
          (body['invite'] is Map ? body['invite']['code'] : null);
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: const Text('Guardian invite created'),
                content: Text(code == null
                    ? 'The invite was created. The server did not return a one-time '
                        'code; ask the guardian to use the approved link.'
                    : 'One-time invite code:\n\n$code\n\nShare this code securely '
                        'with the intended guardian only. It will not be shown again '
                        'after closing this dialog.'),
                actions: [
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Done'))
                ],
              ));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  String get _createLabel => switch (section) {
        'Student Management' => 'Add student',
        'Attendance' => 'Record attendance',
        'Results' => 'Enter result draft',
        'Assignments' => 'Post assignment',
        'Activities' => 'Post activity',
        'Announcements' => 'Send announcement',
        'Conduct/Achievements' => 'Record conduct',
        _ => 'Create',
      };

  Future<void> _create() async {
    final fields = <String, TextEditingController>{
      if (section == 'Student Management') ...{
        'fullName': TextEditingController(),
        'admissionNumber': TextEditingController(),
        'className': TextEditingController(),
      },
      if (section == 'Attendance') ...{
        'studentId': TextEditingController(),
        'status': TextEditingController(text: 'Present'),
        'note': TextEditingController(),
      },
      if (section == 'Results') ...{
        'studentId': TextEditingController(),
        'subject': TextEditingController(),
        'ca': TextEditingController(),
        'exam': TextEditingController(),
      },
      if (section == 'Assignments') ...{
        'title': TextEditingController(),
        'subject': TextEditingController(),
        'description': TextEditingController(),
        'dueDate': TextEditingController(),
      },
      if (section == 'Activities') ...{
        'title': TextEditingController(),
        'category': TextEditingController(text: 'Class activity'),
        'description': TextEditingController(),
        'date': TextEditingController(),
      },
      if (section == 'Announcements') ...{
        'title': TextEditingController(),
        'message': TextEditingController(),
        'audience': TextEditingController(text: 'school'),
      },
      if (section == 'Conduct/Achievements') ...{
        'studentId': TextEditingController(),
        'type': TextEditingController(text: 'Achievement'),
        'note': TextEditingController(),
        'parentVisible': TextEditingController(text: 'false'),
      },
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_createLabel),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: fields.entries
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: entry.value,
                        maxLines: entry.key == 'description' ||
                                entry.key == 'message' ||
                                entry.key == 'note'
                            ? 3
                            : 1,
                        decoration: InputDecoration(
                          labelText: _label(entry.key),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.activityAction(
        resource!,
        fields.map((key, value) => MapEntry(key, value.text.trim())),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$section record saved.')));
      _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
    }
  }

  Future<void> _bulkAttendance() async {
    final body = <String, dynamic>{};
    final date = TextEditingController();
    final status = TextEditingController(text: 'Present');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bulk attendance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: date,
              decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
            ),
            TextField(
              controller: status,
              decoration: const InputDecoration(
                labelText: 'Status: Present, Absent, Late, Excused',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    body['date'] = date.text.trim();
    body['status'] = status.text.trim();
    body['classId'] = ''; // backend resolves/validates class scope.
    try {
      await api.bulkAttendance(body);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Attendance submitted.')));
        _load();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
    }
  }

  String _label(String value) => value
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}')
      .replaceFirst('_', ' ')
      .trim()
      .split(' ')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  String _display(Object? value) {
    if (value is Map) return '${value['name'] ?? value['_id'] ?? ''}';
    if (value is List) return '${value.length} items';
    return '$value';
  }
}
