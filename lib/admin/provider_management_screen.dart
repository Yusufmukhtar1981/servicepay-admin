import 'package:flutter/material.dart';

import 'provider_management_api.dart';

bool providerManagementActionIsLocked({
  required String service,
  required String provider,
}) {
  final String normalizedService =
      service.toLowerCase().replaceAll(RegExp(r'[_\-\s]+'), '');
  final String normalizedProvider =
      provider.toLowerCase().replaceAll(RegExp(r'[_\-\s]+'), '');
  return normalizedService.contains('cable') ||
      normalizedProvider == 'ta' ||
      normalizedProvider == 'telecomabode';
}

class ProviderManagementScreen extends StatefulWidget {
  const ProviderManagementScreen({super.key, this.api});

  final ProviderManagementApi? api;

  @override
  State<ProviderManagementScreen> createState() =>
      _ProviderManagementScreenState();
}

class _ProviderManagementScreenState extends State<ProviderManagementScreen> {
  static const Color _green = Color(0xFF08783E);
  static const Color _ink = Color(0xFF18342A);
  static const Color _canvas = Color(0xFFF4F7F3);
  late final ProviderManagementApi _api =
      widget.api ?? ProviderManagementApi();

  List<ProviderService> _services = <ProviderService>[];
  bool _loading = true;
  String? _error;
  final Set<String> _saving = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<ProviderService> services = await _api.loadServices();
      if (!mounted) return;
      setState(() {
        _services = services;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _cleanError(error);
        _loading = false;
      });
    }
  }

  String _cleanError(Object error) =>
      error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  String _normalized(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[_\-\s]+'), '');

  String _providerKey(Map<String, dynamic> provider) =>
      (provider['provider'] ?? '').toString();

  bool _isTelecomAbodeProvider(Map<String, dynamic> provider) {
    final String key = _normalized(_providerKey(provider));
    return key == 'ta' || key == 'telecomabode';
  }

  bool _lockedService(ProviderService service) {
    final String name = service.service
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ');
    return name.contains('cable');
  }

  bool _lockedProvider(ProviderService service, Map<String, dynamic> provider) =>
      providerManagementActionIsLocked(
        service: service.service,
        provider: _providerKey(provider),
      );

  String _lockReason(ProviderService service) {
    final String name = service.service
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ');
    if (name.contains('cable')) {
      return 'Provider controls are locked: cable purchases are not available on a live purchase route.';
    }
    return 'Telecom Abode provider actions are not supported yet.';
  }

  Future<void> _act(
    ProviderService service,
    Map<String, dynamic> provider,
    String action,
  ) async {
    final String id = _providerKey(provider);
    if (_lockedProvider(service, provider) || id.isEmpty) return;
    if (action == 'disable' &&
        service.service.trim().toLowerCase() == 'electricity' &&
        _normalized(id) == _normalized(service.currentProvider ?? '')) {
      final bool confirmed = await _confirmActiveElectricityDisable(id);
      if (!confirmed || !mounted) return;
    }
    final String key = '${service.service}:$id:$action';
    setState(() => _saving.add(key));
    try {
      await _api.updateProvider(
        service: service.service,
        action: action,
        provider: id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Provider settings updated.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_cleanError(error)),
          backgroundColor: const Color(0xFF9A3028),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  Future<bool> _confirmActiveElectricityDisable(String provider) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFF9A5A18)),
        title: const Text('Disable active provider?'),
        content: Text(
          '$provider is the current electricity provider. Disabling it will stop new electricity purchases until another provider is active.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep provider active'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF9A3028),
            ),
            child: const Text('Disable provider'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  String _date(String? value) {
    if (value == null) return 'No recorded update';
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final DateTime local = parsed.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} · '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _green,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(child: _header()),
              if (_error != null)
                SliverToBoxAdapter(child: _errorPanel(_error!)),
              if (_loading)
                SliverToBoxAdapter(child: _loadingPanel())
              else if (_error == null && _services.isEmpty)
                SliverToBoxAdapter(child: _emptyPanel())
              else if (!_loading)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  sliver: SliverList.separated(
                    itemCount: _services.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (BuildContext context, int index) =>
                        _serviceCard(_services[index]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1EFE5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.hub_outlined, color: _green),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'HEAD OFFICE · OPERATIONS',
                      style: TextStyle(
                        color: _green,
                        fontSize: 10,
                        letterSpacing: 1.35,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Provider Management',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 23,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh provider settings',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                color: _green,
              ),
            ],
          ),
          const SizedBox(height: 17),
          const Text(
            'Control live service routing from one audited view. Changes apply only to supported provider routes.',
            style: TextStyle(color: Color(0xFF62736B), height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _errorPanel(String error) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEFEC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEBC6BF)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.error_outline, color: Color(0xFF9A3028)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Could not load provider settings',
                      style: TextStyle(
                        color: Color(0xFF7A2822),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(error, style: const TextStyle(color: _ink)),
                    TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 17),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _loadingPanel() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          children: List<Widget>.generate(
            2,
            (int index) => Container(
              margin: const EdgeInsets.only(bottom: 14),
              height: 178,
              decoration: BoxDecoration(
                color: const Color(0xFFE8EEE8),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      );

  Widget _emptyPanel() => Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            children: <Widget>[
              Icon(Icons.hub_outlined, size: 36, color: _green),
              SizedBox(height: 12),
              Text(
                'No provider services returned',
                style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
              ),
              SizedBox(height: 5),
              Text(
                'Refresh to check the latest routing configuration.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF62736B)),
              ),
            ],
          ),
        ),
      );

  Widget _serviceCard(ProviderService service) {
    final bool locked = _lockedService(service);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2EAE3)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x0A163C28), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    service.service,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _pill(
                  locked ? 'LOCKED' : 'LIVE CONFIG',
                  locked ? const Color(0xFFFFF0DF) : const Color(0xFFE4F3E8),
                  locked ? const Color(0xFF865019) : _green,
                  locked ? Icons.lock_outline : Icons.check_circle_outline,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _routeChip('PRIMARY', service.primaryProvider),
                _routeChip('FALLBACK', service.fallbackProvider),
                _routeChip('CURRENT', service.currentProvider),
              ],
            ),
            if (locked) ...<Widget>[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7EA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.lock_outline, size: 18, color: Color(0xFF865019)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _lockReason(service),
                        style: const TextStyle(
                          color: Color(0xFF704A20),
                          height: 1.35,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (service.providers.isEmpty)
              const Text('No providers are configured for this service.')
            else
              ...service.providers.map(
                (Map<String, dynamic> provider) =>
                    _providerRow(service, provider, locked),
              ),
            if (!service.fallbackSupported) ...<Widget>[
              const SizedBox(height: 10),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.lock_outline, size: 15, color: Color(0xFF865019)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Fallback provider selection is not supported for this service.',
                      style: TextStyle(
                        color: Color(0xFF865019),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 24, color: Color(0xFFE9EEE9)),
            Row(
              children: <Widget>[
                const Icon(Icons.history, size: 15, color: Color(0xFF819087)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_date(service.updatedAt)} · ${service.updatedBy ?? 'Unknown actor'}',
                    style: const TextStyle(
                      color: Color(0xFF718078),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerRow(
    ProviderService service,
    Map<String, dynamic> provider,
    bool serviceLocked,
  ) {
    final String id = _providerKey(provider);
    final String label = _providerDisplayName(provider);
    final bool enabled = provider['enabled'] == true;
    final bool available = provider['available'] == true;
    final String? reason = provider['reason']?.toString();
    final bool locked = serviceLocked || _lockedProvider(service, provider) || id.isEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 9),
      padding: const EdgeInsets.fromLTRB(12, 11, 9, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECF0EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _status(enabled ? 'Enabled' : 'Disabled', enabled),
              const SizedBox(width: 6),
              _status(available ? 'Available' : 'Unavailable', available),
            ],
          ),
          if (reason != null && reason.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              reason,
              style: const TextStyle(
                color: Color(0xFF718078),
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
          if (!serviceLocked && _isTelecomAbodeProvider(provider)) ...<Widget>[
            const SizedBox(height: 5),
            const Text(
              'Telecom Abode actions are not supported yet.',
              style: TextStyle(
                color: Color(0xFF865019),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: <Widget>[
              _actionButton(
                label: enabled ? 'Disable' : 'Enable',
                icon: enabled ? Icons.pause_circle_outline : Icons.play_circle_outline,
                action: enabled ? 'disable' : 'enable',
                service: service,
                provider: provider,
                locked: locked,
              ),
              _actionButton(
                label: 'Set primary',
                icon: Icons.radio_button_checked,
                action: 'setPrimary',
                service: service,
                provider: provider,
                locked: locked,
              ),
              _actionButton(
                label: 'Set fallback',
                icon: Icons.alt_route,
                action: 'setFallback',
                service: service,
                provider: provider,
                locked: locked || !service.fallbackSupported,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _providerDisplayName(Map<String, dynamic> provider) {
    final String key = _providerKey(provider);
    if (_normalized(key) == 'nellobytes') return 'ClubKonnect / Nellobyte';
    final String label = (provider['label'] ?? key).toString();
    return label;
  }

  String _routeProviderName(String? value) {
    if (value != null && _normalized(value) == 'nellobytes') {
      return 'ClubKonnect / Nellobyte';
    }
    return value ?? '—';
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required String action,
    required ProviderService service,
    required Map<String, dynamic> provider,
    required bool locked,
  }) {
    final String id = _providerKey(provider);
    final bool saving = _saving.contains('${service.service}:$id:$action');
    return OutlinedButton.icon(
      onPressed: locked || saving ? null : () => _act(service, provider, action),
      icon: saving
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(locked ? Icons.lock_outline : icon, size: 15),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: _green,
        disabledForegroundColor: const Color(0xFF9AA69E),
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        side: const BorderSide(color: Color(0xFFDCE7DE)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }

  Widget _routeChip(String label, String? value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6F1),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$label  ${_routeProviderName(value)}',
        style: const TextStyle(
          color: Color(0xFF496054),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _status(String text, bool positive) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: positive ? const Color(0xFFE5F2E8) : const Color(0xFFF0F1EF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: positive ? _green : const Color(0xFF69766E),
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _pill(String text, Color background, Color foreground, IconData icon) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: foreground, size: 13),
            const SizedBox(width: 5),
            Text(
              text,
              style: TextStyle(
                color: foreground,
                fontSize: 9,
                letterSpacing: .5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}