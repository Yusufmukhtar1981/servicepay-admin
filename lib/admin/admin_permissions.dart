import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract final class AdminPermissions {
  static const dashboardView = 'dashboard.view';
  static const staffCreate = 'staff.create';
  static const staffView = 'staff.view';
  static const staffUpdate = 'staff.update';
  static const staffSuspend = 'staff.suspend';
  static const staffAssignRole = 'staff.assign_role';
  static const rolesCreate = 'roles.create';
  static const rolesView = 'roles.view';
  static const rolesUpdate = 'roles.update';
  static const rolesDelete = 'roles.delete';
  static const rolesAssignPermissions = 'roles.assign_permissions';
  static const rolesEnable = 'roles.enable';
  static const usersView = 'users.view';
  static const privacyView = 'privacy.view';
  static const privacyManage = 'privacy.manage';
  static const customer360View = 'customer360.view';
  static const customer360Financial = 'customer360.financial';
  static const customer360Kyc = 'customer360.kyc';
  static const customer360Security = 'customer360.security';
  static const transactionsView = 'transactions.view';
  static const transactionIntelligenceView = 'transactions.intelligence.view';
  static const transactionIntelligenceRequery =
      'transactions.intelligence.requery';
  static const walletsView = 'wallets.view';
  static const fundingView = 'funding.view';
  static const withdrawalsView = 'withdrawals.view';
  static const financeView = 'finance.view';
  static const deliveryView = 'delivery.view';
  static const logisticsView = 'logistics.view';
  static const logisticsManage = 'logistics.manage';
  static const marketplaceView = 'marketplace.view';
  static const solarView = 'solar.view';
  static const phoneFinancingView = 'phone_financing.view';
  static const empowermentView = 'empowerment.view';
  static const amanaView = 'amana.view';
  static const airtimeToCashView = 'airtime_to_cash.view';
  static const supportView = 'support.view';
  static const kycView = 'kyc.view';
  static const trustView = 'trust.view';
  static const notificationsView = 'notifications.view';
  static const notificationsCreate = 'notifications.create';
  static const notificationsSend = 'notifications.send';
  static const communicationsView = 'communications.view';
  static const emailCampaignCreate = 'email_campaign.create';
  static const emailCampaignSend = 'email_campaign.send';
  static const emailCampaignHistoryView = 'email_campaign.history_view';
  static const emailCampaignManage = 'email_campaign.manage';
  static const settingsView = 'settings.view';
  static const settingsUpdate = 'settings.update';
  static const featureControlView = 'feature_control.view';
  static const featureControlManage = 'feature_control.manage';
  static const featureControlProtectedManage =
      'feature_control.protected_manage';
  static const auditView = 'audit.view';
  static const reportsView = 'reports.view';
  static const reportsExport = 'reports.export';
  static const branchesView = 'branches.view';
  static const svpManagementView = 'svp.management.view';
  static const svpReportsView = 'svp.reports.view';
  static const svpAuditView = 'svp.audit.view';

  // Head Office organization administration permissions.
  static const organizationsView = 'organizations.view';
  static const organizationsReview = 'organizations.review';
  static const organizationsStatusManage = 'organizations.status.manage';
  static const organizationsWalletManage = 'organizations.wallet.manage';
  static const organizationsMembersView = 'organizations.members.view';
  static const organizationsPaymentsView = 'organizations.payments.view';
  static const organizationsAuditView = 'organizations.audit.view';
  static const organizationsWithdrawalsView = 'organizations.withdrawals.view';
  static const organizationsWithdrawalsReview =
      'organizations.withdrawals.review';
  static const organizationsSettlementAccountsView =
      'organizations.settlement_accounts.view';
  static const organizationsSettlementAccountsReview =
      'organizations.settlement_accounts.review';
  static const organizationsTreasuryManage = 'organizations.treasury.manage';
}

class AdminAccess {
  const AdminAccess({
    required this.role,
    required this.permissions,
    this.scope = const <String, dynamic>{},
  });

  final String role;
  final Set<String> permissions;
  final Map<String, dynamic> scope;

  static const Set<String> _fullAccessRoles = <String>{
    'HEAD_OFFICE',
    'ADMIN',
    'SUPER_ADMIN',
    'HEAD_OFFICE_ADMIN',
    'SERVICEPAY_SUPER_ADMIN',
  };

  bool get isFullAccess =>
      _fullAccessRoles.contains(normalizeRole(role)) ||
      permissions.contains('*');

  static String normalizeRole(String? value) =>
      (value ?? '').trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_');

  bool has(String permission) {
    final String normalizedPermission = permission.trim().toLowerCase();
    if (normalizedPermission == AdminPermissions.featureControlView) {
      return canViewFeatureControls;
    }
    if (normalizedPermission == AdminPermissions.featureControlManage) {
      return canManageFeatureControls;
    }
    if (normalizedPermission ==
        AdminPermissions.featureControlProtectedManage) {
      return canProtectedManageFeatureControls;
    }
    if (isFullAccess || permissions.contains(permission)) return true;
    const Map<String, String> legacy = <String, String>{
      AdminPermissions.communicationsView: AdminPermissions.notificationsView,
      AdminPermissions.emailCampaignCreate:
          AdminPermissions.notificationsCreate,
      AdminPermissions.emailCampaignSend: AdminPermissions.notificationsSend,
      AdminPermissions.emailCampaignHistoryView:
          AdminPermissions.notificationsView,
      AdminPermissions.emailCampaignManage: AdminPermissions.notificationsSend,
    };
    return permissions.contains(legacy[permission]);
  }

  bool get isServicePaySuperAdmin =>
      normalizeRole(role) == 'SERVICEPAY_SUPER_ADMIN';

  bool _hasExplicit(String permission) => permissions.any(
        (value) => value.trim().toLowerCase() == permission.toLowerCase(),
      );

  bool hasFeatureControl(String permission) {
    final normalized = permission.trim().toLowerCase();
    if (normalized == AdminPermissions.featureControlView) {
      return isServicePaySuperAdmin ||
          _hasExplicit(AdminPermissions.featureControlView);
    }
    if (normalized == AdminPermissions.featureControlManage) {
      return isServicePaySuperAdmin ||
          _hasExplicit(AdminPermissions.featureControlManage);
    }
    if (normalized == AdminPermissions.featureControlProtectedManage) {
      return isServicePaySuperAdmin ||
          _hasExplicit(AdminPermissions.featureControlProtectedManage);
    }
    return false;
  }

  /// Feature Controls deliberately does not inherit the broad legacy admin
  /// access rules. The API's three feature-control permissions are explicit;
  /// only SERVICEPAY_SUPER_ADMIN has implicit access to protected changes.
  bool get canViewFeatureControls =>
      hasFeatureControl(AdminPermissions.featureControlView);

  bool get canManageFeatureControls =>
      hasFeatureControl(AdminPermissions.featureControlManage);

  bool get canProtectedManageFeatureControls =>
      hasFeatureControl(AdminPermissions.featureControlProtectedManage);

  bool hasAny(Iterable<String> required) {
    final values = required.toList();
    if (values.isNotEmpty &&
        values.every(
          (permission) =>
              permission.trim().toLowerCase().startsWith('feature_control.'),
        )) {
      return values.any(has);
    }
    return isFullAccess || values.any(permissions.contains);
  }

  static AdminAccess fromUser(Map<String, dynamic> user) {
    final dynamic rawPermissions =
        user['permissions'] ?? (user['staffRole'] as Map?)?['permissions'];
    final Set<String> permissions = rawPermissions is List
        ? rawPermissions
            .map((dynamic value) => value.toString().trim())
            .where((String value) => value.isNotEmpty)
            .toSet()
        : <String>{};
    final dynamic rawScope = user['accessScope'];
    return AdminAccess(
      role: normalizeRole(
        (user['role'] ?? user['effectiveRole'] ?? '').toString(),
      ),
      permissions: permissions,
      scope: rawScope is Map
          ? Map<String, dynamic>.from(rawScope)
          : const <String, dynamic>{},
    );
  }
}

abstract final class AdminSessionStore {
  static const _permissionsKey = 'admin_effective_permissions';
  static const _scopeKey = 'admin_access_scope';

  static Future<void> saveAccess(AdminAccess access) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _permissionsKey,
      access.permissions.toList()..sort(),
    );
    await prefs.setString(_scopeKey, jsonEncode(access.scope));
  }

  static Future<AdminAccess> loadAccess() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String role = (prefs.getString('user_role') ?? '').toUpperCase();
    final Set<String> permissions =
        (prefs.getStringList(_permissionsKey) ?? const <String>[]).toSet();
    Map<String, dynamic> scope = const <String, dynamic>{};
    final String? encodedScope = prefs.getString(_scopeKey);
    if (encodedScope != null && encodedScope.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(encodedScope);
        if (decoded is Map) scope = Map<String, dynamic>.from(decoded);
      } catch (_) {
        scope = const <String, dynamic>{};
      }
    }
    return AdminAccess(role: role, permissions: permissions, scope: scope);
  }

  static Future<void> clearSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    const List<String> keys = <String>[
      'auth_token',
      'token',
      'access_token',
      'accessToken',
      'jwt_token',
      'jwt',
      'user_id',
      'user_name',
      'user_phone',
      'user_email',
      'user_role',
      'user_status',
      'wallet_balance',
      _permissionsKey,
      _scopeKey,
    ];
    for (final String key in keys) {
      await prefs.remove(key);
    }
  }
}
