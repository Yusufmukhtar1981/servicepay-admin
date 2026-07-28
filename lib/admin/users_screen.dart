import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'create_admin_user_dialog.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  static const String baseUrl = 'https://api.servicepay.ng/api';

  final TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> users = [];

  bool isLoading = true;
  bool isUpdating = false;
  String? errorMessage;

  String selectedRole = 'ALL';
  String selectedStatus = 'ALL';

  @override
  void initState() {
    super.initState();
    loadUsers();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('auth_token') ??
        prefs.getString('token') ??
        prefs.getString('admin_token');
  }

  Future<void> loadUsers() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final token = await getToken();

      if (token == null || token.isEmpty) {
        throw Exception('Admin authentication token was not found.');
      }

      final queryParameters = <String, String>{
        'limit': '100',
      };

      final search = searchController.text.trim();

      if (search.isNotEmpty) {
        queryParameters['search'] = search;
      }

      if (selectedRole != 'ALL') {
        queryParameters['role'] = selectedRole;
      }

      if (selectedStatus != 'ALL') {
        queryParameters['status'] = selectedStatus;
      }

      final uri = Uri.parse('$baseUrl/admin/users').replace(
        queryParameters: queryParameters,
      );

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 45));

      final body = jsonDecode(response.body);

      if (response.statusCode == 200 && body['success'] == true) {
        final data = body['data'];
        final rawUsers = data?['users'];

        if (rawUsers is List) {
          setState(() {
            users = rawUsers
                .whereType<Map>()
                .map(
                  (item) => Map<String, dynamic>.from(item),
                )
                .toList();
          });
        } else {
          setState(() {
            users = [];
          });
        }
      } else {
        throw Exception(
          body['message'] ?? 'Failed to load users.',
        );
      }
    } catch (error) {
      setState(() {
        errorMessage = error.toString().replaceFirst(
              'Exception: ',
              '',
            );
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> updateUserStatus(
    Map<String, dynamic> user,
    String newStatus,
  ) async {
    final userId = user['_id']?.toString();

    if (userId == null || userId.isEmpty) {
      showMessage('User ID was not found.', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Action'),
          content: Text(
            'Change ${user['fullName'] ?? 'this user'} status to $newStatus?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      isUpdating = true;
    });

    try {
      final token = await getToken();

      if (token == null || token.isEmpty) {
        throw Exception('Admin authentication token was not found.');
      }

      final response = await http.patch(
        Uri.parse('$baseUrl/admin/users/$userId/status'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'status': newStatus,
        }),
      ).timeout(const Duration(seconds: 45));

      final body = jsonDecode(response.body);

      if (response.statusCode == 200 && body['success'] == true) {
        showMessage(
          body['message'] ?? 'User status updated successfully.',
          isError: false,
        );

        await loadUsers();
      } else {
        throw Exception(
          body['message'] ?? 'Failed to update user status.',
        );
      }
    } catch (error) {
      showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isUpdating = false;
        });
      }
    }
  }

  void showMessage(
    String message, {
    required bool isError,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  void showUserDetails(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['fullName']?.toString() ?? 'Unknown User',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user['role']?.toString() ?? 'CUSTOMER',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _detailRow(
                    'Phone',
                    user['phone']?.toString() ?? 'Not provided',
                  ),
                  _detailRow(
                    'Email',
                    user['email']?.toString() ?? 'Not provided',
                  ),
                  _detailRow(
                    'Status',
                    user['status']?.toString() ?? 'UNKNOWN',
                  ),
                  _detailRow(
                    'Wallet Balance',
                    '₦${formatMoney(user['walletBalance'])}',
                  ),
                  _detailRow(
                    'Commission Balance',
                    '₦${formatMoney(user['commissionBalance'])}',
                  ),
                  _detailRow(
                    'Total Earnings',
                    '₦${formatMoney(user['totalEarnings'])}',
                  ),
                  _detailRow(
                    'KYC Verified',
                    user['kycVerified'] == true ? 'Yes' : 'No',
                  ),
                  _detailRow(
                    'State',
                    user['state']?.toString() ?? 'Not provided',
                  ),
                  _detailRow(
                    'LGA',
                    user['lga']?.toString() ?? 'Not provided',
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Account Actions',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: isUpdating
                            ? null
                            : () {
                                Navigator.pop(context);
                                updateUserStatus(user, 'ACTIVE');
                              },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Activate'),
                      ),
                      OutlinedButton.icon(
                        onPressed: isUpdating
                            ? null
                            : () {
                                Navigator.pop(context);
                                updateUserStatus(user, 'SUSPENDED');
                              },
                        icon: const Icon(Icons.pause_circle_outline),
                        label: const Text('Suspend'),
                      ),
                      OutlinedButton.icon(
                        onPressed: isUpdating
                            ? null
                            : () {
                                Navigator.pop(context);
                                updateUserStatus(user, 'BLOCKED');
                              },
                        icon: const Icon(Icons.block),
                        label: const Text('Block'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String formatMoney(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;

    return amount.toStringAsFixed(2);
  }

  Color statusColor(String status) {
    switch (status) {
      case 'ACTIVE':
        return Colors.green;
      case 'SUSPENDED':
        return Colors.orange;
      case 'BLOCKED':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData roleIcon(String role) {
    switch (role) {
      case 'HEAD_OFFICE':
        return Icons.admin_panel_settings;
      case 'ZONAL_MANAGER':
        return Icons.public;
      case 'STATE_MANAGER':
        return Icons.location_city;
      case 'AGENT':
        return Icons.support_agent;
      default:
        return Icons.person;
    }
  }

  Widget buildFilterDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Expanded(
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        items: items.map((item) {
          return DropdownMenuItem(
            value: item,
            child: Text(
              item.replaceAll('_', ' '),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      appBar: AppBar(
        title: const Text(
          'Manage Users',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Create Account',
            onPressed: isUpdating
                ? null
                : () async {
                    final created =
                        await showCreateAdminUserDialog(
                      context,
                      users,
                    );

                    if (created == true) {
                      await loadUsers();
                    }
                  },
            icon: const Icon(
              Icons.person_add_alt_1,
            ),
          ),
          IconButton(
            onPressed: isLoading ? null : loadUsers,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isUpdating
            ? null
            : () async {
                final created =
                    await showCreateAdminUserDialog(
                  context,
                  users,
                );

                if (created == true) {
                  await loadUsers();
                }
              },
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Create Account'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            color: Colors.green,
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => loadUsers(),
                  decoration: InputDecoration(
                    hintText: 'Search name, phone or email',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              searchController.clear();
                              loadUsers();
                            },
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    buildFilterDropdown(
                      value: selectedRole,
                      items: const [
                        'ALL',
                        'HEAD_OFFICE',
                        'ZONAL_MANAGER',
                        'STATE_MANAGER',
                        'AGENT',
                        'CUSTOMER',
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          selectedRole = value;
                        });

                        loadUsers();
                      },
                    ),
                    const SizedBox(width: 10),
                    buildFilterDropdown(
                      value: selectedStatus,
                      items: const [
                        'ALL',
                        'ACTIVE',
                        'SUSPENDED',
                        'BLOCKED',
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          selectedStatus = value;
                        });

                        loadUsers();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : errorMessage != null
                    ? _buildErrorState()
                    : users.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: loadUsers,
                            child: ListView.separated(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              itemCount: users.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final user = users[index];

                                final role =
                                    user['role']?.toString() ?? 'CUSTOMER';

                                final status =
                                    user['status']?.toString() ?? 'UNKNOWN';

                                return Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () {
                                      showUserDetails(user);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 25,
                                            backgroundColor:
                                                Colors.green.withOpacity(0.12),
                                            child: Icon(
                                              roleIcon(role),
                                              color: Colors.green,
                                            ),
                                          ),
                                          const SizedBox(width: 13),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  user['fullName']
                                                          ?.toString() ??
                                                      'Unknown User',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  user['phone']?.toString() ??
                                                      user['email']
                                                          ?.toString() ??
                                                      'No contact information',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color:
                                                        Colors.grey.shade700,
                                                  ),
                                                ),
                                                const SizedBox(height: 7),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 6,
                                                  children: [
                                                    _smallBadge(
                                                      role.replaceAll('_', ' '),
                                                      Colors.blueGrey,
                                                    ),
                                                    _smallBadge(
                                                      status,
                                                      statusColor(status),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.chevron_right,
                                            color: Colors.grey,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
          if (isUpdating)
            const LinearProgressIndicator(
              minHeight: 3,
            ),
        ],
      ),
    );
  }

  Widget _smallBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 70,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 18),
            const Text(
              'Unable to load users',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: loadUsers,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.people_outline,
              size: 72,
              color: Colors.grey,
            ),
            const SizedBox(height: 18),
            const Text(
              'No users found',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try changing the search or filters.',
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}