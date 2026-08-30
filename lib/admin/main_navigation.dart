import 'package:flutter/material.dart';

import 'admin_dashboard_screen.dart';
import 'admin_manual_funding_screen.dart';
import 'admin_notifications_screen.dart';
import 'admin_bulk_email_screen.dart';
import 'admin_customer_support_screen.dart';
import 'admin_kyc_review_screen.dart';
import 'admin_empowerment_screen.dart';
import 'admin_amana_screen.dart';
import 'admin_fintech_operations_screen.dart';
import 'admin_customer_withdrawals_screen.dart';

import 'admin_airtime_to_cash_screen.dart';
import 'admin_solar_screen.dart';
import 'admin_permissions.dart';
import 'admin_roles_permissions_screen.dart';

class AdminMainNavigation extends StatefulWidget {
  const AdminMainNavigation({super.key});

  @override
  State<AdminMainNavigation> createState() => _AdminMainNavigationState();
}

class _AdminMainNavigationState extends State<AdminMainNavigation> {
  int currentIndex = 0;
  AdminAccess? access;

  static const List<_AdminDestination> destinations = <_AdminDestination>[
    _AdminDestination(
        'Dashboard',
        Icons.dashboard_outlined,
        Icons.dashboard_rounded,
        AdminPermissions.dashboardView,
        AdminDashboardScreen()),
    _AdminDestination(
        'Funding',
        Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet_rounded,
        AdminPermissions.fundingView,
        AdminManualFundingScreen()),
    _AdminDestination(
        'Notifications',
        Icons.notifications_outlined,
        Icons.notifications_rounded,
        AdminPermissions.notificationsView,
        AdminNotificationsScreen()),
    _AdminDestination(
        'Bulk Email',
        Icons.mark_email_unread_outlined,
        Icons.mark_email_unread_rounded,
        AdminPermissions.notificationsView,
        AdminBulkEmailScreen()),
    _AdminDestination(
        'Support',
        Icons.support_agent_outlined,
        Icons.support_agent_rounded,
        AdminPermissions.supportView,
        AdminCustomerSupportScreen()),
    _AdminDestination(
        'Control',
        Icons.admin_panel_settings_outlined,
        Icons.admin_panel_settings_rounded,
        AdminPermissions.financeView,
        AdminFintechOperationsScreen()),
    _AdminDestination(
        'Withdrawals',
        Icons.payments_outlined,
        Icons.payments_rounded,
        AdminPermissions.withdrawalsView,
        AdminCustomerWithdrawalsScreen()),
    _AdminDestination(
        'Airtime Cash',
        Icons.currency_exchange_outlined,
        Icons.currency_exchange_rounded,
        AdminPermissions.airtimeToCashView,
        AdminAirtimeToCashScreen()),
    _AdminDestination('KYC', Icons.verified_user_outlined, Icons.verified_user,
        AdminPermissions.kycView, AdminKycReviewScreen()),
    _AdminDestination(
        'Empowerment',
        Icons.volunteer_activism_outlined,
        Icons.volunteer_activism,
        AdminPermissions.empowermentView,
        AdminEmpowermentScreen()),
    _AdminDestination('Amana', Icons.shopping_basket_outlined,
        Icons.shopping_basket, AdminPermissions.amanaView, AdminAmanaScreen()),
    _AdminDestination('Solar', Icons.solar_power_outlined, Icons.solar_power,
        AdminPermissions.solarView, AdminSolarScreen()),
    _AdminDestination(
        'Staff & Roles',
        Icons.manage_accounts_outlined,
        Icons.manage_accounts,
        AdminPermissions.rolesView,
        AdminRolesPermissionsScreen()),
  ];

  @override
  void initState() {
    super.initState();
    AdminSessionStore.loadAccess().then((AdminAccess value) {
      if (mounted) setState(() => access = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (access == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final List<_AdminDestination> allowed = destinations
        .where((_AdminDestination item) => access!.has(item.permission))
        .toList();
    if (allowed.isEmpty) {
      return const Scaffold(
        body: Center(
            child: Text('No Admin modules are assigned to this account.')),
      );
    }
    if (currentIndex >= allowed.length) currentIndex = 0;
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: allowed.map((_AdminDestination item) => item.page).toList(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF0F766E),
        unselectedItemColor: const Color(0xFF94A3B8),
        backgroundColor: Colors.white,
        elevation: 12,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
        onTap: (int index) {
          setState(() {
            currentIndex = index;
          });
        },
        items: allowed
            .map(
              (_AdminDestination item) => BottomNavigationBarItem(
                icon: Icon(item.icon),
                activeIcon: Icon(item.activeIcon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _AdminDestination {
  const _AdminDestination(
    this.label,
    this.icon,
    this.activeIcon,
    this.permission,
    this.page,
  );

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String permission;
  final Widget page;
}
