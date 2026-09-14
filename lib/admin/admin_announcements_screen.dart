import 'package:flutter/material.dart';

import 'admin_announcements_api.dart';
import 'admin_permissions.dart';

class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key, this.api, this.initialAccess});

  final AdminAnnouncementsApi? api;
  final AdminAccess? initialAccess;

  @override
  State<AdminAnnouncementsScreen> createState() =>
      _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  late final AdminAnnouncementsApi _api;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _summary = {};
  AdminAccess? _access;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? AdminAnnouncementsApi();
    _load();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final access =
          widget.initialAccess ?? await AdminSessionStore.loadAccess();
      final responses = access.has(AdminPermissions.announcementsSummary)
          ? await Future.wait([_api.list(), _api.summary()])
          : [await _api.list(), <String, dynamic>{}];
      final listData = responses[0]['data'];
      final raw = listData is Map ? listData['announcements'] : null;
      final summaryData = responses[1]['data'];
      setState(() {
        _items = raw is List
            ? raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
            : [];
        _summary = summaryData is Map && summaryData['summary'] is Map
            ? Map<String, dynamic>.from(summaryData['summary'])
            : <String, dynamic>{};
        _access = access;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  bool _can(String permission) => _access?.has(permission) == true;

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = (item['_id'] ?? item['id'])?.toString();
    if (id == null || id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: const Text(
            'This removes the notice from the publishing workspace. This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.remove(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Announcement deleted.')));
        _load();
      }
    } catch (e) {
      if (mounted) _message(e);
    }
  }

  Future<void> _toggle(Map<String, dynamic> item) async {
    final id = (item['_id'] ?? item['id'])?.toString();
    if (id == null || id.isEmpty) return;
    final active = item['isActive'] == true;
    try {
      await _api.updateStatus(id, !active);
      _load();
    } catch (e) {
      if (mounted) _message(e);
    }
  }

  void _message(Object error) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error.toString())));

  String _value(Map<String, dynamic> item, String key,
          [String fallback = '']) =>
      item[key]?.toString().trim().isNotEmpty == true
          ? item[key].toString()
          : fallback;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF102A43);
    const teal = Color(0xFF0F766E);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('Customer Announcements'),
        backgroundColor: Colors.white,
        foregroundColor: ink,
        elevation: 0,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          if (_can(AdminPermissions.announcementsCreate))
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _openEditor,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New announcement'),
                style: FilledButton.styleFrom(backgroundColor: teal),
              ),
            ),
        ],
      ),
      body: _loading
          ? const _LoadingState()
          : _error != null
              ? _ErrorState(message: _error!, retry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (_can(AdminPermissions.announcementsSummary))
                        _SummaryStrip(summary: _summary),
                      const SizedBox(height: 20),
                      if (_items.isEmpty)
                        const _EmptyState()
                      else
                        ..._items.map((item) => _AnnouncementTile(
                              item: item,
                              value: _value,
                              canEdit:
                                  _can(AdminPermissions.announcementsUpdate),
                              canActivate:
                                  _can(AdminPermissions.announcementsActivate),
                              canDelete:
                                  _can(AdminPermissions.announcementsDelete),
                              onEdit: () => _openEditor(item),
                              onToggle: () => _toggle(item),
                              onDelete: () => _delete(item),
                            )),
                    ],
                  ),
                ),
    );
  }

  Future<void> _openEditor([Map<String, dynamic>? item]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AnnouncementEditor(item: item),
    );
    if (result == null) return;
    try {
      if (item == null) {
        await _api.create(result);
      } else {
        final id = (item['_id'] ?? item['id']).toString();
        await _api.update(id, result);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(item == null
                ? 'Announcement created.'
                : 'Announcement updated.')));
        _load();
      }
    } catch (e) {
      if (mounted) _message(e);
    }
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary});
  final Map<String, dynamic> summary;
  @override
  Widget build(BuildContext context) {
    final values = [
      ['Total', summary['total'] ?? 0],
      ['Active', summary['active'] ?? 0],
      ['Scheduled', summary['scheduled'] ?? 0],
      ['Expired', summary['expired'] ?? 0],
      ['Views', summary['views'] ?? 0],
      ['Acknowledgements', summary['acknowledgements'] ?? 0],
      ['Dismissals', summary['dismissals'] ?? 0],
      ['Clicks', summary['clicks'] ?? 0],
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: values
          .map((v) => Container(
                width: 180,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDCE7E3)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v[0].toString(),
                          style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 8),
                      Text('${v[1]}',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800)),
                    ]),
              ))
          .toList(),
    );
  }
}

class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile(
      {required this.item,
      required this.value,
      required this.onEdit,
      required this.onToggle,
      required this.onDelete,
      required this.canEdit,
      required this.canActivate,
      required this.canDelete});
  final Map<String, dynamic> item;
  final String Function(Map<String, dynamic>, String, [String]) value;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final bool canEdit;
  final bool canActivate;
  final bool canDelete;
  @override
  Widget build(BuildContext context) {
    final active = item['isActive'] == true;
    final metrics = item['metrics'] is Map
        ? Map<String, dynamic>.from(item['metrics'])
        : const <String, dynamic>{};
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFDCE7E3))),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value(item, 'title', 'Untitled announcement'),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(value(item, 'message', 'No message'),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
            ),
            PopupMenuButton<String>(
              enabled: canEdit || canDelete,
              onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => [
                if (canEdit)
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (canDelete)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Chip(label: Text(value(item, 'type', 'GENERAL'))),
            Chip(label: Text(value(item, 'visibility', 'IN_APP'))),
            Chip(label: Text(active ? 'ACTIVE' : 'INACTIVE')),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 20, runSpacing: 8, children: [
            Text('Views ${metrics['views'] ?? 0}'),
            Text('Acknowledgements ${metrics['acknowledgements'] ?? 0}'),
            Text('Dismissals ${metrics['dismissals'] ?? 0}'),
            Text('Clicks ${metrics['clicks'] ?? 0}'),
          ]),
          const Divider(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (canActivate)
                TextButton.icon(
                    onPressed: onToggle,
                    icon: Icon(active
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline),
                    label: Text(active ? 'Deactivate' : 'Activate')),
              Text('Priority ${value(item, 'priority', 'NORMAL')}',
                  style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ]),
      ),
    );
  }
}

class _AnnouncementEditor extends StatefulWidget {
  const _AnnouncementEditor({this.item});
  final Map<String, dynamic>? item;
  @override
  State<_AnnouncementEditor> createState() => _AnnouncementEditorState();
}

class _AnnouncementEditorState extends State<_AnnouncementEditor> {
  late final TextEditingController _title;
  late final TextEditingController _message;
  late final TextEditingController _image;
  late final TextEditingController _ctaLabel;
  late final TextEditingController _ctaUrl;
  late final TextEditingController _startAt;
  late final TextEditingController _endAt;
  late final TextEditingController _selectedCustomerIds;
  late final TextEditingController _selectedRole;
  late final TextEditingController _priority;
  String _type = 'INFO';
  String _style = 'BANNER';
  String _visibility = 'ONCE';
  String _audience = 'ALL';
  final _formKey = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    final i = widget.item ?? {};
    _title = TextEditingController(text: i['title']?.toString());
    _message = TextEditingController(text: i['message']?.toString());
    _image = TextEditingController(text: i['imageUrl']?.toString());
    final cta = i['cta'] is Map ? i['cta'] as Map : {};
    _ctaLabel = TextEditingController(text: cta['label']?.toString());
    _ctaUrl = TextEditingController(text: cta['url']?.toString());
    _startAt = TextEditingController(text: i['startAt']?.toString());
    _endAt = TextEditingController(text: i['endAt']?.toString());
    _selectedCustomerIds = TextEditingController(
        text: (i['selectedCustomerIds'] is List)
            ? (i['selectedCustomerIds'] as List).join(', ')
            : '');
    _selectedRole = TextEditingController(text: i['selectedRole']?.toString());
    _priority = TextEditingController(text: '${i['priority'] ?? 0}');
    _type = i['type']?.toString() ?? _type;
    _style = i['style']?.toString() ?? _style;
    _visibility = i['visibility']?.toString() ?? _visibility;
    _audience = i['audience']?.toString() ?? _audience;
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _message,
      _image,
      _ctaLabel,
      _ctaUrl,
      _startAt,
      _endAt,
      _selectedCustomerIds,
      _selectedRole,
      _priority
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  InputDecoration _dec(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder());
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.item == null ? 'New announcement' : 'Edit announcement'),
        content: SizedBox(
          width: 560,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(children: [
                TextFormField(
                    controller: _title,
                    decoration: _dec('Title'),
                    validator: (v) =>
                        v!.trim().isEmpty ? 'Title is required' : null),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _message,
                    decoration: _dec('Message'),
                    minLines: 4,
                    maxLines: 7,
                    validator: (v) =>
                        v!.trim().isEmpty ? 'Message is required' : null),
                const SizedBox(height: 12),
                Column(children: [
                  DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _type,
                      decoration: _dec('Type'),
                      items: [
                        'INFO',
                        'SUCCESS',
                        'WARNING',
                        'CRITICAL',
                        'PROMOTION',
                        'MAINTENANCE',
                        'SECURITY'
                      ]
                          .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)))
                          .toList(),
                      onChanged: (v) => setState(() => _type = v!)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _style,
                      decoration: _dec('Display style'),
                      items: ['POPUP', 'BANNER', 'BOTH']
                          .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)))
                          .toList(),
                      onChanged: (v) => setState(() => _style = v!)),
                ]),
                const SizedBox(height: 12),
                Column(children: [
                  DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _audience,
                      decoration: _dec('Audience'),
                      items: [
                        'ALL',
                        'ACTIVE',
                        'KYC_PENDING',
                        'KYC_VERIFIED',
                        'SELECTED_CUSTOMERS',
                        'SELECTED_ROLE'
                      ]
                          .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)))
                          .toList(),
                      onChanged: (v) => setState(() => _audience = v!)),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _priority,
                      keyboardType: TextInputType.number,
                      decoration: _dec('Priority (integer)'),
                      validator: (v) => int.tryParse(v?.trim() ?? '') == null
                          ? 'Enter a whole number'
                          : null),
                ]),
                const SizedBox(height: 12),
                if (_audience == 'SELECTED_CUSTOMERS' ||
                    _audience == 'SELECTED_ROLE')
                  TextFormField(
                    controller: _audience == 'SELECTED_CUSTOMERS'
                        ? _selectedCustomerIds
                        : _selectedRole,
                    decoration: _dec(_audience == 'SELECTED_CUSTOMERS'
                        ? 'Selected customer IDs (comma separated)'
                        : 'Selected role'),
                    validator: (v) => v!.trim().isEmpty
                        ? 'Targeting values are required'
                        : null,
                  ),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _image,
                    decoration: _dec('Image URL (optional)')),
                const SizedBox(height: 12),
                Column(children: [
                  TextFormField(
                      controller: _ctaLabel,
                      decoration: _dec('CTA label (optional)')),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _ctaUrl,
                      decoration: _dec('CTA URL (optional)')),
                ]),
                const SizedBox(height: 12),
                Column(children: [
                  TextFormField(
                      controller: _startAt,
                      decoration: _dec('Start at (ISO 8601)')),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _endAt,
                      decoration: _dec('End at (ISO 8601)')),
                ]),
                DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _visibility,
                    decoration: _dec('Visibility'),
                    items: [
                      'ONCE',
                      'EVERY_LOGIN',
                      'UNTIL_DISMISSED',
                      'MANDATORY'
                    ]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => setState(() => _visibility = v!)),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          OutlinedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) _preview();
              },
              child: const Text('Preview')),
          FilledButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  Navigator.pop(context, _payload());
                }
              },
              child: const Text('Save')),
        ],
      );
  Map<String, dynamic> _payload() => {
        'title': _title.text.trim(),
        'message': _message.text.trim(),
        'type': _type,
        'style': _style,
        'imageUrl': _image.text.trim(),
        'cta': {'label': _ctaLabel.text.trim(), 'url': _ctaUrl.text.trim()},
        'priority': int.parse(_priority.text.trim()),
        'audience': _audience,
        'selectedCustomerIds': _selectedCustomerIds.text
            .split(',')
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toList(),
        'selectedRole': _selectedRole.text.trim().isEmpty
            ? null
            : _selectedRole.text.trim(),
        'startAt': _startAt.text.trim().isEmpty ? null : _startAt.text.trim(),
        'endAt': _endAt.text.trim().isEmpty ? null : _endAt.text.trim(),
        'visibility': _visibility,
        'isActive': widget.item?['isActive'] ?? false,
      };
  void _preview() => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Customer preview'),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title.text,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(_message.text),
                if (_ctaLabel.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  FilledButton(onPressed: null, child: Text('Preview CTA'))
                ],
              ]),
        ),
      );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 44),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: retry, child: const Text('Retry'))
      ]));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.symmetric(vertical: 90),
      child: Column(children: [
        Icon(Icons.campaign_outlined, size: 54, color: Colors.black38),
        SizedBox(height: 12),
        Text('No customer announcements yet',
            style: TextStyle(fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text(
            'Create a notice to reach customers from one controlled workspace.')
      ]));
}
