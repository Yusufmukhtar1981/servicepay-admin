import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_phone_financing_screen.dart';
import 'login_screen.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      home: const AdminLoginScreen(),
      routes: <String, WidgetBuilder>{
        '/phone-financing': (_) => const _PhoneFinancingRouteGate(),
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
