part of 'enterprise_devices_screen.dart';

// ---------------------------------------------------------------- staff picker

Future<Map<String, dynamic>?> pickActiveStaff(
  BuildContext context,
  EnterpriseDevicesApi api,
) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _StaffPicker(api: api),
    );

class _StaffPicker extends StatefulWidget {
  const _StaffPicker({required this.api});
  final EnterpriseDevicesApi api;
  @override
  State<_StaffPicker> createState() => _StaffPickerState();
}

class _StaffPickerState extends State<_StaffPicker> {
  final TextEditingController q = TextEditingController();
  Future<Map<String, dynamic>>? future;
  Timer? t;
  @override
  void initState() {
    super.initState();
    future = widget.api.staff('');
  }

  @override
  void dispose() {
    t?.cancel();
    q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Select active staff'),
        content: SizedBox(
          width: 420,
          height: 380,
          child: Column(
            children: <Widget>[
              TextField(
                controller: q,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Search staff',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (String v) {
                  t?.cancel();
                  t = Timer(
                    const Duration(milliseconds: 350),
                    () => setState(() => future = widget.api.staff(v)),
                  );
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: future,
                  builder: (
                    BuildContext context,
                    AsyncSnapshot<Map<String, dynamic>> s,
                  ) {
                    if (s.connectionState != ConnectionState.done) {
                      return const _Skeleton();
                    }
                    if (s.hasError) {
                      return SingleChildScrollView(
                        child: _ErrorBox(error: s.error!),
                      );
                    }
                    final List<Map<String, dynamic>> staff = _l(
                      s.data!['staff'],
                    );
                    if (staff.isEmpty) {
                      return const _Empty(
                        icon: Icons.person_search_outlined,
                        title: 'No active staff found',
                        text: 'Try another name.',
                      );
                    }
                    return ListView.builder(
                      itemCount: staff.length,
                      itemBuilder: (BuildContext context, int i) {
                        final Map<String, dynamic> p = staff[i];
                        final String name = _s(p['fullName']).isNotEmpty
                            ? _s(p['fullName'])
                            : _s(p['name']);
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: EdColors.greenSoft,
                            child: Text(
                              name.isEmpty ? '?' : name[0].toUpperCase(),
                              style: const TextStyle(color: EdColors.forest),
                            ),
                          ),
                          title: Text(name),
                          subtitle: Text(
                            '${_s(p['role'])} · ${_s(p['department'])}',
                          ),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      );
}

String _staffName(Map<String, dynamic> p) =>
    _s(p['fullName']).isNotEmpty ? _s(p['fullName']) : _s(p['name']);

// ---------------------------------------------------------------- register

class _RegisterView extends StatefulWidget {
  const _RegisterView({
    super.key,
    required this.api,
    required this.canManage,
    required this.onCreated,
  });
  final EnterpriseDevicesApi api;
  final bool canManage;
  final void Function(String id) onCreated;
  @override
  State<_RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<_RegisterView> {
  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final Map<String, TextEditingController> c = <String, TextEditingController>{
    for (final String k in <String>[
      'model',
      'imei1',
      'imei2',
      'serialNumber',
      'androidVersion',
      'purchaseDate',
      'purchasePrice',
      'warrantyExpiry',
      'department',
      'state',
    ])
      k: TextEditingController(),
  };
  String manufacturer = 'TECNO';
  Map<String, dynamic>? staff;
  bool saving = false;
  Object? error;
  // One requestId per submission attempt series; regenerated after success.
  String requestId = newEnterpriseRequestId();

  @override
  void dispose() {
    for (final TextEditingController x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  String? req(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;
  String? imei(String? v, {bool optional = false}) {
    final String s = (v ?? '').trim();
    if (s.isEmpty) return optional ? null : 'Required';
    return RegExp(r'^\d{15}$').hasMatch(s) ? null : 'IMEI must be 15 digits';
  }

  String? date(String? v) =>
      DateTime.tryParse((v ?? '').trim()) == null ? 'Use YYYY-MM-DD' : null;

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (c['imei2']!.text.trim().isNotEmpty &&
        c['imei2']!.text.trim() == c['imei1']!.text.trim()) {
      setState(
        () => error = EnterpriseDevicesException(
          'IMEI 2 must differ from IMEI 1.',
        ),
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final Map<String, dynamic> d = await widget.api.register(
        <String, dynamic>{
          'requestId': requestId,
          'manufacturer': manufacturer,
          'model': c['model']!.text.trim(),
          'imei1': c['imei1']!.text.trim(),
          if (c['imei2']!.text.trim().isNotEmpty)
            'imei2': c['imei2']!.text.trim(),
          'serialNumber': c['serialNumber']!.text.trim(),
          'androidVersion': c['androidVersion']!.text.trim(),
          'purchaseDate': c['purchaseDate']!.text.trim(),
          'purchasePrice': num.parse(c['purchasePrice']!.text.trim()),
          'warrantyExpiry': c['warrantyExpiry']!.text.trim(),
          'department': c['department']!.text.trim(),
          'state': c['state']!.text.trim(),
          if (staff != null) 'staffId': _s(staff!['_id']),
        },
      );
      requestId = newEnterpriseRequestId();
      if (!mounted) return;
      _toast(context, 'Device registered.');
      widget.onCreated(_s(_m(d['device'])['_id']));
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget f(
    String k,
    String label, {
    String? Function(String?)? v,
    TextInputType? type,
    String? hint,
  }) =>
      SizedBox(
        width: 250,
        child: TextFormField(
          key: Key('ed-reg-$k'),
          controller: c[k],
          keyboardType: type,
          validator: v ?? req,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!widget.canManage) {
      return const _Empty(
        icon: Icons.lock_outline,
        title: 'Read-only access',
        text: 'Registering devices requires enterprise.devices.manage.',
      );
    }
    return SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (error != null) _ErrorBox(error: error!),
            if (error != null) const SizedBox(height: 10),
            _Panel(
              title: 'Hardware',
              child: Wrap(
                spacing: 10,
                runSpacing: 12,
                children: <Widget>[
                  SizedBox(
                    width: 250,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: manufacturer,
                      decoration: const InputDecoration(
                        labelText: 'Manufacturer',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: enterpriseManufacturers
                          .map(
                            (String m) => DropdownMenuItem<String>(
                              value: m,
                              child: Text(m),
                            ),
                          )
                          .toList(),
                      onChanged: (String? v) =>
                          setState(() => manufacturer = v ?? 'TECNO'),
                    ),
                  ),
                  f('model', 'Model'),
                  f('imei1', 'IMEI 1', v: imei, type: TextInputType.number),
                  f(
                    'imei2',
                    'IMEI 2 (optional)',
                    v: (String? x) => imei(x, optional: true),
                    type: TextInputType.number,
                  ),
                  f('serialNumber', 'Serial number'),
                  f('androidVersion', 'Android version'),
                ],
              ),
            ),
            _Panel(
              title: 'Purchase & warranty',
              child: Wrap(
                spacing: 10,
                runSpacing: 12,
                children: <Widget>[
                  f(
                    'purchaseDate',
                    'Purchase date',
                    v: date,
                    hint: 'YYYY-MM-DD',
                  ),
                  f(
                    'purchasePrice',
                    'Purchase price (NGN)',
                    type: const TextInputType.numberWithOptions(decimal: true),
                    v: (String? x) {
                      final num? n = num.tryParse((x ?? '').trim());
                      return n == null || n < 0 ? 'Enter a valid amount' : null;
                    },
                  ),
                  f(
                    'warrantyExpiry',
                    'Warranty expiry',
                    v: date,
                    hint: 'YYYY-MM-DD',
                  ),
                ],
              ),
            ),
            _Panel(
              title: 'Placement',
              child: Wrap(
                spacing: 10,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  f('department', 'Department'),
                  f('state', 'State'),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final Map<String, dynamic>? p = await pickActiveStaff(
                        context,
                        widget.api,
                      );
                      if (p != null) setState(() => staff = p);
                    },
                    icon: const Icon(Icons.person_add_alt_outlined),
                    label: Text(
                      staff == null
                          ? 'Assign staff (optional)'
                          : _staffName(staff!),
                    ),
                  ),
                  if (staff != null)
                    IconButton(
                      tooltip: 'Clear staff',
                      onPressed: () => setState(() => staff = null),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('ed-reg-submit'),
                style: FilledButton.styleFrom(backgroundColor: EdColors.forest),
                onPressed: saving ? null : submit,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: const Text('Register device'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
