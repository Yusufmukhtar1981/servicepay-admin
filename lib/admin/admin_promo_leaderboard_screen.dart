import 'package:flutter/material.dart';

import 'admin_announcements_api.dart';
import 'admin_permissions.dart';

/// Head Office report for tracked promotion performance.
///
/// This report deliberately checks the participant permission before making
/// the first request.  It must not become an alternate way of browsing
/// customer data for admins who can only edit announcements.
class AdminPromoLeaderboardScreen extends StatefulWidget {
  const AdminPromoLeaderboardScreen({
    super.key,
    this.api,
    this.initialAccess,
    this.initialCampaignId,
  });

  final AdminAnnouncementsApi? api;
  final AdminAccess? initialAccess;
  final String? initialCampaignId;

  @override
  State<AdminPromoLeaderboardScreen> createState() =>
      _AdminPromoLeaderboardScreenState();
}

class _AdminPromoLeaderboardScreenState
    extends State<AdminPromoLeaderboardScreen> {
  late final AdminAnnouncementsApi _api;
  late final bool _ownsApi;
  final TextEditingController _search = TextEditingController();
  final TextEditingController _campaign = TextEditingController();
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();

  AdminAccess? _access;
  bool _loading = true;
  String? _error;
  String _range = 'campaign';
  String _status = 'ALL';
  int _page = 1;
  int _pages = 1;
  int _total = 0;
  static const int _limit = 25;
  String? _lastUpdated;
  Map<String, dynamic> _campaignData = <String, dynamic>{};
  Map<String, dynamic> _summary = <String, dynamic>{};
  List<Map<String, dynamic>> _participants = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _topParticipants = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? AdminAnnouncementsApi();
    _ownsApi = widget.api == null;
    _campaign.text = widget.initialCampaignId ?? '';
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _campaign.dispose();
    _from.dispose();
    _to.dispose();
    if (_ownsApi) _api.close();
    super.dispose();
  }

  bool _canView(AdminAccess access) => access.isHeadOffice;

  Future<void> _load({int? page}) async {
    final access = widget.initialAccess ?? await AdminSessionStore.loadAccess();
    if (!_canView(access)) {
      if (!mounted) return;
      setState(() {
        _access = access;
        _loading = false;
        _error = 'You do not have permission to view the promo leaderboard.';
      });
      return;
    }
    final requestedPage = page ?? _page;
    if (mounted) {
      setState(() {
        _access = access;
        _loading = true;
        _error = null;
        _page = requestedPage;
      });
    }
    try {
      final result = await _api.promoLeaderboard(
        campaignId: _campaign.text,
        range: _range,
        from: _range == 'custom' ? _from.text : null,
        to: _range == 'custom' ? _to.text : null,
        status: _status == 'ALL' ? null : _status,
        search: _search.text,
        page: requestedPage,
        limit: _limit,
      );
      final data = _map(result['data']) ?? result;
      final rawParticipants =
          data['participants'] ?? result['participants'] ?? const [];
      final rawTop =
          data['topParticipants'] ?? result['topParticipants'] ?? const [];
      final pagination = _map(data['pagination']) ?? _map(result['pagination']);
      final total = _integer(
        pagination?['total'] ?? data['total'] ?? result['total'],
        rawParticipants is List ? rawParticipants.length : 0,
      );
      final pages = _integer(
        pagination?['totalPages'] ??
            pagination?['pages'] ??
            data['totalPages'] ??
            result['totalPages'],
        total == 0 ? 1 : ((total + _limit - 1) ~/ _limit),
      );
      if (!mounted) return;
      setState(() {
        _campaignData = _map(data['campaign'] ?? result['campaign']) ?? {};
        _summary = _map(data['summary'] ?? result['summary']) ?? {};
        _participants = _maps(rawParticipants);
        _topParticipants = _maps(rawTop).take(5).toList();
        if (_topParticipants.isEmpty) {
          _topParticipants = _participants.take(5).toList();
        }
        _total = total;
        _pages = pages < 1 ? 1 : pages;
        _lastUpdated =
            (data['lastUpdated'] ?? result['lastUpdated'])?.toString();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _cleanError(error);
      });
    }
  }

  void _applyFilters() {
    _page = 1;
    _load(page: 1);
  }

  Future<void> _showDetail(Map<String, dynamic> participant) async {
    final customerId = _customerId(participant);
    if (customerId.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _LeaderboardDetailDialog(
        api: _api,
        customerId: customerId,
        customerName: _string(
            participant,
            [
              'name',
              'customerName',
            ],
            'Customer'),
        campaignId: _campaign.text,
        range: _range,
        from: _range == 'custom' ? _from.text : null,
        to: _range == 'custom' ? _to.text : null,
        status: _status == 'ALL' ? null : _status,
        search: _search.text,
      ),
    );
  }

  static Map<String, dynamic>? _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];

  static int _integer(dynamic value, [int fallback = 0]) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  static String _cleanError(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  static String _string(
    Map<String, dynamic> value,
    List<String> keys, [
    String fallback = '—',
  ]) {
    for (final key in keys) {
      final item = value[key];
      if (item != null && item.toString().trim().isNotEmpty) {
        return item.toString();
      }
    }
    return fallback;
  }

  static String _customerId(Map<String, dynamic> value) {
    final customer = value['customer'];
    final id = value['customerId'] ??
        (customer is Map ? customer['_id'] ?? customer['id'] : null) ??
        value['id'];
    return id?.toString() ?? '';
  }

  static double _progress(Map<String, dynamic> value) {
    final raw = value['progressPercentage'] ??
        value['progressPercent'] ??
        value['progress'] ??
        0;
    final number = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
    return (number > 1 ? number / 100 : number).clamp(0, 1);
  }

  static int _rank(Map<String, dynamic> value, int page, int localIndex) {
    final raw = value['rank'] ??
        value['globalRank'] ??
        value['globalPosition'] ??
        value['position'];
    final parsed = _integer(raw, 0);
    return parsed > 0 ? parsed : ((page - 1) * _limit) + localIndex + 1;
  }

  @override
  Widget build(BuildContext context) {
    if (_access != null && !_canView(_access!)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Promo Leaderboard')),
        body: _PermissionState(message: _error ?? 'Access denied.'),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('Promo Leaderboard'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF102A43),
        elevation: 0,
        actions: [
          if (_lastUpdated != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  'Updated ${_lastUpdated!}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(page: _page),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _participants.isEmpty
          ? const _LeaderboardSkeleton()
          : _error != null && _participants.isEmpty
              ? _ErrorState(message: _error!, retry: _applyFilters)
              : RefreshIndicator(
                  onRefresh: () => _load(page: _page),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _CampaignHeading(campaign: _campaignData),
                      const SizedBox(height: 14),
                      _SummaryCards(summary: _summary, total: _total),
                      const SizedBox(height: 18),
                      _LeaderboardFilters(
                        search: _search,
                        campaign: _campaign,
                        from: _from,
                        to: _to,
                        range: _range,
                        status: _status,
                        onApply: _applyFilters,
                        onRange: (value) {
                          setState(() => _range = value);
                          _applyFilters();
                        },
                        onStatus: (value) {
                          setState(() => _status = value);
                          _applyFilters();
                        },
                      ),
                      if (_error != null)
                        _InlineError(message: _error!, retry: _applyFilters),
                      const SizedBox(height: 16),
                      if (_topParticipants.isNotEmpty) ...[
                        _TopParticipants(
                          participants: _topParticipants,
                          onTap: _showDetail,
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (_loading) const LinearProgressIndicator(minHeight: 2),
                      if (_participants.isEmpty)
                        const _EmptyLeaderboard()
                      else
                        LayoutBuilder(
                          builder: (context, constraints) =>
                              constraints.maxWidth >= 820
                                  ? _LeaderboardTable(
                                      participants: _participants,
                                      page: _page,
                                      onTap: _showDetail,
                                    )
                                  : _LeaderboardCards(
                                      participants: _participants,
                                      page: _page,
                                      onTap: _showDetail,
                                    ),
                        ),
                      const SizedBox(height: 14),
                      _LeaderboardPagination(
                        page: _page,
                        pages: _pages,
                        total: _total,
                        onPage: (value) => _load(page: value),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _CampaignHeading extends StatelessWidget {
  const _CampaignHeading({required this.campaign});
  final Map<String, dynamic> campaign;
  @override
  Widget build(BuildContext context) {
    final name = campaign['name'] ?? campaign['title'];
    if (name == null || name.toString().trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      elevation: 0,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.campaign_outlined)),
        title: Text(
          name.toString(),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${campaign['status'] ?? 'Campaign'}${campaign['id'] == null ? '' : ' · ${campaign['id']}'}',
        ),
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.summary, required this.total});
  final Map<String, dynamic> summary;
  final int total;
  @override
  Widget build(BuildContext context) {
    final cards = <List<dynamic>>[
      ['Active participants', summary['activeParticipants'] ?? total],
      ['Qualified customers', summary['qualifiedCustomers'] ?? 0],
      ['Almost qualified', summary['almostQualified'] ?? 0],
      ['Rewards pending', summary['rewardsPending'] ?? 0],
      ['Rewards paid', summary['rewardsPaid'] ?? 0],
      ['Eligible transactions', summary['totalEligibleTransactions'] ?? 0],
      ['Transaction value', summary['totalEligibleTransactionValue'] ?? 0],
      ['Conversion rate', '${summary['conversionRate'] ?? 0}%'],
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards
          .map(
            (card) => Container(
              width: 178,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDCE7E3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card[0].toString(),
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    card[1].toString(),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _LeaderboardFilters extends StatelessWidget {
  const _LeaderboardFilters({
    required this.search,
    required this.campaign,
    required this.from,
    required this.to,
    required this.range,
    required this.status,
    required this.onApply,
    required this.onRange,
    required this.onStatus,
  });
  final TextEditingController search;
  final TextEditingController campaign;
  final TextEditingController from;
  final TextEditingController to;
  final String range;
  final String status;
  final VoidCallback onApply;
  final ValueChanged<String> onRange;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 210,
                child: TextField(
                  controller: campaign,
                  onSubmitted: (_) => onApply(),
                  decoration: const InputDecoration(
                    labelText: 'Campaign ID',
                    prefixIcon: Icon(Icons.campaign_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 145,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: range,
                  decoration: const InputDecoration(
                    labelText: 'Date range',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'campaign', child: Text('Campaign')),
                    DropdownMenuItem(value: 'today', child: Text('Today')),
                    DropdownMenuItem(value: 'week', child: Text('This week')),
                    DropdownMenuItem(value: 'month', child: Text('This month')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom')),
                  ],
                  onChanged: (value) {
                    if (value != null) onRange(value);
                  },
                ),
              ),
              SizedBox(
                width: 155,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('All statuses')),
                    DropdownMenuItem(
                        value: 'QUALIFIED', child: Text('Qualified')),
                    DropdownMenuItem(
                      value: 'ALMOST_QUALIFIED',
                      child: Text('Almost qualified'),
                    ),
                    DropdownMenuItem(
                      value: 'IN_PROGRESS',
                      child: Text('In progress'),
                    ),
                    DropdownMenuItem(
                      value: 'REWARD_PENDING',
                      child: Text('Reward pending'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) onStatus(value);
                  },
                ),
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: search,
                  onSubmitted: (_) => onApply(),
                  decoration: const InputDecoration(
                    labelText: 'Search name or identifier',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (range == 'custom') ...[
                SizedBox(
                  width: 165,
                  child: TextField(
                    controller: from,
                    decoration: const InputDecoration(
                      labelText: 'From (ISO date)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 165,
                  child: TextField(
                    controller: to,
                    decoration: const InputDecoration(
                      labelText: 'To (ISO date)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
              FilledButton.icon(
                onPressed: onApply,
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Apply filters'),
              ),
            ],
          ),
        ),
      );
}

class _TopParticipants extends StatelessWidget {
  const _TopParticipants({required this.participants, required this.onTap});
  final List<Map<String, dynamic>> participants;
  final ValueChanged<Map<String, dynamic>> onTap;
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Top 5 promo participants',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...participants.take(5).toList().asMap().entries.map((entry) {
                final item = entry.value;
                return _ParticipantRow(
                  participant: item,
                  rank: entry.key + 1,
                  onTap: () => onTap(item),
                );
              }),
            ],
          ),
        ),
      );
}

/// Compact dashboard presentation.  The dashboard owns fetching and passes
/// the already permission-checked records to this widget.
class AdminPromoLeaderboardTop5 extends StatelessWidget {
  const AdminPromoLeaderboardTop5({
    super.key,
    required this.participants,
    required this.onViewFullLeaderboard,
    this.loading = false,
    this.error,
    this.onRetry,
  });
  final List<Map<String, dynamic>> participants;
  final VoidCallback onViewFullLeaderboard;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Top Promo Participants',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: onViewFullLeaderboard,
                    child: const Text('View Full Leaderboard'),
                  ),
                ],
              ),
              if (loading)
                const LinearProgressIndicator()
              else if (error != null)
                _InlineError(message: error!, retry: onRetry ?? () {})
              else if (participants.isEmpty)
                const Text('No promotion participants yet.')
              else
                ...participants.take(5).toList().asMap().entries.map(
                      (entry) => _ParticipantRow(
                        participant: entry.value,
                        rank: entry.key + 1,
                      ),
                    ),
            ],
          ),
        ),
      );
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.rank,
    this.onTap,
  });
  final Map<String, dynamic> participant;
  final int rank;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final name = _AdminPromoLeaderboardScreenState._string(
        participant,
        [
          'name',
          'customerName',
        ],
        'Customer');
    final progress = _AdminPromoLeaderboardScreenState._progress(participant);
    final count = participant['eligibleTransactionCount'] ??
        participant['transactionCount'] ??
        0;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _RankBadge(rank: rank),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: LinearProgressIndicator(value: progress, minHeight: 5),
      ),
      trailing: Text('$count txns'),
      onTap: onTap,
    );
  }
}

class _LeaderboardCards extends StatelessWidget {
  const _LeaderboardCards({
    required this.participants,
    required this.page,
    required this.onTap,
  });
  final List<Map<String, dynamic>> participants;
  final int page;
  final ValueChanged<Map<String, dynamic>> onTap;
  @override
  Widget build(BuildContext context) => Column(
        children: participants
            .asMap()
            .entries
            .map(
              (entry) => Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => onTap(entry.value),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: _ParticipantDetails(
                      participant: entry.value,
                      rank: _AdminPromoLeaderboardScreenState._rank(
                        entry.value,
                        page,
                        entry.key,
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      );
}

class _ParticipantDetails extends StatelessWidget {
  const _ParticipantDetails({required this.participant, required this.rank});
  final Map<String, dynamic> participant;

  /// One-based global leaderboard rank.
  final int rank;
  @override
  Widget build(BuildContext context) {
    final progress = _AdminPromoLeaderboardScreenState._progress(participant);
    final target = participant['qualificationTargetCount'] ?? '—';
    final count = participant['eligibleTransactionCount'] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _RankBadge(rank: rank),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _AdminPromoLeaderboardScreenState._string(participant, [
                  'name',
                  'customerName',
                ]),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            _StatusChip(
              status: _AdminPromoLeaderboardScreenState._string(
                  participant,
                  [
                    'status',
                  ],
                  'IN_PROGRESS'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: progress, minHeight: 7),
        const SizedBox(height: 7),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            Text('${(progress * 100).round()}% progress'),
            Text('$count / $target transactions'),
            Text(
              'Value ${_AdminPromoLeaderboardScreenState._string(participant, [
                    'totalEligibleTransactionValue'
                  ])}',
            ),
            Text(
              'Campaign ${_AdminPromoLeaderboardScreenState._string(participant, [
                    'campaignName'
                  ])}',
            ),
          ],
        ),
      ],
    );
  }
}

class _LeaderboardTable extends StatelessWidget {
  const _LeaderboardTable({
    required this.participants,
    required this.page,
    required this.onTap,
  });
  final List<Map<String, dynamic>> participants;
  final int page;
  final ValueChanged<Map<String, dynamic>> onTap;
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('#')),
              DataColumn(label: Text('Participant')),
              DataColumn(label: Text('Campaign')),
              DataColumn(label: Text('Progress')),
              DataColumn(label: Text('Transactions')),
              DataColumn(label: Text('Value')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Last eligible transaction')),
            ],
            rows: participants.asMap().entries.map((entry) {
              final item = entry.value;
              final progress =
                  _AdminPromoLeaderboardScreenState._progress(item);
              return DataRow(
                onSelectChanged: (_) => onTap(item),
                cells: [
                  DataCell(
                    _RankBadge(
                      rank: _AdminPromoLeaderboardScreenState._rank(
                        item,
                        page,
                        entry.key,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      _AdminPromoLeaderboardScreenState._string(item, [
                        'name',
                        'customerName',
                      ]),
                    ),
                  ),
                  DataCell(
                    Text(
                      _AdminPromoLeaderboardScreenState._string(item, [
                        'campaignName',
                      ]),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 130,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LinearProgressIndicator(
                              value: progress, minHeight: 6),
                          Text('${(progress * 100).round()}%'),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${item['eligibleTransactionCount'] ?? 0} / ${item['qualificationTargetCount'] ?? '—'}',
                    ),
                  ),
                  DataCell(
                    Text(
                      _AdminPromoLeaderboardScreenState._string(item, [
                        'totalEligibleTransactionValue',
                      ]),
                    ),
                  ),
                  DataCell(
                    _StatusChip(
                      status: _AdminPromoLeaderboardScreenState._string(
                          item,
                          [
                            'status',
                          ],
                          'IN_PROGRESS'),
                    ),
                  ),
                  DataCell(
                    Text(
                      _AdminPromoLeaderboardScreenState._string(item, [
                        'lastEligibleTransactionAt',
                      ]),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      );
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;
  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFFFFC107),
      const Color(0xFF90A4AE),
      const Color(0xFFCD7F32),
    ];
    return CircleAvatar(
      radius: 16,
      backgroundColor: rank < 3 ? colors[rank] : const Color(0xFFEAF0F5),
      child: Text(
        '${rank + 1}',
        style: TextStyle(
          color: rank < 3 ? Colors.white : const Color(0xFF102A43),
          fontWeight: FontWeight.w800,
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
        label: Text(status.replaceAll('_', ' ')),
        visualDensity: VisualDensity.compact,
        backgroundColor: status == 'QUALIFIED'
            ? const Color(0xFFDFF3E8)
            : const Color(0xFFEAF0F5),
      );
}

class _LeaderboardPagination extends StatelessWidget {
  const _LeaderboardPagination({
    required this.page,
    required this.pages,
    required this.total,
    required this.onPage,
  });
  final int page;
  final int pages;
  final int total;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: page > 1 ? () => onPage(page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('Page $page of $pages · $total participants'),
          IconButton(
            onPressed: page < pages ? () => onPage(page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      );
}

class _LeaderboardDetailDialog extends StatefulWidget {
  const _LeaderboardDetailDialog({
    required this.api,
    required this.customerId,
    required this.customerName,
    required this.campaignId,
    required this.range,
    required this.from,
    required this.to,
    required this.status,
    required this.search,
  });
  final AdminAnnouncementsApi api;
  final String customerId;
  final String customerName;
  final String campaignId;
  final String range;
  final String? from;
  final String? to;
  final String? status;
  final String search;

  @override
  State<_LeaderboardDetailDialog> createState() =>
      _LeaderboardDetailDialogState();
}

class _LeaderboardDetailDialogState extends State<_LeaderboardDetailDialog> {
  static const int _limit = 25;
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _pages = 1;
  int _total = 0;
  Map<String, dynamic> _data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([int? requestedPage]) async {
    final page = requestedPage ?? _page;
    if (mounted) {
      setState(() {
        _page = page;
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await widget.api.promoLeaderboardDetail(
        widget.customerId,
        campaignId: widget.campaignId,
        range: widget.range,
        from: widget.from,
        to: widget.to,
        status: widget.status,
        search: widget.search,
        page: page,
        limit: _limit,
      );
      final data =
          _AdminPromoLeaderboardScreenState._map(result['data']) ?? result;
      final pagination = _AdminPromoLeaderboardScreenState._map(
            data['pagination'] ??
                data['eligibleTransactionsPagination'] ??
                result['pagination'],
          ) ??
          <String, dynamic>{};
      final total = _AdminPromoLeaderboardScreenState._integer(
        pagination['total'] ?? data['total'],
      );
      final pages = _AdminPromoLeaderboardScreenState._integer(
        pagination['totalPages'] ??
            pagination['pages'] ??
            data['totalPages'] ??
            result['totalPages'],
        total == 0 ? 1 : ((total + _limit - 1) ~/ _limit),
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _total = total;
        _pages = pages < 1 ? 1 : pages;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.customerName),
        content: SizedBox(
          width: 620,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: _loading
                ? const Center(
                    child: SizedBox(
                      height: 150,
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _error != null
                    ? Text(_error!)
                    : SingleChildScrollView(child: _DetailContent(data: _data)),
          ),
        ),
        actions: [
          if (!_loading && _error == null && _pages > 1)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Page $_page of $_pages · $_total transactions'),
                TextButton(
                  onPressed: _page > 1 ? () => _load(_page - 1) : null,
                  child: const Text('Previous'),
                ),
                TextButton(
                  onPressed: _page < _pages ? () => _load(_page + 1) : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final customer = _AdminPromoLeaderboardScreenState._map(data['customer']);
    final progress = _AdminPromoLeaderboardScreenState._map(data['progress']);
    final requirements = _AdminPromoLeaderboardScreenState._map(
      data['requirements'],
    );
    final reward = _AdminPromoLeaderboardScreenState._map(data['reward']);
    final transactions = _AdminPromoLeaderboardScreenState._maps(
      data['eligibleTransactions'],
    );
    final count = data['eligibleTransactionCount'] ??
        progress?['eligibleTransactionCount'] ??
        0;
    final value = data['eligibleTransactionValue'] ??
        data['totalEligibleTransactionValue'] ??
        0;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (customer != null)
            Text(
              '${customer['name'] ?? customer['fullName'] ?? 'Customer'} · ${customer['maskedIdentifier'] ?? ''}',
            ),
          const SizedBox(height: 12),
          _DetailLine(
            'Campaign',
            _text(data['campaign'] ?? data['campaignName']),
          ),
          _DetailLine(
            'Requirements',
            _text(requirements ?? data['requirements']),
          ),
          _DetailLine('Progress', _text(progress ?? data['progress'])),
          _DetailLine('Eligible transactions', '$count'),
          _DetailLine('Eligible value', '$value'),
          _DetailLine(
            'Qualification date',
            '${data['qualificationDate'] ?? 'Not qualified'}',
          ),
          _DetailLine('Reward', reward == null ? 'No reward' : _text(reward)),
          const Divider(height: 24),
          const Text(
            'Eligible transactions',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          if (transactions.isEmpty)
            const Text('No eligible transactions on this page.')
          else
            ...transactions.map(
              (transaction) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${transaction['type'] ?? 'Transaction'}'),
                subtitle: Text(
                  '${transaction['createdAt'] ?? transaction['date'] ?? ''}',
                ),
                trailing: Text(
                  '${transaction['amount'] ?? transaction['value'] ?? ''}',
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _text(dynamic value) {
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join(' · ');
    }
    return value?.toString() ?? '—';
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

class _LeaderboardSkeleton extends StatelessWidget {
  const _LeaderboardSkeleton();
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(
              8,
              (_) => Container(
                width: 178,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(height: 150, color: Colors.white),
          const SizedBox(height: 18),
          ...List.generate(
            5,
            (_) => const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Card(child: SizedBox(height: 76)),
            ),
          ),
        ],
      );
}

class _EmptyLeaderboard extends StatelessWidget {
  const _EmptyLeaderboard();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 65),
        child: Column(
          children: [
            Icon(Icons.emoji_events_outlined, size: 52, color: Colors.black38),
            SizedBox(height: 12),
            Text(
              'No promo participants found',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 5),
            Text('Try changing the campaign, date range, or filters.'),
          ],
        ),
      );
}

class _PermissionState extends StatelessWidget {
  const _PermissionState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) =>
      Center(child: Text(message, textAlign: TextAlign.center));
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(onPressed: retry, child: const Text('Retry')),
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
        child: Row(
          children: [
            Expanded(child: Text(message)),
            TextButton(onPressed: retry, child: const Text('Retry')),
          ],
        ),
      );
}
