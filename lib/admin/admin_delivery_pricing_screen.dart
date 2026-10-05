import 'package:flutter/material.dart';

import 'admin_delivery_pricing_api.dart';

class AdminDeliveryPricingScreen extends StatefulWidget {
  const AdminDeliveryPricingScreen({super.key, this.api});

  final AdminDeliveryPricingApiClient? api;

  @override
  State<AdminDeliveryPricingScreen> createState() =>
      _AdminDeliveryPricingScreenState();
}

class _AdminDeliveryPricingScreenState
    extends State<AdminDeliveryPricingScreen> {
  static const Color _green = Color(0xFF08783E);
  static const Color _ink = Color(0xFF183328);
  late final AdminDeliveryPricingApiClient _api;
  final TextEditingController _search = TextEditingController();
  Map<String, dynamic> _snapshot = <String, dynamic>{};
  bool _loading = true;
  bool _mutating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? AdminDeliveryPricingApi();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _routes => _list(_snapshot['routes']);
  List<Map<String, dynamic>> get _branches => _list(_snapshot['branches']);
  List<Map<String, dynamic>> get _audit => _list(_snapshot['audit']);
  Map<String, dynamic> get _summary => _map(_snapshot['summary']);
  Map<String, dynamic> get _intraState => _map(_snapshot['intraState']);

  static Map<String, dynamic> _map(dynamic value) =>
      AdminDeliveryPricingApi.mapFrom(value);

  static List<Map<String, dynamic>> _list(dynamic value) => value is List
      ? value.whereType<Map>().map(_map).toList()
      : <Map<String, dynamic>>[];

  String _str(dynamic value, [String fallback = '—']) {
    final String result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  String _money(dynamic value) =>
      '₦${_number(value).toStringAsFixed(_number(value) % 1 == 0 ? 0 : 2)}';

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final Map<String, dynamic> result = await _api.getPricing();
      if (!mounted) return;
      setState(() {
        _snapshot = result;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    String confirmLabel = 'Confirm change',
    bool destructive = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB42318))
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _perform(Future<void> Function() mutation) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      await mutation();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: const Color(0xFF9E2A22),
            behavior: SnackBarBehavior.floating,
          ),
        );
      if (error is AdminDeliveryPricingApiException && error.isConflict) {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _editIntraPrice() async {
    final TextEditingController controller = TextEditingController(
      text: _number(_intraState['price']).toString(),
    );
    final String? input = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _PriceDialog(
        title: 'Update Intra-State price',
        controller: controller,
      ),
    );
    controller.dispose();
    final double? price = double.tryParse(input ?? '');
    if (price == null || price < 0) return;
    if (!await _confirm(
      title: 'Confirm Intra-State price',
      message:
          'Set the current Intra-State delivery price to ${_money(price)}? New orders use this price. Existing orders and receipts keep their saved price.',
    )) {
      return;
    }
    await _perform(() async {
      await _api.updateIntraStatePrice(
        price: price,
        expectedVersion: int.tryParse('${_intraState['version']}') ?? 0,
      );
      _success('Intra-State price updated.');
    });
  }

  Future<void> _editPrice(Map<String, dynamic> route) async {
    final String id = _str(route['_id'], '');
    final String updatedAt = _str(route['updatedAt'], '');
    if (id.isEmpty || updatedAt.isEmpty) {
      _notice(
          'This route is missing its update version. Refresh before editing.');
      return;
    }
    final TextEditingController controller = TextEditingController(
      text: _number(route['baseFare']).toString(),
    );
    final String? input = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _PriceDialog(
        title: 'Edit route price',
        controller: controller,
      ),
    );
    controller.dispose();
    final double? price = double.tryParse(input ?? '');
    if (price == null || price < 0) return;
    final String from = _str(route['originState']);
    final String to = _str(route['destinationState']);
    if (!await _confirm(
      title: 'Confirm route price',
      message:
          'Change $from → $to to ${_money(price)} and use FIXED pricing? This applies only to NEW orders. Historical prices and receipts remain unchanged.',
    )) {
      return;
    }
    await _perform(() async {
      await _api.updateRoutePrice(
        routeId: id,
        baseFare: price,
        expectedUpdatedAt: updatedAt,
      );
      _success('Route price updated for new orders.');
    });
  }

  Future<void> _toggleRoute(Map<String, dynamic> route) async {
    final String id = _str(route['_id'], '');
    if (id.isEmpty) return;
    final bool active = _str(route['status']).toUpperCase() == 'ACTIVE';
    final String origin = _str(route['originState']);
    final String destination = _str(route['destinationState']);
    if (!await _confirm(
      title: active ? 'Deactivate route?' : 'Activate route?',
      message: active
          ? 'New bookings for $origin → $destination will be blocked. Existing orders are not changed.'
          : 'Allow new bookings for $origin → $destination at the current configured price?',
      confirmLabel: active ? 'Deactivate route' : 'Activate route',
      destructive: active,
    )) {
      return;
    }
    await _perform(() async {
      await _api.setRouteActive(routeId: id, active: !active);
      _success(active ? 'Route deactivated.' : 'Route activated.');
    });
  }

  Future<void> _deleteRoute(Map<String, dynamic> route) async {
    final String id = _str(route['_id'], '');
    final String updatedAt = _str(route['updatedAt'], '');
    if (id.isEmpty || updatedAt.isEmpty) {
      _notice(
          'This route is missing its update version. Refresh before deleting.');
      return;
    }
    if (!await _confirm(
      title: 'Delete route?',
      message:
          'Delete ${_str(route['originState'])} → ${_str(route['destinationState'])}? The server will refuse deletion if linked records make it unsafe.',
      confirmLabel: 'Delete route',
      destructive: true,
    )) {
      return;
    }
    await _perform(() async {
      await _api.deleteRoute(routeId: id, expectedUpdatedAt: updatedAt);
      _success('Route deleted.');
    });
  }

  Future<void> _addRoute() async {
    final List<Map<String, dynamic>> branches = _branches
        .where((Map<String, dynamic> b) =>
            _str(b['status']).toUpperCase() == 'ACTIVE')
        .where((Map<String, dynamic> b) => _str(b['_id'], '').isNotEmpty)
        .toList();
    if (branches.length < 2) {
      _notice(
          'At least two active ServicePay branches are required to add a route.');
      return;
    }
    final Map<String, dynamic>? values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) => _CreateRouteDialog(branches: branches),
    );
    if (values == null) return;
    final Map<String, dynamic> origin = _map(values['origin']);
    final Map<String, dynamic> destination = _map(values['destination']);
    final String originState = _str(origin['state'], '');
    final String destinationState = _str(destination['state'], '');
    if (originState.isEmpty || destinationState.isEmpty) {
      _notice(
          'The selected branches need configured states before they can be used.');
      return;
    }
    final bool duplicateActive = _routes.any((Map<String, dynamic> route) =>
        _str(route['status']).toUpperCase() == 'ACTIVE' &&
        _str(route['originState']).toUpperCase() == originState.toUpperCase() &&
        _str(route['destinationState']).toUpperCase() ==
            destinationState.toUpperCase());
    if (duplicateActive) {
      _notice('An active route already exists for this direction.');
      return;
    }
    final bool reverse = values['applySamePriceToReverse'] == true;
    if (!await _confirm(
      title: 'Confirm new route',
      message:
          'Create $originState → $destinationState at ${_money(values['baseFare'])} as ${values['status']}?${reverse ? ' Also apply this price to the reverse direction if it exists.' : ''} Capacity and delivery timing will use the values you entered. Historical orders are not affected.',
      confirmLabel: 'Create route',
    )) {
      return;
    }
    await _perform(() async {
      await _api.createRoute(<String, dynamic>{
        'name': values['name'],
        'originState': originState,
        'destinationState': destinationState,
        'originBranchId': origin['_id'],
        'destinationBranchId': destination['_id'],
        'baseFare': values['baseFare'],
        'pricingMode': 'FIXED',
        'maximumWeightKg': values['maximumWeightKg'],
        'minimumWeightKg': 0,
        'pricePerAdditionalKg': 0,
        'standardDeliveryTime': values['standardDeliveryTime'],
        'customerVisible': true,
        'status': values['status'],
        'applySamePriceToReverse': reverse,
        'confirmed': true,
      });
      _success('Route created.');
    });
  }

  void _success(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _green,
      ));
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  List<Map<String, dynamic>> get _filteredRoutes {
    final String query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _routes;
    return _routes.where((Map<String, dynamic> route) {
      return <String>[
        _str(route['originState']),
        _str(route['destinationState']),
        _str(route['name']),
        _str(route['status']),
        _str(route['pricingMode']),
      ].any((String value) => value.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F4),
      appBar: AppBar(
        title: const Text('Delivery Pricing'),
        backgroundColor: colors.surface,
        foregroundColor: _ink,
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh pricing',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _snapshot.isEmpty
          ? const _PricingSkeleton()
          : _error != null && _snapshot.isEmpty
              ? _PricingMessage(
                  icon: Icons.cloud_off_outlined,
                  title: 'Pricing could not be loaded',
                  message: _error!,
                  action: FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
                    children: <Widget>[
                      _pageIntro(),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 14),
                        MaterialBanner(
                          content: Text(_error!),
                          leading: const Icon(Icons.warning_amber_rounded),
                          actions: <Widget>[
                            TextButton(
                                onPressed: _load, child: const Text('Retry')),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      _summaryCards(),
                      const SizedBox(height: 24),
                      _routeSection(),
                      const SizedBox(height: 26),
                      _auditSection(),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mutating ? null : _addRoute,
        backgroundColor: _green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add route'),
      ),
    );
  }

  Widget _pageIntro() => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool narrow = constraints.maxWidth < 650;
          final Widget title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Delivery & Logistics',
                style: TextStyle(
                  color: Color(0xFF698074),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Delivery pricing',
                style: TextStyle(
                  color: _ink,
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Manage live Intra-State fares and real branch-to-branch routes.',
                style: TextStyle(color: Color(0xFF66776E), height: 1.4),
              ),
            ],
          );
          final Widget note = Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3EC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD5E6D9)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.lock_outline, color: _green, size: 19),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Price changes apply to new orders only. Saved order totals and receipts remain unchanged.',
                    style: TextStyle(
                      color: Color(0xFF315944),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
          return narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[title, const SizedBox(height: 14), note],
                )
              : Row(
                  children: <Widget>[
                    Expanded(child: title),
                    const SizedBox(width: 16),
                    note,
                  ],
                );
        },
      );

  Widget _summaryCards() {
    final int active = int.tryParse('${_summary['activeRoutes']}') ??
        _routes
            .where((Map<String, dynamic> r) =>
                _str(r['status']).toUpperCase() == 'ACTIVE')
            .length;
    final int inactive = int.tryParse('${_summary['inactiveRoutes']}') ??
        _routes
            .where((Map<String, dynamic> r) =>
                _str(r['status']).toUpperCase() != 'ACTIVE')
            .length;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 680;
        final List<Widget> cards = <Widget>[
          _MetricCard(
            label: 'Active routes',
            value: '$active',
            icon: Icons.route_outlined,
            accent: const Color(0xFF08783E),
          ),
          _MetricCard(
            label: 'Inactive routes',
            value: '$inactive',
            icon: Icons.pause_circle_outline,
            accent: const Color(0xFF8A6540),
          ),
          _MetricCard(
            label: 'Intra-State price',
            value: _money(_intraState['price']),
            icon: Icons.payments_outlined,
            accent: const Color(0xFF315B89),
            action: TextButton(
              onPressed: _mutating ? null : _editIntraPrice,
              child: const Text('Edit'),
            ),
          ),
        ];
        return narrow
            ? Column(
                children: cards
                    .map((Widget card) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: card,
                        ))
                    .toList(),
              )
            : Row(
                children: <Widget>[
                  for (int i = 0; i < cards.length; i++) ...<Widget>[
                    Expanded(child: cards[i]),
                    if (i != cards.length - 1) const SizedBox(width: 12),
                  ],
                ],
              );
      },
    );
  }

  Widget _routeSection() => Container(
        padding: const EdgeInsets.all(18),
        decoration: _panelDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Widget heading = const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Interstate routes',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Prices and availability for each direction are managed independently.',
                      style: TextStyle(color: Color(0xFF75847B), fontSize: 12),
                    ),
                  ],
                );
                final Widget search = SizedBox(
                  width: constraints.maxWidth < 570 ? double.infinity : 260,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search route or status',
                      prefixIcon: const Icon(Icons.search, size: 19),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF5F8F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close, size: 18),
                            ),
                    ),
                  ),
                );
                return constraints.maxWidth < 570
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          heading,
                          const SizedBox(height: 13),
                          search
                        ],
                      )
                    : Row(
                        children: <Widget>[
                          Expanded(child: heading),
                          const SizedBox(width: 12),
                          search,
                        ],
                      );
              },
            ),
            const SizedBox(height: 16),
            if (_routes.isEmpty)
              const _PricingMessage(
                icon: Icons.alt_route_outlined,
                title: 'No interstate routes yet',
                message:
                    'Add a route using an existing active branch in each direction.',
              )
            else if (_filteredRoutes.isEmpty)
              const _PricingMessage(
                icon: Icons.search_off_outlined,
                title: 'No matching routes',
                message: 'Try another state, route name, or status.',
              )
            else
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  if (constraints.maxWidth < 980) {
                    return Column(
                      children: _filteredRoutes
                          .map((Map<String, dynamic> route) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _RouteCard(
                                  route: route,
                                  money: _money,
                                  str: _str,
                                  date: _date,
                                  mutating: _mutating,
                                  onEdit: () => _editPrice(route),
                                  onToggle: () => _toggleRoute(route),
                                  onDelete: () => _deleteRoute(route),
                                ),
                              ))
                          .toList(),
                    );
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                        headingRowHeight: 44,
                        dataRowMinHeight: 66,
                        dataRowMaxHeight: 82,
                        horizontalMargin: 12,
                        columnSpacing: 22,
                        columns: const <DataColumn>[
                          DataColumn(label: Text('Origin')),
                          DataColumn(label: Text('Destination')),
                          DataColumn(label: Text('Price')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Last updated')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: _filteredRoutes.map((Map<String, dynamic> route) {
                          final bool active =
                              _str(route['status']).toUpperCase() == 'ACTIVE';
                          final bool fixed =
                              _str(route['pricingMode']).toUpperCase() ==
                                  'FIXED';
                          return DataRow(cells: <DataCell>[
                            DataCell(_stateCell(_str(route['originState']))),
                            DataCell(
                                _stateCell(_str(route['destinationState']))),
                            DataCell(Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(_money(route['baseFare']),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 3),
                                _PricingModeLabel(fixed: fixed),
                              ],
                            )),
                            DataCell(_StatusChip(active: active)),
                            DataCell(Text(_date(route['updatedAt']),
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF718078)))),
                            DataCell(_actions(route, active)),
                          ]);
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );

  Widget _stateCell(String state) => Text(
        state,
        style: const TextStyle(
          color: _ink,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      );

  Widget _actions(Map<String, dynamic> route, bool active) => Wrap(
        spacing: 2,
        children: <Widget>[
          IconButton(
            tooltip: 'Edit price',
            onPressed: _mutating ? null : () => _editPrice(route),
            icon: const Icon(Icons.edit_outlined, size: 19),
            color: _green,
          ),
          IconButton(
            tooltip: active ? 'Deactivate route' : 'Activate route',
            onPressed: _mutating ? null : () => _toggleRoute(route),
            icon: Icon(
                active ? Icons.pause_circle_outline : Icons.play_circle_outline,
                size: 20),
            color: active ? const Color(0xFF8A6540) : _green,
          ),
          IconButton(
            tooltip: 'Delete route',
            onPressed: _mutating || _str(route['updatedAt'], '').isEmpty
                ? null
                : () => _deleteRoute(route),
            icon: const Icon(Icons.delete_outline, size: 19),
            color: const Color(0xFFB42318),
          ),
        ],
      );

  Widget _auditSection() => Container(
        padding: const EdgeInsets.all(18),
        decoration: _panelDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.receipt_long_outlined, color: _green, size: 20),
                SizedBox(width: 9),
                Text(
                  'Internal price-change audit',
                  style: TextStyle(
                      color: _ink, fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              'Recorded changes, operators, and timestamps from the pricing service.',
              style: TextStyle(color: Color(0xFF75847B), fontSize: 12),
            ),
            const SizedBox(height: 13),
            if (_audit.isEmpty)
              const Text('No recorded price changes.',
                  style: TextStyle(color: Color(0xFF6F7E75)))
            else
              ..._audit.take(12).map(_auditRow),
          ],
        ),
      );

  Widget _auditRow(Map<String, dynamic> row) {
    final Map<String, dynamic> metadata = _map(row['metadata']);
    final String operation =
        _str(metadata['operation'], 'Price updated').replaceAll('_', ' ');
    final String route =
        '${_str(metadata['originState'])} → ${_str(metadata['destinationState'])}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE9EEEA))),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(operation,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: _ink)),
              const SizedBox(height: 4),
              Text(
                '$route · ${_str(row['actorName'], 'Admin')} (${_str(row['actorRole'], 'Staff')})',
                style: const TextStyle(fontSize: 12, color: Color(0xFF67786E)),
              ),
            ],
          );
          final Widget prices = Text(
            '${_money(metadata['oldPrice'])}  →  ${_money(metadata['newPrice'])}',
            style: const TextStyle(fontWeight: FontWeight.w800, color: _green),
          );
          final Widget time = Text(
            _date(row['createdAt']),
            style: const TextStyle(fontSize: 11, color: Color(0xFF7D8982)),
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                body,
                const SizedBox(height: 9),
                prices,
                const SizedBox(height: 4),
                time
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: body),
              const SizedBox(width: 12),
              prices,
              const SizedBox(width: 16),
              SizedBox(width: 125, child: time),
            ],
          );
        },
      ),
    );
  }

  String _date(dynamic value) {
    final DateTime? date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} · ${two(date.hour)}:${two(date.minute)}';
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3EAE4)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Color(0x080B3921), blurRadius: 14, offset: Offset(0, 5)),
        ],
      );
}

class _PriceDialog extends StatelessWidget {
  const _PriceDialog({required this.title, required this.controller});
  final String title;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Price (₦)',
            prefixText: '₦ ',
            helperText: 'Enter a non-negative amount.',
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final double? value = double.tryParse(controller.text.trim());
              if (value == null || value < 0) return;
              Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Continue'),
          ),
        ],
      );
}

class _CreateRouteDialog extends StatefulWidget {
  const _CreateRouteDialog({required this.branches});
  final List<Map<String, dynamic>> branches;

  @override
  State<_CreateRouteDialog> createState() => _CreateRouteDialogState();
}

class _CreateRouteDialogState extends State<_CreateRouteDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _fare = TextEditingController();
  final TextEditingController _capacity = TextEditingController();
  final TextEditingController _time = TextEditingController();
  Map<String, dynamic>? _origin;
  Map<String, dynamic>? _destination;
  bool _reverse = false;
  String _status = 'ACTIVE';

  @override
  void dispose() {
    _name.dispose();
    _fare.dispose();
    _capacity.dispose();
    _time.dispose();
    super.dispose();
  }

  String _branchLabel(Map<String, dynamic> branch) =>
      '${branch['name'] ?? 'Branch'} · ${branch['state'] ?? 'State not set'}';

  void _setBranch(
      {required bool origin, required Map<String, dynamic>? branch}) {
    setState(() {
      if (origin) {
        _origin = branch;
      } else {
        _destination = branch;
      }
      final String from = _origin?['name']?.toString() ?? '';
      final String to = _destination?['name']?.toString() ?? '';
      if (from.isNotEmpty && to.isNotEmpty && _name.text.trim().isEmpty) {
        _name.text = '$from to $to';
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add interstate route'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: _origin,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Origin branch'),
                    items: widget.branches
                        .map((Map<String, dynamic> branch) => DropdownMenuItem(
                            value: branch,
                            child: Text(_branchLabel(branch),
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (Map<String, dynamic>? value) =>
                        _setBranch(origin: true, branch: value),
                    validator: (Map<String, dynamic>? value) =>
                        value == null ? 'Choose a real branch.' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: _destination,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Destination branch'),
                    items: widget.branches
                        .map((Map<String, dynamic> branch) => DropdownMenuItem(
                            value: branch,
                            child: Text(_branchLabel(branch),
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (Map<String, dynamic>? value) =>
                        _setBranch(origin: false, branch: value),
                    validator: (Map<String, dynamic>? value) {
                      if (value == null) return 'Choose a real branch.';
                      if (_origin?['_id'] == value['_id']) {
                        return 'Choose a different branch.';
                      }
                      if (_origin?['state'] == value['state']) {
                        return 'Choose a branch in a different state.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Route name'),
                    validator: (String? value) =>
                        value?.trim().isNotEmpty == true
                            ? null
                            : 'Enter a route name.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _fare,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Fixed price (₦)'),
                    validator: _validNumber,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _capacity,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Maximum included weight (kg)'),
                    validator: _validNumber,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _time,
                    decoration: const InputDecoration(
                      labelText: 'Standard delivery time',
                      hintText: 'Enter operator-approved delivery timing',
                    ),
                    validator: (String? value) =>
                        value?.trim().isNotEmpty == true
                            ? null
                            : 'Enter a delivery time.',
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _status,
                    decoration:
                        const InputDecoration(labelText: 'Initial status'),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                      DropdownMenuItem(
                          value: 'INACTIVE', child: Text('Inactive')),
                    ],
                    onChanged: (String? value) =>
                        setState(() => _status = value ?? 'ACTIVE'),
                  ),
                  const SizedBox(height: 5),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _reverse,
                    onChanged: (bool? value) =>
                        setState(() => _reverse = value ?? false),
                    title: const Text('Apply same price to reverse route'),
                    subtitle: const Text(
                        'You can price each direction independently later.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const Text(
                    'States are taken from the selected ServicePay branches. Delivery timing and capacity must be entered by the operator.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF68796F)),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              Navigator.pop(context, <String, dynamic>{
                'origin': _origin,
                'destination': _destination,
                'name': _name.text.trim(),
                'baseFare': double.parse(_fare.text.trim()),
                'maximumWeightKg': double.parse(_capacity.text.trim()),
                'standardDeliveryTime': _time.text.trim(),
                'status': _status,
                'applySamePriceToReverse': _reverse,
              });
            },
            child: const Text('Review route'),
          ),
        ],
      );

  String? _validNumber(String? value) {
    final double? amount = double.tryParse(value?.trim() ?? '');
    if (amount == null || !amount.isFinite || amount < 0) {
      return 'Enter a valid non-negative number.';
    }
    return null;
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.action,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3EAE4)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label,
                      style: const TextStyle(
                          color: Color(0xFF728178), fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(value,
                      style: const TextStyle(
                          color: Color(0xFF183328),
                          fontSize: 21,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            if (action != null) action!,
          ],
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE8F4EB) : const Color(0xFFF4EEE6),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          active ? 'ACTIVE' : 'INACTIVE',
          style: TextStyle(
            color: active ? const Color(0xFF17663B) : const Color(0xFF805B32),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: .4,
          ),
        ),
      );
}

class _PricingModeLabel extends StatelessWidget {
  const _PricingModeLabel({required this.fixed});
  final bool fixed;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: fixed ? const Color(0xFFEAF3EC) : const Color(0xFFFFF2DB),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          fixed ? 'FIXED' : 'CALCULATED · SURCHARGES',
          style: TextStyle(
            color: fixed ? const Color(0xFF17663B) : const Color(0xFF805B32),
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.route,
    required this.money,
    required this.str,
    required this.date,
    required this.mutating,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });
  final Map<String, dynamic> route;
  final String Function(dynamic) money;
  final String Function(dynamic, [String]) str;
  final String Function(dynamic) date;
  final bool mutating;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final bool active = str(route['status']).toUpperCase() == 'ACTIVE';
    final bool fixed = str(route['pricingMode']).toUpperCase() == 'FIXED';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFA),
        border: Border.all(color: const Color(0xFFE3EAE4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${str(route['originState'])}  →  ${str(route['destinationState'])}',
                  style: const TextStyle(
                      color: Color(0xFF183328),
                      fontWeight: FontWeight.w800,
                      fontSize: 15),
                ),
              ),
              _StatusChip(active: active),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 9,
            runSpacing: 6,
            children: <Widget>[
              Text(money(route['baseFare']),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 19)),
              _PricingModeLabel(fixed: fixed),
              Text(date(route['updatedAt']),
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF75847B))),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: <Widget>[
              TextButton.icon(
                onPressed: mutating ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Edit price'),
              ),
              TextButton.icon(
                onPressed: mutating ? null : onToggle,
                icon: Icon(
                    active
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    size: 17),
                label: Text(active ? 'Deactivate' : 'Activate'),
              ),
              TextButton.icon(
                onPressed: mutating || str(route['updatedAt'], '').isEmpty
                    ? null
                    : onDelete,
                icon: const Icon(Icons.delete_outline, size: 17),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PricingMessage extends StatelessWidget {
  const _PricingMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 34, color: const Color(0xFF75917D)),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Color(0xFF183328))),
              const SizedBox(height: 5),
              Text(message,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Color(0xFF6F7E75), height: 1.4)),
              if (action != null) ...<Widget>[
                const SizedBox(height: 14),
                action!
              ],
            ],
          ),
        ),
      );
}

class _PricingSkeleton extends StatelessWidget {
  const _PricingSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Container(height: 78, decoration: _shape()),
          const SizedBox(height: 22),
          Row(
            children: List<Widget>.generate(
              3,
              (int i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 10 : 0),
                  child: Container(height: 94, decoration: _shape()),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Container(height: 310, decoration: _shape()),
        ],
      );

  BoxDecoration _shape() => BoxDecoration(
        color: const Color(0xFFE7EDE8),
        borderRadius: BorderRadius.circular(15),
      );
}
