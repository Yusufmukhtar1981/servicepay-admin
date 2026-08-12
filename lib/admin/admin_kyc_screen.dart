import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminKycScreen extends StatefulWidget {
  const AdminKycScreen({super.key});

  @override
  State<AdminKycScreen> createState() => _AdminKycScreenState();
}

class _AdminKycScreenState extends State<AdminKycScreen> {
  static const String baseUrl = 'https://api.servicepay.ng/api';

  bool isLoading = true;
  String errorMessage = '';
  String selectedStatus = 'ALL';

  List<Map<String, dynamic>> applications = [];

  final statuses = const [
    'ALL',
    'PENDING',
    'UNDER_REVIEW',
    'VERIFIED',
    'REJECTED',
  ];

  @override
  void initState() {
    super.initState();
    _loadKyc();
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<void> _loadKyc() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final token = await _token();

      if (token == null || token.isEmpty) {
        throw Exception('Admin session expired.');
      }

      var url = '$baseUrl/admin/kyc';

      if (selectedStatus != 'ALL') {
        url += '?status=$selectedStatus';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      dynamic body;

      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = {};
      }

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          body is Map &&
          body['success'] == true) {
        final raw = body['applications'] ??
            body['kycApplications'] ??
            body['data'] ??
            [];

        final list = raw is List ? raw : [];

        if (!mounted) return;

        setState(() {
          applications = list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

          isLoading = false;
        });

        return;
      }

      throw Exception(
        body is Map
            ? (body['message'] ?? 'Unable to load KYC applications.').toString()
            : 'Unable to load KYC applications.',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<bool> _updateKyc({
    required String id,
    required String status,
    String rejectionReason = '',
  }) async {
    try {
      final token = await _token();

      if (token == null || token.isEmpty) {
        _message('Admin session expired.');
        return false;
      }

      final response = await http.patch(
        Uri.parse('$baseUrl/admin/kyc/$id/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'status': status,
          if (rejectionReason.trim().isNotEmpty)
            'rejectionReason': rejectionReason.trim(),
        }),
      );

      dynamic body;

      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = {};
      }

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          body is Map &&
          body['success'] == true) {
        _message(
          (body['message'] ?? 'KYC updated successfully.').toString(),
        );

        await _loadKyc();
        return true;
      }

      _message(
        body is Map
            ? (body['message'] ?? 'Unable to update KYC.').toString()
            : 'Unable to update KYC.',
      );

      return false;
    } catch (_) {
      _message('Unable to update KYC.');
      return false;
    }
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _safe(dynamic value, [String fallback = '-']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _name(Map<String, dynamic> item) {
    final user = item['user'];

    if (user is Map) {
      final fullName = _safe(user['fullName'], '');
      if (fullName.isNotEmpty) return fullName;
    }

    final parts = [
      _safe(item['firstName'], ''),
      _safe(item['middleName'], ''),
      _safe(item['lastName'], ''),
    ].where((e) => e.isNotEmpty).toList();

    return parts.isEmpty ? 'Customer' : parts.join(' ');
  }

  String _phone(Map<String, dynamic> item) {
    final user = item['user'];

    if (user is Map) {
      final phone = _safe(user['phone'], '');
      if (phone.isNotEmpty) return phone;
    }

    return _safe(item['phone']);
  }

  String _email(Map<String, dynamic> item) {
    final user = item['user'];

    if (user is Map) {
      final email = _safe(user['email'], '');
      if (email.isNotEmpty) return email;
    }

    return _safe(item['email']);
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'VERIFIED':
        return Colors.green;
      case 'REJECTED':
        return Colors.red;
      case 'UNDER_REVIEW':
        return Colors.orange;
      case 'PENDING':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (e) => e.isEmpty
              ? e
              : '${e[0].toUpperCase()}${e.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Future<void> _openApplication(
    Map<String, dynamic> item,
  ) async {
    final id = _safe(item['_id'], '');

    if (id.isEmpty) {
      _message('KYC ID not found.');
      return;
    }

    final reasonController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 700,
              maxHeight: 760,
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  color: const Color(0xFF08783E),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_user,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _name(item),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        _row('Phone', _phone(item)),
                        _row('Email', _email(item)),
                        _row(
                          'First Name',
                          _safe(item['firstName']),
                        ),
                        _row(
                          'Middle Name',
                          _safe(item['middleName']),
                        ),
                        _row(
                          'Last Name',
                          _safe(item['lastName']),
                        ),
                        _row(
                          'Date of Birth',
                          _safe(item['dateOfBirth']),
                        ),
                        _row(
                          'Gender',
                          _safe(item['gender']),
                        ),
                        _row(
                          'Address',
                          _safe(item['address']),
                        ),
                        _row(
                          'State',
                          _safe(item['state']),
                        ),
                        _row(
                          'LGA',
                          _safe(item['lga']),
                        ),
                        _row(
                          'KYC Level',
                          _safe(item['level'], 'TIER_1'),
                        ),
                        _row(
                          'Status',
                          _safe(item['status'], 'PENDING'),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final ok = await _updateKyc(
                                  id: id,
                                  status: 'UNDER_REVIEW',
                                );

                                if (ok && dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                              },
                              icon: const Icon(
                                Icons.manage_search,
                              ),
                              label: const Text(
                                'Under Review',
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF08783E),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                final ok = await _updateKyc(
                                  id: id,
                                  status: 'VERIFIED',
                                );

                                if (ok && dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                              },
                              icon: const Icon(Icons.verified),
                              label: const Text('Verify'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: reasonController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Rejection Reason',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            onPressed: () async {
                              final reason = reasonController.text.trim();

                              if (reason.isEmpty) {
                                _message(
                                  'Please enter rejection reason.',
                                );
                                return;
                              }

                              final ok = await _updateKyc(
                                id: id,
                                status: 'REJECTED',
                                rejectionReason: reason,
                              );

                              if (ok && dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            },
                            icon: const Icon(Icons.cancel),
                            label: const Text('Reject KYC'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    reasonController.dispose();
  }

  Widget _row(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 135,
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF08783E);

    return Scaffold(
      appBar: AppBar(
        title: const Text('KYC Review'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadKyc,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 62,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(10),
              children: statuses.map((status) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_statusLabel(status)),
                    selected: selectedStatus == status,
                    onSelected: (_) {
                      setState(() {
                        selectedStatus = status;
                      });
                      _loadKyc();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : errorMessage.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.cloud_off,
                              size: 52,
                            ),
                            const SizedBox(height: 12),
                            Text(errorMessage),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _loadKyc,
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      )
                    : applications.isEmpty
                        ? const Center(
                            child: Text(
                              'No KYC applications found.',
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadKyc,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(14),
                              itemCount: applications.length,
                              itemBuilder: (context, index) {
                                final item = applications[index];

                                final status = _safe(
                                  item['status'],
                                  'PENDING',
                                ).toUpperCase();

                                final color = _statusColor(status);

                                return Card(
                                  margin: const EdgeInsets.only(
                                    bottom: 10,
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(14),
                                    leading: CircleAvatar(
                                      backgroundColor: color.withValues(
                                        alpha: 0.12,
                                      ),
                                      child: Icon(
                                        Icons.person_search,
                                        color: color,
                                      ),
                                    ),
                                    title: Text(
                                      _name(item),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 5),
                                        Text(_phone(item)),
                                        const SizedBox(height: 5),
                                        Text(
                                          _statusLabel(status),
                                          style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right,
                                    ),
                                    onTap: () => _openApplication(item),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
