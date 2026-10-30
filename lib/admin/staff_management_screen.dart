import 'package:flutter/material.dart';

import 'create_staff_screen.dart';
import 'admin_permissions.dart';
import 'admin_roles_permissions_api.dart';
import 'admin_staff_workspace_api.dart';
import 'admin_roles_permissions_screen.dart' show StaffHistoryDialog;
import 'phase1_operations_api.dart';
import 'roles_permissions_screen.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({
    super.key,
    this.api,
    this.staffApi,
    this.workspaceApi,
    this.role = '',
  });

  final Phase1OperationsApi? api;
  final AdminRolesPermissionsApi? staffApi;
  final AdminStaffWorkspaceApi? workspaceApi;
  final String role;

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  bool isLoading = true;
  bool isRefreshing = false;
  String errorMessage = '';

  final TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> staff = [];
  late final Phase1OperationsApi operationsApi =
      widget.api ?? Phase1OperationsApi();
  late final AdminRolesPermissionsApi staffApi =
      widget.staffApi ?? AdminRolesPermissionsApi();
  late final AdminStaffWorkspaceApi workspaceApi =
      widget.workspaceApi ?? AdminStaffWorkspaceApi();

  bool get isHeadOffice =>
      AdminAccess.normalizeRole(widget.role) == 'HEAD_OFFICE' ||
      const <String>{
        'ADMIN',
        'SUPER_ADMIN',
        'HEAD_OFFICE_ADMIN',
        'SERVICEPAY_SUPER_ADMIN',
      }.contains(AdminAccess.normalizeRole(widget.role));

  @override
  void initState() {
    super.initState();
    loadStaff();
  }

  @override
  void dispose() {
    searchController.dispose();
    if (widget.workspaceApi == null) workspaceApi.close();
    super.dispose();
  }

  Future<void> loadStaff({
    bool refresh = false,
  }) async {
    if (!isHeadOffice) {
      if (mounted) {
        setState(() {
          isLoading = false;
          isRefreshing = false;
          errorMessage =
              'This account does not have access to Staff Management.';
          staff = <Map<String, dynamic>>[];
        });
      }
      return;
    }
    if (refresh) {
      setState(() {
        isRefreshing = true;
      });
    } else {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final List<Map<String, dynamic>> list =
          await staffApi.loadStaff(search: searchController.text);

      if (!mounted) {
        return;
      }

      setState(() {
        staff = list;
        errorMessage = '';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage = error.toString().replaceFirst(
              'Exception: ',
              '',
            );
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          isRefreshing = false;
        });
      }
    }
  }

  String textValue(
    Map<String, dynamic> data,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final String key in keys) {
      final dynamic value = data[key];

      if (value == null) {
        continue;
      }

      final String text = value.toString().trim();

      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return fallback;
  }

  Map<String, dynamic> mapValue(
    dynamic value,
  ) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
  }

  Future<void> updateStatus(
    Map<String, dynamic> staffMember,
    String newStatus,
  ) async {
    final String staffId = textValue(
      staffMember,
      const [
        '_id',
        'id',
      ],
    );

    if (staffId.isEmpty) {
      return;
    }

    try {
      await staffApi.updateStaffStatus(staffId, newStatus);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Staff status changed to $newStatus.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );

      await loadStaff(
        refresh: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst(
                    'Exception: ',
                    '',
                  ),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  String staffAccountId(Map<String, dynamic> member) =>
      textValue(member, const <String>['_id', 'id', 'staffId']);

  Map<String, dynamic> assignedRole(Map<String, dynamic> member) {
    final dynamic populated =
        member['staffRoleId'] ?? member['staffRole'] ?? member['role'];
    return mapValue(populated);
  }

  String assignedRoleId(Map<String, dynamic> member) {
    final Map<String, dynamic> role = assignedRole(member);
    final String populatedId = textValue(
      role,
      const <String>['_id', 'id', 'roleId'],
    );
    if (populatedId.isNotEmpty) return populatedId;
    final dynamic rawRole = member['staffRoleId'] ?? member['staffRole'];
    return rawRole is String
        ? rawRole.trim()
        : textValue(member, const <String>['roleId']);
  }

  bool hasActiveAssignedRole(Map<String, dynamic> member) {
    final Map<String, dynamic> assigned = assignedRole(member);
    final String roleId = assignedRoleId(member);
    final String roleStatus =
        textValue(assigned, const <String>['status'], fallback: 'ACTIVE')
            .toUpperCase();
    return roleId.isNotEmpty && roleStatus == 'ACTIVE';
  }

  Future<void> editStaff(Map<String, dynamic> member) async {
    final String id = staffAccountId(member);
    if (id.isEmpty) return;
    final name = TextEditingController(
        text: textValue(member, const ['fullName', 'name']));
    final email =
        TextEditingController(text: textValue(member, const ['email']));
    final phone = TextEditingController(
        text: textValue(member, const ['phone', 'phoneNumber']));
    final Map<String, dynamic>? values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit staff account'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Full name')),
            TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email')),
            TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, <String, dynamic>{
                    'fullName': name.text.trim(),
                    'email': email.text.trim(),
                    'phone': phone.text.trim(),
                  }),
              child: const Text('Save changes')),
        ],
      ),
    );
    name.dispose();
    email.dispose();
    phone.dispose();
    if (values == null) return;
    try {
      await staffApi.updateStaff(id, values);
      _showMessage('Staff account updated.');
      await loadStaff(refresh: true);
    } catch (error) {
      _showMessage('$error', failure: true);
    }
  }

  Future<void> assignRole(Map<String, dynamic> member) async {
    final String id = staffAccountId(member);
    if (id.isEmpty) return;
    try {
      final List<Map<String, dynamic>> roles = await staffApi.loadRoles();
      final activeRoles = roles
          .where((r) =>
              (r['status'] ?? 'ACTIVE').toString().toUpperCase() == 'ACTIVE')
          .toList();
      if (!mounted) return;
      final String currentRoleId = assignedRoleId(member);
      String selected = activeRoles.any(
        (role) => (role['_id'] ?? role['id'] ?? '').toString() == currentRoleId,
      )
          ? currentRoleId
          : '';
      final String? roleId = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                  title: const Text('Assign a role'),
                  content: DropdownButtonFormField<String>(
                    value: selected.isEmpty ? null : selected,
                    items: activeRoles.map((role) {
                      final roleId =
                          (role['_id'] ?? role['id'] ?? '').toString();
                      return DropdownMenuItem(
                          value: roleId,
                          child: Text(
                              (role['displayName'] ?? role['name'] ?? 'Role')
                                  .toString()));
                    }).toList(),
                    onChanged: (value) =>
                        setState(() => selected = value ?? ''),
                    decoration: const InputDecoration(
                        labelText: 'Existing active role'),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(dialogContext, selected),
                        child: const Text('Assign')),
                  ],
                )),
      );
      if (roleId == null) return;
      await staffApi.assignStaffRole(id, roleId);
      _showMessage('Role assigned.');
      await loadStaff(refresh: true);
    } catch (error) {
      _showMessage('$error', failure: true);
    }
  }

  Future<void> revokeRole(Map<String, dynamic> member) async {
    final String id = staffAccountId(member);
    if (id.isEmpty) return;
    final reason = TextEditingController();
    final String? confirmedReason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke assigned role?'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'This suspends the account and revokes active sessions.'),
              const SizedBox(height: 12),
              TextField(
                  controller: reason,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'Reason (required)')),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => reason.text.trim().isEmpty
                  ? null
                  : Navigator.pop(dialogContext, reason.text.trim()),
              child: const Text('Revoke role')),
        ],
      ),
    );
    reason.dispose();
    if (confirmedReason == null) return;
    try {
      await staffApi.revokeStaffRole(id, reason: confirmedReason);
      _showMessage('Role revoked; account suspended and sessions revoked.');
      await loadStaff(refresh: true);
    } catch (error) {
      _showMessage('$error', failure: true);
    }
  }

  Future<void> resetPassword(Map<String, dynamic> member) async {
    final String id = staffAccountId(member);
    if (id.isEmpty) return;
    final password = TextEditingController();
    String? temporaryPassword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: password,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
              labelText: 'Temporary password',
              helperText:
                  'Use a unique temporary password. It will not be shown again.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => password.text.length < 8
                  ? null
                  : Navigator.pop(dialogContext, password.text),
              child: const Text('Reset password')),
        ],
      ),
    );
    password.clear();
    password.dispose();
    if (temporaryPassword == null) return;
    try {
      await staffApi.resetStaffPassword(id,
          temporaryPassword: temporaryPassword);
      _showMessage(
          'Password reset completed. Share the temporary password securely.');
      temporaryPassword = null;
    } catch (error) {
      temporaryPassword = null;
      _showMessage('$error', failure: true);
    }
  }

  Future<void> showStaffHistory(Map<String, dynamic> member) async {
    if (!isHeadOffice) return;
    final id = staffAccountId(member);
    if (id.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => StaffHistoryDialog(
        api: workspaceApi,
        staffId: id,
        staffName: textValue(member, const ['fullName', 'name'],
            fallback: 'Staff history'),
      ),
    );
  }

  void _showMessage(String message, {bool failure = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: failure ? Colors.red.shade700 : null));
  }

  Future<void> showCreateZonalManagerDialog() async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController nameController = TextEditingController();
    final TextEditingController emailController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController zoneController = TextEditingController();
    final TextEditingController stateController = TextEditingController();
    String? dialogError;
    bool submitting = false;

    try {
      final bool? created = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) =>
              AlertDialog(
            title: const Text('Create Zonal Manager'),
            content: SizedBox(
              width: 440,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (dialogError != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          color: const Color(0xFFFEE2E2),
                          child: Text(
                            dialogError!,
                            style: const TextStyle(
                              color: Color(0xFF991B1B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration:
                            const InputDecoration(labelText: 'Full name *'),
                        validator: requiredField,
                      ),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email *'),
                        validator: (String? value) {
                          final String? error = requiredField(value);
                          if (error != null) return error;
                          if (!value!.contains('@')) {
                            return 'Enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone *'),
                        validator: requiredField,
                      ),
                      TextFormField(
                        controller: passwordController,
                        obscureText: true,
                        decoration:
                            const InputDecoration(labelText: 'Password *'),
                        validator: requiredField,
                      ),
                      TextFormField(
                        controller: zoneController,
                        decoration: const InputDecoration(labelText: 'Zone *'),
                        validator: requiredField,
                      ),
                      TextFormField(
                        controller: stateController,
                        decoration: const InputDecoration(
                            labelText: 'State (optional)'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() {
                          submitting = true;
                          dialogError = null;
                        });
                        try {
                          await operationsApi.createZonalManager(
                            fullName: nameController.text,
                            email: emailController.text,
                            phone: phoneController.text,
                            password: passwordController.text,
                            zone: zoneController.text,
                            state: stateController.text,
                          );
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        } on Phase1OperationsException catch (error) {
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              submitting = false;
                              dialogError = error.message;
                            });
                          }
                        } catch (_) {
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              submitting = false;
                              dialogError =
                                  'Unable to create the Zonal Manager.';
                            });
                          }
                        }
                      },
                child: Text(submitting ? 'Creating…' : 'Create Manager'),
              ),
            ],
          ),
        ),
      );

      if (created == true && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Zonal Manager created successfully.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        await loadStaff(refresh: true);
      }
    } finally {
      nameController.dispose();
      emailController.dispose();
      phoneController.dispose();
      passwordController.dispose();
      zoneController.dispose();
      stateController.dispose();
    }
  }

  String? requiredField(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  Widget buildStaffCard(
    Map<String, dynamic> item,
  ) {
    final Map<String, dynamic> role = assignedRole(item);

    final String fullName = textValue(
      item,
      const [
        'fullName',
        'full_name',
        'name',
      ],
      fallback: 'ServicePay Staff',
    );

    final String email = textValue(
      item,
      const ['email'],
    );

    final String phone = textValue(
      item,
      const [
        'phone',
        'phoneNumber',
      ],
    );

    final String staffId = textValue(
      item,
      const ['staffId'],
    );

    final String roleName = textValue(
      role,
      const [
        'displayName',
        'name',
      ],
      fallback: 'Staff',
    );

    final String department = textValue(
      item,
      const ['department'],
      fallback: textValue(
        role,
        const ['department'],
        fallback: 'General',
      ),
    );

    final String status = textValue(
      item,
      const ['status'],
      fallback: 'ACTIVE',
    ).toUpperCase();

    final bool active = status == 'ACTIVE';

    return Card(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          18,
        ),
        side: const BorderSide(
          color: Color(0xFFE5E7EB),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: active
                      ? const Color(0xFFE7F7EE)
                      : const Color(0xFFFEE2E2),
                  child: Icon(
                    Icons.badge_outlined,
                    color: active
                        ? const Color(0xFF15803D)
                        : const Color(0xFFB91C1C),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        roleName,
                        style: const TextStyle(
                          color: Color(0xFF0F766E),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFE7F7EE)
                        : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(
                      20,
                    ),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: active
                          ? const Color(
                              0xFF15803D,
                            )
                          : const Color(
                              0xFFB91C1C,
                            ),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (staffId.isNotEmpty)
              Text(
                'Staff ID: $staffId',
              ),
            if (department.isNotEmpty)
              Text(
                'Department: '
                '${department.replaceAll('_', ' ')}',
              ),
            if (email.isNotEmpty)
              Text(
                'Email: $email',
              ),
            if (phone.isNotEmpty)
              Text(
                'Phone: $phone',
              ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton.icon(
                    onPressed: () => editStaff(item),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit')),
                TextButton.icon(
                    onPressed: () => assignRole(item),
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text('Assign role')),
                TextButton.icon(
                    onPressed: () => revokeRole(item),
                    icon: const Icon(Icons.person_remove_alt_1_outlined),
                    label: const Text('Revoke role')),
                TextButton.icon(
                    onPressed: () => resetPassword(item),
                    icon: const Icon(Icons.password_outlined),
                    label: const Text('Reset password')),
                TextButton.icon(
                    onPressed: () => showStaffHistory(item),
                    icon: const Icon(Icons.history),
                    label: const Text('History')),
                OutlinedButton.icon(
                  onPressed: () {
                    if (!active && !hasActiveAssignedRole(item)) {
                      _showMessage(
                        'Assign a valid active role before activating this account.',
                        failure: true,
                      );
                      return;
                    }
                    updateStatus(item, active ? 'SUSPENDED' : 'ACTIVE');
                  },
                  icon: Icon(active
                      ? Icons.pause_circle_outline
                      : Icons.check_circle_outline),
                  label: Text(active ? 'Suspend' : 'Activate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (!isHeadOffice) {
      return Scaffold(
        appBar: AppBar(title: const Text('Staff Management')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Access denied. Staff administration requires a Head Office session.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: const Text(
          'Staff Management',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            onPressed: isRefreshing
                ? null
                : () {
                    loadStaff(
                      refresh: true,
                    );
                  },
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      floatingActionButton: isHeadOffice
          ? FloatingActionButton.extended(
              onPressed: () async {
                final bool? created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => const CreateStaffScreen(),
                  ),
                );

                if (created == true && mounted) {
                  await loadStaff(
                    refresh: true,
                  );
                }
              },
              icon: const Icon(
                Icons.person_add_alt_1_rounded,
              ),
              label: const Text(
                'Create Staff',
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => loadStaff(
          refresh: true,
        ),
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: showCreateZonalManagerDialog,
                icon: const Icon(Icons.hub_outlined),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '+ Create Zonal Manager',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const RolesPermissionsScreen(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.admin_panel_settings_outlined,
                ),
                label: const Text(
                  'Roles & Permissions',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                loadStaff(
                  refresh: true,
                );
              },
              decoration: InputDecoration(
                hintText: 'Search staff by name, email or ID',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                ),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          searchController.clear();

                          loadStaff(
                            refresh: true,
                          );
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                        ),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (errorMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(
                    16,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF991B1B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: loadStaff,
                      child: const Text(
                        'Try Again',
                      ),
                    ),
                  ],
                ),
              )
            else if (staff.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.groups_outlined,
                        size: 54,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'No staff account found.',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...staff.map(
                buildStaffCard,
              ),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}
