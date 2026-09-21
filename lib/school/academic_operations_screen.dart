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
    this.teacher = false,
  });
  final EduPaySchoolApi api;
  final String? initialSection;
  final List<String>? allowedSections;
  final bool manager;
  final bool teacher;
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
  List<AcademicStudentLink> studentLinks = [];
  Map<String, dynamic> studentLinksSummary = {};
  String? studentLinksError;
  bool studentLinksLoading = false;
  List<Map<String, dynamic>> roster = [];
  final attendance = <String, String>{};
  String? attendanceClassId;
  String catalogLevel = 'All levels';
  String classQuery = '';
  String subjectQuery = '';
  final selectedCatalogClasses = <String>{};
  final selectedCatalogSubjects = <String>{};
  static const _classCatalog = <String, List<String>>{
    'Early Years': [
      'Creche',
      'Playgroup',
      'Pre-Nursery',
      'Nursery 1',
      'Nursery 2',
      'Nursery 3',
      'Kindergarten 1',
      'Kindergarten 2',
      'Reception',
    ],
    'Primary': [
      'Primary 1',
      'Primary 2',
      'Primary 3',
      'Primary 4',
      'Primary 5',
      'Primary 6',
    ],
    'Junior Secondary': ['JSS 1', 'JSS 2', 'JSS 3'],
    'Senior Secondary': ['SSS 1', 'SSS 2', 'SSS 3'],
  };
  static const _subjectCatalog = <String, List<String>>{
    'Early Years': [
      'English Language',
      'Mathematics',
      'Literacy',
      'Numeracy',
      'Phonics',
      'Handwriting',
      'Rhymes',
      'Reading',
      'Basic Science',
      'Social Habits',
      'Health Habits',
      'Creative Arts',
      'Physical Education',
      'Computer Studies',
      'Religious Studies',
    ],
    'Primary': [
      'English Language',
      'Mathematics',
      'Basic Science',
      'Basic Technology',
      'Basic Science and Technology',
      'Social Studies',
      'Civic Education',
      'National Values',
      'Computer Studies / ICT',
      'Agricultural Science',
      'Home Economics',
      'Physical and Health Education',
      'Cultural and Creative Arts',
      'Christian Religious Studies',
      'Islamic Religious Studies',
      'Hausa',
      'Yoruba',
      'Igbo',
      'French',
      'Arabic',
      'History',
      'Security Education',
    ],
    'Junior Secondary': [
      'English Studies',
      'Mathematics',
      'Basic Science',
      'Basic Technology',
      'Social Studies',
      'Civic Education',
      'Business Studies',
      'Agricultural Science',
      'Home Economics',
      'Computer Studies / ICT',
      'Physical and Health Education',
      'Cultural and Creative Arts',
      'Christian Religious Studies',
      'Islamic Religious Studies',
      'Hausa',
      'Yoruba',
      'Igbo',
      'French',
      'Arabic',
      'History',
    ],
    'Senior Secondary': [
      'English Language',
      'General Mathematics',
      'Further Mathematics',
      'Biology',
      'Chemistry',
      'Physics',
      'Agricultural Science',
      'Geography',
      'Economics',
      'Government',
      'Civic Education',
      'Commerce',
      'Financial Accounting',
      'Literature in English',
      'Computer Studies',
      'Data Processing',
      'Information and Communication Technology',
      'Christian Religious Studies',
      'Islamic Studies',
      'Hausa',
      'Yoruba',
      'Igbo',
      'French',
      'Arabic',
      'History',
      'Visual Art',
      'Music',
      'Technical Drawing',
      'Food and Nutrition',
      'Home Management',
      'Marketing',
      'Office Practice',
      'Insurance',
      'Tourism',
      'Fisheries',
      'Animal Husbandry',
    ],
  };

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
        'Classes & subjects' => await widget.api.academicOverview(),
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
      if (section == 'Students' && widget.manager) {
        await _loadStudentLinks();
      }
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadStudentLinks() async {
    if (!widget.manager) return;
    if (mounted) {
      setState(() {
        studentLinksLoading = true;
        studentLinksError = null;
      });
    }
    try {
      final result = await widget.api.academicStudentLinks();
      studentLinks = result.links;
      studentLinksSummary = result.summary;
    } catch (e) {
      studentLinksError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => studentLinksLoading = false);
    }
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
    return <String, dynamic>{...values[0], ...values[1], ...values[2]};
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
    if (section == 'Teachers') return _teachers(compact);
    if (section == 'Assessments') return _assessments();
    if (section == 'Classes & subjects') return _classesSubjects(compact);
    final key = switch (section) {
      'Sessions & terms' => 'sessions',
      'Classes & subjects' => 'classes',
      'Timetable' => 'timetable',
      _ => 'activities',
    };
    final rows = _rows(key);
    final action = widget.manager
        ? switch (section) {
            'Classes & subjects' => _createSubject,
            'Timetable' => _createTimetable,
            'Activities' => _createActivity,
            _ => null,
          }
        : section == 'Activities'
        ? _createActivity
        : null;
    return _friendlyAcademicTable(
      rows,
      compact,
      title: section,
      action: action,
    );
  }

  Widget _friendlyAcademicTable(
    List<Map<String, dynamic>> rows,
    bool compact, {
    required String title,
    VoidCallback? action,
  }) {
    final columns = switch (title) {
      'Sessions & terms' => const ['Name', 'Status', 'Starts', 'Ends'],
      'Timetable' => const [
        'Day',
        'Period',
        'Class',
        'Subject',
        'Teacher',
        'Starts',
        'Ends',
      ],
      'Activities' => const ['Title', 'Audience', 'Status', 'Published'],
      _ => const ['Name', 'Status'],
    };
    String value(Map<String, dynamic> row, String column) {
      dynamic raw = switch (column) {
        'Name' => row['name'],
        'Status' => row['status'],
        'Starts' => row['startsAt'] ?? row['startDate'],
        'Ends' => row['endsAt'] ?? row['endDate'],
        'Day' => row['day'],
        'Period' => row['period'],
        'Class' => row['classLevel'],
        'Subject' => row['subject'],
        'Teacher' => row['teacher'],
        'Title' => row['title'],
        'Audience' => row['audience'],
        'Published' => row['publishedAt'],
        _ => null,
      };
      if (raw is Map) {
        raw = raw['name'] ?? raw['fullName'] ?? raw['title'];
      }
      return raw?.toString() ?? '—';
    }

    if (rows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (action != null)
            FilledButton.icon(
              onPressed: action,
              icon: const Icon(Icons.add),
              label: Text('Add $title'),
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
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              onPressed: action,
              icon: const Icon(Icons.add),
              label: Text('Add $title'),
            ),
          ),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: columns
                  .map((column) => DataColumn(label: Text(column)))
                  .toList(),
              rows: rows
                  .map(
                    (row) => DataRow(
                      cells: columns
                          .map((column) => DataCell(Text(value(row, column))))
                          .toList(),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  String _displayClass(Map<String, dynamic> row) =>
      '${row['name'] ?? 'Class'}${('${row['arm'] ?? ''}').trim().isEmpty ? '' : ' • ${row['arm']}'}';

  List<Map<String, dynamic>> _catalogRows(
    Map<String, List<String>> catalog,
    String level, {
    String query = '',
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final rows = catalog.entries
        .where(
          (entry) => catalogLevel == 'All levels' || entry.key == catalogLevel,
        )
        .expand(
          (entry) => entry.value.map(
            (name) => {
              'name': name,
              'level': entry.key,
              'key': '${entry.key}:$name',
            },
          ),
        )
        .where(
          (row) =>
              normalizedQuery.isEmpty ||
              '${row['name']} ${row['level']}'.toLowerCase().contains(
                normalizedQuery,
              ),
        )
        .toList();
    final isClassCatalog = identical(catalog, _classCatalog);
    final existing = _rows(isClassCatalog ? 'classes' : 'subjects')
        .map(
          (row) => {
            'name': '${row['name'] ?? ''}',
            'level': 'Already added',
            'key':
                'existing:${isClassCatalog ? _classCanonical(row) : _canonical(row['name'])}',
            'existing': true,
          },
        )
        .where(
          (row) => '${row['name']} ${row['level']}'.toLowerCase().contains(
            normalizedQuery,
          ),
        )
        .toList();
    return [...rows, ...existing];
  }

  String _canonical(dynamic value) =>
      '$value'.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  String _classCanonical(Map<String, dynamic> row) =>
      '${_canonical(row['name'])}|${_canonical(row['arm'] ?? '')}';

  Widget _catalogSection({
    required String title,
    required Map<String, List<String>> catalog,
    required Set<String> selected,
    required String actionLabel,
    required VoidCallback action,
    required String query,
    required VoidCallback addNew,
  }) {
    final rows = _catalogRows(catalog, '', query: query);
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      grouped.putIfAbsent('${row['level']}', () => []).add(row);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: rows.isEmpty
                      ? null
                      : () => setState(() {
                          final keys = rows.map((r) => '${r['key']}');
                          if (keys.every(selected.contains)) {
                            selected.removeAll(keys);
                          } else {
                            selected.addAll(keys);
                          }
                        }),
                  child: const Text('Select all'),
                ),
              ],
            ),
            const Divider(height: 12),
            if (rows.isEmpty)
              const Text('No catalogue items match your search.'),
            if (rows.isEmpty && query.trim().isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: addNew,
                  icon: const Icon(Icons.add),
                  label: Text(
                    '${title.startsWith('Class') ? 'Add New Class' : 'Add New Subject'} “${query.trim()}”',
                  ),
                ),
              ),
            ...grouped.entries.map(
              (group) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      group.key,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ...group.value.map(
                    (row) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains('${row['key']}'),
                      title: Row(
                        children: [
                          Expanded(child: Text('${row['name']}')),
                          if (row['existing'] == true)
                            const Text(
                              'Already added',
                              style: TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                      onChanged: row['existing'] == true
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                selected.add('${row['key']}');
                              } else {
                                selected.remove('${row['key']}');
                              }
                            }),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: selected.isEmpty ? null : action,
                icon: const Icon(Icons.add),
                label: Text('$actionLabel (${selected.length})'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _classesSubjects(bool compact) {
    final classes = _rows('classes');
    final subjects = _rows('subjects');
    if (!widget.manager) {
      if (classes.isEmpty && subjects.isEmpty) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'No classes or subjects have been assigned to your teacher account yet. '
              'Please contact the School Administrator.',
            ),
          ),
        );
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your assigned academic work',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...classes.map(
                    (row) => Chip(
                      avatar: const Icon(Icons.class_outlined, size: 17),
                      label: Text(_displayClass(row)),
                    ),
                  ),
                  ...subjects.map(
                    (row) => Chip(
                      avatar: const Icon(Icons.menu_book_outlined, size: 17),
                      label: Text('${row['name'] ?? 'Subject'}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    final levels = [
      'All levels',
      ..._classCatalog.keys,
      ..._subjectCatalog.keys,
    ].toSet().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: compact ? double.infinity : 300,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search classes',
                  hintText: 'Try “JSS 1” or “Primary”',
                ),
                onChanged: (value) => setState(() => classQuery = value),
              ),
            ),
            SizedBox(
              width: compact ? double.infinity : 300,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search subjects',
                  hintText: 'Try “Mathematics” or “Biology”',
                ),
                onChanged: (value) => setState(() => subjectQuery = value),
              ),
            ),
            SizedBox(
              width: compact ? double.infinity : 190,
              child: DropdownButtonFormField<String>(
                value: catalogLevel,
                decoration: const InputDecoration(labelText: 'School level'),
                items: levels
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => catalogLevel = v ?? 'All levels'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (classes.isNotEmpty || subjects.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Already in your school',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...classes.map(
                        (c) => Chip(
                          avatar: const Icon(Icons.class_outlined, size: 17),
                          label: Text(_displayClass(c)),
                        ),
                      ),
                      ...subjects.map(
                        (s) => Chip(
                          avatar: const Icon(
                            Icons.menu_book_outlined,
                            size: 17,
                          ),
                          label: Text('${s['name'] ?? 'Subject'}'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (compact)
          Column(
            children: [
              _catalogSection(
                title: 'Class catalogue',
                catalog: _classCatalog,
                selected: selectedCatalogClasses,
                actionLabel: 'Add classes',
                action: _addCatalogClasses,
                query: classQuery,
                addNew: () => _createCustomClass(initialName: classQuery),
              ),
              const SizedBox(height: 12),
              _catalogSection(
                title: 'Subject catalogue',
                catalog: _subjectCatalog,
                selected: selectedCatalogSubjects,
                actionLabel: 'Add subjects',
                action: _addCatalogSubjects,
                query: subjectQuery,
                addNew: () => _createSubject(initialName: subjectQuery),
              ),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _catalogSection(
                  title: 'Class catalogue',
                  catalog: _classCatalog,
                  selected: selectedCatalogClasses,
                  actionLabel: 'Add classes',
                  action: _addCatalogClasses,
                  query: classQuery,
                  addNew: () => _createCustomClass(initialName: classQuery),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _catalogSection(
                  title: 'Subject catalogue',
                  catalog: _subjectCatalog,
                  selected: selectedCatalogSubjects,
                  actionLabel: 'Add subjects',
                  action: _addCatalogSubjects,
                  query: subjectQuery,
                  addNew: () => _createSubject(initialName: subjectQuery),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        _mappingCard(classes, subjects),
      ],
    );
  }

  Future<void> _addCatalogClasses() async {
    final session = await _ensureAcademicSession();
    if (session == null) return;
    final rows = _catalogRows(
      _classCatalog,
      '',
    ).where((row) => selectedCatalogClasses.contains('${row['key']}')).toList();
    final existing = _rows('classes').map(_classCanonical).toSet();
    final unique = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final key = '${_canonical(row['name'])}|';
      if (!existing.contains(key)) unique[key] = row;
    }
    if (unique.isEmpty) {
      selectedCatalogClasses.clear();
      return _notice('All selected classes are already added to your school.');
    }
    try {
      await widget.api.createAcademicClassesBatch(
        session: session,
        classes: unique.values
            .map((row) => {'name': row['name'], 'educationLevel': row['level']})
            .toList(),
      );
      selectedCatalogClasses.clear();
      _notice(
        unique.length == 1
            ? 'Class added successfully.'
            : '${unique.length} classes added successfully.',
      );
      await _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _addCatalogSubjects() async {
    final rows = _catalogRows(_subjectCatalog, '')
        .where((row) => selectedCatalogSubjects.contains('${row['key']}'))
        .toList();
    final existing = _rows(
      'subjects',
    ).map((row) => _canonical(row['name'])).toSet();
    final unique = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final key = _canonical(row['name']);
      if (!existing.contains(key)) unique[key] = row;
    }
    if (unique.isEmpty) {
      selectedCatalogSubjects.clear();
      return _notice('All selected subjects are already added to your school.');
    }
    try {
      await widget.api.createAcademicSubjectsBatch(
        unique.values
            .map((row) => {'name': row['name'], 'educationLevel': row['level']})
            .toList(),
      );
      selectedCatalogSubjects.clear();
      _notice(
        unique.length == 1
            ? 'Subject added successfully.'
            : '${unique.length} subjects added successfully.',
      );
      await _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _createCustomClass({String? initialName}) async {
    final name = TextEditingController(text: initialName?.trim());
    final arm = TextEditingController();
    String level = 'Primary';
    final ok = await _form('Create custom class', [
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Class name *'),
      ),
      TextField(
        controller: arm,
        decoration: const InputDecoration(
          labelText: 'Class arm (optional)',
          hintText: 'A, B or Gold',
        ),
      ),
      DropdownButtonFormField<String>(
        value: level,
        decoration: const InputDecoration(labelText: 'Education level'),
        items: const [
          'Early years',
          'Primary',
          'Junior Secondary',
          'Senior Secondary',
        ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => level = v ?? level,
      ),
    ], submitLabel: 'Create class');
    if (ok != true || name.text.trim().isEmpty) return;
    final session = await _ensureAcademicSession();
    if (session == null) return;
    try {
      await widget.api.createAcademicClassesBatch(
        session: session,
        classes: [
          {
            'name': name.text.trim(),
            if (arm.text.trim().isNotEmpty) 'arm': arm.text.trim(),
            'educationLevel': level,
          },
        ],
      );
      _notice('Class added successfully.');
      await _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _currentSchoolYear() {
    final now = DateTime.now();
    final start = now.month >= 8 ? now.year : now.year - 1;
    return '$start/${start + 1}';
  }

  Future<String?> _ensureAcademicSession() async {
    final active = _rows('sessions')
        .where(
          (row) => '${row['status'] ?? 'ACTIVE'}'.toUpperCase() == 'ACTIVE',
        )
        .toList();
    if (active.isNotEmpty) {
      final sessionId = _id(active.first);
      final activeTerms = _rows('terms').where(
        (row) =>
            '${row['status'] ?? 'ACTIVE'}'.toUpperCase() == 'ACTIVE' &&
            '${row['session'] is Map ? _id(Map<String, dynamic>.from(row['session'])) : row['session']}' ==
                sessionId,
      );
      if (activeTerms.isNotEmpty) return sessionId;
      try {
        await widget.api.createAcademicPortalTerm({
          'name': 'First Term',
          'session': sessionId,
          'status': 'ACTIVE',
        });
        _notice('First Term created successfully.');
        await _load();
        return sessionId;
      } catch (e) {
        _notice(e.toString().replaceFirst('Exception: ', ''));
        await _load();
        return null;
      }
    }
    final year = TextEditingController(text: _currentSchoolYear());
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set up Academic Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Set up an academic session before adding your first class.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: year,
              decoration: const InputDecoration(labelText: 'School year'),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'First Term will be created and activated automatically.',
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
            child: const Text('Set up session'),
          ),
        ],
      ),
    );
    if (ok != true || year.text.trim().isEmpty) return null;
    try {
      final response = await widget.api.createAcademicPortalSession({
        'name': year.text.trim(),
        'status': 'ACTIVE',
      });
      final session = response['session'] is Map
          ? Map<String, dynamic>.from(response['session'] as Map)
          : response;
      final sessionId = '${session['_id'] ?? session['id'] ?? ''}';
      if (sessionId.isEmpty) {
        _notice('Academic session was created but could not be selected.');
        return null;
      }
      await _load();
      await widget.api.createAcademicPortalTerm({
        'name': 'First Term',
        'session': sessionId,
        'status': 'ACTIVE',
      });
      _notice('Academic session and First Term created successfully.');
      await _load();
      return sessionId;
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
      return null;
    }
  }

  Widget _mappingCard(
    List<Map<String, dynamic>> classes,
    List<Map<String, dynamic>> subjects,
  ) {
    if (classes.isEmpty || subjects.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Class-to-subject mapping',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose the subjects learners should see for each class.',
            ),
            const SizedBox(height: 10),
            ...classes.map((classRow) {
              final classId = _id(classRow);
              final mapped = (_rows('classSubjects'))
                  .where((mapping) {
                    final level = mapping['classLevel'];
                    return level is Map
                        ? _id(Map<String, dynamic>.from(level)) == classId
                        : '$level' == classId;
                  })
                  .map((mapping) {
                    final subject = mapping['subject'];
                    return subject is Map
                        ? _id(Map<String, dynamic>.from(subject))
                        : '$subject';
                  })
                  .toSet();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_displayClass(classRow)),
                subtitle: Text(
                  mapped.isEmpty
                      ? 'No subjects mapped yet'
                      : '${mapped.length} subjects mapped',
                ),
                trailing: TextButton(
                  onPressed: () =>
                      _editClassMapping(classRow, subjects, mapped),
                  child: const Text('Edit subjects'),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _editClassMapping(
    Map<String, dynamic> classRow,
    List<Map<String, dynamic>> subjects,
    Set<String> initial,
  ) async {
    final selected = {...initial};
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Subjects for ${_displayClass(classRow)}'),
            content: SizedBox(
              width: 430,
              child: SingleChildScrollView(
                child: Column(
                  children: subjects.map((subject) {
                    final id = _id(subject);
                    return CheckboxListTile(
                      value: selected.contains(id),
                      title: Text('${subject['name'] ?? 'Subject'}'),
                      onChanged: (value) => setDialogState(() {
                        if (value == true)
                          selected.add(id);
                        else
                          selected.remove(id);
                      }),
                    );
                  }).toList(),
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
                child: const Text('Save mapping'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.updateClassSubjects(_id(classRow), selected.toList());
      _notice('Subject mapping saved.');
      await _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  List<Map<String, dynamic>> _assignmentsForTeacher(
    Map<String, dynamic> teacher,
  ) {
    final teacherId = _id(teacher);
    return _rows('assignments').where((assignment) {
      final value = assignment['teacher'];
      if (value is Map)
        return _id(Map<String, dynamic>.from(value)) == teacherId;
      return '$value' == teacherId;
    }).toList();
  }

  String _assignmentNames(Map<String, dynamic> teacher, String key) {
    final names = _assignmentsForTeacher(teacher)
        .map((assignment) => assignment[key])
        .whereType<Map>()
        .map((value) => '${value['name'] ?? ''}'.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    return names.isEmpty ? 'Not assigned' : names.join(', ');
  }

  Widget _teachers(bool compact) {
    final teachers = _rows('teachers');
    final addButton = FilledButton.icon(
      key: const Key('add-teacher-button'),
      onPressed: _createTeacher,
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('Add Teacher'),
    );
    if (teachers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          addButton,
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No teachers have been created yet.'),
            ),
          ),
        ],
      );
    }
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          addButton,
          const SizedBox(height: 12),
          ...teachers.map((teacher) {
            final assignments = _assignmentsForTeacher(teacher);
            return Card(
              child: ListTile(
                title: Text('${teacher['fullName'] ?? 'Teacher'}'),
                subtitle: Text(
                  'Staff ID: ${teacher['staffId'] ?? ''}\n'
                  'Classes: ${_assignmentNames(teacher, 'classLevel')}\n'
                  'Subjects: ${_assignmentNames(teacher, 'subject')}\n'
                  'Status: ${assignments.isEmpty ? 'Not Assigned' : teacher['status'] ?? 'ACTIVE'}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'VIEW') _viewTeacher(teacher);
                    if (action == 'ASSIGN') _assignTeacher(teacher);
                    if (action == 'EDIT') _editTeacher(teacher);
                    if (action == 'RESET') _resetTeacherPassword(teacher);
                    if (action == 'STATUS') _toggleTeacherStatus(teacher);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'VIEW', child: Text('View')),
                    const PopupMenuItem(
                      value: 'ASSIGN',
                      child: Text('Assign Class & Subject'),
                    ),
                    const PopupMenuItem(value: 'EDIT', child: Text('Edit')),
                    const PopupMenuItem(
                      value: 'RESET',
                      child: Text('Reset temporary password'),
                    ),
                    PopupMenuItem(
                      value: 'STATUS',
                      child: Text(
                        '${teacher['status'] ?? 'ACTIVE'}'.toUpperCase() ==
                                'ACTIVE'
                            ? 'Deactivate teacher'
                            : 'Reactivate teacher',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        addButton,
        const SizedBox(height: 12),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Staff ID')),
                DataColumn(label: Text('Phone')),
                DataColumn(label: Text('Assigned Classes')),
                DataColumn(label: Text('Assigned Subjects')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Actions')),
              ],
              rows: teachers.map((teacher) {
                final assignments = _assignmentsForTeacher(teacher);
                return DataRow(
                  cells: [
                    DataCell(Text('${teacher['fullName'] ?? 'Teacher'}')),
                    DataCell(Text('${teacher['staffId'] ?? ''}')),
                    DataCell(Text('${teacher['phone'] ?? ''}')),
                    DataCell(Text(_assignmentNames(teacher, 'classLevel'))),
                    DataCell(Text(_assignmentNames(teacher, 'subject'))),
                    DataCell(
                      Text(
                        assignments.isEmpty
                            ? 'Not Assigned'
                            : '${teacher['status'] ?? 'ACTIVE'}',
                      ),
                    ),
                    DataCell(
                      Wrap(
                        children: [
                          TextButton(
                            onPressed: () => _viewTeacher(teacher),
                            child: const Text('View'),
                          ),
                          TextButton(
                            onPressed: () => _assignTeacher(teacher),
                            child: const Text('Assign Class & Subject'),
                          ),
                          TextButton(
                            onPressed: () => _editTeacher(teacher),
                            child: const Text('Edit'),
                          ),
                          TextButton(
                            onPressed: () => _resetTeacherPassword(teacher),
                            child: const Text('Reset password'),
                          ),
                          TextButton(
                            onPressed: () => _toggleTeacherStatus(teacher),
                            child: Text(
                              '${teacher['status'] ?? 'ACTIVE'}'
                                          .toUpperCase() ==
                                      'ACTIVE'
                                  ? 'Deactivate'
                                  : 'Reactivate',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
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

  bool get _canManageStudents => widget.manager || widget.teacher;

  String _studentClassName(Map<String, dynamic> student) {
    final value = student['classLevel'];
    if (value is Map) {
      return '${value['name'] ?? 'Class'} ${value['arm'] ?? ''}'.trim();
    }
    for (final row in _rows('classes')) {
      if (_id(row) == '$value') {
        return '${row['name'] ?? 'Class'} ${row['arm'] ?? ''}'.trim();
      }
    }
    return 'Not assigned';
  }

  Widget _students() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _canManageStudents ? _createStudent : null,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add student'),
          ),
          OutlinedButton.icon(
            onPressed: _canManageStudents ? _bulkImport : null,
            icon: const Icon(Icons.upload_file),
            label: const Text('Validate bulk import'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (widget.manager) _parentStudentLinks(),
      if (widget.manager) const SizedBox(height: 12),
      ..._rows('students').map(
        (student) => Card(
          child: ListTile(
            title: Text('${student['fullName'] ?? 'Student'}'),
            subtitle: Text(
              'Admission: ${student['studentId'] ?? ''}\n'
              'Class: ${_studentClassName(student)}\n'
              'Gender: ${student['gender'] ?? 'Not specified'}\n'
              'Parent/Guardian: ${student['parentName'] ?? 'Not provided'}',
            ),
            isThreeLine: true,
            trailing: _canManageStudents
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

  Widget _parentStudentLinks() {
    final unresolved = studentLinks
        .where((link) => link.linkStatus.toUpperCase() != 'RESOLVED')
        .toList();
    final count =
        studentLinksSummary['unresolved'] ??
        studentLinksSummary['unresolvedCount'] ??
        unresolved.length;
    if (studentLinksLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading Parent/Guardian links…'),
            ],
          ),
        ),
      );
    }
    if (studentLinksError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: Text(studentLinksError!)),
              TextButton(
                onPressed: _loadStudentLinks,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Parent/Guardian links',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.link_outlined, size: 17),
                  label: Text('$count unresolved'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (unresolved.isEmpty)
              const Text(
                'All visible Parent/Guardian relationships are linked to an academic student.',
              )
            else
              ...unresolved.map(_studentLinkTile),
          ],
        ),
      ),
    );
  }

  Widget _studentLinkTile(AcademicStudentLink link) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const CircleAvatar(child: Icon(Icons.person_search_outlined)),
    title: Text(link.childName),
    subtitle: Text(
      'Class: ${link.className}\n'
      'Parent/Guardian: ${link.parentDisplay}',
    ),
    isThreeLine: true,
    trailing: FilledButton.tonal(
      onPressed: link.candidates.isEmpty
          ? null
          : () => _resolveStudentLink(link),
      child: const Text('Resolve Parent Link'),
    ),
  );

  Future<void> _resolveStudentLink(AcademicStudentLink link) async {
    if (!widget.manager || link.candidates.isEmpty) return;
    AcademicStudentLinkCandidate? selected = link.candidates.length == 1
        ? link.candidates.first
        : null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Resolve Parent Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${link.childName}\n'
                'Class: ${link.className}\n'
                'Parent/Guardian: ${link.parentDisplay}',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AcademicStudentLinkCandidate>(
                value: selected,
                decoration: const InputDecoration(
                  labelText: 'Academic student',
                ),
                items: link.candidates
                    .map(
                      (candidate) => DropdownMenuItem(
                        value: candidate,
                        child: Text(
                          '${candidate.fullName} · ${candidate.studentId} · '
                          '${candidate.className}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => selected = value),
              ),
              const SizedBox(height: 8),
              const Text(
                'Confirm only when the school records identify the same child. '
                'This does not change attendance or create a student.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm link'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selected == null) return;
    try {
      await widget.api.resolveAcademicStudentLink(
        childToken: link.childToken,
        candidateToken: selected!.candidateToken,
      );
      _notice('Parent/Guardian link resolved successfully.');
      await _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
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
                  if ([
                    'DRAFT',
                    'RETURNED',
                  ].contains('${row['status']}'.toUpperCase()))
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
        dateOfBirth = TextEditingController(),
        parentName = TextEditingController(),
        parentPhone = TextEditingController(),
        parentEmail = TextEditingController();
    final classes = _rows('classes');
    if (classes.isEmpty) {
      return _notice(
        'No class has been assigned to your teacher account yet. Please contact the School Administrator.',
      );
    }
    String? classId = _id(classes.first);
    String? gender;
    final ok = await _form('ADD STUDENT', [
      TextField(
        controller: name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Student Full Name *'),
      ),
      TextField(
        controller: studentId,
        decoration: const InputDecoration(labelText: 'Admission Number *'),
      ),
      DropdownButtonFormField<String>(
        decoration: const InputDecoration(labelText: 'Gender'),
        items: const ['FEMALE', 'MALE', 'OTHER']
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
        onChanged: (value) => gender = value,
      ),
      TextField(
        controller: dateOfBirth,
        keyboardType: TextInputType.datetime,
        decoration: const InputDecoration(
          labelText: 'Date of Birth',
          hintText: 'YYYY-MM-DD',
        ),
      ),
      DropdownButtonFormField<String>(
        value: classId,
        decoration: const InputDecoration(labelText: 'Class *'),
        items: classes
            .map(
              (row) => DropdownMenuItem(
                value: _id(row),
                child: Text('${row['name']} ${row['arm'] ?? ''}'.trim()),
              ),
            )
            .toList(),
        onChanged: (value) => classId = value,
      ),
      TextField(
        controller: parentName,
        decoration: const InputDecoration(labelText: 'Parent/Guardian Name'),
      ),
      TextField(
        controller: parentPhone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'Parent/Guardian Phone Number',
        ),
      ),
      TextField(
        controller: parentEmail,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(
          labelText: 'Parent/Guardian Email (optional)',
        ),
      ),
    ], submitLabel: 'Add Student');
    if (ok != true) return;
    if (name.text.trim().isEmpty) {
      return _notice('Student full name is required.');
    }
    if (studentId.text.trim().isEmpty) {
      return _notice('Admission number is required.');
    }
    if (classId == null) return _notice('Select a class.');
    try {
      await widget.api.createAcademicStudent({
        'studentId': studentId.text.trim(),
        'fullName': name.text.trim(),
        'classLevel': classId,
        if (gender != null) 'gender': gender,
        if (dateOfBirth.text.trim().isNotEmpty)
          'dateOfBirth': dateOfBirth.text.trim(),
        if (parentName.text.trim().isNotEmpty)
          'parentName': parentName.text.trim(),
        if (parentPhone.text.trim().isNotEmpty)
          'parentPhone': parentPhone.text.trim(),
        if (parentEmail.text.trim().isNotEmpty)
          'parentEmail': parentEmail.text.trim().toLowerCase(),
      });
      _notice('Student added successfully.');
      await _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _bulkImport() async {
    final classes = _rows('classes');
    if (classes.isEmpty) {
      return _notice(
        'No class has been assigned to your teacher account yet. Please contact the School Administrator.',
      );
    }
    String classId = _id(classes.first);
    final chooseClass = await _form('Select import class', [
      DropdownButtonFormField<String>(
        value: classId,
        decoration: const InputDecoration(labelText: 'Class'),
        items: classes
            .map(
              (row) => DropdownMenuItem(
                value: _id(row),
                child: Text('${row['name']} ${row['arm'] ?? ''}'.trim()),
              ),
            )
            .toList(),
        onChanged: (value) => classId = value!,
      ),
    ], submitLabel: 'Choose CSV');
    if (chooseClass != true) return;
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
      final values = lines[index]
          .split(',')
          .map((value) => value.trim())
          .toList();
      if (index == 0 && values.first.toLowerCase().contains('student'))
        continue;
      if (values.length < 2) continue;
      rows.add({
        'studentId': values[0],
        'fullName': values[1],
        'classLevel': classId,
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
    final parentName = TextEditingController(
          text: '${student['parentName'] ?? ''}',
        ),
        parentPhone = TextEditingController(
          text: '${student['parentPhone'] ?? ''}',
        ),
        parentEmail = TextEditingController(
          text: '${student['parentEmail'] ?? ''}',
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
          value: classes.any((row) => _id(row) == classLevel)
              ? classLevel
              : null,
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
        controller: parentName,
        decoration: const InputDecoration(labelText: 'Parent/Guardian Name'),
      ),
      TextField(
        controller: parentPhone,
        decoration: const InputDecoration(
          labelText: 'Parent/Guardian Phone Number',
        ),
      ),
      TextField(
        controller: parentEmail,
        decoration: const InputDecoration(
          labelText: 'Parent/Guardian Email (optional)',
        ),
      ),
    ]);
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await widget.api.updateAcademicStudent(_id(student), {
        'fullName': name.text.trim(),
        'classLevel': classLevel,
        'status': status,
        'parentName': parentName.text.trim(),
        'parentPhone': parentPhone.text.trim(),
        'parentEmail': parentEmail.text.trim().toLowerCase(),
      });
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _createSubject({String? initialName}) async {
    final name = TextEditingController(text: initialName?.trim()),
        code = TextEditingController();
    String educationLevel = 'Primary';
    final ok = await _form('Create subject', [
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Subject name'),
      ),
      TextField(
        controller: code,
        decoration: const InputDecoration(labelText: 'Code (optional)'),
      ),
      DropdownButtonFormField<String>(
        value: educationLevel,
        decoration: const InputDecoration(labelText: 'Education level'),
        items:
            const [
                  'Early years',
                  'Primary',
                  'Junior Secondary',
                  'Senior Secondary',
                ]
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
        onChanged: (value) => educationLevel = value ?? educationLevel,
      ),
    ]);
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await widget.api.createSubject({
        'name': name.text.trim(),
        if (code.text.trim().isNotEmpty) 'code': code.text.trim(),
        'educationLevel': educationLevel,
      });
      _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _createTeacher() async {
    final staff = TextEditingController(),
        name = TextEditingController(),
        email = TextEditingController(),
        phone = TextEditingController(),
        password = TextEditingController();
    String gender = '';
    String responsibility = '';
    final ok = await _form('CREATE TEACHER', [
      TextField(
        controller: name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Full Name *'),
      ),
      TextField(
        controller: phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Phone Number *'),
      ),
      TextField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email *'),
      ),
      TextField(
        controller: staff,
        decoration: const InputDecoration(labelText: 'Staff ID *'),
      ),
      DropdownButtonFormField<String>(
        decoration: const InputDecoration(labelText: 'Gender (optional)'),
        items: const [
          'FEMALE',
          'MALE',
          'OTHER',
        ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => gender = v ?? '',
      ),
      DropdownButtonFormField<String>(
        decoration: const InputDecoration(
          labelText: 'Responsibility / Position (optional)',
        ),
        items:
            const [
                  'Teacher',
                  'Class Teacher',
                  'Head Teacher',
                  'Academic Officer',
                  'Principal',
                  'Vice Principal',
                  'Other',
                ]
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
        onChanged: (value) => responsibility = value ?? '',
      ),
      TextField(
        controller: password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Temporary Password *'),
      ),
    ], submitLabel: 'Create Teacher');
    if (ok != true) return;
    if (name.text.trim().isEmpty) return _notice('Full name is required.');
    final normalizedPhone = phone.text.replaceAll(RegExp(r'[\s()-]'), '');
    if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(normalizedPhone)) {
      return _notice('Enter a valid phone number.');
    }
    final normalizedEmail = email.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
      return _notice('Enter a valid email address.');
    }
    if (staff.text.trim().isEmpty) {
      return _notice('Staff ID is required.');
    }
    if (password.text.isEmpty) {
      return _notice('Temporary password is required.');
    }
    try {
      await widget.api.createTeacher({
        'staffId': staff.text.trim(),
        'fullName': name.text.trim(),
        'email': normalizedEmail,
        'phone': normalizedPhone,
        if (gender.isNotEmpty) 'gender': gender,
        if (responsibility.isNotEmpty) 'responsibility': responsibility,
        'temporaryPassword': password.text,
      });
      _notice('Teacher created successfully.');
      await _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _viewTeacher(Map<String, dynamic> teacher) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${teacher['fullName'] ?? 'Teacher'}'),
        content: Text(
          'Staff ID: ${teacher['staffId'] ?? ''}\n'
          'Phone: ${teacher['phone'] ?? ''}\n'
          'Email: ${teacher['email'] ?? ''}\n'
          'Classes: ${_assignmentNames(teacher, 'classLevel')}\n'
          'Subjects: ${_assignmentNames(teacher, 'subject')}\n'
          'Status: ${_assignmentsForTeacher(teacher).isEmpty ? 'Not Assigned' : teacher['status'] ?? 'ACTIVE'}',
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

  Future<void> _editTeacher(Map<String, dynamic> teacher) async {
    final id = _id(teacher);
    if (id == 'null') return;
    final name = TextEditingController(text: '${teacher['fullName'] ?? ''}');
    final email = TextEditingController(text: '${teacher['email'] ?? ''}');
    final phone = TextEditingController(text: '${teacher['phone'] ?? ''}');
    final staff = TextEditingController(text: '${teacher['staffId'] ?? ''}');
    final responsibility = TextEditingController(
      text: '${teacher['responsibility'] ?? ''}',
    );
    final ok = await _form('Edit teacher', [
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Full name'),
      ),
      TextField(
        controller: email,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      TextField(
        controller: phone,
        decoration: const InputDecoration(labelText: 'Phone'),
      ),
      TextField(
        controller: staff,
        decoration: const InputDecoration(labelText: 'Staff ID'),
      ),
      TextField(
        controller: responsibility,
        decoration: const InputDecoration(labelText: 'Responsibility'),
      ),
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Confirm'),
          ),
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
        decoration: const InputDecoration(labelText: 'New temporary password'),
      ),
      TextField(
        controller: confirmation,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Confirm temporary password',
        ),
      ),
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

  Future<void> _assignTeacher([Map<String, dynamic>? selectedTeacher]) async {
    final teachers = _rows('teachers'),
        classes = _rows('classes'),
        subjects = _rows('subjects');
    if (teachers.isEmpty) return _notice('Create a teacher first.');
    if (classes.isEmpty) {
      return _notice('No classes have been created yet. Create a class first.');
    }
    if (subjects.isEmpty) {
      return _notice(
        'No subjects have been created yet. Create a subject first.',
      );
    }
    String teacher = _id(selectedTeacher ?? teachers.first),
        classLevel = _id(classes.first),
        subject = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final mapped = _mappedSubjectIds(classLevel);
          final available = mapped.isEmpty
              ? subjects
              : subjects.where((row) => mapped.contains(_id(row))).toList();
          if (available.isNotEmpty &&
              !available.any((row) => _id(row) == subject)) {
            subject = _id(available.first);
          }
          return AlertDialog(
            title: const Text('Assign Class & Subject'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                    onChanged: selectedTeacher == null
                        ? (value) => setDialogState(() => teacher = value!)
                        : null,
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
                    onChanged: (value) =>
                        setDialogState(() => classLevel = value!),
                  ),
                  DropdownButtonFormField<String>(
                    value: subject,
                    decoration: const InputDecoration(labelText: 'Subject'),
                    items: available
                        .map(
                          (row) => DropdownMenuItem(
                            value: _id(row),
                            child: Text('${row['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => subject = value!),
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
                onPressed: available.isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('Assign'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.assignTeacher({
        'teacher': teacher,
        'classLevel': classLevel,
        'subject': subject,
      });
      _notice('Class and subject assigned successfully.');
      await _load();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Set<String> _mappedSubjectIds(String classId) {
    return _rows('classSubjects')
        .where((mapping) {
          final level = mapping['classLevel'];
          final mappedClass = level is Map
              ? _id(Map<String, dynamic>.from(level))
              : '$level';
          return mappedClass == classId;
        })
        .map((mapping) {
          final subject = mapping['subject'];
          return subject is Map
              ? _id(Map<String, dynamic>.from(subject))
              : '$subject';
        })
        .toSet();
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
    final mappedSubjectIds = _mappedSubjectIds(_id(classes.first));
    final availableSubjects = mappedSubjectIds.isEmpty
        ? subjects
        : subjects
              .where((subject) => mappedSubjectIds.contains(_id(subject)))
              .toList();
    if (availableSubjects.isEmpty) {
      _notice('Map subjects to this class before creating an assessment.');
      return;
    }
    final title = TextEditingController();
    String session = _id(sessions.first),
        term = _id(terms.first),
        classLevel = _id(classes.first),
        subject = _id(availableSubjects.first);
    final values = await _assessmentDialog(
      title: title,
      sessions: sessions,
      terms: terms,
      classes: classes,
      subjects: subjects,
      session: session,
      term: term,
      classLevel: classLevel,
      subject: subject,
    );
    /*
    final legacyOk = await _form('Create assessment', [
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
            .where((row) =>
                mappedSubjectIds.isEmpty || mappedSubjectIds.contains(_id(row)))
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
    */
    if (values == null || title.text.trim().isEmpty) return;
    session = values['session']!;
    term = values['term']!;
    classLevel = values['classLevel']!;
    subject = values['subject']!;
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

  Future<Map<String, String>?> _assessmentDialog({
    required TextEditingController title,
    required List<Map<String, dynamic>> sessions,
    required List<Map<String, dynamic>> terms,
    required List<Map<String, dynamic>> classes,
    required List<Map<String, dynamic>> subjects,
    required String session,
    required String term,
    required String classLevel,
    required String subject,
  }) {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final mapped = _mappedSubjectIds(classLevel);
          final available = mapped.isEmpty
              ? subjects
              : subjects.where((row) => mapped.contains(_id(row))).toList();
          if (available.isNotEmpty &&
              !available.any((row) => _id(row) == subject)) {
            subject = _id(available.first);
          }
          return AlertDialog(
            title: const Text('Create assessment'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Assessment title',
                    ),
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
                    onChanged: (value) =>
                        setDialogState(() => session = value!),
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
                    onChanged: (value) => setDialogState(() => term = value!),
                  ),
                  DropdownButtonFormField<String>(
                    value: classLevel,
                    decoration: const InputDecoration(labelText: 'Class'),
                    items: classes
                        .map(
                          (row) => DropdownMenuItem(
                            value: _id(row),
                            child: Text(_displayClass(row)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => classLevel = value!),
                  ),
                  DropdownButtonFormField<String>(
                    value: available.isEmpty ? null : subject,
                    decoration: const InputDecoration(labelText: 'Subject'),
                    items: available
                        .map(
                          (row) => DropdownMenuItem(
                            value: _id(row),
                            child: Text('${row['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: available.isEmpty
                        ? null
                        : (value) => setDialogState(() => subject = value!),
                  ),
                  const Text('Default scoring: CA 30 + Exam 70.'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: available.isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, {
                        'session': session,
                        'term': term,
                        'classLevel': classLevel,
                        'subject': subject,
                      }),
                child: const Text('Create assessment'),
              ),
            ],
          );
        },
      ),
    );
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
      final components =
          (assessment['components'] as List? ??
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
                                        controller:
                                            controllers['${_id(student)}:${component['name']}'],
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
                    controllers['${_id(student)}:${component['name']}']!.text
                        .trim(),
                  ),
              },
            },
          )
          .toList();
      final invalidScores = scores
          .expand((row) => (row['values'] as Map).entries)
          .map(
            (entry) => <String, dynamic>{
              'label': entry.key,
              'value': entry.value,
            },
          )
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
          })
          .toList();
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
              .map(
                (row) => DropdownMenuItem(
                  value: _id(row),
                  child: Text('${row['name'] ?? 'Class'} ${row['arm'] ?? ''}'),
                ),
              )
              .toList(),
          onChanged: (value) => classLevel = value,
        ),
      if (!widget.manager && students.isNotEmpty)
        DropdownButtonFormField<String>(
          value: student,
          decoration: const InputDecoration(labelText: 'Assigned student'),
          items: students
              .map(
                (row) => DropdownMenuItem(
                  value: _id(row),
                  child: Text('${row['fullName'] ?? 'Student'}'),
                ),
              )
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

  Future<bool?> _form(
    String title,
    List<Widget> fields, {
    String submitLabel = 'Save',
  }) => showDialog<bool>(
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
          child: Text(submitLabel),
        ),
      ],
    ),
  );
}
