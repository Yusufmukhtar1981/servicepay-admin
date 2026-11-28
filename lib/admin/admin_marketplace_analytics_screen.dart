part of 'admin_marketplace_operations_screens.dart';

// ---------------------------------------------------------------- Analytics

class AdminMarketplaceAnalyticsScreen extends StatefulWidget {
  const AdminMarketplaceAnalyticsScreen({super.key, this.api});
  final AdminMarketplaceOperationsApi? api;
  @override
  State<AdminMarketplaceAnalyticsScreen> createState() => _AnalyticsState();
}

class _AnalyticsState extends State<AdminMarketplaceAnalyticsScreen> {
  late final api = widget.api ?? AdminMarketplaceOperationsApi();
  DateTimeRange? range;
  Map<String, dynamic>? a;
  String? error;
  bool loading = true;

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
      final r = await api.analytics(
          from: range == null ? null : _isoDay(range!.start), to: range == null ? null : _isoDay(range!.end));
      if (mounted) setState(() => a = r);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(title: const Text('Marketplace Analytics'), actions: [
        IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
      ]),
      body: loading
          ? const _Skeleton()
          : error != null
              ? _StateView.error(error!, _load)
              : _body(a ?? const {}),
    );
  }

  Widget _body(Map<String, dynamic> a) {
    final merchants = AdminMarketplaceOperationsApi.listOf(a['bestMerchants']);
    final products = AdminMarketplaceOperationsApi.listOf(a['bestProducts']);
    return ListView(padding: const EdgeInsets.all(18), children: [
      Align(
        alignment: Alignment.centerLeft,
        child: _DateRangeButton(range: range, onChanged: (r) {
          setState(() => range = r);
          _load();
        }),
      ),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _Metric('Total sales', mpMoney(a['totalSales']), emphasis: true),
        _Metric('Total orders', mpText(a['totalOrders'])),
        _Metric('Active merchants', mpText(a['activeMerchants'])),
        _Metric('Registered merchants', mpText(a['registeredMerchants'])),
        _Metric('Commission', mpMoney(a['commissionAmount'])),
        _Metric('Merchant net', mpMoney(a['merchantNetAmount'])),
        _Metric('Delivery fees', mpMoney(a['deliveryFees'])),
        _Metric('Pending', mpText(a['pendingOrders'])),
        _Metric('Completed', mpText(a['completedOrders'])),
        _Metric('Cancelled', mpText(a['cancelledOrders'])),
      ]),
      const SizedBox(height: 14),
      _Panel(
        title: 'Best merchants',
        child: merchants.isEmpty
            ? const Text('No merchant sales in this period.', style: TextStyle(color: _muted))
            : Column(children: [
                for (var i = 0; i < merchants.length; i++)
                  _KV('${i + 1}. ${mpText(merchants[i]['storeName'] ?? merchants[i]['name'] ?? merchants[i]['_id'])}',
                      '${mpMoney(merchants[i]['totalSales'] ?? merchants[i]['sales'])}  -  ${mpText(merchants[i]['quantity'])} units'),
              ]),
      ),
      _Panel(
        title: 'Best products',
        child: products.isEmpty
            ? const Text('No product sales in this period.', style: TextStyle(color: _muted))
            : Column(children: [
                for (var i = 0; i < products.length; i++)
                  _KV('${i + 1}. ${mpText(products[i]['title'] ?? products[i]['name'])}',
                      '${mpMoney(products[i]['totalSales'] ?? products[i]['sales'])}  -  ${mpText(products[i]['quantity'] ?? products[i]['unitsSold'])} sold'),
              ]),
      ),
    ]);
  }
}

