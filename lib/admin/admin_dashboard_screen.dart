import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_notifications_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState
    extends State<AdminDashboardScreen> {
  static const String baseUrl =
      'https://api.servicepay.ng/api';

  String adminName = 'Admin';
  String adminRole = 'HEAD_OFFICE';

  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';

  int totalUsers = 0;
  int activeUsers = 0;
  int suspendedUsers = 0;
  int blockedUsers = 0;

  int totalCustomers = 0;
  int totalAgents = 0;
  int totalStateManagers = 0;
  int totalZonalManagers = 0;

  int verifiedUsers = 0;
  int pendingVerifications = 0;

  int totalTransactions = 0;
  int successfulTransactions = 0;
  int pendingTransactions = 0;
  int failedTransactions = 0;

  double totalTransactionValue = 0;
  double totalWalletBalance = 0;
  double totalCommissionBalance = 0;
  double totalEarnings = 0;
  double servicepayProfit = 0;

  List<dynamic> recentUsers = [];
  List<dynamic> recentTransactions = [];

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        hasError = false;
        errorMessage = '';
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      final savedName =
          prefs.getString('user_name') ??
          prefs.getString('full_name') ??
          prefs.getString('name');

      final savedRole =
          prefs.getString('user_role') ??
          prefs.getString('role') ??
          'HEAD_OFFICE';

      final token =
          prefs.getString('auth_token') ??
          prefs.getString('token');

      if (token == null || token.trim().isEmpty) {
        throw Exception(
          'Admin login token was not found. Please log in again.',
        );
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/admin/dashboard'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(
            const Duration(seconds: 30),
          );

      final decodedBody = jsonDecode(response.body);

      if (response.statusCode != 200) {
        final message = decodedBody is Map<String, dynamic>
            ? decodedBody['message']?.toString()
            : null;

        throw Exception(
          message ?? 'Unable to load admin dashboard.',
        );
      }

      if (decodedBody is! Map<String, dynamic>) {
        throw Exception(
          'Invalid response received from the server.',
        );
      }

      if (decodedBody['success'] != true) {
        throw Exception(
          decodedBody['message']?.toString() ??
              'Unable to load admin dashboard.',
        );
      }

      final data =
          decodedBody['data'] as Map<String, dynamic>? ?? {};

      final users =
          data['users'] as Map<String, dynamic>? ?? {};

      final kyc =
          data['kyc'] as Map<String, dynamic>? ?? {};

      final wallets =
          data['wallets'] as Map<String, dynamic>? ?? {};

      final transactions =
          data['transactions'] as Map<String, dynamic>? ?? {};

      if (!mounted) return;

      setState(() {
        adminName = savedName?.trim().isNotEmpty == true
            ? savedName!.trim()
            : 'Admin';

        adminRole = savedRole.trim().isNotEmpty
            ? savedRole.trim().toUpperCase()
            : 'HEAD_OFFICE';

        totalUsers = toInt(users['total']);
        activeUsers = toInt(users['active']);
        suspendedUsers = toInt(users['suspended']);
        blockedUsers = toInt(users['blocked']);

        totalCustomers = toInt(users['customers']);
        totalAgents = toInt(users['agents']);
        totalStateManagers =
            toInt(users['stateManagers']);
        totalZonalManagers =
            toInt(users['zonalManagers']);

        verifiedUsers = toInt(kyc['verified']);
        pendingVerifications = toInt(kyc['pending']);

        totalWalletBalance =
            toDouble(wallets['totalBalance']);

        totalCommissionBalance =
            toDouble(wallets['totalCommissionBalance']);

        totalEarnings =
            toDouble(wallets['totalEarnings']);

        totalTransactions =
            toInt(transactions['total']);

        totalTransactionValue =
            toDouble(transactions['totalValue']);

        successfulTransactions =
            toInt(transactions['successful']);

        pendingTransactions =
            toInt(transactions['pending']);

        failedTransactions =
            toInt(transactions['failed']);

        servicepayProfit =
            toDouble(transactions['servicepayProfit']);

        recentUsers =
            data['recentUsers'] is List
                ? data['recentUsers'] as List<dynamic>
                : [];

        recentTransactions =
            data['recentTransactions'] is List
                ? data['recentTransactions']
                    as List<dynamic>
                : [];

        isLoading = false;
        hasError = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = cleanError(error);
      });
    }
  }

  int toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double toDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .trim();
  }

  String formatMoney(double amount) {
    final rounded = amount.toStringAsFixed(2);
    final parts = rounded.split('.');
    final wholeNumber = parts[0];

    final formattedWhole = wholeNumber.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );

    return '₦$formattedWhole.${parts[1]}';
  }

  String formatDate(dynamic rawDate) {
    if (rawDate == null) {
      return 'Unknown date';
    }

    final date = DateTime.tryParse(rawDate.toString());

    if (date == null) {
      return 'Unknown date';
    }

    final localDate = date.toLocal();

    return '${localDate.day}/${localDate.month}/${localDate.year}';
  }

  Future<void> refreshDashboard() async {
    await loadDashboard();
  }

  Future<void> openPage(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => page,
      ),
    );

    await refreshDashboard();
  }

  void showComingSoon(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title is coming soon.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.045,
            ),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: color,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAdminAction({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.grey.shade200,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.green.withValues(
              alpha: 0.1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: Colors.green,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 17,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget buildErrorState() {
    return RefreshIndicator(
      onRefresh: refreshDashboard,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.cloud_off_rounded,
            size: 72,
            color: Colors.red.shade300,
          ),
          const SizedBox(height: 20),
          const Text(
            'Unable to load dashboard',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: loadDashboard,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildRecentUsersSection() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Users',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${recentUsers.length} shown',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recentUsers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(
                vertical: 20,
              ),
              child: Text(
                'No users found.',
              ),
            )
          else
            ...recentUsers.map((rawUser) {
              final user =
                  rawUser as Map<String, dynamic>? ?? {};

              final name =
                  user['fullName']?.toString() ??
                      'Unknown User';

              final role =
                  user['role']?.toString() ??
                      'CUSTOMER';

              final status =
                  user['status']?.toString() ??
                      'UNKNOWN';

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor:
                      Colors.green.shade50,
                  child: Text(
                    name.isNotEmpty
                        ? name[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  '${role.replaceAll('_', ' ')} • '
                  '${formatDate(user['createdAt'])}',
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: status == 'ACTIVE'
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius:
                        BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: status == 'ACTIVE'
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget buildRecentTransactionsSection() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Transactions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${recentTransactions.length} shown',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recentTransactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(
                vertical: 20,
              ),
              child: Text(
                'No transactions found.',
              ),
            )
          else
            ...recentTransactions.map((rawTransaction) {
              final transaction =
                  rawTransaction
                          as Map<String, dynamic>? ??
                      {};

              final customer =
                  transaction['customerId']
                          as Map<String, dynamic>? ??
                      {};

              final serviceType =
                  transaction['serviceType']
                          ?.toString() ??
                      'TRANSACTION';

              final status =
                  transaction['status']?.toString() ??
                      'UNKNOWN';

              final amount =
                  toDouble(transaction['amount']);

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius:
                        BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: Colors.purple,
                  ),
                ),
                title: Text(
                  serviceType.replaceAll('_', ' '),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  '${customer['fullName'] ?? 'Unknown User'} • '
                  '${formatDate(transaction['createdAt'])}',
                ),
                trailing: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  crossAxisAlignment:
                      CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoney(amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      status,
                      style: TextStyle(
                        color: transactionStatusColor(
                          status,
                        ),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Color transactionStatusColor(String status) {
    switch (status) {
      case 'SUCCESSFUL':
        return Colors.green;
      case 'FAILED':
        return Colors.red;
      case 'REFUNDED':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed:
                isLoading ? null : refreshDashboard,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Send Notifications',
            onPressed: () {
              openPage(
                const AdminNotificationsScreen(),
              );
            },
            icon: const Icon(
              Icons.notifications_active_outlined,
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.green,
              ),
            )
          : hasError
              ? buildErrorState()
              : RefreshIndicator(
                  onRefresh: refreshDashboard,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final contentWidth =
                          constraints.maxWidth > 1100
                              ? 1050.0
                              : double.infinity;

                      final crossAxisCount =
                          constraints.maxWidth >= 900
                              ? 4
                              : constraints.maxWidth >= 600
                                  ? 3
                                  : 2;

                      return ListView(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        padding:
                            const EdgeInsets.all(18),
                        children: [
                          Align(
                            alignment:
                                Alignment.topCenter,
                            child: SizedBox(
                              width: contentWidth,
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Container(
                                    width:
                                        double.infinity,
                                    padding:
                                        const EdgeInsets
                                            .all(22),
                                    decoration:
                                        BoxDecoration(
                                      gradient:
                                          const LinearGradient(
                                        colors: [
                                          Color(
                                            0xFF1D7D32,
                                          ),
                                          Color(
                                            0xFF48A84F,
                                          ),
                                        ],
                                        begin:
                                            Alignment.topLeft,
                                        end: Alignment
                                            .bottomRight,
                                      ),
                                      borderRadius:
                                          BorderRadius
                                              .circular(22),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors
                                              .green
                                              .withValues(
                                            alpha: 0.24,
                                          ),
                                          blurRadius: 18,
                                          offset:
                                              const Offset(
                                            0,
                                            8,
                                          ),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .start,
                                            children: [
                                              const Text(
                                                'Welcome Back',
                                                style:
                                                    TextStyle(
                                                  color: Colors
                                                      .white70,
                                                  fontSize:
                                                      15,
                                                ),
                                              ),
                                              const SizedBox(
                                                height: 6,
                                              ),
                                              Text(
                                                adminName,
                                                style:
                                                    const TextStyle(
                                                  color: Colors
                                                      .white,
                                                  fontSize:
                                                      26,
                                                  fontWeight:
                                                      FontWeight
                                                          .bold,
                                                ),
                                              ),
                                              const SizedBox(
                                                height: 8,
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets
                                                        .symmetric(
                                                  horizontal:
                                                      12,
                                                  vertical:
                                                      6,
                                                ),
                                                decoration:
                                                    BoxDecoration(
                                                  color: Colors
                                                      .white
                                                      .withValues(
                                                    alpha:
                                                        0.18,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius
                                                          .circular(
                                                    20,
                                                  ),
                                                ),
                                                child: Text(
                                                  adminRole
                                                      .replaceAll(
                                                    '_',
                                                    ' ',
                                                  ),
                                                  style:
                                                      const TextStyle(
                                                    color: Colors
                                                        .white,
                                                    fontWeight:
                                                        FontWeight
                                                            .w600,
                                                    fontSize:
                                                        12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons
                                              .admin_panel_settings_rounded,
                                          color:
                                              Colors.white,
                                          size: 64,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 26,
                                  ),
                                  const Text(
                                    'Overview',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 15,
                                  ),
                                  GridView.count(
                                    crossAxisCount:
                                        crossAxisCount,
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    mainAxisSpacing: 14,
                                    crossAxisSpacing: 14,
                                    childAspectRatio:
                                        constraints
                                                    .maxWidth <
                                                600
                                            ? 1.38
                                            : 1.5,
                                    children: [
                                      buildStatCard(
                                        title:
                                            'Total Users',
                                        value: totalUsers
                                            .toString(),
                                        icon: Icons
                                            .groups_outlined,
                                        color:
                                            Colors.blue,
                                      ),
                                      buildStatCard(
                                        title:
                                            'Active Users',
                                        value: activeUsers
                                            .toString(),
                                        icon: Icons
                                            .verified_user_outlined,
                                        color:
                                            Colors.green,
                                      ),
                                      buildStatCard(
                                        title:
                                            'Customers',
                                        value:
                                            totalCustomers
                                                .toString(),
                                        icon: Icons
                                            .person_outline,
                                        color:
                                            Colors.indigo,
                                      ),
                                      buildStatCard(
                                        title: 'Agents',
                                        value:
                                            totalAgents
                                                .toString(),
                                        icon: Icons
                                            .support_agent_outlined,
                                        color:
                                            Colors.teal,
                                      ),
                                      buildStatCard(
                                        title:
                                            'Transactions',
                                        value:
                                            totalTransactions
                                                .toString(),
                                        icon: Icons
                                            .receipt_long_outlined,
                                        color:
                                            Colors.purple,
                                      ),
                                      buildStatCard(
                                        title:
                                            'Transaction Value',
                                        value:
                                            formatMoney(
                                          totalTransactionValue,
                                        ),
                                        icon: Icons
                                            .payments_outlined,
                                        color:
                                            Colors.deepPurple,
                                      ),
                                      buildStatCard(
                                        title:
                                            'Wallet Balance',
                                        value:
                                            formatMoney(
                                          totalWalletBalance,
                                        ),
                                        icon: Icons
                                            .account_balance_wallet_outlined,
                                        color:
                                            Colors.orange,
                                      ),
                                      buildStatCard(
                                        title:
                                            'Pending KYC',
                                        value:
                                            pendingVerifications
                                                .toString(),
                                        icon: Icons
                                            .badge_outlined,
                                        color:
                                            Colors.deepOrange,
                                      ),
                                      buildStatCard(
                                        title:
                                            'Successful',
                                        value:
                                            successfulTransactions
                                                .toString(),
                                        icon: Icons
                                            .check_circle_outline,
                                        color:
                                            Colors.green,
                                      ),
                                      buildStatCard(
                                        title:
                                            'Pending Transactions',
                                        value:
                                            pendingTransactions
                                                .toString(),
                                        icon: Icons
                                            .schedule_outlined,
                                        color:
                                            Colors.orange,
                                      ),
                                      buildStatCard(
                                        title:
                                            'Failed Transactions',
                                        value:
                                            failedTransactions
                                                .toString(),
                                        icon: Icons
                                            .error_outline,
                                        color:
                                            Colors.red,
                                      ),
                                      buildStatCard(
                                        title:
                                            'Servicepay Profit',
                                        value:
                                            formatMoney(
                                          servicepayProfit,
                                        ),
                                        icon: Icons
                                            .trending_up_outlined,
                                        color:
                                            Colors.green,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: 26,
                                  ),
                                  buildRecentUsersSection(),
                                  const SizedBox(
                                    height: 18,
                                  ),
                                  buildRecentTransactionsSection(),
                                  const SizedBox(
                                    height: 28,
                                  ),
                                  const Text(
                                    'Admin Tools',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 14,
                                  ),
                                  buildAdminAction(
                                    title:
                                        'Manage Users',
                                    subtitle:
                                        'View, activate, suspend and manage Servicepay users.',
                                    icon: Icons
                                        .manage_accounts_outlined,
                                    onTap: () {
                                      showComingSoon(
                                        'User Management',
                                      );
                                    },
                                  ),
                                  buildAdminAction(
                                    title:
                                        'Transactions',
                                    subtitle:
                                        'Monitor all customer transactions.',
                                    icon: Icons
                                        .receipt_long_outlined,
                                    onTap: () {
                                      showComingSoon(
                                        'Admin Transactions',
                                      );
                                    },
                                  ),
                                  buildAdminAction(
                                    title:
                                        'Delivery Management',
                                    subtitle:
                                        'Set delivery fees and update delivery status.',
                                    icon: Icons
                                        .local_shipping_outlined,
                                    onTap: () {
                                      showComingSoon(
                                        'Delivery Management',
                                      );
                                    },
                                  ),
                                  buildAdminAction(
                                    title:
                                        'ID Verification',
                                    subtitle:
                                        'Review and approve customer verification requests.',
                                    icon: Icons
                                        .verified_user_outlined,
                                    onTap: () {
                                      showComingSoon(
                                        'ID Verification Management',
                                      );
                                    },
                                  ),
                                  buildAdminAction(
                                    title:
                                        'Send Notifications',
                                    subtitle:
                                        'Send direct or broadcast notifications to users.',
                                    icon: Icons
                                        .notifications_active_outlined,
                                    onTap: () {
                                      openPage(
                                        const AdminNotificationsScreen(),
                                      );
                                    },
                                  ),
                                  buildAdminAction(
                                    title:
                                        'Commission Management',
                                    subtitle:
                                        'Manage agent and manager commissions.',
                                    icon: Icons
                                        .percent_outlined,
                                    onTap: () {
                                      showComingSoon(
                                        'Commission Management',
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
    );
  }
}