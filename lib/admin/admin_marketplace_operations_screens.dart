import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'admin_marketplace_operations_api.dart';

part 'admin_marketplace_analytics_screen.dart';
part 'admin_marketplace_orders_screen.dart';
part 'admin_marketplace_settings_screen.dart';

// Shared visual language with the existing moderation screen.
const _ink = Color(0xFF12372A);
const _brand = Color(0xFF08783E);
const _brandSoft = Color(0xFFEAF6F0);
const _muted = Color(0xFF667085);
const _canvas = Color(0xFFF7F9F8);
const _line = Color(0xFFE9ECEB);
const _danger = Color(0xFFB42318);

String mpMoney(dynamic raw) {
  if (raw == null) return 'Unavailable';
  final v = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (v == null) return 'Unavailable';
  final parts = v.abs().toStringAsFixed(2).split('.');
  final buf = StringBuffer();
  final w = parts.first;
  for (var i = 0; i < w.length; i++) {
    if (i > 0 && (w.length - i) % 3 == 0) buf.write(',');
    buf.write(w[i]);
  }
  return '${v < 0 ? '-' : ''}\u20A6$buf.${parts.last}';
}

String mpDate(dynamic raw) {
  final d = DateTime.tryParse('${raw ?? ''}')?.toLocal();
  if (d == null) return 'Unavailable';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String mpText(dynamic v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty || s == 'null' ? 'Unavailable' : s;
}

const int mpApprovedDefaultRateBps = 300;

const _fulfillmentFlow = {
  'PAID': 'ACCEPTED',
  'ACCEPTED': 'PROCESSING',
  'PROCESSING': 'READY',
  'READY': 'SHIPPED',
  'SHIPPED': 'OUT_FOR_DELIVERY',
};

/// Mirrors server transitions: one step at a time, only for PAID/HELD
/// orders, and pickup orders stop at READY.
String? mpNextFulfillmentStatus(String status, String method, String paymentStatus, String fundsStatus) {
  if (paymentStatus.toUpperCase() != 'PAID' || fundsStatus.toUpperCase() != 'HELD') return null;
  final next = _fulfillmentFlow[status.toUpperCase()];
  if (next == null) return null;
  if (method.toUpperCase() == 'PICKUP' && (next == 'SHIPPED' || next == 'OUT_FOR_DELIVERY')) return null;
  return next;
}

String _isoDay(DateTime d) => d.toIso8601String().substring(0, 10);

Color mpStatusColor(String s) {
  switch (s.toUpperCase()) {
    case 'ACTIVE':
    case 'COMPLETED':
    case 'DELIVERED':
    case 'SETTLED':
    case 'PAID':
    case 'VERIFIED':
      return const Color(0xFF087443);
    case 'REJECTED':
    case 'CANCELLED':
    case 'FAILED':
    case 'REFUNDED':
      return _danger;
    case 'SUSPENDED':
      return const Color(0xFFC4320A);
    case 'SHIPPED':
    case 'OUT_FOR_DELIVERY':
    case 'READY':
    case 'PROCESSING':
    case 'ACCEPTED':
      return const Color(0xFF175CD3);
    default:
      return const Color(0xFFB54708);
  }
}

class MpStatusPill extends StatelessWidget {
  const MpStatusPill(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final c = mpStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(30)),
      child: Text(status.toUpperCase().replaceAll('_', ' '),
          style: TextStyle(
              color: c,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.4)),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.title});
  final Widget child;
  final String? title;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) ...[
            Text(title!,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: _ink, fontSize: 15)),
            const SizedBox(height: 12),
          ],
          child,
        ]),
      );
}

class _KV extends StatelessWidget {
  const _KV(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 150,
              child: Text(label, style: const TextStyle(color: _muted))),
          Expanded(
              child: SelectableText(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: value == 'Unavailable' ? _muted : _ink))),
        ]),
      );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, {this.emphasis = false});
  final String label;
  final String value;
  final bool emphasis;
  @override
  Widget build(BuildContext context) => Container(
        width: 170,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: emphasis ? _ink : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: emphasis ? _ink : _line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: emphasis ? Colors.white70 : _muted, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: emphasis ? Colors.white : _ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 18)),
        ]),
      );
}

class _StateView extends StatelessWidget {
  const _StateView.error(this.message, this.onRetry)
      : icon = Icons.cloud_off_rounded,
        title = 'Could not load';
  const _StateView.empty(this.message, this.onRetry)
      : icon = Icons.inbox_outlined,
        title = 'Nothing here yet';
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 52, color: icon == Icons.cloud_off_rounded ? _danger : const Color(0xFF98A2B3)),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry')),
          ]),
        ),
      );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.all(18),
        itemCount: 5,
        itemBuilder: (_, __) => Container(
          height: 78,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
              color: const Color(0xFFEDF1EF),
              borderRadius: BorderRadius.circular(18)),
        ),
      );
}

/// Mandatory-reason confirmation shared by merchant/order/settings actions.
Future<String?> mpReasonDialog(BuildContext context,
    {required String title, required String message, required String action}) async {
  final controller = TextEditingController();
  final key = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: key,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('mp-reason'),
            controller: controller,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
                labelText: 'Reason (required)', border: OutlineInputBorder()),
            validator: (v) => (v?.trim().length ?? 0) < 10
                ? 'Enter at least 10 characters.'
                : null,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (key.currentState!.validate()) Navigator.pop(ctx, controller.text.trim());
          },
          child: Text(action),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

void _toast(BuildContext context, String m) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

Widget _pager(MarketplacePage? p, void Function(int) go) {
  if (p == null || p.pages <= 1) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    child: Row(children: [
      Text('Page ${p.page} of ${p.pages}  -  ${p.total} total',
          style: const TextStyle(color: _muted)),
      const Spacer(),
      IconButton(
          tooltip: 'Previous page',
          onPressed: p.page > 1 ? () => go(p.page - 1) : null,
          icon: const Icon(Icons.chevron_left_rounded)),
      IconButton(
          tooltip: 'Next page',
          onPressed: p.page < p.pages ? () => go(p.page + 1) : null,
          icon: const Icon(Icons.chevron_right_rounded)),
    ]),
  );
}

class _DateRangeButton extends StatelessWidget {
  const _DateRangeButton({required this.range, required this.onChanged});
  final DateTimeRange? range;
  final ValueChanged<DateTimeRange?> onChanged;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range_rounded, size: 18),
          label: Text(range == null
              ? 'All dates'
              : '${_isoDay(range!.start)} to ${_isoDay(range!.end)}'),
          onPressed: () async {
            final now = DateTime.now();
            final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2023),
                lastDate: now,
                initialDateRange: range);
            if (r != null) onChanged(r);
          },
        ),
        if (range != null)
          IconButton(
              tooltip: 'Clear dates',
              onPressed: () => onChanged(null),
              icon: const Icon(Icons.close_rounded, size: 18)),
      ]);
}

// ---------------------------------------------------------------- Merchants

class AdminMarketplaceMerchantsScreen extends StatefulWidget {
  const AdminMarketplaceMerchantsScreen({super.key, this.api});
  final AdminMarketplaceOperationsApi? api;
  @override
  State<AdminMarketplaceMerchantsScreen> createState() => _MerchantsState();
}

class _MerchantsState extends State<AdminMarketplaceMerchantsScreen> {
  late final api = widget.api ?? AdminMarketplaceOperationsApi();
  final q = TextEditingController();
  final stateCtl = TextEditingController();
  final lgaCtl = TextEditingController();
  String status = 'ALL';
  DateTimeRange? range;
  MarketplacePage? page;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    q.dispose();
    stateCtl.dispose();
    lgaCtl.dispose();
    super.dispose();
  }

  Future<void> _load([int p = 1]) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await api.merchants(
          q: q.text,
          status: status == 'ALL' ? null : status,
          state: stateCtl.text,
          lga: lgaCtl.text,
          from: range == null ? null : _isoDay(range!.start),
          to: range == null ? null : _isoDay(range!.end),
          page: p);
      if (mounted) setState(() => page = r);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = page?.items ?? const [];
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(title: const Text('Marketplace Merchants')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Column(children: [
            TextField(
              controller: q,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search store, business, phone or email',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final s in ['ALL', 'PENDING', ...AdminMarketplaceOperationsApi.merchantStatuses])
                ChoiceChip(
                    label: Text(s),
                    selected: status == s,
                    onSelected: (_) {
                      setState(() => status = s);
                      _load();
                    }),
              SizedBox(
                  width: 130,
                  child: TextField(
                      controller: stateCtl,
                      onSubmitted: (_) => _load(),
                      decoration: const InputDecoration(labelText: 'State', isDense: true))),
              SizedBox(
                  width: 130,
                  child: TextField(
                      controller: lgaCtl,
                      onSubmitted: (_) => _load(),
                      decoration: const InputDecoration(labelText: 'LGA', isDense: true))),
              _DateRangeButton(
                  range: range,
                  onChanged: (r) {
                    setState(() => range = r);
                    _load();
                  }),
            ]),
          ]),
        ),
        Expanded(
          child: loading
              ? const _Skeleton()
              : error != null
                  ? _StateView.error(error!, _load)
                  : items.isEmpty
                      ? _StateView.empty('No merchants match these filters.', _load)
                      : RefreshIndicator(
                          onRefresh: () => _load(page?.page ?? 1),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                            itemCount: items.length,
                            itemBuilder: (_, i) => _merchantTile(items[i]),
                          ),
                        ),
        ),
        _pager(page, _load),
      ]),
    );
  }

  Widget _merchantTile(Map<String, dynamic> m) {
    final user = AdminMarketplaceOperationsApi.mapOf(m['user']);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _line)),
      color: Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: _brandSoft, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.storefront_rounded, color: _brand),
        ),
        title: Text(mpText(m['storeName'] ?? m['businessName']),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            '${mpText(user['fullName'])}  -  ${mpText(m['state'])}${m['lga'] != null ? ', ${m['lga']}' : ''}\nJoined ${mpDate(m['createdAt'])}',
            style: const TextStyle(color: _muted, height: 1.35)),
        isThreeLine: true,
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          MpStatusPill(mpText(m['status'])),
          if (m['verified'] == true)
            const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Verified', style: TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w700))),
        ]),
        onTap: () async {
          final id = '${m['_id'] ?? ''}';
          if (id.isEmpty) return;
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AdminMarketplaceMerchantProfileScreen(merchantId: id, api: api)));
          if (mounted) _load(page?.page ?? 1);
        },
      ),
    );
  }
}

class AdminMarketplaceMerchantProfileScreen extends StatefulWidget {
  const AdminMarketplaceMerchantProfileScreen({super.key, required this.merchantId, this.api});
  final String merchantId;
  final AdminMarketplaceOperationsApi? api;
  @override
  State<AdminMarketplaceMerchantProfileScreen> createState() => _MerchantProfileState();
}

class _MerchantProfileState extends State<AdminMarketplaceMerchantProfileScreen> {
  late final api = widget.api ?? AdminMarketplaceOperationsApi();
  Map<String, dynamic>? data;
  String? error;
  bool loading = true;
  bool acting = false;

  static const tabs = ['Overview', 'Business Information', 'Products', 'Orders', 'Transactions', 'Verification'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await api.merchant(widget.merchantId);
      if (mounted) setState(() => data = r);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, dynamic> get merchant => AdminMarketplaceOperationsApi.mapOf(data?['merchant']);

  Future<void> _changeStatus(String next) async {
    final current = '${merchant['status'] ?? ''}';
    final reason = await mpReasonDialog(context,
        title: 'Set merchant to $next',
        message: 'This is recorded in the Head Office audit trail. Current status: ${mpText(current)}.',
        action: next == 'ACTIVE' ? 'Activate' : next == 'SUSPENDED' ? 'Suspend' : 'Reject');
    if (reason == null) return;
    setState(() => acting = true);
    try {
      await api.setMerchantStatus(widget.merchantId, status: next, expectedStatus: current, reason: reason);
      if (mounted) _toast(context, 'Merchant status updated to $next.');
      await _load();
    } catch (e) {
      if (mounted) _toast(context, e.toString());
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = '${merchant['status'] ?? ''}'.toUpperCase();
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          title: Text(loading && data == null ? 'Merchant' : mpText(merchant['storeName'] ?? merchant['businessName'])),
          actions: [
            if (data != null)
              PopupMenuButton<String>(
                tooltip: 'Change status',
                enabled: !acting,
                onSelected: _changeStatus,
                itemBuilder: (_) => [
                  for (final s in AdminMarketplaceOperationsApi.merchantStatuses)
                    if (s != status) PopupMenuItem(value: s, child: Text('Set $s')),
                ],
                icon: const Icon(Icons.admin_panel_settings_outlined),
              ),
            IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
          ],
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t)]),
        ),
        body: loading && data == null
            ? const _Skeleton()
            : error != null && data == null
                ? _StateView.error(error!, _load)
                : TabBarView(children: [
                    _overview(),
                    _business(),
                    _list(data?['products'], 'No products from this merchant.', _productRow),
                    _list(data?['orders'], 'No orders for this merchant.', _orderRow),
                    _transactions(),
                    _verification(),
                  ]),
      ),
    );
  }

  Widget _overview() {
    final s = AdminMarketplaceOperationsApi.mapOf(data?['summary']);
    final wallet = AdminMarketplaceOperationsApi.mapOf(data?['wallet']);
    return ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [
        MpStatusPill(mpText(merchant['status'])),
        const SizedBox(width: 8),
        if (merchant['verified'] == true) const MpStatusPill('VERIFIED'),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _Metric('Total sales', mpMoney(s['totalSales']), emphasis: true),
        _Metric('Total orders', mpText(s['totalOrders'])),
        _Metric('Completed', mpText(s['completedOrders'])),
        _Metric('Pending', mpText(s['pendingOrders'])),
        _Metric('Cancelled', mpText(s['cancelledOrders'])),
        _Metric('Commission', mpMoney(s['commissionAmount'])),
        _Metric('Merchant net', mpMoney(s['merchantNetAmount'])),
        _Metric('Settled earnings', mpMoney(s['settledEarnings'])),
      ]),
      const SizedBox(height: 14),
      _Panel(
        title: 'Merchant wallet',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (wallet['available'] == true) ...[
            Text(mpMoney(wallet['balance']),
                key: const Key('mp-wallet-balance'),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: _ink)),
            const SizedBox(height: 2),
            Text('${mpText(wallet['currency'])}  -  ${mpText(wallet['type']).replaceAll('_', ' ')}',
                style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 8),
          ],
          Text(mpText(wallet['message'] ?? 'Merchant wallet balance is not available from this API.'),
              style: const TextStyle(color: _muted)),
        ]),
      ),
    ]);
  }

  Widget _business() {
    final user = AdminMarketplaceOperationsApi.mapOf(merchant['user']);
    final pay = AdminMarketplaceOperationsApi.mapOf(data?['paymentDetails']);
    return ListView(padding: const EdgeInsets.all(18), children: [
      _Panel(title: 'Business', child: Column(children: [
        _KV('Store name', mpText(merchant['storeName'])),
        _KV('Business name', mpText(merchant['businessName'])),
        _KV('Business phone', mpText(merchant['phone'])),
        _KV('Business email', mpText(merchant['email'])),
        _KV('Address', mpText(merchant['address'])),
        _KV('State', mpText(merchant['state'])),
        _KV('LGA', mpText(merchant['lga'])),
        _KV('Registered', mpDate(merchant['createdAt'])),
        _KV('Merchant ID', mpText(merchant['_id'])),
      ])),
      _Panel(title: 'Account owner', child: Column(children: [
        _KV('Full name', mpText(user['fullName'])),
        _KV('Phone', mpText(user['phone'])),
        _KV('Email', mpText(user['email'])),
        _KV('User ID', mpText(user['_id'])),
      ])),
      _Panel(
        title: 'Payment details',
        child: Text(
          mpText(pay['message'] ?? 'Payment details are not available from this API.'),
          style: const TextStyle(color: _muted),
        ),
      ),
    ]);
  }

  Widget _list(dynamic raw, String empty, Widget Function(Map<String, dynamic>) row) {
    final items = AdminMarketplaceOperationsApi.listOf(raw);
    if (items.isEmpty) return _StateView.empty(empty, _load);
    return ListView(padding: const EdgeInsets.all(18), children: [for (final i in items) row(i)]);
  }

  Widget _productRow(Map<String, dynamic> p) => _Panel(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mpText(p['title'] ?? p['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${mpMoney(p['price'])}  -  Stock ${mpText(p['stock'])}  -  ${mpText(p['category'])}',
                  style: const TextStyle(color: _muted)),
            ]),
          ),
          MpStatusPill(mpText(p['status'])),
        ]),
      );

  Widget _orderRow(Map<String, dynamic> o) => InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AdminMarketplaceOrderDetailScreen(orderId: '${o['_id']}', api: api))),
        child: _Panel(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(mpText(o['reference'] ?? o['orderReference'] ?? o['_id']),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${mpMoney(o['totalAmount'])}  -  ${mpText(o['fulfillmentMethod'])}  -  ${mpDate(o['createdAt'])}',
                    style: const TextStyle(color: _muted)),
              ]),
            ),
            MpStatusPill(mpText(o['orderStatus'] ?? o['status'])),
          ]),
        ),
      );

  Widget _transactions() {
    final items = AdminMarketplaceOperationsApi.listOf(data?['transactions']);
    if (items.isEmpty) return _StateView.empty('No marketplace transactions recorded for this merchant.', _load);
    return ListView(padding: const EdgeInsets.all(18), children: [
      for (final t in items)
        _Panel(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(mpText(t['type'] ?? t['description'] ?? t['reference']),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${mpText(t['reference'])}  -  ${mpDate(t['createdAt'])}', style: const TextStyle(color: _muted)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(mpMoney(t['amount']), style: const TextStyle(fontWeight: FontWeight.w800)),
              if (t['status'] != null) ...[const SizedBox(height: 4), MpStatusPill('${t['status']}')],
            ]),
          ]),
        ),
    ]);
  }

  Widget _verification() {
    final v = AdminMarketplaceOperationsApi.mapOf(data?['verification']);
    final docs = AdminMarketplaceOperationsApi.listOf(v['documents']);
    return ListView(padding: const EdgeInsets.all(18), children: [
      _Panel(title: 'Verification status', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [MpStatusPill(mpText(v['status']))]),
        const SizedBox(height: 12),
        _KV('KYC status', mpText(v['kycStatus'])),
        _KV('KYC level', mpText(v['kycLevel'])),
        _KV('KYC ID', mpText(v['kycId'])),
      ])),
      _Panel(
        title: 'Documents',
        child: docs.isEmpty
            ? const Text('No verification documents are available to your role from this API.', style: TextStyle(color: _muted))
            : Column(children: [
                for (final d in docs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_outline_rounded, color: _brand),
                    title: Text(mpText(d['type']).replaceAll('_', ' ')),
                    subtitle: Text(mpText(d['status'])),
                    trailing: '${d['path'] ?? ''}'.isEmpty
                        ? null
                        : TextButton(onPressed: () => _openDocument('${d['type']}', '${d['path']}'), child: const Text('View')),
                  ),
              ]),
      ),
    ]);
  }

  Future<void> _openDocument(String type, String path) async {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type.replaceAll('_', ' ')),
        content: SizedBox(
          width: 520,
          child: FutureBuilder<({List<int> bytes, String contentType})>(
            future: api.kycDocument(path),
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) return Text(snap.error.toString(), style: const TextStyle(color: _danger));
              final doc = snap.data!;
              if (!doc.contentType.startsWith('image/')) {
                return Text('This document (${doc.contentType.isEmpty ? 'unknown type' : doc.contentType}) cannot be previewed here. Use Review KYC.');
              }
              return InteractiveViewer(
                child: Image.memory(Uint8List.fromList(doc.bytes),
                    errorBuilder: (_, __, ___) => const Text('Document could not be rendered.')),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }
}
