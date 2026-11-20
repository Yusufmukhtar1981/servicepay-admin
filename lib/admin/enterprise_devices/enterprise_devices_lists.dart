part of 'enterprise_devices_screen.dart';

// ---------------------------------------------------------------- overview

class _OverviewView extends StatelessWidget {
  const _OverviewView({super.key, required this.api, required this.onOpen});
  final EnterpriseDevicesApi api;
  final void Function(EdSection s, {String? id}) onOpen;
  @override
  Widget build(BuildContext context) => _Loader<Map<String, dynamic>>(
        load: api.overview,
        builder: (Map<String, dynamic> d, VoidCallback reload) {
          final Map<String, dynamic> s = _m(d['stats']);
          final List<(String, String, EdSection?)> tiles =
              <(String, String, EdSection?)>[
            ('Total devices', 'total', EdSection.all),
            ('Active', 'active', EdSection.all),
            ('Available', 'available', EdSection.available),
            ('Assigned', 'assigned', EdSection.assigned),
            ('Inactive', 'inactive', EdSection.all),
            ('Lost / stolen', 'lostStolen', EdSection.all),
            ('Retired', 'retired', EdSection.all),
          ];
          return ListView(
            children: <Widget>[
              _Panel(
                title: 'Inventory status',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: tiles.map(((String, String, EdSection?) t) {
                    final bool lead = t.$2 == 'total';
                    return InkWell(
                      onTap: t.$3 == null ? null : () => onOpen(t.$3!),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 158,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: lead ? EdColors.forest : Colors.transparent,
                          border: Border.all(
                            color: lead ? EdColors.forest : EdColors.line,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              t.$1.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10.5,
                                letterSpacing: .8,
                                fontWeight: FontWeight.w700,
                                color: lead
                                    ? const Color(0xFFA9D8BC)
                                    : EdColors.muted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_i(s[t.$2])}',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: lead ? Colors.white : EdColors.ink,
                                fontFeatures: const <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              _Panel(
                title: 'Quick actions',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () => onOpen(EdSection.register),
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('Register device'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => onOpen(EdSection.available),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Assign from stock'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => onOpen(EdSection.reports),
                      icon: const Icon(Icons.table_rows_outlined),
                      label: const Text('Reports'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
}

// ---------------------------------------------------------------- list

class _DeviceListView extends StatefulWidget {
  const _DeviceListView({
    super.key,
    required this.api,
    required this.onOpen,
    this.fixedStatus,
  });
  final EnterpriseDevicesApi api;
  final void Function(String id) onOpen;
  final String? fixedStatus;
  @override
  State<_DeviceListView> createState() => _DeviceListViewState();
}

class _DeviceListViewState extends State<_DeviceListView> {
  final TextEditingController q = TextEditingController();
  final TextEditingController model = TextEditingController();
  final TextEditingController staff = TextEditingController();
  final TextEditingController dept = TextEditingController();
  String manufacturer = '';
  String status = '';
  int page = 1;
  int pages = 1;
  int total = 0;
  bool loading = true;
  Object? error;
  List<Map<String, dynamic>> devices = <Map<String, dynamic>>[];
  Timer? debounce;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    for (final TextEditingController c in <TextEditingController>[
      q,
      model,
      staff,
      dept,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void typed(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), () {
      page = 1;
      load();
    });
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final Map<String, dynamic> d = await widget.api.search(
        q: q.text,
        manufacturer: manufacturer,
        model: model.text,
        staff: staff.text,
        department: dept.text,
        status: widget.fixedStatus ?? status,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        devices = _l(d['devices']);
        total = _i(d['total']);
        pages = _i(d['pages']) < 1 ? 1 : _i(d['pages']);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e;
        loading = false;
      });
    }
  }

  Widget field(TextEditingController c, String label, double w) => SizedBox(
        width: w,
        child: TextField(
          controller: c,
          onChanged: typed,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 1100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 260,
              child: TextField(
                key: const Key('ed-search'),
                controller: q,
                onChanged: typed,
                decoration: const InputDecoration(
                  labelText: 'Search ID, IMEI, serial',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                value: manufacturer,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Manufacturer',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(value: '', child: Text('All')),
                  ...enterpriseManufacturers.map(
                    (String m) => DropdownMenuItem<String>(
                      value: m,
                      child: Text(m, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (String? v) {
                  manufacturer = v ?? '';
                  page = 1;
                  load();
                },
              ),
            ),
            field(model, 'Model', 130),
            field(staff, 'Staff', 140),
            field(dept, 'Department', 140),
            if (widget.fixedStatus == null)
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: status,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('All'),
                    ),
                    ...enterpriseDeviceStatuses.map(
                      (String m) => DropdownMenuItem<String>(
                        value: m,
                        child: Text(m, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (String? v) {
                    status = v ?? '';
                    page = 1;
                    load();
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          loading
              ? 'Loading…'
              : '$total device${total == 1 ? '' : 's'} · page $page of $pages',
          style: const TextStyle(color: EdColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: loading
              ? const _Skeleton()
              : error != null
                  ? SingleChildScrollView(
                      child: _ErrorBox(error: error!, onRetry: load),
                    )
                  : devices.isEmpty
                      ? const _Empty(
                          icon: Icons.devices_other_outlined,
                          title: 'No devices match',
                          text:
                              'Adjust the filters or register a new company device.',
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCFDFB),
                            border: Border.all(color: EdColors.line),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.separated(
                            itemCount: devices.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, color: EdColors.line),
                            itemBuilder: (BuildContext context, int i) =>
                                _DeviceRow(
                              device: devices[i],
                              wide: wide,
                              onTap: () => widget.onOpen(_s(devices[i]['_id'])),
                            ),
                          ),
                        ),
        ),
        if (pages > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              IconButton(
                tooltip: 'Previous page',
                onPressed: page > 1 && !loading
                    ? () {
                        page--;
                        load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$page / $pages'),
              IconButton(
                tooltip: 'Next page',
                onPressed: page < pages && !loading
                    ? () {
                        page++;
                        load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.wide,
    required this.onTap,
  });
  final Map<String, dynamic> device;
  final bool wide;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> st = _m(device['assignedStaff']);
    final String who = st.isEmpty ? 'Unassigned' : _s(st['name']);
    final TextStyle mono = const TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      color: EdColors.ink,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: wide
            ? Row(
                children: <Widget>[
                  SizedBox(
                    width: 140,
                    child: Text(
                      _s(device['deviceId']),
                      style: mono.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${_s(device['manufacturer'])} ${_s(device['model'])}',
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: Text(_s(device['imei1']), style: mono),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(who, overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: Text(
                      _s(device['department']),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusPill(_s(device['status'])),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: EdColors.muted),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _s(device['deviceId']),
                          style: mono.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      StatusPill(_s(device['status'])),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_s(device['manufacturer'])} ${_s(device['model'])} · ${_s(device['imei1'])} · SN ${_s(device['serialNumber'])}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  Text(
                    '$who · ${_s(device['department'])}',
                    style: const TextStyle(fontSize: 12, color: EdColors.muted),
                  ),
                ],
              ),
      ),
    );
  }
}
