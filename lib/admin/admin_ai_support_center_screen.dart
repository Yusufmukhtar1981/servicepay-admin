import 'package:flutter/material.dart';

import 'admin_permissions.dart';
import 'admin_support_api.dart';
import 'admin_customer_support_screen.dart';

class AdminAiSupportCenterScreen extends StatefulWidget {
  const AdminAiSupportCenterScreen({
    super.key,
    this.api,
    this.initialAccess,
  });

  final AdminSupportApi? api;
  final AdminAccess? initialAccess;

  @override
  State<AdminAiSupportCenterScreen> createState() =>
      _AdminAiSupportCenterScreenState();
}

class _AdminAiSupportCenterScreenState extends State<AdminAiSupportCenterScreen>
    with SingleTickerProviderStateMixin {
  late final AdminSupportApi _api = widget.api ?? AdminSupportApi();
  late final TabController _tabs;
  AdminAccess _access = const AdminAccess(role: '', permissions: <String>{});
  Map<String, dynamic> _metrics = <String, dynamic>{};
  Map<String, dynamic> _settings = <String, dynamic>{};
  List<Map<String, dynamic>> _conversations = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _articles = <Map<String, dynamic>>[];
  int _revision = 0;
  int _page = 1;
  int _pages = 1;
  bool _loading = true;
  bool _saving = false;
  String _error = '';

  bool get _canView => _access.has(AdminPermissions.supportView);
  bool get _canResolve => _access.has(AdminPermissions.supportResolve);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final AdminAccess access =
          widget.initialAccess ?? await AdminSessionStore.loadAccess();
      if (!access.has(AdminPermissions.supportView)) {
        if (mounted) {
          setState(() {
            _access = access;
            _loading = false;
            _error = 'You do not have permission to view AI Support.';
          });
        }
        return;
      }
      // Staff may inspect AI conversations and continue work through the
      // ticket queue, but AI configuration and knowledge management are
      // Head Office controls. Do not even request those protected resources.
      if (!access.isHeadOffice) {
        final Map<String, dynamic> conversations =
            _nested(await _api.aiConversations(page: _page, limit: 20));
        if (!mounted) return;
        final dynamic rawItems = conversations['items'];
        setState(() {
          _access = access;
          _conversations = rawItems is List
              ? rawItems
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
              : <Map<String, dynamic>>[];
          _page = (conversations['page'] as num?)?.toInt() ?? _page;
          _pages = (conversations['pages'] as num?)?.toInt() ?? 1;
          _metrics = <String, dynamic>{};
          _settings = <String, dynamic>{};
          _articles = <Map<String, dynamic>>[];
        });
        return;
      }
      final values = await Future.wait([
        _api.aiMetrics(),
        _api.aiSettings(),
        _api.aiConversations(page: _page, limit: 20),
        _api.aiKnowledge(),
      ]);
      final metrics = _nested(values[0]);
      final settings = _nested(values[1]);
      final conversations = _nested(values[2]);
      final knowledge = _nested(values[3]);
      if (!mounted) return;
      setState(() {
        _access = access;
        _metrics = metrics;
        _settings = settings;
        final dynamic rawItems = conversations['items'];
        _conversations = rawItems is List
            ? rawItems
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[];
        _page = (conversations['page'] as num?)?.toInt() ?? _page;
        _pages = (conversations['pages'] as num?)?.toInt() ?? 1;
        final dynamic rawArticles = knowledge['articles'];
        _articles = rawArticles is List
            ? rawArticles
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[];
        _revision = (knowledge['revision'] as num?)?.toInt() ?? 0;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _nested(Map<String, dynamic> value) =>
      value['data'] is Map ? Map<String, dynamic>.from(value['data']) : value;

  Future<void> _saveSettings() async {
    if (!_canResolve || _saving) return;
    setState(() => _saving = true);
    try {
      final updated = await _api.saveAiSettings({
        'enabled': _settings['enabled'] == true,
        'retentionDays':
            int.tryParse('${_settings['retentionDays'] ?? 30}') ?? 30,
        'dailyBudgetUsd':
            double.tryParse('${_settings['dailyBudgetUsd'] ?? 0}') ?? 0,
        'englishVoiceEnabled': _settings['englishVoiceVerified'] == true &&
            _settings['englishVoiceEnabled'] == true,
        'hausaVoiceEnabled': false,
      });
      if (mounted) {
        final saved = _nested(updated);
        setState(() {
          _settings = saved;
          if (saved.containsKey('dailyBudgetUsd')) {
            _metrics = {
              ..._metrics,
              'dailyBudgetUsd': saved['dailyBudgetUsd'],
            };
          }
        });
        _message('AI support settings saved.');
      }
    } catch (error) {
      if (mounted) _message('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editArticle([Map<String, dynamic>? article]) async {
    if (!_canResolve) return;
    final title = TextEditingController(text: '${article?['title'] ?? ''}');
    final body = TextEditingController(text: '${article?['body'] ?? ''}');
    final reason = TextEditingController();
    String language = '${article?['language'] ?? 'en'}';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title:
              Text(article == null ? 'Add knowledge article' : 'Edit article'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Title')),
                  DropdownButtonFormField<String>(
                    value: language,
                    decoration: const InputDecoration(labelText: 'Language'),
                    items: const [
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'ha', child: Text('Hausa')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => language = value ?? 'en'),
                  ),
                  TextField(
                    controller: body,
                    minLines: 5,
                    maxLines: 10,
                    decoration: const InputDecoration(
                        labelText: 'Approved support content'),
                  ),
                  TextField(
                      controller: reason,
                      decoration: const InputDecoration(
                          labelText: 'Reason for change')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'title': title.text.trim(),
                'body': body.text.trim(),
                'language': language,
                'reason': reason.text.trim(),
              }),
              child: const Text('Save article'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    body.dispose();
    reason.dispose();
    if (result == null ||
        result['title'] == '' ||
        result['body'] == '' ||
        result['reason'] == '') {
      return;
    }
    final List<Map<String, dynamic>> updated =
        _articles.map((e) => Map<String, dynamic>.from(e)).toList();
    if (article == null) {
      updated.add({
        'title': result['title'],
        'body': result['body'],
        'language': result['language'],
        'id': 'new-${DateTime.now().microsecondsSinceEpoch}',
        'approved': true
      });
    } else {
      final index =
          updated.indexWhere((e) => '${e['id']}' == '${article['id']}');
      if (index >= 0) {
        updated[index] = {
          ...updated[index],
          'title': result['title'],
          'body': result['body'],
          'language': result['language'],
          'approved': true,
        };
      }
    }
    await _saveKnowledge(updated, '${result['reason']}');
  }

  Future<void> _saveKnowledge(
      List<Map<String, dynamic>> articles, String reason) async {
    if (!_canResolve || _saving) return;
    setState(() => _saving = true);
    try {
      final response = await _api.saveAiKnowledge({
        'revision': _revision,
        'articles': articles,
        'reason': reason,
      });
      final data = _nested(response);
      if (!mounted) return;
      setState(() {
        _revision = (data['revision'] as num?)?.toInt() ?? _revision;
        final raw = data['articles'];
        if (raw is List) {
          _articles = raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else {
          _articles = articles;
        }
      });
      _message('Knowledge revision saved.');
    } catch (error) {
      if (mounted) _message('$error. Reload to resolve any revision conflict.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showConversation(Map<String, dynamic> item) async {
    try {
      final response = await _api.aiConversation('${item['id']}');
      final conversation = _nested(response);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _ConversationDetail(conversation: conversation),
        ),
      );
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_canView) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_canView) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI Support Center')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error.isEmpty
                ? 'You do not have permission to view AI Support.'
                : _error),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Support Center'),
        actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const AdminCustomerSupportScreen(),
            )),
            icon: const Icon(Icons.confirmation_number_outlined),
            label: const Text('Tickets'),
          ),
        ],
        bottom: _access.isHeadOffice
            ? TabBar(
                controller: _tabs,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'Overview & controls'),
                  Tab(text: 'Knowledge base'),
                  Tab(text: 'Conversations'),
                ],
              )
            : null,
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error.isNotEmpty)
            MaterialBanner(
              content: Text(_error),
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry'))
              ],
            ),
          Expanded(
            child: _access.isHeadOffice
                ? TabBarView(
                    controller: _tabs,
                    children: [
                      _overview(),
                      _knowledge(),
                      _conversationList(),
                    ],
                  )
                : _conversationList(),
          ),
        ],
      ),
    );
  }

  Widget _overview() {
    const metricLabels = <String, String>{
      'conversations': 'Conversations',
      'complaints': 'Complaints',
      'open': 'Open',
      'pending': 'Pending',
      'resolved': 'Resolved',
      'escalated': 'Escalated',
      'averageResponseSeconds': 'Avg response (sec)',
      'averageResolutionSeconds': 'Avg resolution (sec)',
      'satisfactionAverage': 'Satisfaction',
      'satisfactionCount': 'Ratings',
      'budgetReservedUsd': 'Reserved budget (USD)',
      'dailyBudgetUsd': 'Daily budget (USD)',
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth > 1050
              ? 4
              : constraints.maxWidth > 620
                  ? 3
                  : 2;
          return GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: metricLabels.entries
                .map((entry) => _MetricTile(
                      label: entry.value,
                      value: '${_metrics[entry.key] ?? '—'}',
                    ))
                .toList(),
          );
        }),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Service controls',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    'Retention, budget approval and voice controls are enforced by the server.'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('AI support enabled'),
                  value: _settings['enabled'] == true,
                  onChanged: !_canResolve || _saving
                      ? null
                      : (value) => setState(() => _settings['enabled'] = value),
                ),
                _numberField('Retention days', 'retentionDays', integer: true),
                _numberField('Daily budget (USD)', 'dailyBudgetUsd'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('English voice messages'),
                  subtitle: Text(
                    _settings['englishVoiceVerified'] == true
                        ? 'Quality verification passed. Availability remains controlled by the service.'
                        : 'Disabled pending backend quality verification.',
                  ),
                  value: _settings['englishVoiceVerified'] == true &&
                      _settings['englishVoiceEnabled'] == true,
                  onChanged: !_canResolve ||
                          _saving ||
                          _settings['englishVoiceVerified'] != true
                      ? null
                      : (value) => setState(
                            () => _settings['englishVoiceEnabled'] = value,
                          ),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.lock_outline),
                  title: Text('Hausa voice'),
                  subtitle: Text(
                      'Unavailable pending verification. It cannot be enabled here.'),
                  trailing: Text('OFF'),
                ),
                Text(
                    'Approved daily budget: \$${_settings['approvedDailyBudgetUsd'] ?? '—'}'),
                if (_canResolve)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _saveSettings,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save controls'),
                    ),
                  )
                else
                  const Text(
                      'Settings are read-only: support.resolve permission required.'),
              ],
            ),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Support desk is not a financial operations tool'),
            subtitle: Text(
                'AI and human support must never request or perform transfers, wallet edits, refunds, PIN changes, OTP handling, or other financial actions.'),
          ),
        ),
      ],
    );
  }

  Widget _numberField(String label, String key, {bool integer = false}) {
    return TextFormField(
      key: ValueKey('$key-${_settings[key]}'),
      initialValue: '${_settings[key] ?? ''}',
      enabled: _canResolve && !_saving,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => _settings[key] =
          integer ? (int.tryParse(value) ?? 0) : (double.tryParse(value) ?? 0),
    );
  }

  Widget _knowledge() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Expanded(
                    child: Text('Approved content · revision $_revision',
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                if (_canResolve)
                  FilledButton.icon(
                      onPressed: _saving ? null : () => _editArticle(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add article')),
              ],
            ),
          ),
          Expanded(
            child: _articles.isEmpty
                ? const _EmptyPanel(
                    title: 'No approved articles',
                    detail:
                        'Knowledge articles will appear here after they are published.')
                : ListView.builder(
                    itemCount: _articles.length,
                    itemBuilder: (context, index) {
                      final article = _articles[index];
                      return Card(
                        margin: const EdgeInsets.fromLTRB(16, 5, 16, 5),
                        child: ListTile(
                          title: Text('${article['title'] ?? 'Untitled'}'),
                          subtitle: Text(
                              '${article['language'] ?? 'en'} · ${article['approved'] == true ? 'Approved' : 'Draft'}\n${article['body'] ?? ''}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis),
                          trailing: _canResolve
                              ? IconButton(
                                  tooltip: 'Edit article',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: _saving
                                      ? null
                                      : () => _editArticle(article))
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      );

  Widget _conversationList() => Column(
        children: [
          Expanded(
            child: _conversations.isEmpty
                ? const _EmptyPanel(
                    title: 'No conversations yet',
                    detail: 'New AI support conversations will appear here.')
                : ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final item = _conversations[index];
                      final customer = item['customer'] is Map
                          ? Map<String, dynamic>.from(item['customer'])
                          : <String, dynamic>{};
                      return Card(
                        margin: const EdgeInsets.fromLTRB(16, 5, 16, 5),
                        child: ListTile(
                          leading: const CircleAvatar(
                              child: Icon(Icons.person_outline)),
                          title: Text('${customer['fullName'] ?? 'Customer'}'),
                          subtitle: Text(
                              '${item['messageCount'] ?? 0} messages · ${item['updatedAt'] ?? 'Time unavailable'}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showConversation(item),
                        ),
                      );
                    },
                  ),
          ),
          if (_pages > 1)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                      onPressed: _page > 1
                          ? () async {
                              setState(() => _page--);
                              await _load();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left)),
                  Text('Page $_page of $_pages'),
                  IconButton(
                      onPressed: _page < _pages
                          ? () async {
                              setState(() => _page++);
                              await _load();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_right)),
                ],
              ),
            ),
        ],
      );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.title, required this.detail});
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined, size: 36),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(detail, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _ConversationDetail extends StatelessWidget {
  const _ConversationDetail({required this.conversation});
  final Map<String, dynamic> conversation;

  @override
  Widget build(BuildContext context) {
    final customer = conversation['customer'] is Map
        ? Map<String, dynamic>.from(conversation['customer'])
        : <String, dynamic>{};
    final raw = conversation['messages'];
    final messages = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    return Scaffold(
      appBar:
          AppBar(title: Text('${customer['fullName'] ?? 'AI conversation'}')),
      body: messages.isEmpty
          ? const _EmptyPanel(
              title: 'No messages',
              detail: 'This conversation has no visible messages.')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Read-only AI conversation'),
                    subtitle: Text(
                        'Reply to a customer through their support ticket. AI conversations do not replace secure ticket replies.'),
                  ),
                ),
                ...messages.map((message) {
                  final isCustomer =
                      '${message['role']}'.toUpperCase() == 'USER';
                  return Align(
                    alignment: isCustomer
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 620),
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: isCustomer
                            ? const Color(0xFFE5F2E9)
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isCustomer ? 'Customer' : 'AI assistant',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 5),
                          Text('${message['message'] ?? ''}'),
                          const SizedBox(height: 5),
                          Text('${message['createdAt'] ?? ''}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
