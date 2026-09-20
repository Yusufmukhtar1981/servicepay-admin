import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'change_password_screen.dart';
import 'edupay_school_api.dart';
import 'school_login_screen.dart';
import 'school_portal_screen.dart';

class SchoolSessionGate extends StatefulWidget {
  const SchoolSessionGate({super.key, this.api, this.portalBuilder});

  final EduPaySchoolApi? api;
  final Widget Function(EduPaySchoolApi api)? portalBuilder;

  @override
  State<SchoolSessionGate> createState() => _SchoolSessionGateState();
}

class _SchoolSessionGateState extends State<SchoolSessionGate> {
  bool loading = true;
  bool authenticated = false;
  bool mustChangePassword = false;
  bool restorationFailed = false;
  String? error;

  EduPaySchoolApi get api => widget.api ?? EduPaySchoolApi();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    setState(() {
      loading = true;
      restorationFailed = false;
      error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('school_auth_token')?.trim() ?? '';
    final schoolId = prefs.getString('school_id')?.trim() ?? '';
    final role = prefs.getString('school_role')?.trim().toUpperCase() ?? '';
    final status =
        prefs.getString('school_membership_status')?.trim().toUpperCase() ?? '';
    if (token.isEmpty ||
        schoolId.isEmpty ||
        role.isEmpty ||
        status != 'ACTIVE') {
      await _clearSession(prefs);
      if (mounted) {
        setState(() {
          authenticated = false;
          loading = false;
        });
      }
      return;
    }
    try {
      final validationPath =
          const {'OWNER', 'ADMIN', 'SCHOOL_ADMIN', 'FINANCE'}.contains(role)
              ? '/edupay/school/dashboard'
              : '/edupay/school/academic/dashboard';
      await api.request('GET', validationPath);
      if (mounted) {
        setState(() {
          authenticated = true;
          mustChangePassword =
              prefs.getBool('school_must_change_password') == true;
          loading = false;
        });
      }
    } catch (exception) {
      final denied = exception is EduPaySchoolApiException &&
          (exception.statusCode == 401 || exception.statusCode == 403);
      if (denied) await _clearSession(prefs);
      if (mounted) {
        setState(() {
          authenticated = false;
          loading = false;
          restorationFailed = !denied;
          error = exception.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _clearSession(SharedPreferences prefs) async {
    for (final key in const [
      'school_auth_token',
      'school_role',
      'school_name',
      'school_id',
      'school_membership_status',
      'school_status',
      'school_authenticated_user',
      'school_must_change_password',
    ]) {
      await prefs.remove(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (restorationFailed) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Unable to restore the School Portal session.',
                  textAlign: TextAlign.center,
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 16),
                FilledButton(onPressed: _restore, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }
    if (!authenticated) {
      return SchoolLoginScreen(initialError: error);
    }
    if (mustChangePassword) return const ChangePasswordScreen();
    return widget.portalBuilder?.call(api) ?? SchoolPortalScreen(api: api);
  }
}
