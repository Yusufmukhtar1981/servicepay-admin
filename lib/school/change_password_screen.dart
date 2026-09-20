import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'edupay_school_api.dart';
import 'school_login_screen.dart';
import 'school_portal_screen.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final currentPassword = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool loading = false;
  String? error;

  Future<void> _submit() async {
    if (currentPassword.text.isEmpty) {
      setState(() => error = 'Enter your current temporary password.');
      return;
    }
    if (password.text.length < 8 || password.text != confirm.text) {
      setState(() =>
          error = 'Passwords must match and contain at least 8 characters.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response =
          await EduPaySchoolApi().request('PUT', '/auth/change-password', {
        'currentPassword': currentPassword.text,
        'newPassword': password.text,
        'confirmPassword': confirm.text,
      });
      final replacementToken = response['token']?.toString().trim();
      if (replacementToken == null || replacementToken.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('school_auth_token');
        await prefs.remove('school_role');
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const SchoolLoginScreen()),
            (_) => false,
          );
        }
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('school_auth_token', replacementToken);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SchoolPortalScreen()),
        );
      }
    } catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Set a new password')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                            'Your temporary password must be changed before continuing.'),
                        const SizedBox(height: 20),
                        TextField(
                            controller: currentPassword,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            decoration: const InputDecoration(
                                labelText: 'Current temporary password')),
                        const SizedBox(height: 12),
                        TextField(
                            controller: password,
                            obscureText: true,
                            decoration: const InputDecoration(
                                labelText: 'New password')),
                        const SizedBox(height: 12),
                        TextField(
                            controller: confirm,
                            obscureText: true,
                            decoration: const InputDecoration(
                                labelText: 'Confirm new password')),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(error!,
                                style: TextStyle(color: Colors.red.shade700)),
                          ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: loading ? null : _submit,
                          child: loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Change password'),
                        ),
                      ]),
                ),
              ),
            ),
          ),
        ),
      );
}
