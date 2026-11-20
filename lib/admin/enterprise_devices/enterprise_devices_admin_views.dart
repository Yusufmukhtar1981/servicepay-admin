part of 'enterprise_devices_screen.dart';

// ---------------------------------------------------------------- reports

class _ReportsView extends StatelessWidget {
  const _ReportsView({super.key, required this.api});
  final EnterpriseDevicesApi api;
  @override
  Widget build(BuildContext context) => _Loader<Map<String, dynamic>>(
        load: api.reports,
        builder: (Map<String, dynamic> d, VoidCallback reload) {
          final List<Map<String, dynamic>> rows = _l(d['rows']);
          final Map<String, dynamic> totals = _m(d['totals']);
          final List<String> cols = rows.isEmpty
              ? <String>[]
              : rows.first.keys.where((String k) => k != '_id').toList();
          return ListView(
            children: <Widget>[
              Text(
                'Generated ${_date(d['generatedAt'])}',
                style: const TextStyle(color: EdColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              if (totals.isNotEmpty)
                _Panel(
                  title: 'Totals',
                  child: Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    children: totals.entries
                        .map(
                          (MapEntry<String, dynamic> e) => Text.rich(
                            TextSpan(
                              children: <InlineSpan>[
                                TextSpan(
                                  text: '${e.key}  ',
                                  style: const TextStyle(
                                    color: EdColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                TextSpan(
                                  text: _s(e.value),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              _Panel(
                title: 'Report rows',
                child: rows.isEmpty
                    ? const Text(
                        'No report rows.',
                        style: TextStyle(color: EdColors.muted),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 36,
                          dataRowMinHeight: 32,
                          dataRowMaxHeight: 40,
                          headingTextStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: EdColors.forest,
                            fontSize: 12,
                          ),
                          columns: cols
                              .map((String c) => DataColumn(label: Text(c)))
                              .toList(),
                          rows: rows
                              .map(
                                (Map<String, dynamic> r) => DataRow(
                                  cells: cols.map((String c) {
                                    final String v = r[c] is Map
                                        ? _s(_m(r[c])['name'])
                                        : _s(r[c]);
                                    // Defensive: never render a full IMEI in reports.
                                    final bool imeiCol =
                                        c.toLowerCase().contains(
                                              'imei',
                                            );
                                    return DataCell(
                                      Text(
                                        imeiCol ? maskImei(v) : v,
                                        style: const TextStyle(fontSize: 12.5),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              )
                              .toList(),
                        ),
                      ),
              ),
            ],
          );
        },
      );
}

// ---------------------------------------------------------------- settings

class _SettingsView extends StatelessWidget {
  const _SettingsView({super.key, required this.api, required this.canManage});
  final EnterpriseDevicesApi api;
  final bool canManage;
  @override
  Widget build(BuildContext context) => _Loader<Map<String, dynamic>>(
        load: api.settings,
        builder: (Map<String, dynamic> d, VoidCallback reload) => _SettingsForm(
          api: api,
          settings: _m(d['settings']),
          canManage: canManage,
          onSaved: reload,
        ),
      );
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({
    required this.api,
    required this.settings,
    required this.canManage,
    required this.onSaved,
  });
  final EnterpriseDevicesApi api;
  final Map<String, dynamic> settings;
  final bool canManage;
  final VoidCallback onSaved;
  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late bool wallpaper = widget.settings['allowWallpaper'] == true;
  late bool launcher = widget.settings['allowLauncher'] == true;
  late final TextEditingController pkgs = TextEditingController(
    text: (widget.settings['approvedPackages'] is List
            ? (widget.settings['approvedPackages'] as List).map(_s)
            : const <String>[])
        .join('\n'),
  );
  bool saving = false;

  @override
  void dispose() {
    pkgs.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final List<String> list = pkgs.text
        .split(RegExp(r'[\n,]'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    final RegExp pkg = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$');
    final String? bad = list.where((String s) => !pkg.hasMatch(s)).firstOrNull;
    if (bad != null) {
      _toast(context, 'Invalid package name: $bad', error: true);
      return;
    }
    final String? reason = await askReason(
      context,
      'Save device policy',
      action: 'Save',
    );
    if (reason == null) return;
    setState(() => saving = true);
    try {
      await widget.api.updateSettings(
        allowWallpaper: wallpaper,
        allowLauncher: launcher,
        approvedPackages: list,
        revision: _i(widget.settings['revision']),
        reason: reason,
      );
      if (!mounted) return;
      _toast(context, 'Settings saved.');
      widget.onSaved();
    } catch (e) {
      if (mounted) _toast(context, _err(e), error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        children: <Widget>[
          _Panel(
            title:
                'Device policy · revision ${_i(widget.settings['revision'])}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow staff to change wallpaper'),
                  value: wallpaper,
                  onChanged: widget.canManage
                      ? (bool v) => setState(() => wallpaper = v)
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow alternative launcher'),
                  value: launcher,
                  onChanged: widget.canManage
                      ? (bool v) => setState(() => launcher = v)
                      : null,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pkgs,
                  readOnly: !widget.canManage,
                  minLines: 4,
                  maxLines: 10,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Approved packages (one per line)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (widget.canManage) ...<Widget>[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: EdColors.forest,
                      ),
                      onPressed: saving ? null : save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save settings'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
}
