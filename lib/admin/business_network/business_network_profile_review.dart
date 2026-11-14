part of 'business_network_screen.dart';

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({
    required this.api,
    required this.profile,
    required this.onDone,
  });

  final BusinessNetworkAdminApi api;
  final Map<String, dynamic> profile;
  final VoidCallback onDone;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final reason = TextEditingController();
  final group = TextEditingController();
  final Set<String> services = {};
  List<Map<String, dynamic>> serviceCatalogue = [];
  bool serviceCatalogueLoading = true;
  String? serviceCatalogueError;
  String status = 'UNDER_REVIEW';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    group.text = widget.profile['group']?.toString() ?? '';
    services.addAll((widget.profile['services'] as List? ?? const [])
        .map((value) => value.toString()));
    _loadServiceCatalogue();
  }

  Future<void> _loadServiceCatalogue() async {
    setState(() {
      serviceCatalogueLoading = true;
      serviceCatalogueError = null;
    });
    try {
      final settings = await widget.api.get('premium') as Map;
      final catalogue = settings['serviceCatalogue'];
      final kind = widget.profile['kind']?.toString().toUpperCase();
      final rows = catalogue is Map && catalogue[kind] is List
          ? (catalogue[kind] as List)
          : const [];
      final processable = rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where(
              (row) => row['available'] == true && row['processable'] == true)
          .toList();
      final allowed = processable
          .map((row) => row['code']?.toString() ?? '')
          .where((code) => code.isNotEmpty)
          .toSet();
      if (!mounted) return;
      setState(() {
        serviceCatalogue = processable;
        services.removeWhere((code) => !allowed.contains(code));
        serviceCatalogueLoading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          serviceCatalogueError = error.toString();
          serviceCatalogueLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    reason.dispose();
    group.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.profile['_id']?.toString() ?? '';
    final details = widget.profile['details'] is Map
        ? Map<String, dynamic>.from(widget.profile['details'] as Map)
        : <String, dynamic>{};
    return AlertDialog(
      title: Text(details['businessName']?.toString() ??
          details['ownerName']?.toString() ??
          'Profile review'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Network ID: ${widget.profile['networkId'] ?? id}'),
            Text('Status: ${widget.profile['status'] ?? ''}'),
            Text(
                'Contact: ${details['phone'] ?? ''} · ${details['email'] ?? ''}'),
            Text('Location: ${details['state'] ?? ''} ${details['lga'] ?? ''}'),
            Text('Address: ${details['address'] ?? ''}'),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: status,
              items: const [
                'UNDER_REVIEW',
                'APPROVED',
                'REJECTED',
                'SUSPENDED',
              ]
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.replaceAll('_', ' ')),
                      ))
                  .toList(),
              onChanged: (value) =>
                  setState(() => status = value ?? 'UNDER_REVIEW'),
            ),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                  labelText: 'Decision reason / feedback'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Enabled bill services',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const Text(
              'Only processable, globally available bill services can be approved. Product/logistics-only profiles may be approved with no bill services; that grants no bill-payment or commission authority.',
              style: TextStyle(fontSize: 12),
            ),
            if (serviceCatalogueLoading)
              const LinearProgressIndicator()
            else if (serviceCatalogueError != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Service catalogue could not be loaded: $serviceCatalogueError',
                    style: const TextStyle(color: Color(0xFF9A4F31)),
                  ),
                  TextButton(
                    onPressed: _loadServiceCatalogue,
                    child: const Text('Retry catalogue'),
                  ),
                ],
              )
            else if (serviceCatalogue.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No processable bill services are available. Approval, if selected, is products/logistics only.',
                ),
              )
            else
              ...serviceCatalogue.map((service) {
                final code = service['code']?.toString() ?? '';
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(service['label']?.toString() ?? code),
                  subtitle: Text(service['category']?.toString() ?? ''),
                  value: services.contains(code),
                  onChanged: (value) => setState(() {
                    if (value == true) {
                      services.add(code);
                    } else {
                      services.remove(code);
                    }
                  }),
                );
              }),
            if (details['preferredServices'] is List &&
                (details['preferredServices'] as List).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Customer preferences (not authority): ${(details['preferredServices'] as List).join(', ')}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            TextField(
              controller: group,
              decoration: const InputDecoration(labelText: 'Commission group'),
            ),
            if (widget.profile['kind'] == 'MERCHANT') ...[
              const SizedBox(height: 16),
              _AdminMerchantAccessPanel(api: widget.api, profileId: id),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed:
              busy || serviceCatalogueLoading || serviceCatalogueError != null
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await widget.api.post('profiles/$id/review', {
                          'status': status,
                          'reason': reason.text.trim(),
                          'services': services.toList(),
                          'group': group.text.trim(),
                          'revision': widget.profile['revision'] ?? 0,
                        });
                        if (!mounted) return;
                        Navigator.of(this.context).pop();
                        widget.onDone();
                      } catch (error) {
                        if (mounted) {
                          setState(() => busy = false);
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      }
                    },
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save review'),
        ),
      ],
    );
  }
}

class _AdminMerchantAccessPanel extends StatefulWidget {
  const _AdminMerchantAccessPanel({
    required this.api,
    required this.profileId,
  });

  final BusinessNetworkAdminApi api;
  final String profileId;

  @override
  State<_AdminMerchantAccessPanel> createState() =>
      _AdminMerchantAccessPanelState();
}

class _AdminMerchantAccessPanelState extends State<_AdminMerchantAccessPanel> {
  List<dynamic> _branches = [];
  List<dynamic> _staff = [];
  bool _loading = true;
  String? _error;

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
      final responses = await Future.wait<dynamic>([
        widget.api.getProfileBranches(widget.profileId),
        widget.api.getProfileStaff(widget.profileId),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = (responses[0] as Map)['items'] as List? ?? [];
        _staff = (responses[1] as Map)['items'] as List? ?? [];
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _addBranch() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add merchant branch'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Branch name'),
          ),
          TextField(
            controller: address,
            decoration: const InputDecoration(labelText: 'Address'),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save branch'),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;
    if (name.text.trim().isEmpty || address.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a branch name and address.')),
      );
      return;
    }
    try {
      await widget.api.createProfileBranch(widget.profileId, {
        'name': name.text.trim(),
        'address': address.text.trim(),
      });
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      name.dispose();
      address.dispose();
    }
  }

  Future<void> _updateBranch(Map<String, dynamic> branch) async {
    final branchId = (branch['_id'] ?? '').toString();
    if (branchId.isEmpty) return;
    final suspended =
        (branch['status'] ?? 'ACTIVE').toString().toUpperCase() == 'SUSPENDED';
    try {
      await widget.api.updateProfileBranch(
        widget.profileId,
        branchId,
        {'status': suspended ? 'ACTIVE' : 'SUSPENDED'},
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _inviteStaff() async {
    if (_branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a branch before inviting staff.')),
      );
      return;
    }
    final userId = TextEditingController();
    String? branchId;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Invite merchant staff'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: userId,
              decoration:
                  const InputDecoration(labelText: 'ServicePay user ID'),
            ),
            DropdownButtonFormField<String>(
              value: branchId,
              decoration: const InputDecoration(labelText: 'Branch'),
              items: _branches.map((raw) {
                final branch = Map<String, dynamic>.from(raw as Map);
                return DropdownMenuItem<String>(
                  value: branch['_id']?.toString(),
                  child: Text(branch['name']?.toString() ?? 'Branch'),
                );
              }).toList(),
              onChanged: (value) => setDialogState(() => branchId = value),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Send invitation'),
            ),
          ],
        ),
      ),
    );
    if (result != true || !mounted) {
      userId.dispose();
      return;
    }
    if (userId.text.trim().isEmpty || branchId == null) {
      userId.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a user ID and select a branch.')),
      );
      return;
    }
    try {
      await widget.api.inviteProfileStaff(widget.profileId, {
        'userId': userId.text.trim(),
        'branchId': branchId,
        'permissions': const <String>['reports.view'],
      });
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      userId.dispose();
    }
  }

  Future<void> _reinviteStaff(Map<String, dynamic> staff) async {
    final staffId = (staff['_id'] ?? '').toString();
    if (staffId.isEmpty || _branches.isEmpty) return;
    final existingBranch = staff['branchId'] is Map
        ? (staff['branchId'] as Map)['_id']?.toString()
        : staff['branchId']?.toString();
    final initialBranchId = _branches.any(
      (raw) => (raw as Map)['_id']?.toString() == existingBranch,
    )
        ? existingBranch
        : (_branches.first as Map)['_id']?.toString();
    String? branchId = initialBranchId;
    final permissions = <String>{
      ...((staff['permissions'] as List? ?? const [])
          .map((value) => value.toString())
          .where(
              (value) => value == 'reports.view' || value == 'payments.view')),
    };
    if (permissions.isEmpty) permissions.add('reports.view');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Reinvite or change staff access'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: branchId,
              decoration: const InputDecoration(labelText: 'Branch'),
              items: _branches.map((raw) {
                final branch = Map<String, dynamic>.from(raw as Map);
                return DropdownMenuItem<String>(
                  value: branch['_id']?.toString(),
                  child: Text(branch['name']?.toString() ?? 'Branch'),
                );
              }).toList(),
              onChanged: (value) => setDialogState(() => branchId = value),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('View reports'),
              value: permissions.contains('reports.view'),
              onChanged: (value) => setDialogState(() {
                if (value == true) {
                  permissions.add('reports.view');
                } else {
                  permissions.remove('reports.view');
                }
              }),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use permitted payment features'),
              subtitle: const Text(
                'This does not grant finance approval or funds authority.',
              ),
              value: permissions.contains('payments.view'),
              onChanged: (value) => setDialogState(() {
                if (value == true) {
                  permissions.add('payments.view');
                } else {
                  permissions.remove('payments.view');
                }
              }),
            ),
            const Text(
              'Changing access sends a new invitation. The staff member must accept it; this does not activate membership.',
              style: TextStyle(fontSize: 12),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Send invitation'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    if (branchId == null || permissions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Choose a branch and at least one restricted permission.'),
        ),
      );
      return;
    }
    try {
      await widget.api.updateProfileStaff(staffId, {
        'status': 'INVITED',
        'branchId': branchId,
        'permissions': permissions.toList(),
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Invitation sent; staff acceptance is required again.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _suspendStaff(Map<String, dynamic> staff) async {
    final id = (staff['_id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      await widget.api.updateProfileStaff(id, {'status': 'SUSPENDED'});
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFFF4F8F5),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Merchant branches & staff',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const Text(
                'Uses the authenticated Business Network branch/staff endpoints. Staff must accept invitations themselves.',
                style: TextStyle(fontSize: 12),
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: Text('Retry: $_error'),
                ),
              if (!_loading && _error == null && _branches.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No branches registered.'),
                ),
              ..._branches.map((raw) {
                final branch = Map<String, dynamic>.from(raw as Map);
                final status =
                    (branch['status'] ?? 'ACTIVE').toString().toUpperCase();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(branch['name']?.toString() ?? 'Branch'),
                  subtitle: Text(
                    '${branch['address'] ?? ''} · $status',
                  ),
                  trailing: TextButton(
                    onPressed: () => _updateBranch(branch),
                    child: Text(status == 'SUSPENDED' ? 'Resume' : 'Pause'),
                  ),
                );
              }),
              ..._staff.map((raw) {
                final staff = Map<String, dynamic>.from(raw as Map);
                final status = (staff['status'] ?? '').toString().toUpperCase();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(staff['name']?.toString() ??
                      staff['userId']?.toString() ??
                      'Business staff'),
                  subtitle: Text(
                    '$status · ${staff['branchName'] ?? staff['branchId'] ?? ''}',
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Staff access actions',
                    onSelected: (action) {
                      if (action == 'reinvite') {
                        _reinviteStaff(staff);
                      } else if (action == 'suspend') {
                        _suspendStaff(staff);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'reinvite',
                        child: Text('Reinvite / change access'),
                      ),
                      if (status != 'SUSPENDED')
                        const PopupMenuItem(
                          value: 'suspend',
                          child: Text('Suspend staff'),
                        ),
                    ],
                  ),
                );
              }),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _addBranch,
                  icon: const Icon(Icons.add),
                  label: const Text('Add branch'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _inviteStaff,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Invite staff'),
                ),
              ]),
              const Text(
                'Pausing a branch revokes member access. Resuming a branch does not restore suspended memberships. Staff access is limited to reports and supported payment features; it does not grant finance approval or funds authority.',
                style: TextStyle(fontSize: 11, color: Color(0xFF59685F)),
              ),
            ],
          ),
        ),
      );
}
