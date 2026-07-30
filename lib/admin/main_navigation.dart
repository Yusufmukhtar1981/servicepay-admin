import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_dashboard_screen.dart';
import 'admin_delivery_screen.dart';
import 'admin_manual_funding_screen.dart';
import 'admin_notifications_screen.dart';
import 'admin_settings_screen.dart';
import 'users_screen.dart';

class AdminMainNavigation extends StatefulWidget {
  const AdminMainNavigation({super.key});

  @override
  State<AdminMainNavigation> createState() =>
      _AdminMainNavigationState();
}

class _AdminMainNavigationState
    extends State<AdminMainNavigation> {
  int currentIndex = 0;
  bool isLoading = true;
  String adminRole = '';

  List<Widget> pages = const [];
  List<BottomNavigationBarItem> items = const [];

  @override
  void initState() {
    super.initState();
    loadRole();
  }

  String normalizeRole(String? value) {
    return (value ?? '')
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]+'), '_');
  }

  Future<void> loadRole() async {
    final prefs =
        await SharedPreferences.getInstance();

    final role = normalizeRole(
      prefs.getString('user_role') ??
          prefs.getString('admin_role') ??
          prefs.getString('role'),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      adminRole = role;
      currentIndex = 0;
      configureNavigation();
      isLoading = false;
    });
  }

  void configureNavigation() {
    if (adminRole == 'HEAD_OFFICE') {
      pages = const [
        AdminDashboardScreen(),
        AdminDeliveryScreen(),
        AdminManualFundingScreen(),
        AdminNotificationsScreen(),
        AdminSettingsScreen(),
      ];

      items = const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_outlined),
          activeIcon: Icon(Icons.dashboard_rounded),
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.local_shipping_outlined),
          activeIcon: Icon(Icons.local_shipping_rounded),
          label: 'Deliveries',
        ),
        BottomNavigationBarItem(
          icon: Icon(
            Icons.account_balance_wallet_outlined,
          ),
          activeIcon: Icon(
            Icons.account_balance_wallet_rounded,
          ),
          label: 'Funding',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.notifications_outlined),
          activeIcon: Icon(Icons.notifications_rounded),
          label: 'Alerts',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings_rounded),
          label: 'Settings',
        ),
      ];

      return;
    }

    if (adminRole == 'ZONAL_MANAGER' ||
        adminRole == 'STATE_MANAGER') {
      pages = const [
        AdminDashboardScreen(),
        AdminUsersScreen(),
      ];

      items = const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_outlined),
          activeIcon: Icon(Icons.dashboard_rounded),
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.manage_accounts_outlined),
          activeIcon: Icon(Icons.manage_accounts_rounded),
          label: 'Users',
        ),
      ];

      return;
    }

    pages = const [
      _AccessDeniedScreen(),
    ];

    items = const [
      BottomNavigationBarItem(
        icon: Icon(Icons.block_outlined),
        activeIcon: Icon(Icons.block_rounded),
        label: 'Access',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final safeIndex =
        currentIndex < pages.length
            ? currentIndex
            : 0;

    return Scaffold(
      body: IndexedStack(
        index: safeIndex,
        children: pages,
      ),
      bottomNavigationBar:
          BottomNavigationBar(
        currentIndex: safeIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor:
            const Color(0xFF0F766E),
        unselectedItemColor:
            const Color(0xFF94A3B8),
        backgroundColor: Colors.white,
        onTap: (index) {
          if (index >= pages.length) {
            return;
          }

          setState(() {
            currentIndex = index;
          });
        },
        items: items,
      ),
    );
  }
}

class _AccessDeniedScreen
    extends StatelessWidget {
  const _AccessDeniedScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.block_rounded,
                color: Colors.red,
                size: 64,
              ),
              SizedBox(height: 16),
              Text(
                'Access denied',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'This account is not allowed to use the management application.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
