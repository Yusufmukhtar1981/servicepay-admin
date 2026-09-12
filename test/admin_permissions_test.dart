import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';

void main() {
  test('Head Office retains full access', () {
    const AdminAccess access = AdminAccess(
      role: 'HEAD_OFFICE',
      permissions: <String>{},
    );

    expect(access.isFullAccess, isTrue);
    expect(access.has(AdminPermissions.rolesDelete), isTrue);
  });

  test('ServicePay super admin retains full access', () {
    const AdminAccess access = AdminAccess(
      role: 'servicepay-super-admin',
      permissions: <String>{},
    );

    expect(access.isFullAccess, isTrue);
    expect(access.has(AdminPermissions.organizationsView), isTrue);
  });

  test('staff access exposes only assigned modules', () {
    const AdminAccess access = AdminAccess(
      role: 'STAFF',
      permissions: <String>{
        AdminPermissions.dashboardView,
        AdminPermissions.supportView,
      },
    );

    expect(access.has(AdminPermissions.dashboardView), isTrue);
    expect(access.has(AdminPermissions.supportView), isTrue);
    expect(access.has(AdminPermissions.rolesView), isFalse);
    expect(access.has(AdminPermissions.walletsView), isFalse);
  });

  test('server user payload hydrates role, permissions, and scope', () {
    final AdminAccess access = AdminAccess.fromUser(<String, dynamic>{
      'role': 'STATE_MANAGER',
      'permissions': <String>[AdminPermissions.usersView],
      'accessScope': <String, dynamic>{'type': 'STATE', 'state': 'Lagos'},
    });

    expect(access.role, 'STATE_MANAGER');
    expect(access.has(AdminPermissions.usersView), isTrue);
    expect(access.scope['type'], 'STATE');
    expect(access.scope['state'], 'Lagos');
  });

  test('legacy notification permissions keep Email Center access', () {
    const AdminAccess access = AdminAccess(
      role: 'STAFF',
      permissions: <String>{
        AdminPermissions.notificationsView,
        AdminPermissions.notificationsCreate,
        AdminPermissions.notificationsSend,
      },
    );

    expect(access.has(AdminPermissions.communicationsView), isTrue);
    expect(access.has(AdminPermissions.emailCampaignCreate), isTrue);
    expect(access.has(AdminPermissions.emailCampaignSend), isTrue);
    expect(access.has(AdminPermissions.emailCampaignHistoryView), isTrue);
    expect(access.has(AdminPermissions.emailCampaignManage), isTrue);
  });

  test('transaction intelligence has an explicit read permission', () {
    const AdminAccess access = AdminAccess(
      role: 'STAFF',
      permissions: <String>{AdminPermissions.transactionIntelligenceView},
    );
    expect(access.has(AdminPermissions.transactionIntelligenceView), isTrue);
    expect(
      access.has(AdminPermissions.transactionIntelligenceRequery),
      isFalse,
    );
  });

  test(
    'organization administration permissions remain independently scoped',
    () {
      const AdminAccess reviewer = AdminAccess(
        role: 'STAFF',
        permissions: <String>{
          AdminPermissions.organizationsView,
          AdminPermissions.organizationsReview,
        },
      );
      expect(reviewer.has(AdminPermissions.organizationsView), isTrue);
      expect(reviewer.has(AdminPermissions.organizationsReview), isTrue);
      expect(reviewer.has(AdminPermissions.organizationsStatusManage), isFalse);
      expect(reviewer.has(AdminPermissions.organizationsWalletManage), isFalse);
    },
  );

  test(
    'treasury permissions are independently scoped from organization admin',
    () {
      const AdminAccess access = AdminAccess(
        role: 'STAFF',
        permissions: <String>{
          AdminPermissions.organizationsWithdrawalsView,
          AdminPermissions.organizationsSettlementAccountsReview,
          AdminPermissions.organizationsTreasuryManage,
        },
      );

      expect(access.has(AdminPermissions.organizationsWithdrawalsView), isTrue);
      expect(
        access.has(AdminPermissions.organizationsWithdrawalsReview),
        isFalse,
      );
      expect(
        access.has(AdminPermissions.organizationsSettlementAccountsView),
        isFalse,
      );
      expect(
        access.has(AdminPermissions.organizationsSettlementAccountsReview),
        isTrue,
      );
      expect(access.has(AdminPermissions.organizationsTreasuryManage), isTrue);
      expect(access.has(AdminPermissions.organizationsReview), isFalse);
    },
  );

  test('feature control permissions stay explicit by action', () {
    const AdminAccess viewer = AdminAccess(
      role: 'STAFF',
      permissions: <String>{AdminPermissions.featureControlView},
    );
    expect(viewer.canViewFeatureControls, isTrue);
    expect(viewer.has(AdminPermissions.featureControlView), isTrue);
    expect(viewer.has(AdminPermissions.featureControlManage), isFalse);
    expect(viewer.canManageFeatureControls, isFalse);
    expect(viewer.canProtectedManageFeatureControls, isFalse);

    const AdminAccess manager = AdminAccess(
      role: 'STAFF',
      permissions: <String>{
        AdminPermissions.featureControlView,
        AdminPermissions.featureControlManage,
      },
    );
    expect(manager.canViewFeatureControls, isTrue);
    expect(manager.canManageFeatureControls, isTrue);
    expect(manager.has(AdminPermissions.featureControlManage), isTrue);
    expect(manager.canProtectedManageFeatureControls, isFalse);
  });

  test('only ServicePay super admin has implicit protected access', () {
    const AdminAccess superAdmin = AdminAccess(
      role: 'servicepay-super-admin',
      permissions: <String>{},
    );
    expect(superAdmin.canViewFeatureControls, isTrue);
    expect(superAdmin.canManageFeatureControls, isTrue);
    expect(superAdmin.canProtectedManageFeatureControls, isTrue);

    const AdminAccess headOffice = AdminAccess(
      role: 'HEAD_OFFICE',
      permissions: <String>{},
    );
    expect(headOffice.canViewFeatureControls, isFalse);
    expect(headOffice.has(AdminPermissions.featureControlView), isFalse);
    expect(headOffice.has(AdminPermissions.featureControlManage), isFalse);
    expect(headOffice.canManageFeatureControls, isFalse);
    expect(headOffice.canProtectedManageFeatureControls, isFalse);
  });
}
