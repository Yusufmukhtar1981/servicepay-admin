import 'package:flutter/material.dart';

import 'admin_staff_workspace_api.dart';

/// Read-only operational visibility for sampled DATA, AIRTIME and ELECTRICITY
/// transactions and the all-age unresolved verification queue.
class AdminTransactionReliabilityPanel extends StatefulWidget {
  const AdminTransactionReliabilityPanel({
    super.key,
    required this.api,
  });

  final AdminStaffWorkspaceApi api;

  @override
  AdminTransactionReliabilityPanelState createState() =>
      AdminTransactionReliabilityPanelState();
}

class AdminTransactionReliabilityPanelState
    extends State<AdminTransactionReliabilityPanel> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String _error = '';
  int _page = 1;
  int _total = 0;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
      : <Map<String, dynamic>>[];

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<void> _load({int page = 1}) async {
    final int generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = '';
      _page = page;
    });
    try {
      final Map<String, dynamic> response =
          await widget.api.reliability(page: page);
      final Map<String, dynamic> data = _map(response['data']);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _data = data;
        _total = (data['total'] as num?)?.toInt() ?? 0;
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> refresh() => _load(page: _page);

  String _metric(dynamic value, {String suffix = ''}) =>
      value is num ? '${value.toString()}$suffix' : 'Not recorded';

  Widget _metricBlock(String label, String value, {String? note}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xff53666a),
                        fontWeight: FontWeight.w600,
                      )),
              const SizedBox(height: 4),
              Text(value,
                  softWrap: true,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xff18383b),
                        fontWeight: FontWeight.w800,
                      )),
              if (note != null) ...[
                const SizedBox(height: 2),
                Text(note, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      );

  Widget _sectionLabel(String title, {String? trailing}) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xff18383b),
                        fontWeight: FontWeight.w800,
                      )),
            ),
            if (trailing != null)
              Text(trailing,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xff53666a),
                      )),
          ],
        ),
      );

  Widget _metricPair(String leftLabel, dynamic leftValue, String rightLabel,
      dynamic rightValue) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metricBlock(leftLabel, '$leftValue'),
          _metricBlock(rightLabel, '$rightValue'),
        ],
      );

  Color _severityColor(String severity) {
    switch (severity.toUpperCase()) {
      case 'HIGH':
      case 'CRITICAL':
        return const Color(0xffa13d35);
      case 'MEDIUM':
      case 'WARNING':
        return const Color(0xff8a5a19);
      default:
        return const Color(0xff356b55);
    }
  }

  Widget _alert(Map<String, dynamic> alert) {
    final Color color = _severityColor('${alert['severity'] ?? ''}');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Text('${alert['severity'] ?? 'INFO'}',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w800, fontSize: 12)),
              Text('${alert['code'] ?? 'Operational alert'}',
                  style: const TextStyle(
                      color: Color(0xff18383b), fontWeight: FontWeight.w700)),
              if (alert['count'] != null)
                Text('Count ${alert['count']}',
                    style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text('${alert['message'] ?? ''}'),
        ],
      ),
    );
  }

  Widget _queueItem(Map<String, dynamic> item) {
    final String reference =
        '${item['reference'] ?? item['id'] ?? 'Transaction'}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xfff4f7f4),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xffdce6df)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reference,
              softWrap: true,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                  color: Color(0xff18383b), fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 7,
            runSpacing: 3,
            children: [
              Text('${item['type'] ?? 'Service'}'),
              Text('· ${item['provider'] ?? 'Provider not recorded'}'),
              Text('· ${item['financialStatus'] ?? 'Status unavailable'}'),
            ],
          ),
          if (item['lifecycleState'] != null ||
              item['reasonCode'] != null ||
              item['walletStatus'] != null) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 3,
              children: [
                if (item['lifecycleState'] != null)
                  Text('Lifecycle ${item['lifecycleState']}'),
                if (item['reasonCode'] != null)
                  Text('Reason ${item['reasonCode']}'),
                if (item['walletStatus'] != null)
                  Text('Wallet ${item['walletStatus']}'),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Attempts ${item['verificationAttempts'] ?? 0}'
            '${item['lastCheckedAt'] == null ? '' : ' · Checked ${item['lastCheckedAt']}'}'
            '${item['nextCheckAt'] == null ? '' : ' · Next ${item['nextCheckAt']}'}',
            softWrap: true,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> summary = _map(_data['summary']);
    final Map<String, dynamic> backlog = _map(_data['backlog']);
    final List<Map<String, dynamic>> alerts = _maps(_data['alerts']);
    final List<Map<String, dynamic>> providers = _maps(_data['providers']);
    final List<Map<String, dynamic>> items = _maps(_data['items']);
    final int window = (_data['windowHours'] as num?)?.toInt() ?? 24;
    final int pageCount = _total == 0 ? 1 : (_total / 20).ceil();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.monitor_heart_outlined,
                    color: Color(0xff287452)),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Transaction reliability',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      const Text(
                          'Read-only DATA, AIRTIME and ELECTRICITY monitoring'),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh reliability data',
                  onPressed: _loading ? null : () => _load(page: _page),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading && _data.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Column(
                  children: [
                    LinearProgressIndicator(),
                    SizedBox(height: 10),
                    LinearProgressIndicator(),
                  ],
                ),
              ),
            if (_error.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xfffff3ed),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error, softWrap: true),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _loading ? null : () => _load(page: _page),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ),
                  ],
                ),
              ),
            if (_loading && _data.isNotEmpty)
              const LinearProgressIndicator(),
            if (_data.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Last $window hours · summary is sampled, capped at 5,000 records'
                '${_data['windowTruncated'] == true ? ' · window truncated' : ''}'
                '${_data['generatedAt'] == null ? '' : ' · Generated ${_data['generatedAt']}'}',
                softWrap: true,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _sectionLabel('Sampled transaction outcomes'),
              _metricPair('Total sampled', summary['total'] ?? 0,
                  'Success rate', _metric(summary['successRate'], suffix: '%')),
              _metricPair('Successful', summary['successCount'] ?? 0,
                  'Recorded failure rate',
                  _metric(summary['failureRate'], suffix: '%')),
              _metricPair('Failed', summary['failedCount'] ?? 0,
                  'Refunded', summary['refundedCount'] ?? 0),
              _metricPair('Pending', summary['pendingCount'] ?? 0,
                  'Recorded HTTP error rate / samples',
                  summary['httpErrorRate'] is num
                      ? '${summary['httpErrorRate']}% · ${summary['httpSamples'] ?? 0} samples'
                      : 'Not recorded'),
              _metricPair(
                'Average recorded admission-to-settlement evidence',
                _metric(summary['averageRecordedSettlementMs'],
                    suffix: ' ms'),
                'Settlement samples',
                summary['settlementSamples'] ?? 0,
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'The average is recorded admission-to-settlement evidence, not provider or device end-to-end duration.',
                  softWrap: true,
                ),
              ),
              _sectionLabel('Unresolved verification queue · all ages'),
              _metricPair('Pending', backlog['pendingCount'] ?? 0,
                  'Manual review', backlog['manualReviewCount'] ?? 0),
              _metricPair('Wallet discrepancies',
                  backlog['walletDiscrepancyCount'] ?? 0,
                  'Ledger audited', backlog['ledgerAuditedCount'] ?? 0),
              _metricPair('Legacy unlinked',
                  backlog['legacyUnlinkedCount'] ?? 0,
                  'Automatic verification limit',
                  backlog['automaticVerificationLimit'] ?? 12),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Ledger exceptions cover sampled modern linked debit/reversals only; this is not full wallet certification.',
                  softWrap: true,
                ),
              ),
              _sectionLabel('Backend reliability alerts'),
              if (alerts.isEmpty)
                const Text('No active reliability alerts were returned.')
              else
                ...alerts.map(_alert),
              _sectionLabel('Provider outcomes'),
              if (providers.isEmpty)
                const Text('No provider outcome records are available.')
              else
                ...providers.map((provider) => Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text('${provider['provider'] ?? 'Provider'}',
                                softWrap: true,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              '${provider['total'] ?? 0} total · ${provider['successCount'] ?? 0} success · ${provider['failedCount'] ?? 0} failed',
                              textAlign: TextAlign.end,
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                    )),
              _sectionLabel(
                'Unresolved transaction records',
                trailing: 'All-age queue',
              ),
              if (items.isEmpty && !_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No unresolved transactions on this page.'),
                )
              else
                ...items.map(_queueItem),
              Row(
                children: [
                  Expanded(
                    child: Text('Page $_page of $pageCount · $_total records',
                        softWrap: true,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  IconButton(
                    tooltip: 'Previous queue page',
                    onPressed:
                        _page > 1 && !_loading ? () => _load(page: _page - 1) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Next queue page',
                    onPressed: _page < pageCount && _page < 250 && !_loading
                        ? () => _load(page: _page + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
            if (!_loading && _data.isEmpty && _error.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('No reliability data is available yet.'),
              ),
          ],
        ),
      ),
    );
  }
}
