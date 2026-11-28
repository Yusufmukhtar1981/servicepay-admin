part of 'admin_marketplace_operations_screens.dart';

// ---------------------------------------------------------------- Orders

class AdminMarketplaceOrdersScreen extends StatefulWidget {
  const AdminMarketplaceOrdersScreen({super.key, this.api, this.merchantId});
  final AdminMarketplaceOperationsApi? api;
  final String? merchantId;
  @override
  State<AdminMarketplaceOrdersScreen> createState() => _OrdersState();
}

class _OrdersState extends State<AdminMarketplaceOrdersScreen> {
  late final api = widget.api ?? AdminMarketplaceOperationsApi();
  final q = TextEditingController();
  String status = 'ALL';
  String paymentStatus = 'ALL';
  DateTimeRange? range;
  MarketplacePage? page;
  String? error;
  bool loading = true;

  // Mirrors MarketplaceOrder.orderStatus / paymentStatus mongoose enums.
  static const statuses = ['ALL', 'PENDING', 'PAID', 'ACCEPTED', 'PENDING_PAYMENT', 'PLACED', 'CONFIRMED', 'PROCESSING', 'READY', 'SHIPPED', 'READY_FOR_DELIVERY', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED', 'REFUNDED'];
  static const paymentStatuses = ['ALL', 'PENDING', 'PAID', 'FAILED', 'REFUNDED'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  Future<void> _load([int p = 1]) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await api.orders(
          q: q.text,
          status: status == 'ALL' ? null : status,
          paymentStatus: paymentStatus == 'ALL' ? null : paymentStatus,
          from: range == null ? null : _isoDay(range!.start),
          to: range == null ? null : _isoDay(range!.end),
          merchantId: widget.merchantId,
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
      appBar: AppBar(title: const Text('Marketplace Orders')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Column(children: [
            TextField(
              controller: q,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search reference, buyer or merchant',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropdownButton<String>(
                value: status,
                items: [for (final s in statuses) DropdownMenuItem(value: s, child: Text(s == 'ALL' ? 'All statuses' : s.replaceAll('_', ' ')))],
                onChanged: (v) {
                  setState(() => status = v ?? 'ALL');
                  _load();
                },
              ),
              DropdownButton<String>(
                value: paymentStatus,
                items: [for (final s in paymentStatuses) DropdownMenuItem(value: s, child: Text(s == 'ALL' ? 'All payments' : s))],
                onChanged: (v) {
                  setState(() => paymentStatus = v ?? 'ALL');
                  _load();
                },
              ),
              _DateRangeButton(range: range, onChanged: (r) {
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
                      ? _StateView.empty('No orders match these filters.', _load)
                      : RefreshIndicator(
                          onRefresh: () => _load(page?.page ?? 1),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                            itemCount: items.length,
                            itemBuilder: (_, i) => _orderTile(items[i]),
                          ),
                        ),
        ),
        _pager(page, _load),
      ]),
    );
  }

  Widget _orderTile(Map<String, dynamic> o) {
    final buyer = AdminMarketplaceOperationsApi.mapOf(o['buyer']);
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _line)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Text(mpText(o['orderReference'] ?? o['reference'] ?? o['_id']),
            style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace')),
        subtitle: Text(
            '${mpText(buyer['fullName'] ?? o['customerName'])}  -  ${mpText(o['fulfillmentMethod'])}\n${mpDate(o['createdAt'])}',
            style: const TextStyle(color: _muted, height: 1.35)),
        isThreeLine: true,
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(mpMoney(o['totalAmount']), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          MpStatusPill(mpText(o['orderStatus'] ?? o['status'])),
        ]),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AdminMarketplaceOrderDetailScreen(orderId: '${o['_id']}', api: api)));
          if (mounted) _load(page?.page ?? 1);
        },
      ),
    );
  }
}

class AdminMarketplaceOrderDetailScreen extends StatefulWidget {
  const AdminMarketplaceOrderDetailScreen({super.key, required this.orderId, this.api});
  final String orderId;
  final AdminMarketplaceOperationsApi? api;
  @override
  State<AdminMarketplaceOrderDetailScreen> createState() => _OrderDetailState();
}

class _OrderDetailState extends State<AdminMarketplaceOrderDetailScreen> {
  late final api = widget.api ?? AdminMarketplaceOperationsApi();
  Map<String, dynamic>? order;
  String? error;
  bool loading = true;
  bool acting = false;

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
      final r = await api.order(widget.orderId);
      if (mounted) setState(() => order = r);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _setStatus(String next) async {
    final current = '${order?['orderStatus'] ?? order?['status'] ?? ''}';
    final reason = await mpReasonDialog(context,
        title: 'Mark ${next.replaceAll('_', ' ')}',
        message: 'Fulfillment update only. Payment, delivery confirmation and settlement remain with the buyer and the ledger.',
        action: 'Update');
    if (reason == null) return;
    setState(() => acting = true);
    try {
      await api.setOrderStatus(widget.orderId, status: next, expectedStatus: current, reason: reason);
      if (mounted) _toast(context, 'Order marked ${next.replaceAll('_', ' ')}.');
      await _load();
    } catch (e) {
      if (mounted) _toast(context, e.toString());
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order ?? const <String, dynamic>{};
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        title: Text(order == null ? 'Order' : mpText(o['reference'] ?? o['orderReference'] ?? o['_id'])),
        actions: [IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh')],
      ),
      body: loading && order == null
          ? const _Skeleton()
          : error != null && order == null
              ? _StateView.error(error!, _load)
              : _detail(o),
    );
  }

  Widget _detail(Map<String, dynamic> o) {
    final buyer = AdminMarketplaceOperationsApi.mapOf(o['buyer']);
    final items = AdminMarketplaceOperationsApi.listOf(o['items']);
    final history = AdminMarketplaceOperationsApi.listOf(o['statusHistory']);
    final status = '${o['orderStatus'] ?? o['status'] ?? ''}'.toUpperCase();
    final next = mpNextFulfillmentStatus(status, '${o['fulfillmentMethod'] ?? ''}', '${o['paymentStatus'] ?? ''}', '${o['fundsStatus'] ?? ''}');
    final delivery = '${o['fulfillmentMethod'] ?? ''}'.toUpperCase() == 'DELIVERY';
    return ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [
        MpStatusPill(mpText(status)),
        const SizedBox(width: 8),
        if (o['paymentStatus'] != null) MpStatusPill('${o['paymentStatus']}'),
        const Spacer(),
        Text(mpDate(o['createdAt']), style: const TextStyle(color: _muted)),
      ]),
      const SizedBox(height: 14),
      _Panel(title: 'Financial snapshot', child: Column(children: [
        _KV('Items subtotal', mpMoney(o['subtotal'] ?? o['itemsSubtotal'])),
        _KV('Delivery fee', o['deliveryFee'] == null ? 'None' : mpMoney(o['deliveryFee'])),
        _KV('Buyer total', mpMoney(o['totalAmount'])),
        _KV('Commission', o['commissionAmount'] == null ? 'Not applied' : mpMoney(o['commissionAmount'])),
        _KV('Merchant net', mpMoney(o['merchantNetAmount'])),
        _KV('Funds status', mpText(o['fundsStatus'] ?? o['paymentStatus'])),
        const Text('Commission is deducted from the merchant subtotal. It is never charged to the buyer.', style: TextStyle(color: _muted, fontSize: 12)),
      ])),
      _Panel(title: 'Buyer and fulfillment', child: Column(children: [
        _KV('Buyer', mpText(buyer['fullName'] ?? o['customerName'])),
        _KV('Phone', mpText(buyer['phone'] ?? o['customerPhone'])),
        _KV('Email', mpText(buyer['email'])),
        _KV('Fulfillment', mpText(o['fulfillmentMethod'])),
        if (delivery) ...[
          _KV('Address', mpText(o['deliveryAddress'])),
          _KV('State / LGA', '${mpText(o['state'])} / ${mpText(o['lga'])}'),
        ],
        _KV('Instructions', mpText(o['deliveryNote'])),
      ])),
      _Panel(
        title: 'Items',
        child: items.isEmpty
            ? const Text('No item lines supplied.', style: TextStyle(color: _muted))
            : Column(children: [
                for (final it in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${mpText(it['quantity'])} x ${mpText(it['title'] ?? AdminMarketplaceOperationsApi.mapOf(it['product'])['title'])}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(mpText(AdminMarketplaceOperationsApi.mapOf(it['merchant'])['storeName'] ?? AdminMarketplaceOperationsApi.mapOf(it['merchant'])['fullName']),
                              style: const TextStyle(color: _muted, fontSize: 12)),
                        ]),
                      ),
                      Text(mpMoney(it['unitPrice'] ?? it['price'])),
                    ]),
                  ),
              ]),
      ),
      _Panel(
        title: 'Fulfillment actions',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Head Office may only record fulfillment progress. Paid, delivered and refunded states are set by payment, buyer confirmation and settlement.',
              style: TextStyle(color: _muted)),
          const SizedBox(height: 10),
          if (next == null)
            const Text('No Head Office fulfillment step is available for this order now.', style: TextStyle(fontWeight: FontWeight.w600))
          else
            FilledButton.icon(
              onPressed: acting ? null : () => _setStatus(next),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text('Mark ${next.replaceAll('_', ' ')}'),
            ),
        ]),
      ),
      _Panel(
        title: 'Timeline',
        child: history.isEmpty
            ? const Text('No status history recorded.', style: TextStyle(color: _muted))
            : Column(children: [
                for (var i = 0; i < history.length; i++)
                  IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(
                        width: 22,
                        child: Column(children: [
                          Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(top: 5),
                              decoration: BoxDecoration(color: mpStatusColor('${history[i]['status']}'), shape: BoxShape.circle)),
                          if (i < history.length - 1) Expanded(child: Container(width: 2, color: _line)),
                        ]),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(mpText(history[i]['status']).replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('${mpDate(history[i]['at'] ?? history[i]['createdAt'] ?? history[i]['changedAt'])}  -  ${mpText(history[i]['actorRole'] ?? history[i]['by'] ?? history[i]['changedBy'])}',
                                style: const TextStyle(color: _muted, fontSize: 12)),
                            if (history[i]['reason'] != null || history[i]['note'] != null)
                              Text(mpText(history[i]['reason'] ?? history[i]['note']), style: const TextStyle(fontSize: 13)),
                          ]),
                        ),
                      ),
                    ]),
                  ),
              ]),
      ),
    ]);
  }
}

