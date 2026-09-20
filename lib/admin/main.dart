import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_control_center_screen.dart';
import 'admin_permissions.dart';
import 'admin_phone_financing_screen.dart';
import 'login_screen.dart';
import 'svp_management_screen.dart';
import 'admin_theme.dart';
import 'edupay_control_center_screen.dart';
import '../school/school_session_gate.dart';

void main() {
  runApp(const ServicepayAdminApp());
}

class ServicepayAdminApp extends StatelessWidget {
  const ServicepayAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Servicepay Admin',
      theme: AdminTheme.light(),
      darkTheme: AdminTheme.dark(),
      themeMode: ThemeMode.system,
      home: kIsWeb &&
              (Uri.base.path.startsWith('/school') ||
                  Uri.base.queryParameters['entry'] == 'school')
          ? const SchoolSessionGate()
          : const AdminLoginScreen(),
      routes: <String, WidgetBuilder>{
        '/school': (_) => const SchoolSessionGate(),
        '/edupay': (_) => const _EduPayRouteGate(),
        '/svp': (_) => const _SvpRouteGate(),
        '/phone-financing': (_) => const _PhoneFinancingRouteGate(),
        '/control-center/audit-logs': (_) =>
            const _ControlCenterRouteGate(moduleId: 'audit-logs'),
        '/control-center/security-events': (_) =>
            const _ControlCenterRouteGate(moduleId: 'security-events'),
        '/control-center/access-logs': (_) =>
            const _ControlCenterRouteGate(moduleId: 'access-logs'),
        '/control-center/data-exports': (_) =>
            const _ControlCenterRouteGate(moduleId: 'data-exports'),
        '/control-center/backups': (_) =>
            const _ControlCenterRouteGate(moduleId: 'backups'),
        '/control-center/privacy-controls': (_) =>
            const _ControlCenterRouteGate(moduleId: 'privacy-controls'),
        '/control-center/executive-dashboard': (_) =>
            const _ControlCenterRouteGate(moduleId: 'executive-dashboard'),
        '/control-center/service-performance': (_) =>
            const _ControlCenterRouteGate(moduleId: 'service-performance'),
        '/control-center/transaction-analytics': (_) =>
            const _ControlCenterRouteGate(moduleId: 'transaction-analytics'),
        '/control-center/customer-analytics': (_) =>
            const _ControlCenterRouteGate(moduleId: 'customer-analytics'),
      },
    );
  }
}

class _EduPayRouteGate extends StatefulWidget {
  const _EduPayRouteGate();
  @override
  State<_EduPayRouteGate> createState() => _EduPayRouteGateState();
}

class _EduPayRouteGateState extends State<_EduPayRouteGate> {
  late final Future<bool> _allowed = _check();
  Future<bool> _check() async {
    final p = await SharedPreferences.getInstance();
    final token = p.getString('auth_token')?.trim() ?? '';
    final role = p.getString('user_role')?.trim().toUpperCase() ?? '';
    final permissions = (p.getStringList('staff_permissions') ?? <String>[])
        .map((value) => value.toLowerCase())
        .toSet();
    return token.isNotEmpty &&
        const {
          'HEAD_OFFICE',
          'ADMIN',
          'SUPER_ADMIN',
          'HEAD_OFFICE_ADMIN',
          'SERVICEPAY_SUPER_ADMIN',
        }.contains(role) &&
        permissions.contains(AdminPermissions.edupayView);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _allowed,
        builder: (context, s) => s.connectionState != ConnectionState.done
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : s.data == true
                ? const EduPayControlCenterScreen()
                : const AdminLoginScreen(),
      );
}

class _SvpRouteGate extends StatefulWidget {
  const _SvpRouteGate();

  @override
  State<_SvpRouteGate> createState() => _SvpRouteGateState();
}

class _SvpRouteGateState extends State<_SvpRouteGate> {
  late final Future<String> _access = _checkAccess();

  Future<String> _checkAccess() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String token = preferences.getString('auth_token')?.trim() ?? '';
    if (token.isEmpty) return 'UNAUTHENTICATED';
    final AdminAccess access = await AdminSessionStore.loadAccess();
    return access.has(AdminPermissions.svpManagementView)
        ? 'AUTHORIZED'
        : 'FORBIDDEN';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _access,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == 'AUTHORIZED') {
          return const SvpManagementScreen();
        }
        if (snapshot.data == 'UNAUTHENTICATED') {
          return const AdminLoginScreen();
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Access denied')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '403 — This account does not have access to SVP Management.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhoneFinancingRouteGate extends StatefulWidget {
  const _PhoneFinancingRouteGate();

  @override
  State<_PhoneFinancingRouteGate> createState() =>
      _PhoneFinancingRouteGateState();
}

class _PhoneFinancingRouteGateState extends State<_PhoneFinancingRouteGate> {
  late final Future<bool> _isAuthorized = _checkAuthorization();

  Future<bool> _checkAuthorization() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String token = preferences.getString('auth_token')?.trim() ?? '';
    final String role =
        preferences.getString('user_role')?.trim().toUpperCase() ?? '';

    return token.isNotEmpty && role == 'HEAD_OFFICE';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAuthorized,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data == true) {
          return const AdminPhoneFinancingScreen();
        }

        return const AdminLoginScreen();
      },
    );
  }
}

class _ControlCenterRouteGate extends StatefulWidget {
  const _ControlCenterRouteGate({required this.moduleId});

  final String moduleId;

  @override
  State<_ControlCenterRouteGate> createState() =>
      _ControlCenterRouteGateState();
}

class _ControlCenterRouteGateState extends State<_ControlCenterRouteGate> {
  late final Future<String> _access = _checkAccess();

  Future<String> _checkAccess() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String token = preferences.getString('auth_token')?.trim() ?? '';
    final String role =
        preferences.getString('user_role')?.trim().toUpperCase() ?? '';
    if (token.isEmpty) return 'UNAUTHENTICATED';
    if (role == 'HEAD_OFFICE') return 'AUTHORIZED';
    return 'FORBIDDEN';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _access,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == 'AUTHORIZED') {
          return AdminControlCenterScreen(initialModuleId: widget.moduleId);
        }
        if (snapshot.data == 'UNAUTHENTICATED') {
          return const AdminLoginScreen();
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Access denied')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '403 — This Control Center workspace requires a HEAD_OFFICE account.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}
