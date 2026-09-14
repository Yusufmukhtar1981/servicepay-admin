import 'package:flutter/material.dart';

import 'admin_announcements_api.dart';
import 'admin_permissions.dart';

/// Admin workspace for the participant and winner side of a tracked campaign.
///
/// This is deliberately separate from the announcement editor so contact data
/// and irreversible winner actions remain behind their own permissions.
class AdminPromoParticipantsScreen extends StatefulWidget {
  const AdminPromoParticipantsScreen({
    super.key,
    required this.announcementId,
    this.announcementTitle,
    this.api,
    this.initialAccess,
  });

  final String announcementId;
  final String? announcementTitle;
  final AdminAnnouncementsApi? api;
  final AdminAccess? initialAccess;

  @override
  State<AdminPromoParticipantsScreen> createState() =>
      _AdminPromoParticipantsScreenState();
}

class _AdminPromoParticipantsScreenState
    extends State<AdminPromoParticipantsScreen> {
  late final AdminAnnouncementsApi _api;
  bool _ownsApi = false;
  bool _loading = true;
  bool _historyLoading = false;
  String? _error;
  String? _historyError;
  AdminAccess? _access;
  List<Map<String, dynamic>> _participants = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  Map<String, dynamic> _summary = <String, dynamic>{};
  int _page = 1;
  int _pages = 1;
  int _total = 0;
  static const int _limit = 25;
  String _status = 'ALL';
  String _sort = 'progress';
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? AdminAnnouncementsApi();
    _ownsApi = widget.api == null;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    if (_ownsApi) _api.close();
    super.dispose();
  }

  bool _can(String permission) => _access?.has(permission) == true;

  bool get _canHistory =>
      _can(AdminPermissions.announcementsParticipantsHistoryView) ||
      _can(AdminPermissions.announcementsWinnersView);

  Future<void> _load({int? page}) async {
    final access = widget.initialAccess ?? await AdminSessionStore.loadAccess();
    if (!access.has(AdminPermissions.announcementsParticipantsView)) {
      if (!mounted) return;
      setState(() {
        _access = access;
        _loading = false;
        _error = 'You do not have permission to view promotion participants.';
      });
      return;
    }
    final requestedPage = page ?? _page;
    setState(() {
      _loading = true;
      _error = null;
      _access = access;
      _page = requestedPage;
    });
    try {
      final result = await _api.participants(
        widget.announcementId,
        search: _search.text,
        status: _status == 'ALL' ? null : _status,
        page: requestedPage,
        limit: _limit,
        sort: _sort,
      );
      final data = result['data'] is Map
          ? Map<String, dynamic>.from(result['data'] as Map)
          : result;
      final raw = data['participants'] ?? result['participants'];
      final pagination = data['pagination'] is Map
          ? Map<String, dynamic>.from(data['pagination'] as Map)
          : <String, dynamic>{};
      final rawSummary = data['summary'] ?? result['summary'];
      final total =
          _integer(pagination['total'] ?? data['total'] ?? result['total'], 0);
      final pages = _integer(
        pagination['pages'] ??
            pagination['totalPages'] ??
            data['pages'] ??
            result['pages'],
        total == 0 ? 1 : ((total + _limit - 1) ~/ _limit),
      );
      if (!mounted) return;
      setState(() {
        _participants = raw is List
            ? raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
            : <Map<String, dynamic>>[];
        _summary = rawSummary is Map
            ? Map<String, dynamic>.from(rawSummary)
            : <String, dynamic>{};
        _total = total;
        _pages = pages < 1 ? 1 : pages;
        _loading = false;
      });
      if (_canHistory && _history.isEmpty && !_historyLoading) {
        _loadHistory();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _cleanError(e);
        });
      }
    }
  }

  Future<void> _loadHistory() async {
    if (!_canHistory) return;
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final result = await _api.winnersHistory(widget.announcementId);
      final data = result['data'] is Map
          ? Map<String, dynamic>.from(result['data'] as Map)
          : result;
      final raw = data['winners'] ?? data['history'] ?? result['winners'];
      if (!mounted) return;
      setState(() {
        _history = raw is List
            ? raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
            : <Map<String, dynamic>>[];
        _historyLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _historyLoading = false;
          _historyError = _cleanError(e);
        });
      }
    }
  }

  void _applyFilters() {
    _page = 1;
    _load(page: 1);
  }

  Future<void> _markWinner(Map<String, dynamic> participant) async {
    if (!_can(AdminPermissions.announcementsWinnerManage) ||
        _participantStatus(participant) != 'QUALIFIED') {
      return;
    }
    final customerId = _customerId(participant);
    if (customerId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm winner'),
        content: const Text(confirmWinnerText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mark Winner'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.markWinner(widget.announcementId, customerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Winner confirmed.')));
      await _load(page: _page);
      if (_canHistory) await _loadHistory();
    } catch (e) {
      if (mounted) _showError(e);
    }
  }

  void _showError(Object error) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(_cleanError(error))));

  static String _cleanError(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  static int _integer(dynamic value, int fallback) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  static String _customerId(Map<String, dynamic> value) {
    final customer = value['customer'];
    final id = value['customerId'] ??
        (customer is Map ? customer['_id'] ?? customer['id'] : null) ??
        value['_id'] ??
        value['id'];
    return id?.toString() ?? '';
  }

  static String _participantStatus(Map<String, dynamic> value) =>
      (value['progressStatus'] ??
              value['status'] ??
              value['qualificationStatus'] ??
              '')
          .toString()
          .toUpperCase()
          .replaceAll('-', '_')
          .replaceAll(' ', '_')
          .replaceAll('NOT_QUALIFIED', 'IN_PROGRESS');

  static String _displayValue(Map<String, dynamic> value, List<String> keys,
      [String fallback = '—']) {
    for (final key in keys) {
      final raw = value[key];
      if (raw != null && raw.toString().trim().isNotEmpty) return '$raw';
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.announcementTitle?.trim().isNotEmpty == true
        ? widget.announcementTitle!.trim()
        : 'Promotion participants';
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF102A43),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(page: _page),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _participants.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _participants.isEmpty
              ? _ErrorView(message: _error!, retry: () => _load(page: _page))
              : RefreshIndicator(
                  onRefresh: () => _load(page: _page),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _SummaryMetrics(summary: _summary, total: _total),
                      const SizedBox(height: 18),
                      _Filters(
                        search: _search,
                        status: _status,
                        sort: _sort,
                        onSearch: _applyFilters,
                        onStatus: (value) {
                          setState(() => _status = value);
                          _applyFilters();
                        },
                        onSort: (value) {
                          setState(() => _sort = value);
                          _applyFilters();
                        },
                      ),
                      const SizedBox(height: 18),
                      if (_error != null)
                        _InlineError(message: _error!, retry: _applyFilters),
                      if (_participants.isEmpty)
                        const _EmptyParticipants()
                      else
                        LayoutBuilder(
                          builder: (context, constraints) =>
                              constraints.maxWidth >= 760
                                  ? _ParticipantsTable(
                                      participants: _participants,
                                      canWin: _can(
                                          AdminPermissions.announcementsWinnerManage),
                                      onWinner: _markWinner,
                                    )
                                  : _ParticipantCards(
                                      participants: _participants,
                                      canWin: _can(
                                          AdminPermissions.announcementsWinnerManage),
                                      onWinner: _markWinner,
                                    ),
                        ),
                      const SizedBox(height: 16),
                      _Pagination(
                        page: _page,
                        pages: _pages,
                        onPage: (page) => _load(page: page),
                      ),
                      if (_canHistory) ...[
                        const SizedBox(height: 28),
                        _WinnerHistory(
                          history: _history,
                          loading: _historyLoading,
                          error: _historyError,
                          retry: _loadHistory,
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

const String confirmWinnerText =
    'Confirm this customer as a Smartphone Reward winner?';

class _SummaryMetrics extends StatelessWidget {
  const _SummaryMetrics({required this.summary, required this.total});
  final Map<String, dynamic> summary;
  final int total;

  @override
  Widget build(BuildContext context) {
    final values = <List<dynamic>>[
      [
        'Participants',
        summary['totalParticipants'] ??
            summary['participants'] ??
            summary['total'] ??
            total
      ],
      [
        'Qualified',
        summary['qualifiedCustomers'] ??
            summary['qualified'] ??
            summary['qualifiedCount'] ??
            0
      ],
      ['Qualification rate', _formatPercentage(summary['qualificationRate'])],
      [
        'In progress',
        summary['inProgressCustomers'] ??
            summary['inProgress'] ??
            summary['inProgressCount'] ??
            0
      ],
      [
        'Value',
        summary['totalQualifyingTransactionValue'] ??
            summary['value'] ??
            summary['totalValue'] ??
            summary['totalTransactionValue'] ??
            0
      ],
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: values
          .map((item) => Container(
                width: 170,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDCE7E3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item[0]}',
                        style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 7),
                    Text('${item[1]}',
                        style: const TextStyle(
                            fontSize: 23, fontWeight: FontWeight.w800)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  String _formatPercentage(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '—';
    final normalized = raw.endsWith('%')
        ? raw.substring(0, raw.length - 1).trim()
        : raw;
    final number = num.tryParse(normalized);
    if (number == null) return raw.endsWith('%') ? raw : '$raw%';
    final formatted = number % 1 == 0
        ? number.toInt().toString()
        : number.toString();
    return '$formatted%';
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.search,
    required this.status,
    required this.sort,
    required this.onSearch,
    required this.onStatus,
    required this.onSort,
  });
  final TextEditingController search;
  final String status;
  final String sort;
  final VoidCallback onSearch;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 250,
                child: TextField(
                  controller: search,
                  onSubmitted: (_) => onSearch(),
                  decoration: InputDecoration(
                    labelText: 'Search participants',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                        onPressed: onSearch, icon: const Icon(Icons.tune)),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 145,
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: status,
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('All statuses')),
                    DropdownMenuItem(
                        value: 'QUALIFIED', child: Text('Qualified')),
                    DropdownMenuItem(
                        value: 'IN_PROGRESS', child: Text('In progress')),
                  ],
                  onChanged: (value) {
                    if (value != null) onStatus(value);
                  },
                ),
              ),
              SizedBox(
                width: 145,
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: sort,
                  items: const [
                    DropdownMenuItem(
                        value: 'progress', child: Text('Sort: Progress')),
                    DropdownMenuItem(
                        value: 'value', child: Text('Sort: Value')),
                    DropdownMenuItem(
                        value: 'qualifiedAt',
                        child: Text('Sort: Qualification date')),
                  ],
                  onChanged: (value) {
                    if (value != null) onSort(value);
                  },
                ),
              ),
            ],
          ),
        ),
      );
}

class _ParticipantCards extends StatelessWidget {
  const _ParticipantCards(
      {required this.participants,
      required this.canWin,
      required this.onWinner});
  final List<Map<String, dynamic>> participants;
  final bool canWin;
  final ValueChanged<Map<String, dynamic>> onWinner;

  @override
  Widget build(BuildContext context) => Column(
        children: participants
            .map((participant) => _ParticipantCard(
                participant: participant, canWin: canWin, onWinner: onWinner))
            .toList(),
      );
}

class _ParticipantCard extends StatelessWidget {
  const _ParticipantCard(
      {required this.participant,
      required this.canWin,
      required this.onWinner});
  final Map<String, dynamic> participant;
  final bool canWin;
  final ValueChanged<Map<String, dynamic>> onWinner;

  @override
  Widget build(BuildContext context) {
    final status =
        _AdminPromoParticipantsScreenState._participantStatus(participant);
    final display = _AdminPromoParticipantsScreenState._displayValue;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  display(participant, ['name', 'fullName', 'customerName']),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _StatusChip(status: status),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                Text('Progress ${display(participant, [
                  'progress',
                  'progressPercent'
                ])}'),
                Text('Transactions ${display(participant, [
                  'transactionCount'
                ])}'),
                Text('Value ${display(participant, [
                  'transactionValue',
                  'value',
                  'amount',
                  'totalValue'
                ])}'),
                Text('Count progress ${display(participant, [
                  'countPercentage'
                ])}%'),
                Text('Value progress ${display(participant, [
                  'valuePercentage'
                ])}%'),
                Text('Qualified ${display(participant, [
                  'qualifiedAt',
                  'qualificationDate'
                ])}'),
                if (participant['email'] != null)
                  Text('Email ${participant['email']}'),
                if (participant['phone'] != null)
                  Text('Phone ${participant['phone']}'),
              ],
            ),
            if (canWin && status == 'QUALIFIED') ...[
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => onWinner(participant),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Mark Winner'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ParticipantsTable extends StatelessWidget {
  const _ParticipantsTable(
      {required this.participants,
      required this.canWin,
      required this.onWinner});
  final List<Map<String, dynamic>> participants;
  final bool canWin;
  final ValueChanged<Map<String, dynamic>> onWinner;

  @override
  Widget build(BuildContext context) {
    final display = _AdminPromoParticipantsScreenState._displayValue;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Participant')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Progress')),
            DataColumn(label: Text('Transactions')),
            DataColumn(label: Text('Value')),
            DataColumn(label: Text('Count %')),
            DataColumn(label: Text('Value %')),
            DataColumn(label: Text('Qualification date')),
            DataColumn(label: Text('Action')),
          ],
          rows: participants.map((participant) {
            final status =
                _AdminPromoParticipantsScreenState._participantStatus(
                    participant);
            return DataRow(cells: [
              DataCell(Text(display(
                  participant, ['name', 'fullName', 'customerName']))),
              DataCell(_StatusChip(status: status)),
              DataCell(Text(display(participant, ['progress', 'progressPercent']))),
              DataCell(Text(display(participant, ['transactionCount']))),
              DataCell(Text(display(participant,
                  ['transactionValue', 'value', 'amount', 'totalValue']))),
              DataCell(Text('${display(participant, [
                'countPercentage'
              ])}%')),
              DataCell(Text('${display(participant, [
                'valuePercentage'
              ])}%')),
              DataCell(Text(display(
                  participant, ['qualifiedAt', 'qualificationDate']))),
              DataCell(canWin && status == 'QUALIFIED'
                  ? TextButton(
                      onPressed: () => onWinner(participant),
                      child: const Text('Mark Winner'))
                  : const SizedBox.shrink()),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => Chip(
        label: Text(status.isEmpty ? 'UNKNOWN' : status),
        backgroundColor: status == 'QUALIFIED'
            ? const Color(0xFFDFF3E8)
            : const Color(0xFFEAF0F5),
        visualDensity: VisualDensity.compact,
      );
}

class _Pagination extends StatelessWidget {
  const _Pagination(
      {required this.page, required this.pages, required this.onPage});
  final int page;
  final int pages;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
              onPressed: page > 1 ? () => onPage(page - 1) : null,
              icon: const Icon(Icons.chevron_left)),
          Text('Page $page of $pages'),
          IconButton(
              onPressed: page < pages ? () => onPage(page + 1) : null,
              icon: const Icon(Icons.chevron_right)),
        ],
      );
}

class _WinnerHistory extends StatelessWidget {
  const _WinnerHistory(
      {required this.history,
      required this.loading,
      required this.error,
      required this.retry});
  final List<Map<String, dynamic>> history;
  final bool loading;
  final String? error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Winner history',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (loading)
                const LinearProgressIndicator()
              else if (error != null)
                _InlineError(message: error!, retry: retry)
              else if (history.isEmpty)
                const Text('No winners have been confirmed.')
              else
                ...history.map((winner) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.emoji_events_outlined),
                      title: Text(_winnerName(winner)),
                      subtitle: Text(_winnerSubtitle(winner)),
                    )),
            ],
          ),
        ),
      );

  String _winnerName(Map<String, dynamic> winner) {
    final customer = winner['customerId'];
    if (customer is Map) {
      final name = customer['fullName'] ?? customer['name'];
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString();
      }
    }
    return _AdminPromoParticipantsScreenState._displayValue(
        winner, ['name', 'fullName', 'customerName']);
  }

  String _winnerSubtitle(Map<String, dynamic> winner) {
    final timestamp =
        winner['markedAt'] ?? winner['confirmedAt'] ?? winner['winnerAt'];
    final markedBy = winner['markedBy'];
    final admin = markedBy is Map
        ? (markedBy['fullName'] ?? markedBy['email'])
        : markedBy;
    final values = <String>[
      if (timestamp != null) timestamp.toString(),
      if (admin != null && admin.toString().trim().isNotEmpty)
        'Confirmed by ${admin.toString()}',
    ];
    return values.isEmpty ? 'Winner record' : values.join(' · ');
  }
}

class _EmptyParticipants extends StatelessWidget {
  const _EmptyParticipants();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 70),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 52, color: Colors.black38),
            SizedBox(height: 12),
            Text('No promotion participants found',
                style: TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(height: 5),
            Text('Try changing the search or status filter.'),
          ],
        ),
      );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: Text(message)),
          TextButton(onPressed: retry, child: const Text('Retry')),
        ]),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 44),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton(onPressed: retry, child: const Text('Retry')),
        ]),
      );
}