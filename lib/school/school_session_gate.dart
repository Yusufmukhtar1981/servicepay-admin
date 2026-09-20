import 'dart:convert';

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
    if (await _consumeHandoff(prefs)) return;
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

  Future<bool> _consumeHandoff(SharedPreferences prefs) async {
    try {
      final decoded = await api.consumeHandoff();
      final token = decoded['token']?.toString().trim() ?? '';
      final school = decoded['school'] as Map?;
      final membership = decoded['schoolMembership'] as Map?;
      final user = decoded['user'] as Map?;
      final schoolId = (decoded['schoolId'] ??
              membership?['schoolId'] ??
              school?['_id'] ??
              school?['id'])
          ?.toString()
          .trim();
      final role = (decoded['role'] ?? membership?['role'])
          ?.toString()
          .trim()
          .toUpperCase();
      if (token.isEmpty ||
          schoolId == null ||
          schoolId.isEmpty ||
          role == null ||
          role.isEmpty) {
        throw const EduPaySchoolApiException(
          'School Portal handoff returned an incomplete session.',
          statusCode: 502,
        );
      }
      await prefs.setString('school_auth_token', token);
      await prefs.setString('school_id', schoolId);
      await prefs.setString('school_role', role);
      await prefs.setString(
        'school_name',
        school?['name']?.toString() ?? 'School',
      );
      await prefs.setString(
        'school_membership_status',
        membership?['status']?.toString().trim().toUpperCase() ?? 'ACTIVE',
      );
      await prefs.setString(
        'school_status',
        membership?['schoolStatus']?.toString().trim().toUpperCase() ??
            school?['status']?.toString().trim().toUpperCase() ??
            'APPROVED',
      );
      if (user != null) {
        await prefs.setString(
          'school_authenticated_user',
          jsonEncode(Map<String, dynamic>.from(user)),
        );
      }
      final mustChange = decoded['mustChangePassword'] == true ||
          user?['mustChangePassword'] == true;
      await prefs.setBool('school_must_change_password', mustChange);
      if (mounted) {
        setState(() {
          authenticated = true;
          mustChangePassword = mustChange;
          loading = false;
        });
      }
      return true;
    } on EduPaySchoolApiException catch (exception) {
      if (mounted && exception.statusCode != 401) {
        setState(() => error = exception.message);
      }
      return false;
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.toString().replaceFirst('Exception: ', ''),
        );
      }
      return false;
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
