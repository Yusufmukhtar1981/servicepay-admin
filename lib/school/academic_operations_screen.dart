import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'edupay_school_api.dart';

class AcademicOperationsScreen extends StatefulWidget {
  const AcademicOperationsScreen({
    super.key,
    required this.api,
    this.initialSection,
    this.allowedSections,
    this.manager = true,
  });
  final EduPaySchoolApi api;
  final String? initialSection;
  final List<String>? allowedSections;
  final bool manager;
  @override
  State<AcademicOperationsScreen> createState() =>
      _AcademicOperationsScreenState();
}

class _AcademicOperationsScreenState extends State<AcademicOperationsScreen> {
  final allSections = const [
    'Dashboard',
    'Sessions & terms',
    'Classes & subjects',
    'Students',
    'Teachers',
    'Attendance',
    'Assessments',
    'Timetable',
    'Activities',
  ];
  String section = 'Dashboard';
  bool loading = true;
  String? error;
  Map<String, dynamic> data = {};
  List<Map<String, dynamic>> roster = [];
  final attendance = <String, String>{};
  String? attendanceClassId;

  @override
  void initState() {
    super.initState();
    section = widget.initialSection ?? 'Dashboard';
    if (widget.allowedSections != null &&
        !widget.allowedSections!.contains(section)) {
      section = widget.allowedSections!.first;
    }
    _load();
  }

  List<String> get sections => widget.allowedSections == null
      ? allSections
      : allSections.where(widget.allowedSections!.contains).toList();
  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      data = switch (section) {
        'Dashboard' => await widget.api.academicDashboard(),
        'Sessions & terms' ||
        'Classes & subjects' =>
          await widget.api.academicOverview(),
        'Students' => await _combined(
            widget.api.academicOverview(),
            widget.api.academicStudents(),
          ),
        'Teachers' => await _combined(
            widget.api.academicOverview(),
            widget.api.academicTeachers(),
          ),
        'Attendance' => await widget.api.academicOverview(),
        'Assessments' => await _combined(
            widget.api.academicOverview(),
            widget.api.assessments(),
          ),
        'Timetable' => await _combined(
            widget.api.academicOverview(),
            widget.api.timetable(),
          ),
        'Activities' => await _combinedActivities(),
        _ => data,
      };
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<Map<String, dynamic>> _combined(
    Future<Map<String, dynamic>> first,
    Future<Map<String, dynamic>> second,
  ) async {
    final values = await Future.wait<Map<String, dynamic>>([first, second]);
    return <String, dynamic>{...values[0], ...values[1]};
  }

  Future<Map<String, dynamic>> _combinedActivities() async {
    final values = await Future.wait<Map<String, dynamic>>([
      widget.api.academicOverview(),
      widget.api.academicStudents(),
      widget.api.activities(),
    ]);
    return <String, dynamic>{
      ...values[0],
      ...values[1],
      ...values[2],
    };
  }

  List<Map<String, dynamic>> _rows(String key) =>
      (data[key] is List ? data[key] as List : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  String _id(Map<String, dynamic> row) => '${row['_id'] ?? row['id']}';
  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sections
                  .map(
                    (s) => ChoiceChip(
                      label: Text(s),
                      selected: section == s,
                      onSelected: (_) {
                        setState(() => section = s);
                        _load();
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (loading)
          const LinearProgressIndicator()
        else if (error != null)
          _error()
        else
          _content(compact),
      ],
    );
  }

  Widget _error() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(error!),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
  Widget _content(bool compact) {
    if (section == 'Dashboard') return _dashboard();
    if (section == 'Attendance') return _attendance();
    if (section == 'Students') return _students();
    if (section == 'Assessments') return _assessments();
    final key = switch (section) {
      'Sessions & terms' => 'sessions',
      'Classes & subjects' => 'classes',
      'Teachers' => 'teachers',
      'Timetable' => 'timetable',
      _ => 'activities',
    };
    final rows = _rows(key);
    final action = widget.manager
        ? switch (section) {
            'Classes & subjects' => _createSubject,
            'Teachers' => _teacherActions,
            'Timetable' => _createTimetable,
            'Activities' => _createActivity,
            _ => null,
          }
        : section == 'Activities'
            ? _createActivity
            : null;
    return _table(rows, compact, title: section, action: action);
  }

  Widget _dashboard() {
    final summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: summary.entries
          .map(
            (e) => SizedBox(
              width: 190,
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
                      const SizedBox(height: 10),
                      Text(
                        '${e.value}',
                        style: const TextStyle(
                          fontSize: 25,
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
    );
  }

  Widget _students() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: widget.manager ? _createStudent : null,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add student'),
              ),
              OutlinedButton.icon(
                onPressed: widget.manager ? _bulkImport : null,
                icon: const Icon(Icons.upload_file),
                label: const Text('Validate bulk import'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._rows('students').map(
            (student) => Card(
              child: ListTile(
                title: Text('${student['fullName'] ?? 'Student'}'),
                subtitle: Text(
                  '${student['studentId'] ?? ''} · ${student['status'] ?? 'ACTIVE'}',
                ),
                trailing: widget.manager
                    ? IconButton(
                        tooltip: 'Edit student',
                        onPressed: () => _editStudent(student),
                        icon: const Icon(Icons.edit_outlined),
                      )
                    : null,
              ),
            ),
          ),
        ],
      );
  Widget _table(
    List<Map<String, dynamic>> rows,
    bool compact, {
    required String title,
    VoidCallback? action,
  }) {
    if (rows.isEmpty)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (action != null)
            FilledButton.icon(
              onPressed: action,
              icon: const Icon(Icons.add),
              label: Text(title == 'Teachers' ? 'Add Teacher' : 'Add $title'),
            ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No records are available yet.'),
            ),
          ),
        ],
      );
    final keys = rows.first.keys.take(compact ? 3 : 5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              onPressed: action,
              icon: const Icon(Icons.add),
              label: Text(title == 'Teachers' ? 'Add Teacher' : 'Add $title'),
            ),
          ),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                ...keys.map((k) => DataColumn(label: Text(k))),
                if (section == 'Teachers' && widget.manager)
                  const DataColumn(label: Text('Actions')),
              ],
              rows: rows
                  .map(
                    (r) => DataRow(
                      cells: [
                        ...keys.map((k) => DataCell(Text('${r[k] ?? ''}'))),
                        if (section == 'Teachers' && widget.manager)
                          DataCell(Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Edit teacher',
                                onPressed: () => _editTeacher(r),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Reset temporary password',
                                onPressed: () => _resetTeacherPassword(r),
                                icon: const Icon(Icons.lock_reset_outlined),
                              ),
                              IconButton(
                                tooltip: 'Change teacher status',
                                onPressed: () => _toggleTeacherStatus(r),
                                icon: const Icon(Icons.sync_alt_outlined),
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

  Widget _attendance() {
    final classes = _rows('classes');
    if (classes.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Create a class before recording attendance.'),
        ),
      );
    }
    attendanceClassId ??= _id(classes.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: attendanceClassId,
          decoration: const InputDecoration(labelText: 'Class'),
          items: classes
              .map(
                (row) => DropdownMenuItem(
                  value: _id(row),
                  child: Text('${row['name'] ?? 'Class'} ${row['arm'] ?? ''}'),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              attendanceClassId = value;
              roster = [];
              attendance.clear();
            });
          },
        ),
        const SizedBox(height: 12),
        FutureBuilder<Map<String, dynamic>>(
          future: _loadRoster(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done)
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              );
            if (roster.isEmpty)
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No active students found for this class.'),
                ),
              );
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Today’s attendance',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        FilledButton(
                          onPressed: () {
                            for (final s in roster)
                              attendance[_id(s)] = 'PRESENT';
                            setState(() {});
                          },
                          child: const Text('Mark all present'),
                        ),
                      ],
                    ),
                    ...roster.map(
                      (s) => ListTile(
                        title: Text('${s['fullName']}'),
                        subtitle: Text('${s['studentId'] ?? ''}'),
                        trailing: DropdownButton<String>(
                          value: attendance[_id(s)] ?? 'PRESENT',
                          items: ['PRESENT', 'ABSENT', 'LATE', 'EXCUSED']
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => attendance[_id(s)] = v!),
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: _saveAttendance,
                      child: const Text('Submit attendance'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<Map<String, dynamic>> _loadRoster() async {
    if (roster.isNotEmpty) return {};
    final classes = _rows('classes');
    if (classes.isEmpty) {
      try {
        data = await widget.api.academicOverview();
      } catch (_) {}
    }
    final rows = _rows('classes');
    if (rows.isEmpty || attendanceClassId == null) return {};
    try {
      final result = await widget.api.attendanceRoster(attendanceClassId!);
      roster = (result['students'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}
    return {};
  }

  Future<void> _saveAttendance() async {
    if (attendanceClassId == null ||
        _rows('sessions').isEmpty ||
        _rows('terms').isEmpty)
      return _notice('An active session, term and class are required.');
    try {
      await widget.api.submitAcademicAttendance({
        'classId': attendanceClassId,
        'session': _id(_rows('sessions').first),
        'term': _id(_rows('terms').first),
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'records': roster
            .map(
              (student) => {
                'student': _id(student),
                'status': attendance[_id(student)] ?? 'PRESENT',
              },
            )
            .toList(),
      });
      _notice('Attendance submitted.');
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Widget _assessments() {
    final rows = _rows('assessments');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.manager)
          FilledButton.icon(
            onPressed: _createAssessment,
            icon: const Icon(Icons.add),
            label: const Text('Create assessment'),
          ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No assessments are available yet.'),
            ),
          ),
        ...rows.map(
          (row) => Card(
            child: ListTile(
              title: Text('${row['title'] ?? 'Assessment'}'),
              subtitle: Text('${row['status'] ?? 'DRAFT'}'),
              trailing: Wrap(
                spacing: 6,
                children: [
                  if (['DRAFT', 'RETURNED']
                      .contains('${row['status']}'.toUpperCase()))
                    TextButton(
                      onPressed: () => _scoreAssessment(row),
                      child: const Text('Scores'),
                    ),
                  if ('${row['status']}' == 'SUBMITTED' && widget.manager)
                    TextButton(
                      onPressed: () => _review(row, 'RETURN'),
                      child: const Text('Return'),
                    ),
                  if ('${row['status']}' == 'SUBMITTED' && widget.manager)
                    FilledButton(
                      onPressed: () => _review(row, 'APPROVE'),
                      child: const Text('Approve'),
                    ),
                  if ('${row['status']}' == 'APPROVED' && widget.manager)
                    FilledButton(
                      onPressed: () => _review(row, 'PUBLISH'),
                      child: const Text('Publish'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createStudent() async {
    final studentId = TextEditingController(),
        name = TextEditingController(),
        parent = TextEditingController();
    String? classId =
        _rows('classes').isNotEmpty ? _id(_rows('classes').first) : null;
    final ok = await _form('Add student', [
      TextField(
        controller: studentId,
        decoration: const InputDecoration(labelText: 'Admission number'),
      ),
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Full name'),
      ),
      if (_rows('classes').isNotEmpty)
        DropdownButtonFormField<String>(
          value: classId,
          decoration: const InputDecoration(labelText: 'Class'),
          items: _rows('classes')
              .map(
                (row) => DropdownMenuItem(
                  value: _id(row),
                  child: Text('${row['name']} ${row['arm'] ?? ''}'),
                ),
              )
              .toList(),
          onChanged: (value) => classId = value,
        ),
      TextField(
        controller: parent,
        decoration: const InputDecoration(
          labelText: 'Linked parent user ID (optional)',
        ),
      ),
    ]);
    if (ok != true || studentId.text.trim().isEmpty || name.text.trim().isEmpty)
      return;
    try {
      await widget.api.createAcademicStudent({
        'studentId': studentId.text.trim(),
        'fullName': name.text.trim(),
        if (classId != null) 'classLevel': classId,
        if (parent.text.trim().isNotEmpty) 'parent': parent.text.trim(),
      });
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _bulkImport() async {
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final bytes = selected?.files.single.bytes;
    if (bytes == null) return;
    final content = utf8.decode(bytes, allowMalformed: false);
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final rows = <Map<String, dynamic>>[];
    for (var index = 0; index < lines.length; index++) {
      final values =
          lines[index].split(',').map((value) => value.trim()).toList();
      if (index == 0 && values.first.toLowerCase().contains('student'))
        continue;
      if (values.length < 2) continue;
      rows.add({
        'studentId': values[0],
        'fullName': values[1],
        if (values.length > 2) 'parentName': values[2],
        if (values.length > 3) 'parentPhone': values[3],
        if (values.length > 4) 'parentEmail': values[4],
      });
    }
    try {
      final validation = await widget.api.validateStudentImport(rows);
      if (validation['canCommit'] != true) {
        _notice(
          'Import blocked: ${(validation['invalidRows'] as List? ?? []).length} invalid and ${(validation['duplicates'] as List? ?? []).length} duplicate rows.',
        );
        return;
      }
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Commit student import?'),
          content: Text(
            '${(validation['validRows'] as List? ?? []).length} validated rows will be created.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await widget.api.commitStudentImport(rows);
        _notice('Students imported.');
        _load();
      }
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _editStudent(Map<String, dynamic> student) async {
    final name = TextEditingController(text: '${student['fullName'] ?? ''}');
    final parent = TextEditingController(
      text: _referenceId(student['parent']) == 'null'
          ? ''
          : _referenceId(student['parent']),
    );
    final classes = _rows('classes');
    String? classLevel = student['classLevel'] == null
        ? null
        : _referenceId(student['classLevel']);
    String status = '${student['status'] ?? 'ACTIVE'}';
    final ok = await _form('Edit student', [
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Full name'),
      ),
      if (classes.isNotEmpty)
        DropdownButtonFormField<String>(
          value:
              classes.any((row) => _id(row) == classLevel) ? classLevel : null,
          decoration: const InputDecoration(labelText: 'Class'),
          items: classes
              .map(
                (row) => DropdownMenuItem(
                  value: _id(row),
                  child: Text('${row['name']} ${row['arm'] ?? ''}'),
                ),
              )
              .toList(),
          onChanged: (value) => classLevel = value,
        ),
      DropdownButtonFormField<String>(
        value: status,
        decoration: const InputDecoration(labelText: 'Status'),
        items: ['ACTIVE', 'INACTIVE', 'TRANSFERRED', 'GRADUATED']
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
        onChanged: (value) => status = value!,
      ),
      TextField(
        controller: parent,
        decoration: const InputDecoration(labelText: 'Linked parent user ID'),
      ),
    ]);
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await widget.api.updateAcademicStudent(_id(student), {
        'fullName': name.text.trim(),
        'classLevel': classLevel,
        'status': status,
        'parent': parent.text.trim().isEmpty ? null : parent.text.trim(),
      });
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _createSubject() async {
    final name = TextEditingController(), code = TextEditingController();
    final ok = await _form('Create subject', [
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Subject name'),
      ),
      TextField(
        controller: code,
        decoration: const InputDecoration(labelText: 'Code (optional)'),
      ),
    ]);
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await widget.api.createSubject({
        'name': name.text.trim(),
        if (code.text.trim().isNotEmpty) 'code': code.text.trim(),
      });
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _teacherActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_1),
              title: const Text('Create teacher'),
              onTap: () => Navigator.pop(sheetContext, 'CREATE'),
            ),
            ListTile(
              leading: const Icon(Icons.assignment_ind_outlined),
              title: const Text('Assign class and subject'),
              onTap: () => Navigator.pop(sheetContext, 'ASSIGN'),
            ),
          ],
        ),
      ),
    );
    if (action == 'CREATE') await _createTeacher();
    if (action == 'ASSIGN') await _assignTeacher();
  }

  Future<void> _createTeacher() async {
    final user = TextEditingController(),
        staff = TextEditingController(),
        name = TextEditingController(),
        email = TextEditingController(),
        phone = TextEditingController(),
        responsibility = TextEditingController(),
        password = TextEditingController(),
        classIds = TextEditingController(),
        subjectIds = TextEditingController();
    String gender = '';
    final ok = await _form('Create teacher', [
      TextField(
        controller: user,
        decoration: const InputDecoration(
          labelText: 'Existing ServicePay user ID (optional)',
        ),
      ),
      TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Full name')),
      TextField(
          controller: email,
          decoration: const InputDecoration(labelText: 'Email')),
      TextField(
          controller: phone,
          decoration: const InputDecoration(labelText: 'Phone')),
      TextField(
        controller: staff,
        decoration: const InputDecoration(labelText: 'Staff ID'),
      ),
      DropdownButtonFormField<String>(
        decoration: const InputDecoration(labelText: 'Gender (optional)'),
        items: const ['FEMALE', 'MALE', 'OTHER']
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: (v) => gender = v ?? '',
      ),
      TextField(
          controller: responsibility,
          decoration: const InputDecoration(labelText: 'Responsibility')),
      TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Temporary password')),
      TextField(
          controller: classIds,
          decoration: const InputDecoration(
              labelText: 'Initial class IDs (comma separated)')),
      TextField(
          controller: subjectIds,
          decoration: const InputDecoration(
              labelText: 'Initial subject IDs (comma separated)')),
    ]);
    if (ok != true ||
        staff.text.trim().isEmpty ||
        (user.text.trim().isEmpty &&
            (name.text.trim().isEmpty || email.text.trim().isEmpty))) {
      _notice(
          'Enter staff ID and either an existing user ID or full account details.');
      return;
    }
    try {
      await widget.api.createTeacher({
        if (user.text.trim().isNotEmpty) 'userId': user.text.trim(),
        'staffId': staff.text.trim(),
        if (name.text.trim().isNotEmpty) 'fullName': name.text.trim(),
        if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
        if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim(),
        if (gender.isNotEmpty) 'gender': gender,
        if (responsibility.text.trim().isNotEmpty)
          'responsibility': responsibility.text.trim(),
        if (password.text.isNotEmpty) 'temporaryPassword': password.text,
        'classIds': classIds.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        'subjectIds': subjectIds.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      });
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _editTeacher(Map<String, dynamic> teacher) async {
    final id = _id(teacher);
    if (id == 'null') return;
    final name = TextEditingController(text: '${teacher['fullName'] ?? ''}');
    final email = TextEditingController(text: '${teacher['email'] ?? ''}');
    final phone = TextEditingController(text: '${teacher['phone'] ?? ''}');
    final staff = TextEditingController(text: '${teacher['staffId'] ?? ''}');
    final responsibility =
        TextEditingController(text: '${teacher['responsibility'] ?? ''}');
    final ok = await _form('Edit teacher', [
      TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Full name')),
      TextField(
          controller: email,
          decoration: const InputDecoration(labelText: 'Email')),
      TextField(
          controller: phone,
          decoration: const InputDecoration(labelText: 'Phone')),
      TextField(
          controller: staff,
          decoration: const InputDecoration(labelText: 'Staff ID')),
      TextField(
          controller: responsibility,
          decoration: const InputDecoration(labelText: 'Responsibility')),
    ]);
    if (ok != true) return;
    try {
      await widget.api.updateTeacher(id, {
        'fullName': name.text.trim(),
        'email': email.text.trim(),
        'phone': phone.text.trim(),
        'staffId': staff.text.trim(),
        'responsibility': responsibility.text.trim(),
      });
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _toggleTeacherStatus(Map<String, dynamic> teacher) async {
    final id = _id(teacher);
    final next = '${teacher['status'] ?? 'ACTIVE'}'.toUpperCase() == 'ACTIVE'
        ? 'INACTIVE'
        : 'ACTIVE';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('$next teacher'),
        content: Text('Change this teacher status to $next?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.updateTeacherStatus(id, next);
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _resetTeacherPassword(Map<String, dynamic> teacher) async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    final ok = await _form('Reset temporary password', [
      TextField(
          controller: password,
          obscureText: true,
          decoration:
              const InputDecoration(labelText: 'New temporary password')),
      TextField(
          controller: confirmation,
          obscureText: true,
          decoration:
              const InputDecoration(labelText: 'Confirm temporary password')),
    ]);
    if (ok != true ||
        password.text.length < 8 ||
        password.text != confirmation.text) {
      _notice('Passwords must match and contain at least 8 characters.');
      return;
    }
    try {
      await widget.api.resetTeacherPassword(_id(teacher), password.text);
      _notice('Temporary password reset. It is not displayed.');
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _assignTeacher() async {
    final teachers = _rows('teachers'),
        classes = _rows('classes'),
        subjects = _rows('subjects');
    if (teachers.isEmpty || classes.isEmpty || subjects.isEmpty) {
      _notice('Create a teacher, class and subject before assigning.');
      return;
    }
    String teacher = _id(teachers.first),
        classLevel = _id(classes.first),
        subject = _id(subjects.first);
    final ok = await _form('Assign teacher', [
      DropdownButtonFormField<String>(
        value: teacher,
        decoration: const InputDecoration(labelText: 'Teacher'),
        items: teachers
            .map(
              (row) => DropdownMenuItem(
                value: _id(row),
                child: Text('${row['fullName'] ?? row['staffId']}'),
              ),
            )
            .toList(),
        onChanged: (value) => teacher = value!,
      ),
      DropdownButtonFormField<String>(
        value: classLevel,
        decoration: const InputDecoration(labelText: 'Class'),
        items: classes
            .map(
              (row) => DropdownMenuItem(
                value: _id(row),
                child: Text('${row['name']} ${row['arm'] ?? ''}'),
              ),
            )
            .toList(),
        onChanged: (value) => classLevel = value!,
      ),
      DropdownButtonFormField<String>(
        value: subject,
        decoration: const InputDecoration(labelText: 'Subject'),
        items: subjects
            .map(
              (row) => DropdownMenuItem(
                value: _id(row),
                child: Text('${row['name']}'),
              ),
            )
            .toList(),
        onChanged: (value) => subject = value!,
      ),
    ]);
    if (ok != true) return;
    try {
      await widget.api.updateTeacherAssignments(teacher, {
        'classIds': [classLevel],
        'subjectIds': [subject],
      });
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _createAssessment() async {
    final sessions = _rows('sessions'),
        terms = _rows('terms'),
        classes = _rows('classes'),
        subjects = _rows('subjects');
    if (sessions.isEmpty ||
        terms.isEmpty ||
        classes.isEmpty ||
        subjects.isEmpty) {
      _notice('Create a session, term, class and subject first.');
      return;
    }
    final title = TextEditingController();
    String session = _id(sessions.first),
        term = _id(terms.first),
        classLevel = _id(classes.first),
        subject = _id(subjects.first);
    final ok = await _form('Create assessment', [
      TextField(
        controller: title,
        decoration: const InputDecoration(labelText: 'Assessment title'),
      ),
      DropdownButtonFormField<String>(
        value: session,
        decoration: const InputDecoration(labelText: 'Session'),
        items: sessions
            .map(
              (row) => DropdownMenuItem(
                value: _id(row),
                child: Text('${row['name']}'),
              ),
            )
            .toList(),
        onChanged: (value) => session = value!,
      ),
      DropdownButtonFormField<String>(
        value: term,
        decoration: const InputDecoration(labelText: 'Term'),
        items: terms
            .map(
              (row) => DropdownMenuItem(
                value: _id(row),
                child: Text('${row['name']}'),
              ),
            )
            .toList(),
        onChanged: (value) => term = value!,
      ),
      DropdownButtonFormField<String>(
        value: classLevel,
        decoration: const InputDecoration(labelText: 'Class'),
        items: classes
            .map(
              (row) => DropdownMenuItem(
                value: _id(row),
                child: Text('${row['name']} ${row['arm'] ?? ''}'),
              ),
            )
            .toList(),
        onChanged: (value) => classLevel = value!,
      ),
      DropdownButtonFormField<String>(
        value: subject,
        decoration: const InputDecoration(labelText: 'Subject'),
        items: subjects
            .map(
              (row) => DropdownMenuItem(
                value: _id(row),
                child: Text('${row['name']}'),
              ),
            )
            .toList(),
        onChanged: (value) => subject = value!,
      ),
      const Text(
        'Default scoring: CA 30 + Exam 70. Grading remains school-configurable through the API.',
      ),
    ]);
    if (ok != true || title.text.trim().isEmpty) return;
    try {
      await widget.api.createAssessment({
        'title': title.text.trim(),
        'session': session,
        'term': term,
        'classLevel': classLevel,
        'subject': subject,
        'components': [
          {'name': 'CA', 'max': 30},
          {'name': 'Exam', 'max': 70},
        ],
      });
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _referenceId(dynamic value) {
    if (value is Map) return '${value['_id'] ?? value['id']}';
    return '$value';
  }

  Future<void> _scoreAssessment(Map<String, dynamic> assessment) async {
    try {
      final rosterResult = await widget.api.attendanceRoster(
        _referenceId(assessment['classLevel']),
      );
      final students = (rosterResult['students'] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final components = (assessment['components'] as List? ??
              const [
                {'name': 'Total', 'max': 100},
              ])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (students.isEmpty)
        return _notice('No active students are assigned to this class.');
      final controllers = <String, TextEditingController>{};
      for (final student in students) {
        for (final component in components) {
          controllers['${_id(student)}:${component['name']}'] =
              TextEditingController();
        }
      }
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Scores · ${assessment['title']}'),
          content: SizedBox(
            width: 680,
            height: 500,
            child: ListView(
              children: students
                  .map(
                    (student) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${student['fullName']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Wrap(
                              spacing: 10,
                              children: components
                                  .map(
                                    (component) => SizedBox(
                                      width: 120,
                                      child: TextField(
                                        controller: controllers[
                                            '${_id(student)}:${component['name']}'],
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          labelText:
                                              '${component['name']} / ${component['max']}',
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, 'DRAFT'),
              child: const Text('Save draft'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'SUBMIT'),
              child: const Text('Submit scores'),
            ),
          ],
        ),
      );
      if (action == null) return;
      final scores = students
          .map(
            (student) => {
              'student': _id(student),
              'values': {
                for (final component in components)
                  '${component['name']}': double.tryParse(
                    controllers['${_id(student)}:${component['name']}']!
                        .text
                        .trim(),
                  ),
              },
            },
          )
          .toList();
      final invalidScores = scores
          .expand((row) => (row['values'] as Map).entries)
          .map((entry) => <String, dynamic>{
                'label': entry.key,
                'value': entry.value,
              })
          .where((entry) {
        final raw = entry['value'];
        if (raw is! num) return true;
        final component = components.firstWhere(
          (c) => '${c['name']}' == '${entry['label']}',
          orElse: () => <String, dynamic>{},
        );
        final max = num.tryParse(
          '${component['max'] ?? component['maxScore'] ?? ''}',
        );
        return raw < 0 || (max != null && raw > max);
      }).toList();
      if (invalidScores.isNotEmpty) {
        _notice(
          'Every score must be numeric and within its component maximum.',
        );
        return;
      }
      await widget.api.saveScores(_id(assessment), {
        'submit': action == 'SUBMIT',
        'scores': scores,
      });
      _notice(
        action == 'SUBMIT'
            ? 'Scores submitted for review.'
            : 'Draft scores saved.',
      );
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _review(Map<String, dynamic> assessment, String action) async {
    try {
      await widget.api.reviewAssessment(_id(assessment), action);
      _notice(
        action == 'PUBLISH'
            ? 'Results published to parents.'
            : 'Assessment updated.',
      );
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _createActivity() async {
    final title = TextEditingController(), body = TextEditingController();
    final classes = _rows('classes');
    final students = _rows('students');
    String audience = widget.manager ? 'SCHOOL' : 'CLASS';
    String? classLevel = classes.isEmpty ? null : _id(classes.first);
    String? student = students.isEmpty ? null : _id(students.first);
    if (!widget.manager && classes.isEmpty) {
      _notice('No assigned classes are available for an update.');
      return;
    }
    final activityFields = <Widget>[
      if (!widget.manager)
        DropdownButtonFormField<String>(
          value: audience,
          decoration: const InputDecoration(labelText: 'Audience'),
          items: const [
            DropdownMenuItem(value: 'CLASS', child: Text('Class')),
            DropdownMenuItem(value: 'STUDENT', child: Text('Student')),
          ],
          onChanged: (value) => audience = value ?? audience,
        ),
      if (!widget.manager)
        DropdownButtonFormField<String>(
          value: classLevel,
          decoration: const InputDecoration(labelText: 'Assigned class'),
          items: classes
              .map((row) => DropdownMenuItem(
                    value: _id(row),
                    child:
                        Text('${row['name'] ?? 'Class'} ${row['arm'] ?? ''}'),
                  ))
              .toList(),
          onChanged: (value) => classLevel = value,
        ),
      if (!widget.manager && students.isNotEmpty)
        DropdownButtonFormField<String>(
          value: student,
          decoration: const InputDecoration(labelText: 'Assigned student'),
          items: students
              .map((row) => DropdownMenuItem(
                    value: _id(row),
                    child: Text('${row['fullName'] ?? 'Student'}'),
                  ))
              .toList(),
          onChanged: (value) => student = value,
        ),
      TextField(
        controller: title,
        decoration: const InputDecoration(labelText: 'Title'),
      ),
      TextField(
        controller: body,
        minLines: 4,
        maxLines: 8,
        decoration: const InputDecoration(labelText: 'Message'),
      ),
    ];
    final ok = await _form('Publish school update', activityFields);
    if (ok != true || title.text.trim().isEmpty || body.text.trim().isEmpty)
      return;
    if (!widget.manager &&
        (classLevel == null || (audience == 'STUDENT' && student == null))) {
      _notice('Select an assigned class and student for this update.');
      return;
    }
    try {
      await widget.api.createActivity({
        'type': 'ANNOUNCEMENT',
        'title': title.text.trim(),
        'body': body.text.trim(),
        'audience': audience,
        if (!widget.manager) 'classLevel': classLevel,
        if (!widget.manager && audience == 'STUDENT') 'student': student,
        'status': 'PUBLISHED',
      });
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _createTimetable() async {
    final sessions = _rows('sessions'),
        terms = _rows('terms'),
        classes = _rows('classes'),
        subjects = _rows('subjects'),
        teachers = _rows('teachers');
    if (sessions.isEmpty ||
        terms.isEmpty ||
        classes.isEmpty ||
        subjects.isEmpty ||
        teachers.isEmpty) {
      _notice('Create a session, term, class, subject and teacher first.');
      return;
    }
    final period = TextEditingController(),
        starts = TextEditingController(),
        ends = TextEditingController();
    String session = _id(sessions.first),
        term = _id(terms.first),
        classLevel = _id(classes.first),
        subject = _id(subjects.first),
        teacher = _id(teachers.first),
        day = 'MONDAY';
    final ok = await _form('Add timetable period', [
      DropdownButtonFormField<String>(
        value: day,
        decoration: const InputDecoration(labelText: 'Day'),
        items:
            ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY']
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
        onChanged: (value) => day = value!,
      ),
      DropdownButtonFormField<String>(
        value: classLevel,
        decoration: const InputDecoration(labelText: 'Class'),
        items: classes
            .map(
              (row) => DropdownMenuItem(
                value: _id(row),
                child: Text('${row['name']} ${row['arm'] ?? ''}'),
              ),
            )
            .toList(),
        onChanged: (value) => classLevel = value!,
      ),
      DropdownButtonFormField<String>(
        value: subject,
        decoration: const InputDecoration(labelText: 'Subject'),
        items: subjects
            .map(
              (row) => DropdownMenuItem(
                value: _id(row),
                child: Text('${row['name']}'),
              ),
            )
            .toList(),
        onChanged: (value) => subject = value!,
      ),
      DropdownButtonFormField<String>(
        value: teacher,
        decoration: const InputDecoration(labelText: 'Teacher'),
        items: teachers
            .map(
              (row) => DropdownMenuItem(
                value: _id(row),
                child: Text('${row['fullName'] ?? row['staffId']}'),
              ),
            )
            .toList(),
        onChanged: (value) => teacher = value!,
      ),
      TextField(
        controller: period,
        decoration: const InputDecoration(labelText: 'Period'),
      ),
      TextField(
        controller: starts,
        decoration: const InputDecoration(labelText: 'Start time (08:00)'),
      ),
      TextField(
        controller: ends,
        decoration: const InputDecoration(labelText: 'End time (08:40)'),
      ),
    ]);
    if (ok != true) return;
    try {
      await widget.api.createTimetable({
        'session': session,
        'term': term,
        'classLevel': classLevel,
        'subject': subject,
        'teacher': teacher,
        'day': day,
        'period': period.text.trim(),
        'startsAt': starts.text.trim(),
        'endsAt': ends.text.trim(),
      });
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<bool?> _form(String title, List<Widget> fields) => showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: fields),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );
}
