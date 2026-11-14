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
    .replaceAll('Kobo', 'kobo')
    .replaceAll('_', ' ')
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
