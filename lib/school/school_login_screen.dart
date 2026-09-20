import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'school_portal_screen.dart';
import 'school_registration_screen.dart';
import 'change_password_screen.dart';

class SchoolLoginScreen extends StatefulWidget {
  const SchoolLoginScreen({
    super.key,
    this.initialError,
    this.client,
    this.authenticatedBuilder,
  });

  final String? initialError;
  final http.Client? client;
  final Widget Function(bool mustChangePassword)? authenticatedBuilder;

  @override
  State<SchoolLoginScreen> createState() => _SchoolLoginScreenState();
}

class _SchoolLoginScreenState extends State<SchoolLoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  late String? error = widget.initialError;
  List<Map<String, dynamic>> schoolOptions = [];
  String? selectedSchoolId;

  Future<void> _login() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final uri =
          Uri.parse('https://api.servicepay.ng/api/edupay/school/auth/login');
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      final body = jsonEncode({
        'email': email.text.trim(),
        'password': password.text,
        if (selectedSchoolId != null) 'schoolId': selectedSchoolId,
      });
      final response = widget.client == null
          ? await http.post(uri, headers: headers, body: body)
          : await widget.client!.post(
              uri,
              headers: headers,
              body: body,
            );
      final decoded = jsonDecode(response.body) as Map;
      if (response.statusCode == 409 &&
          decoded['code'] == 'EDUPAY_SCHOOL_CONTEXT_REQUIRED' &&
          decoded['schools'] is List) {
        final options = (decoded['schools'] as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        if (mounted) {
          setState(() {
            schoolOptions = options;
            selectedSchoolId = options.length == 1
                ? options.first['schoolId']?.toString()
                : null;
            error = decoded['message']?.toString() ??
                'Select the school you want to open.';
            loading = false;
          });
        }
        return;
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded['success'] != true) {
        throw Exception(decoded['message'] ?? 'Invalid school credentials.');
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('school_auth_token', decoded['token'].toString());
      final school = decoded['school'] as Map?;
      final membership = decoded['schoolMembership'] as Map?;
      final user = decoded['user'] as Map?;
      final role = decoded['role'] ??
          membership?['role'] ??
          decoded['schoolRole'] ??
          school?['role'] ??
          user?['role'];
      if (role != null) {
        await prefs.setString(
          'school_role',
          role.toString().trim().toUpperCase(),
        );
      }
      await prefs.setString(
        'school_name',
        school?['name']?.toString() ?? 'School',
      );
      final schoolId = decoded['schoolId'] ??
          membership?['schoolId'] ??
          school?['_id'] ??
          school?['id'];
      if (schoolId != null && schoolId.toString().trim().isNotEmpty) {
        await prefs.setString('school_id', schoolId.toString().trim());
      }
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
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                widget.authenticatedBuilder?.call(mustChange) ??
                (mustChange
                    ? const ChangePasswordScreen()
                    : const SchoolPortalScreen()),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.school_rounded,
                      size: 42,
                      color: Color(0xff08783e),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'EduPay School Portal',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A calm workspace for your school fees and settlements.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 26),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'School email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    if (schoolOptions.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: selectedSchoolId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'School',
                          prefixIcon: Icon(Icons.account_balance_outlined),
                        ),
                        items: schoolOptions
                            .map(
                              (school) => DropdownMenuItem<String>(
                                value: school['schoolId']?.toString(),
                                child: Text(
                                  '${school['schoolName'] ?? 'School'} · ${school['role'] ?? ''}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: loading
                            ? null
                            : (value) => setState(() {
                                  selectedSchoolId = value;
                                  error = null;
                                }),
                      ),
                    ],
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          error!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: loading ||
                                (schoolOptions.isNotEmpty &&
                                    selectedSchoolId == null)
                            ? null
                            : _login,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Sign in'),
                        ),
                      ),
                    ),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SchoolRegistrationScreen(),
                          ),
                        ),
                        child: const Text('Register your school'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
