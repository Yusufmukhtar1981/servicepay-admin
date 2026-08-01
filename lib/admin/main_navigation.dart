import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../login_screen.dart';

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

    if (role != 'HEAD_OFFICE') {
      await prefs.clear();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const LoginScreen(),
        ),
        (route) => false,
      );

      return;
    }

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
        label: 'Wallet',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.notifications_outlined),
        activeIcon: Icon(Icons.notifications_rounded),
        label: 'Notifications',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.settings_outlined),
        activeIcon: Icon(Icons.settings_rounded),
        label: 'Settings',
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
