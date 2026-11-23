part of 'business_network_screen.dart';

class _SettingsEditor extends StatefulWidget {
  const _SettingsEditor({
    required this.api,
    required this.categories,
    required this.features,
  });

  final BusinessNetworkAdminApi api;
  final List<String> categories;
  final Map<String, dynamic> features;

  @override
  State<_SettingsEditor> createState() => _SettingsEditorState();
}

class _SettingsEditorState extends State<_SettingsEditor> {
  late final TextEditingController ctrl =
      TextEditingController(text: widget.categories.join('\n'));
  bool busy = false;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Business categories · one per line',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        TextField(
          controller: ctrl,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    await widget.api.put('settings', {
                      'categories': ctrl.text
                          .split('\n')
                          .map((value) => value.trim())
                          .where((value) => value.isNotEmpty)
                          .toList(),
                    });
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('Network settings saved.')),
                    );
                  } catch (error) {
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: const Text('Save categories'),
        ),
        const SizedBox(height: 18),
        _MerchantFundingEditor(api: widget.api),
        const SizedBox(height: 18),
        const Text(
          'Payment capabilities',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        ...['merchantQr', 'payByLink', 'automaticPayouts'].map(
          (key) => ListTile(
            enabled: false,
            leading: const Icon(Icons.lock_outline),
            title: Text(key),
            subtitle: Text(
              widget.features[key] == true
                  ? 'Enabled by verified service configuration'
                  : 'Unavailable until independently verified',
            ),
          ),
        ),
        const Text(
          'This screen cannot enable unsupported collection or payout capabilities.',
          style: TextStyle(fontSize: 12),
        ),
      ]);
}

class _MerchantFundingEditor extends StatefulWidget {
  const _MerchantFundingEditor({required this.api});
  final BusinessNetworkAdminApi api;

  @override
  State<_MerchantFundingEditor> createState() => _MerchantFundingEditorState();
}

class _MerchantFundingEditorState extends State<_MerchantFundingEditor> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  int? _revision;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final data = Map<String, dynamic>.from(await widget.api.get('settings') as Map);
      if (!mounted) return;
      setState(() {
        _revision = data['revision'] as int?;
        final minimum = data['merchantMinimumFundingKobo'];
        _amount.text = minimum is num ? (minimum / 100).toStringAsFixed(2) : '';
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || !amount.isFinite || amount < 100 ||
        amount > 1000000000 ||
        (amount * 100 - (amount * 100).round()).abs() > 0.000001 ||
        _reason.text.trim().isEmpty || _revision == null) {
      setState(() => _error = 'Enter a minimum of at least ₦100 with two decimal places or fewer, and a change reason.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final result = Map<String, dynamic>.from(await widget.api.put('settings', {
        'merchantMinimumFundingKobo': (amount * 100).round(),
        'revision': _revision,
        'reason': _reason.text.trim(),
      }) as Map);
      if (!mounted) return;
      setState(() {
        _revision = result['revision'] as int?;
        _reason.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merchant funding minimum saved.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error Refresh settings before retrying.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Merchant wallet funding', style: TextStyle(fontWeight: FontWeight.w800)),
      const Text('Minimum per new funding request, not a required wallet balance. Customer and Agent minimums remain unchanged. Verified incoming transfers retain existing credit protection.'),
      if (_busy) const LinearProgressIndicator(),
      TextField(controller: _amount, enabled: !_busy && _revision != null,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Merchant minimum (NGN)')),
      TextField(controller: _reason, enabled: !_busy && _revision != null,
        maxLength: 500, decoration: const InputDecoration(labelText: 'Required change reason')),
      if (_error != null) Text(_error!),
      Wrap(spacing: 8, children: [
        FilledButton(onPressed: _busy || _revision == null ? null : _save,
          child: const Text('Save Merchant minimum')),
        TextButton(onPressed: _busy ? null : _load, child: const Text('Refresh settings')),
      ]),
    ],
  );
}

Widget _input(
  TextEditingController controller,
  String label, {
  bool numeric = false,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label),
      ),
    );

String _human(String value) => value
    .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match[1]}')
    .replaceAll('_', ' ')
    .replaceFirst(RegExp(r'\s+kobo$', caseSensitive: false), '')
    .trim();

String _moneyIfKobo(String key, dynamic value) {
  if (value == null) return '—';
  if (key.toLowerCase().contains('kobo') ||
      key == 'volumeKobo' ||
      key == 'amountKobo') {
    final amount =
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    return '₦${(amount / 100).toStringAsFixed(2)}';
  }
  return value.toString();
}
