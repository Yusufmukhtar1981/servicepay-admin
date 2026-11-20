import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'enterprise_devices_api.dart';

export 'enterprise_devices_api.dart'
    show
        canAccessEnterpriseDevicesNavigation,
        canManageEnterpriseDevices,
        canEnrollEnterpriseDevices;

part 'enterprise_devices_widgets.dart';
part 'enterprise_devices_lists.dart';
part 'enterprise_devices_forms.dart';
part 'enterprise_devices_detail.dart';
part 'enterprise_devices_admin_views.dart';

/// ServicePay approved identity: dark forest + bright green.
abstract final class EdColors {
  static const Color forest = Color(0xFF0B3B24);
  static const Color forestDeep = Color(0xFF072A19);
  static const Color green = Color(0xFF19B35A);
  static const Color greenSoft = Color(0xFFE3F5EA);
  static const Color canvas = Color(0xFFF3F6F2);
  static const Color line = Color(0xFFD9E3DB);
  static const Color ink = Color(0xFF13251B);
  static const Color muted = Color(0xFF5C6F63);
  static const Color amber = Color(0xFFB7791F);
  static const Color red = Color(0xFFB42318);
}

enum EdSection {
  overview('Overview', Icons.space_dashboard_outlined),
  all('All Devices', Icons.devices_other_outlined),
  register('Register', Icons.add_box_outlined),
  available('Available', Icons.inventory_2_outlined),
  assigned('Assigned', Icons.assignment_ind_outlined),
  details('Details', Icons.info_outline),
  history('History', Icons.history),
  reports('Reports', Icons.table_rows_outlined),
  settings('Settings', Icons.tune);

  const EdSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

String _s(dynamic v) => v == null ? '' : '$v';
int _i(dynamic v) => v is int ? v : int.tryParse(_s(v)) ?? 0;
Map<String, dynamic> _m(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(dynamic v) =>
    v is List ? v.map(_m).toList() : <Map<String, dynamic>>[];
String _date(dynamic v) {
  final DateTime? d = DateTime.tryParse(_s(v));
  if (d == null) return _s(v).isEmpty ? '-' : _s(v);
  final DateTime l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

String maskImei(String imei) => imei.length <= 4
    ? imei
    : '${'•' * (imei.length - 4)}${imei.substring(imei.length - 4)}';

class EnterpriseDevicesScreen extends StatefulWidget {
  const EnterpriseDevicesScreen({
    super.key,
    required this.canManage,
    this.canEnroll = false,
    this.api,
  });
  final bool canManage;

  /// Enrollment token issue / companion revoke (enterprise.devices.enroll).
  final bool canEnroll;
  final EnterpriseDevicesApi? api;

  @override
  State<EnterpriseDevicesScreen> createState() =>
      _EnterpriseDevicesScreenState();
}

class _EnterpriseDevicesScreenState extends State<EnterpriseDevicesScreen> {
  late final EnterpriseDevicesApi api = widget.api ?? EnterpriseDevicesApi();
  EdSection section = EdSection.overview;
  String? selectedId;
  int refreshTick = 0;

  @override
  void dispose() {
    if (widget.api == null) api.close();
    super.dispose();
  }

  void go(EdSection s, {String? id}) => setState(() {
        section = s;
        if (id != null) selectedId = id;
      });

  void changed() => setState(() => refreshTick++);

  Widget body() {
    final Key k = ValueKey<String>('${section.name}-$selectedId-$refreshTick');
    switch (section) {
      case EdSection.overview:
        return _OverviewView(key: k, api: api, onOpen: go);
      case EdSection.all:
        return _DeviceListView(
          key: k,
          api: api,
          onOpen: (String id) => go(EdSection.details, id: id),
        );
      case EdSection.available:
        return _DeviceListView(
          key: k,
          api: api,
          fixedStatus: 'AVAILABLE',
          onOpen: (String id) => go(EdSection.details, id: id),
        );
      case EdSection.assigned:
        return _DeviceListView(
          key: k,
          api: api,
          fixedStatus: 'ASSIGNED',
          onOpen: (String id) => go(EdSection.details, id: id),
        );
      case EdSection.register:
        return _RegisterView(
          key: k,
          api: api,
          canManage: widget.canManage,
          onCreated: (String id) {
            changed();
            go(EdSection.details, id: id);
          },
        );
      case EdSection.details:
        return selectedId == null
            ? _Empty(
                icon: Icons.touch_app_outlined,
                title: 'No device selected',
                text: 'Open a device from All Devices, Available or Assigned.',
                action: TextButton(
                  onPressed: () => go(EdSection.all),
                  child: const Text('Browse devices'),
                ),
              )
            : _DetailsView(
                key: k,
                api: api,
                id: selectedId!,
                canManage: widget.canManage,
                canEnroll: widget.canEnroll,
                onChanged: changed,
                onHistory: () => go(EdSection.history),
              );
      case EdSection.history:
        return selectedId == null
            ? _Empty(
                icon: Icons.history,
                title: 'No device selected',
                text:
                    'Select a device to review its full assignment and audit history.',
                action: TextButton(
                  onPressed: () => go(EdSection.all),
                  child: const Text('Browse devices'),
                ),
              )
            : _HistoryView(key: k, api: api, id: selectedId!);
      case EdSection.reports:
        return _ReportsView(key: k, api: api);
      case EdSection.settings:
        return _SettingsView(key: k, api: api, canManage: widget.canManage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 900;
    final Widget header = Container(
      color: EdColors.forest,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(
        children: <Widget>[
          const _Wordmark(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'SERVICEPAY ENTERPRISE DEVICES',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    fontSize: 15,
                  ),
                ),
                Text(
                  widget.canManage
                      ? 'Head Office inventory · manage'
                      : 'Head Office inventory · read only',
                  style: const TextStyle(
                    color: Color(0xFFA9D8BC),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: changed,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
    );
    final List<EdSection> secs = EdSection.values
        .where((EdSection s) => widget.canManage || s != EdSection.register)
        .toList();
    final Widget content = Padding(
      padding: const EdgeInsets.all(16),
      child: body(),
    );
    return Scaffold(
      backgroundColor: EdColors.canvas,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            header,
            if (!wide)
              Container(
                color: EdColors.forestDeep,
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  children: secs.map((EdSection s) {
                    final bool on = s == section;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(s.label),
                        selected: on,
                        showCheckmark: false,
                        onSelected: (_) => go(s),
                        backgroundColor: EdColors.forestDeep,
                        selectedColor: EdColors.green,
                        side: const BorderSide(color: Color(0xFF1F5A3A)),
                        labelStyle: TextStyle(
                          color: on ? EdColors.forestDeep : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Container(
                          width: 208,
                          color: EdColors.forestDeep,
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            children: secs.map((EdSection s) {
                              final bool on = s == section;
                              return Semantics(
                                selected: on,
                                button: true,
                                child: InkWell(
                                  onTap: () => go(s),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: on
                                              ? EdColors.green
                                              : Colors.transparent,
                                          width: 3,
                                        ),
                                      ),
                                      color:
                                          on ? const Color(0xFF114A2E) : null,
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        Icon(
                                          s.icon,
                                          size: 18,
                                          color: on
                                              ? EdColors.green
                                              : const Color(0xFF9CC5AD),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            s.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: on
                                                  ? Colors.white
                                                  : const Color(0xFFC8E2D2),
                                              fontWeight: on
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        Expanded(child: content),
                      ],
                    )
                  : content,
            ),
          ],
        ),
      ),
    );
  }
}

/// Official ServicePay logo (assets/image/servicepay_logo.png).
class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'ServicePay logo',
        image: true,
        child: ExcludeSemantics(
          child: Image.asset(
            'assets/image/servicepay_logo.png',
            height: 36,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(width: 36, height: 36),
          ),
        ),
      );
}
