import 'package:flutter/material.dart';

class ManagementPerformanceFilterBar extends StatelessWidget {
  const ManagementPerformanceFilterBar({
    super.key,
    required this.narrow,
    required this.role,
    required this.roles,
    required this.period,
    required this.periods,
    required this.search,
    required this.onRoleChanged,
    required this.onPeriodChanged,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onChooseDates,
    required this.dateLabel,
  });

  final bool narrow;
  final String role;
  final Map<String, String> roles;
  final String period;
  final Map<String, String> periods;
  final TextEditingController search;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String> onPeriodChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onChooseDates;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SizedBox(
          width: narrow ? double.infinity : 180,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: role,
            decoration: const InputDecoration(labelText: 'Manager role'),
            items: roles.entries
                .map((entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value,
                        maxLines: 1, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (String? value) {
              if (value != null) onRoleChanged(value);
            },
          ),
        ),
        SizedBox(
          width: narrow ? double.infinity : 280,
          child: TextField(
            controller: search,
            decoration: InputDecoration(
              labelText: 'Search managers',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Clear search',
                onPressed: onClearSearch,
                icon: const Icon(Icons.close),
              ),
            ),
            onChanged: onSearchChanged,
          ),
        ),
        SizedBox(
          width: narrow ? double.infinity : 190,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: period,
            decoration: const InputDecoration(labelText: 'Report period'),
            items: periods.entries
                .map((entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value,
                        maxLines: 1, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (String? value) {
              if (value != null) onPeriodChanged(value);
            },
          ),
        ),
        if (period == 'CUSTOM')
          OutlinedButton.icon(
            onPressed: onChooseDates,
            icon: const Icon(Icons.date_range),
            label: Text(dateLabel),
          ),
      ],
    );
  }
}

class ManagementManagersPanel extends StatelessWidget {
  const ManagementManagersPanel({
    super.key,
    required this.loading,
    required this.managers,
    required this.roleLabel,
    required this.total,
    required this.page,
    required this.totalPages,
    required this.selectedId,
    required this.idOf,
    required this.nameOf,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final bool loading;
  final List<Map<String, dynamic>> managers;
  final String roleLabel;
  final int total;
  final int page;
  final int totalPages;
  final String? selectedId;
  final String Function(Map<String, dynamic>) idOf;
  final String Function(Map<String, dynamic>) nameOf;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<Map<String, dynamic>> onSelect;

  @override
  Widget build(BuildContext context) {
    if (loading && managers.isEmpty) {
      final Color skeleton =
          Theme.of(context).colorScheme.surfaceContainerHighest;
      return Card(
        child: Column(
          children: <Widget>[
            const LinearProgressIndicator(),
            for (int index = 0; index < 3; index++)
              ListTile(
                leading: Container(
                    width: 36,
                    height: 36,
                    decoration:
                        BoxDecoration(color: skeleton, shape: BoxShape.circle)),
                title: Container(height: 12, color: skeleton),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(height: 9, width: 130, color: skeleton),
                ),
              ),
          ],
        ),
      );
    }
    if (managers.isEmpty) return const SizedBox.shrink();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
            child: Row(
              children: <Widget>[
                Expanded(child: Text('Managers · $total')),
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$page / $totalPages'),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.separated(
              itemCount: managers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final Map<String, dynamic> manager = managers[index];
                return ListTile(
                  dense: true,
                  selected: idOf(manager) == selectedId,
                  title: Text(nameOf(manager),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '$roleLabel · ${manager['state'] ?? manager['zone'] ?? 'Location unavailable'} · ${manager['status'] ?? 'Unknown'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onSelect(manager),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ManagementPerformanceReportView extends StatelessWidget {
  const ManagementPerformanceReportView({
    super.key,
    required this.report,
    required this.narrow,
    required this.exportActions,
    required this.displayPeriod,
    required this.displayDate,
    required this.displayValue,
  });

  final Map<String, dynamic> report;
  final bool narrow;
  final Widget exportActions;
  final String Function(Map<String, dynamic>) displayPeriod;
  final String Function(dynamic, {bool subtractMillisecond}) displayDate;
  final String Function(dynamic, {bool currency}) displayValue;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> overview = report['overview'] is Map
        ? Map<String, dynamic>.from(report['overview'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> kpis = overview['kpis'] is Map
        ? Map<String, dynamic>.from(overview['kpis'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> manager = report['manager'] is Map
        ? Map<String, dynamic>.from(report['manager'] as Map)
        : <String, dynamic>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${manager['fullName'] ?? 'Selected manager'}',
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text('${manager['roleLabel'] ?? 'Manager'} · '
                    '${manager['state'] ?? manager['zone'] ?? 'Location unavailable'} · '
                    '${manager['status'] ?? 'Unknown'} · ${displayPeriod(overview)}'),
                if ('${overview['scope'] ?? ''}'.trim().isNotEmpty)
                  Text('Scope: ${overview['scope']}',
                      style: Theme.of(context).textTheme.bodySmall),
                if (report['generatedAt'] != null)
                  Text('Generated ${report['generatedAt']}',
                      style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                exportActions,
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _metrics(context, kpis),
        if (overview['previous'] is Map) ...<Widget>[
          const SizedBox(height: 12),
          _previousPeriod(context, overview['previous']),
        ],
        const SizedBox(height: 14),
        _sectionTable(
            context, 'Weekly activity', report['weekly'], <(String, String)>[
          ('at', 'Week'),
          ('transactions', 'Transactions'),
          ('successful', 'Successful'),
          ('successfulValue', 'Successful value'),
        ]),
        const SizedBox(height: 12),
        _sectionTable(
            context, 'Monthly activity', report['monthly'], <(String, String)>[
          ('at', 'Month'),
          ('transactions', 'Transactions'),
          ('successful', 'Successful'),
          ('successfulValue', 'Successful value'),
        ]),
        const SizedBox(height: 12),
        _caveat(context),
      ],
    );
  }

  Widget _metrics(BuildContext context, Map<String, dynamic> kpis) {
    const List<(String, String, bool)> rows = <(String, String, bool)>[
      ('totalCustomers', 'Customers in network', false),
      ('newCustomers', 'New customers', false),
      ('activeCustomers', 'Active customers', false),
      ('inactiveCustomers', 'Inactive customers', false),
      ('totalAgents', 'Aggregators', false),
      ('activeAgents', 'Active aggregators', false),
      ('inactiveAgents', 'Inactive aggregators', false),
      ('totalTransactions', 'Transactions · all statuses', false),
      ('successfulTransactions', 'Successful', false),
      ('failedTransactions', 'Failed', false),
      ('pendingTransactions', 'Pending', false),
      ('refundedTransactions', 'Refunded', false),
      ('totalValue', 'Gross transaction value', true),
      ('ownRecordedCommission', 'Own recorded commission', true),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final int columns = narrow ? 2 : (constraints.maxWidth > 1100 ? 4 : 3);
      final double width =
          (constraints.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: rows.map((row) {
          return SizedBox(
            width: width,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(row.$2, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 7),
                    Text(displayValue(kpis[row.$1], currency: row.$3),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      );
    });
  }

  Widget _previousPeriod(BuildContext context, dynamic raw) {
    final Map<String, dynamic> previous = Map<String, dynamic>.from(raw as Map);
    final dynamic rawKpis = previous['kpis'];
    final Map<String, dynamic> values =
        rawKpis is Map ? Map<String, dynamic>.from(rawKpis) : previous;
    const List<(String, String, bool)> metrics = <(String, String, bool)>[
      ('totalCustomers', 'Customers', false),
      ('newCustomers', 'New customers', false),
      ('activeCustomers', 'Active customers', false),
      ('totalTransactions', 'Transactions', false),
      ('successfulTransactions', 'Successful', false),
      ('totalValue', 'Gross value', true),
      ('ownRecordedCommission', 'Own commission', true),
    ];
    final Iterable<(String, String, bool)> available =
        metrics.where((metric) => values[metric.$1] != null);
    if (available.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Previous-period reference',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: available
                  .map((metric) => Text(
                      '${metric.$2}: ${displayValue(values[metric.$1], currency: metric.$3)}'))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTable(BuildContext context, String title, dynamic values,
      List<(String, String)> columns) {
    final List<Map<String, dynamic>> items = values is List
        ? values
            .whereType<Map>()
            .map((Map row) => Map<String, dynamic>.from(row))
            .toList()
        : <Map<String, dynamic>>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Text('No activity in this interval.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 38,
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 48,
                  columns: columns
                      .map((column) => DataColumn(label: Text(column.$2)))
                      .toList(),
                  rows: items.map((Map<String, dynamic> item) {
                    return DataRow(
                      cells: columns.map((column) {
                        final dynamic value = item[column.$1];
                        return DataCell(Text(column.$1 == 'at'
                            ? displayDate(value)
                            : displayValue(value,
                                currency: column.$1 == 'successfulValue')));
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _caveat(BuildContext context) {
    final Map<String, dynamic> definitions = report['definitions'] is Map
        ? Map<String, dynamic>.from(report['definitions'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> policy = report['policy'] is Map
        ? Map<String, dynamic>.from(report['policy'] as Map)
        : <String, dynamic>{};
    final String legacy = '${definitions['legacy'] ?? policy['history'] ?? ''}';
    final String active = '${definitions['active'] ?? ''}';
    final String commission = '${definitions['commission'] ?? ''}';
    final String comparison = '${definitions['comparison'] ?? ''}';
    final String privacy = '${policy['privacy'] ?? ''}';
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Reading this report',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
                'Activity means recorded transactions, not logins. Gross value includes all statuses. Commission is limited to this manager’s own recorded commission; this view cannot change financial records.'),
            if (legacy.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Legacy attribution: $legacy'),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                    'Legacy transactions may not have verified creation-time hierarchy attribution.'),
              ),
            if (active.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Active definition: $active'),
              ),
            if (commission.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Commission definition: $commission'),
              ),
            if (comparison.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Comparison: $comparison'),
              ),
            if (privacy.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Privacy: $privacy'),
              ),
          ],
        ),
      ),
    );
  }
}

class ManagementPerformanceReportSkeleton extends StatelessWidget {
  const ManagementPerformanceReportSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final Color fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(width: 220, height: 17, color: fill),
                const SizedBox(height: 12),
                Container(width: 300, height: 11, color: fill),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List<Widget>.generate(
            8,
            (_) => SizedBox(
              width: 150,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(width: 96, height: 10, color: fill),
                      const SizedBox(height: 12),
                      Container(width: 58, height: 18, color: fill),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
