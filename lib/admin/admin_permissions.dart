import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract final class AdminPermissions {
  static const edupayView = 'edupay.view';
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
  static const announcementsView = 'announcements.view';
  static const announcementsSummary = 'announcements.summary';
  static const announcementsCreate = 'announcements.create';
  static const announcementsUpdate = 'announcements.update';
  static const announcementsActivate = 'announcements.activate';
  static const announcementsDelete = 'announcements.delete';
  static const announcementsParticipantsView =
      'announcements.participants.view';
  static const announcementsParticipantsHistoryView =
      'announcements.participants.history_view';
  static const announcementsWinnerManage = 'announcements.winner.mark';
  static const announcementsWinnersView = 'announcements.winners.view';
  static const promoParticipantsView = announcementsParticipantsView;
  static const promoParticipantsHistoryView =
      announcementsParticipantsHistoryView;
  static const promoWinnerManage = announcementsWinnerManage;
  static const promoWinnersView = announcementsWinnersView;
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
  static const organizationsDocumentsView = 'organizations.documents.view';
  static const organizationsWithdrawalsView = 'organizations.withdrawals.view';
  static const organizationsWithdrawalsReview =
      'organizations.withdrawals.review';
  static const organizationsSettlementAccountsView =
      'organizations.settlement_accounts.view';
  static const organizationsSettlementAccountsReview =
      'organizations.settlement_accounts.review';
  static const organizationsTreasuryManage = 'organizations.treasury.manage';

  // Head Office Business Partner administration. These permissions are
  // intentionally separate from the partner portal's service permissions so
  // customer, financial and audit data is never exposed by a broad Admin role.
  static const businessPartnersView = 'business_partners.view';
  static const referralsView = 'referrals.view';
  static const businessPartnersUpdate = 'business_partners.update';
  static const businessPartnersCreate = 'business_partners.create';
  static const businessPartnersAssign = 'business_partners.assign';
  static const businessPartnersCustomersView =
      'business_partners.customers.view';
  static const businessPartnersOfficersView = 'business_partners.officers.view';
  static const businessPartnersTransactionsView =
      'business_partners.transactions.view';
  static const businessPartnersCommissionsView =
      'business_partners.commissions.view';
  static const businessPartnersTargetsView = 'business_partners.targets.view';
  static const businessPartnersBonusesView = 'business_partners.bonuses.view';
  static const businessPartnersLiabilitiesView =
      'business_partners.liabilities.view';
  static const businessPartnersAuditView = 'business_partners.audit.view';
  static const businessPartnersRulesManage = businessPartnersUpdate;
  static const businessPartnersCommissionRulesManage =
      businessPartnersRulesManage;
  static const businessPartnersBonusRulesManage = businessPartnersRulesManage;
  static const businessPartnersStatus = 'business_partners.status';
  static const businessPartnersStatusManage = businessPartnersStatus;

  static const businessPartnerView = businessPartnersView;
  static const businessPartnerCustomersView = businessPartnersCustomersView;
  static const businessPartnerOfficersView = businessPartnersOfficersView;
  static const businessPartnerTransactionsView =
      businessPartnersTransactionsView;
  static const businessPartnerCommissionsView = businessPartnersCommissionsView;
  static const businessPartnerRulesManage = businessPartnersRulesManage;
  static const businessPartnerStatusManage = businessPartnersStatusManage;
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

  static const Set<String> _headOfficeRoles = <String>{
    'HEAD_OFFICE',
    'HEAD_OFFICE_ADMIN',
    'ADMIN',
    'SUPER_ADMIN',
    'SERVICEPAY_SUPER_ADMIN',
  };

  /// Mirrors the backend role aliases which produce staffAccess.isHeadOffice.
  bool get isHeadOffice => _headOfficeRoles.contains(normalizeRole(role));

  /// High-trust promotion reports require both Head Office identity and the
  /// participant permission. Scoped staff must not gain access through '*'.
  bool hasHeadOfficePermission(String permission) =>
      isHeadOffice && (_hasExplicit(permission) || permissions.contains('*'));

  static const Set<String> _featureControlMasterRoles = <String>{
    'HEAD_OFFICE',
    'SUPER_ADMIN',
    'HEAD_OFFICE_ADMIN',
    'SERVICEPAY_SUPER_ADMIN',
  };

  bool get isFeatureControlMaster =>
      _featureControlMasterRoles.contains(normalizeRole(role));

  bool _hasExplicit(String permission) => permissions.any(
        (value) => value.trim().toLowerCase() == permission.toLowerCase(),
      );

  bool hasFeatureControl(String permission) {
    final normalized = permission.trim().toLowerCase();
    if (normalized == AdminPermissions.featureControlView) {
      return isFeatureControlMaster ||
          _hasExplicit(AdminPermissions.featureControlView);
    }
    if (normalized == AdminPermissions.featureControlManage) {
      return isFeatureControlMaster ||
          _hasExplicit(AdminPermissions.featureControlManage);
    }
    if (normalized == AdminPermissions.featureControlProtectedManage) {
      return isServicePaySuperAdmin ||
          _hasExplicit(AdminPermissions.featureControlProtectedManage);
    }
    return false;
  }

  /// Established master Admin roles may view and manage Feature Controls.
  /// Protected financial changes remain explicit, except for
  /// SERVICEPAY_SUPER_ADMIN.
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

  /// Business Partner administration is restricted to Head Office roles or
  /// an explicitly assigned granular permission. Broad legacy Admin access
  /// must not implicitly expose partner customer or financial records.
  bool hasBusinessPartnerAdmin(String permission) =>
      const <String>{
        'HEAD_OFFICE',
        'HEAD_OFFICE_ADMIN',
      }.contains(normalizeRole(role)) ||
      _hasExplicit(permission);
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
