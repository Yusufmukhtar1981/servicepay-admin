part of 'admin_marketplace_operations_screens.dart';

// ---------------------------------------------------------------- Settings

class AdminMarketplaceSettingsScreen extends StatefulWidget {
  const AdminMarketplaceSettingsScreen({super.key, this.api});
  final AdminMarketplaceOperationsApi? api;
  @override
  State<AdminMarketplaceSettingsScreen> createState() => _SettingsState();
}

class _OverrideRow {
  _OverrideRow(String key, int? bps)
      : keyCtl = TextEditingController(text: key),
        rateCtl = TextEditingController(text: bpsToPercent(bps));
  final TextEditingController keyCtl;
  final TextEditingController rateCtl;
  void dispose() {
    keyCtl.dispose();
    rateCtl.dispose();
  }
}

class _SettingsState extends State<AdminMarketplaceSettingsScreen> {
  late final api = widget.api ?? AdminMarketplaceOperationsApi();
  final formKey = GlobalKey<FormState>();
  MarketplaceSettingsEnvelope? env;
  String? error;
  bool loading = true;
  bool saving = false;

  bool enabled = false;
  bool deliveryEnabled = false;
  String? deliveryFeeRecipient;
  final rateCtl = TextEditingController();
  final feeCtl = TextEditingController();
  final merchantRows = <_OverrideRow>[];
  final categoryRows = <_OverrideRow>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    rateCtl.dispose();
    feeCtl.dispose();
    for (final r in [...merchantRows, ...categoryRows]) {
      r.dispose();
    }
    super.dispose();
  }

  void _apply(MarketplaceSettingsEnvelope e) {
    final s = e.settings;
    for (final r in [...merchantRows, ...categoryRows]) {
      r.dispose();
    }
    merchantRows
      ..clear()
      ..addAll(s.merchantOverrides.map((o) => _OverrideRow(o.merchantId, o.rateBps)));
    categoryRows
      ..clear()
      ..addAll(s.categoryOverrides.map((o) => _OverrideRow(o.category, o.rateBps)));
    enabled = s.enabled;
    deliveryEnabled = s.deliveryEnabled;
    deliveryFeeRecipient = s.deliveryFeeRecipient;
    // Approved starting rate (3% = 300 bps) is only a form prefill when the
    // server has no rate; nothing is saved or enabled until Head Office submits.
    rateCtl.text = bpsToPercent(s.defaultRateBps ?? mpApprovedDefaultRateBps);
    feeCtl.text = s.deliveryFee == null ? '' : s.deliveryFee!.toStringAsFixed(2);
    env = e;
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final e = await api.settings();
      if (mounted) setState(() => _apply(e));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String? _rateValidator(String? v, {bool required = false}) {
    if ((v ?? '').trim().isEmpty) return required ? 'Required when commission is enabled.' : null;
    return percentToBps(v!) == null ? 'Enter a percentage from 0 to 100.' : null;
  }

  Future<void> _save() async {
    final e = env;
    if (e == null || !e.canManage) return;
    if (!formKey.currentState!.validate()) return;
    final next = MarketplaceSettings(
      enabled: enabled,
      defaultRateBps: percentToBps(rateCtl.text),
      merchantOverrides: [
        for (final r in merchantRows)
          if (r.keyCtl.text.trim().isNotEmpty) (merchantId: r.keyCtl.text.trim(), rateBps: percentToBps(r.rateCtl.text)!)
      ],
      categoryOverrides: [
        for (final r in categoryRows)
          if (r.keyCtl.text.trim().isNotEmpty) (category: r.keyCtl.text.trim(), rateBps: percentToBps(r.rateCtl.text)!)
      ],
      deliveryEnabled: deliveryEnabled,
      deliveryFee: feeCtl.text.trim().isEmpty ? null : double.tryParse(feeCtl.text.trim()),
      deliveryFeeRecipient: deliveryFeeRecipient,
      version: e.settings.version,
    );
    final reason = await mpReasonDialog(context,
        title: 'Submit marketplace policy',
        message: 'This changes commission and delivery for new orders only. Existing orders keep their recorded financial snapshot. The server will refuse enabling commission unless the financial ledger is provisioned and approved.',
        action: 'Submit policy');
    if (reason == null) return;
    setState(() => saving = true);
    try {
      final saved = await api.saveSettings(next, expectedVersion: e.settings.version, reason: reason);
      if (!mounted) return;
      setState(() => _apply(saved));
      _toast(context, 'Marketplace policy saved (version ${saved.settings.version}).');
    } catch (err) {
      if (mounted) _toast(context, err.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(title: const Text('Commission and Delivery'), actions: [
        IconButton(onPressed: loading || saving ? null : _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Reload'),
      ]),
      body: loading
          ? const _Skeleton()
          : error != null || env == null
              ? _StateView.error(error ?? 'Settings unavailable.', _load)
              : _form(env!),
    );
  }

  Widget _overrides(String title, String keyLabel, List<_OverrideRow> rows, bool editable) => _Panel(
        title: title,
        child: Column(children: [
          if (rows.isEmpty) const Align(alignment: Alignment.centerLeft, child: Text('No overrides.', style: TextStyle(color: _muted))),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                    flex: 3,
                    child: TextFormField(
                        controller: r.keyCtl,
                        enabled: editable,
                        decoration: InputDecoration(labelText: keyLabel, isDense: true),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null)),
                const SizedBox(width: 8),
                Expanded(
                    flex: 2,
                    child: TextFormField(
                        controller: r.rateCtl,
                        enabled: editable,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Rate %', isDense: true),
                        validator: (v) => _rateValidator(v, required: true))),
                if (editable)
                  IconButton(
                      tooltip: 'Remove override',
                      onPressed: () => setState(() {
                            rows.remove(r);
                            r.dispose();
                          }),
                      icon: const Icon(Icons.delete_outline_rounded)),
              ]),
            ),
          if (editable)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: () => setState(() => rows.add(_OverrideRow('', null))),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add override')),
            ),
        ]),
      );

  Widget _form(MarketplaceSettingsEnvelope e) {
    final can = e.canManage && !saving;
    return Form(
      key: formKey,
      child: ListView(padding: const EdgeInsets.all(18), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(18)),
          child: Text(
            e.canManage
                ? 'Policy version ${e.settings.version}. Rates are entered as percentages and stored as basis points (100% = 10000). Commission is deducted from the merchant subtotal and is never added to the buyer total. Enabling commission requires a provisioned financial ledger and approval; the server will report if that is missing.'
                : 'Read only. Only Head Office administrators with policy authority can change marketplace commission and delivery.',
            style: const TextStyle(color: Colors.white, height: 1.4),
          ),
        ),
        const SizedBox(height: 14),
        _Panel(title: 'Commission', child: Column(children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Commission enabled'),
            subtitle: const Text('Off unless explicitly turned on here.'),
            value: enabled,
            onChanged: can ? (v) => setState(() => enabled = v) : null,
          ),
          TextFormField(
            key: const Key('mp-default-rate'),
            controller: rateCtl,
            enabled: can,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Default rate (%)', helperText: 'Approved default 3% (300 bps). Editable; stored as basis points.'),
            validator: (v) => _rateValidator(v, required: enabled),
          ),
        ])),
        _overrides('Merchant overrides', 'Merchant ID', merchantRows, can),
        _overrides('Category overrides', 'Category', categoryRows, can),
        _Panel(title: 'Delivery', child: Column(children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Delivery enabled'),
            subtitle: const Text('Customers only see Delivery when enabled with a fee.'),
            value: deliveryEnabled,
            onChanged: can ? (v) => setState(() => deliveryEnabled = v) : null,
          ),
          TextFormField(
            controller: feeCtl,
            enabled: can,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Delivery fee (NGN)'),
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return deliveryEnabled ? 'Required when delivery is enabled.' : null;
              final n = double.tryParse(t);
              return n == null || n < 0 ? 'Enter a valid amount.' : null;
            },
          ),
          if (deliveryEnabled && (double.tryParse(feeCtl.text.trim()) ?? 0) > 0) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const Key('mp-delivery-recipient'),
              value: deliveryFeeRecipient,
              decoration: const InputDecoration(labelText: 'Delivery fee recipient'),
              items: const [
                DropdownMenuItem<String?>(value: null, child: Text('Not selected')),
                DropdownMenuItem<String?>(value: 'MERCHANT', child: Text('Merchant arranges delivery')),
              ],
              onChanged: can ? (v) => setState(() => deliveryFeeRecipient = v) : null,
              validator: (v) => MarketplaceSettings.validateDeliveryRecipient(
                deliveryEnabled: deliveryEnabled,
                deliveryFee: double.tryParse(feeCtl.text.trim()),
                recipient: v,
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Commission applies to product subtotal only and excludes delivery. The delivery fee is held and credited to the chosen recipient only after the buyer confirms receipt.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ])),
        if (e.canManage)
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: can ? _save : null,
              icon: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.verified_user_outlined),
              label: const Text('Review and submit policy'),
            ),
          ),
      ]),
    );
  }
}
