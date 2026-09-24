import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'phase1_operations_api.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({
    super.key,
    this.adminRole = '',
    this.permissions = const <String>{},
    this.api,
  });

  /// These values are supplied by the authenticated parent. They are only
  /// presentation guards; the API remains the authority for every operation.
  final String adminRole;
  final Set<String> permissions;
  final Phase1OperationsApi? api;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  static const String _apiBaseUrl = 'https://api.servicepay.ng';

  static const Color _primaryGreen = Color(0xFF08783E);

  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, dynamic>> _roles = const [
    {
      'role': 'ZONAL_MANAGER',
      'label': 'Zonal Managers',
      'icon': Icons.public_rounded,
    },
    {
      'role': 'STATE_MANAGER',
      'label': 'State Managers',
      'icon': Icons.location_city_rounded,
    },
    {
      'role': 'AGENT',
      'label': 'Aggregators / Agents',
      'icon': Icons.groups_rounded,
    },
    {
      'role': 'CUSTOMER',
      'label': 'Customers',
      'icon': Icons.people_alt_rounded,
    },
  ];

  String _selectedRole = 'ZONAL_MANAGER';

  List<Map<String, dynamic>> _users = [];

  bool _loading = true;
  bool _actionLoading = false;
  String? _walletPendingIntent;
  String? _walletPendingKey;

  String _errorMessage = '';

  Timer? _searchDebounce;

  late final Phase1OperationsApi _operationsApi =
      widget.api ?? Phase1OperationsApi();

  bool get _canAdjustWallet =>
      widget.adminRole.trim().toUpperCase() == 'HEAD_OFFICE' &&
      widget.permissions
          .map((permission) => permission.trim().toLowerCase())
          .contains('wallets.adjust');

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    return prefs.getString('auth_token') ??
        prefs.getString('token') ??
        prefs.getString('admin_token');
  }

  Map<String, String> _headers(
    String token, {
    bool jsonBody = false,
  }) {
    return <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (jsonBody) 'Content-Type': 'application/json',
    };
  }

  dynamic _decodeBody(http.Response response) {
    try {
      return jsonDecode(response.body);
    } catch (_) {
      return <String, dynamic>{
        'message': response.body,
      };
    }
  }

  String _messageFromBody(
    dynamic body, {
    String fallback = 'Something went wrong.',
  }) {
    if (body is Map) {
      final dynamic value = body['message'] ?? body['error'];

      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }

    return fallback;
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = '';
    });

    try {
      final String? token = await _getToken();

      if (token == null || token.trim().isEmpty) {
        throw Exception(
          'Admin login token was not found. Please login again.',
        );
      }

      final Map<String, String> query = <String, String>{
        'role': _selectedRole,
      };

      final String search = _searchController.text.trim();

      if (search.isNotEmpty) {
        query['search'] = search;
      }

      final Uri uri = Uri.parse(
        '$_apiBaseUrl/api/admin/role-users',
      ).replace(
        queryParameters: query,
      );

      final http.Response response = await http
          .get(
            uri,
            headers: _headers(token),
          )
          .timeout(
            const Duration(seconds: 30),
          );

      final dynamic body = _decodeBody(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _messageFromBody(
            body,
            fallback: 'Unable to load users (${response.statusCode}).',
          ),
        );
      }

      final dynamic rawUsers = body is Map ? body['users'] : null;

      final List<Map<String, dynamic>> loaded = <Map<String, dynamic>>[];

      if (rawUsers is List) {
        for (final dynamic item in rawUsers) {
          if (item is Map) {
            loaded.add(
              Map<String, dynamic>.from(item),
            );
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _users = loaded;
      });
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Request timed out. Please try again.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _changeRole(String role) {
    if (_selectedRole == role) return;

    setState(() {
      _selectedRole = role;
      _users = [];
      _errorMessage = '';
    });

    _loadUsers();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();

    _searchDebounce = Timer(
      const Duration(milliseconds: 500),
      () {
        _loadUsers();
      },
    );
  }

  String _text(
    Map<String, dynamic> user,
    String key, {
    String fallback = 'Not provided',
  }) {
    final dynamic value = user[key];

    if (value == null || value.toString().trim().isEmpty) {
      return fallback;
    }

    return value.toString();
  }

  String _displayName(
    Map<String, dynamic> user,
  ) {
    return _text(
      user,
      'fullName',
      fallback: 'ServicePay User',
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'ZONAL_MANAGER':
        return 'Zonal Manager';
      case 'STATE_MANAGER':
        return 'State Manager';
      case 'AGENT':
        return 'Agent';
      case 'AGGREGATOR':
        return 'Aggregator';
      case 'CUSTOMER':
        return 'Customer';
      default:
        return role
            .replaceAll('_', ' ')
            .toLowerCase()
            .split(' ')
            .map(
              (String word) => word.isEmpty
                  ? word
                  : '${word[0].toUpperCase()}${word.substring(1)}',
            )
            .join(' ');
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return const Color(0xFF08783E);
      case 'SUSPENDED':
        return const Color(0xFFB7791F);
      case 'BLOCKED':
        return const Color(0xFFB42318);
      default:
        return const Color(0xFF667085);
    }
  }

  String _userRole(Map<String, dynamic> user) =>
      _text(user, 'role', fallback: _selectedRole).trim().toUpperCase();

  Future<void> _promoteUser(
    Map<String, dynamic> user,
    String targetRole,
  ) async {
    final String id = _text(user, '_id', fallback: '');
    if (id.isEmpty) {
      _showSnack('User ID was not found.', error: true);
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Promote to ${_roleLabel(targetRole)}?'),
        content: Text(
          'Promote ${_displayName(user)} to ${_roleLabel(targetRole)}? '
          'The server will preserve this user identity and apply its policy checks.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm promotion'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      setState(() => _actionLoading = true);
      await _operationsApi.promoteUser(userId: id, targetRole: targetRole);
      if (!mounted) return;
      _showSnack('User promoted to ${_roleLabel(targetRole)}.');
      await _loadUsers();
    } catch (error) {
      if (mounted) _showSnack(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _adjustWallet(
    Map<String, dynamic> user, {
    String initialAction = 'CREDIT',
  }) async {
    if (!_canAdjustWallet) return;
    final String id = _text(user, '_id', fallback: '');
    if (id.isEmpty) {
      _showSnack('Customer ID was not found.', error: true);
      return;
    }
    final TextEditingController amount = TextEditingController();
    final TextEditingController reason = TextEditingController();
    final TextEditingController reference = TextEditingController();
    String action = initialAction;
    try {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) =>
              AlertDialog(
            title: Text('Adjust ${_displayName(user)} wallet'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Current balance: ₦${_text(user, 'walletBalance', fallback: '0')}',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: action,
                    decoration: const InputDecoration(labelText: 'Action'),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'CREDIT', child: Text('CREDIT')),
                      DropdownMenuItem(value: 'DEBIT', child: Text('DEBIT')),
                    ],
                    onChanged: (String? value) {
                      if (value != null) setDialogState(() => action = value);
                    },
                  ),
                  TextField(
                    controller: amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(
                        labelText: 'Reason (minimum 5 characters)'),
                  ),
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                        labelText: 'Reference (required)'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This action changes the customer wallet. Review the details before confirming.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final double? value = double.tryParse(amount.text.trim());
                  if (value == null ||
                      value <= 0 ||
                      reason.text.trim().length < 5 ||
                      reference.text.trim().isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Enter a positive amount, a reason of at least 5 characters, and a reference.')),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Confirm adjustment'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
      final intent = [
        id,
        action,
        amount.text.trim(),
        reason.text.trim(),
        reference.text.trim(),
      ].join('\u001f');
      if (_walletPendingIntent != intent) {
        _walletPendingIntent = intent;
        _walletPendingKey = phase1IdempotencyKey();
      }
      setState(() => _actionLoading = true);
      await _operationsApi.adjustWallet(
        identifier: id,
        action: action,
        amount: amount.text.trim(),
        reason: reason.text.trim(),
        reference: reference.text.trim(),
        // Preserve the key after an ambiguous network failure. The same
        // customer/action/amount/reason/reference can safely be retried.
        idempotencyKey: _walletPendingKey!,
      );
      _walletPendingIntent = null;
      _walletPendingKey = null;
      if (mounted) {
        _showSnack('Wallet adjustment completed.');
        await _loadUsers();
      }
    } catch (error) {
      if (mounted) _showSnack(error.toString(), error: true);
    } finally {
      amount.dispose();
      reason.dispose();
      reference.dispose();
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  void _showAdjustmentHistory(Map<String, dynamic> user) {
    if (!_canAdjustWallet) return;
    final String customerId = _text(user, '_id', fallback: '');
    if (customerId.isEmpty) {
      _showSnack('Customer ID was not found.', error: true);
      return;
    }
    int page = 1;
    Future<Map<String, dynamic>> load() =>
        _operationsApi.walletAdjustmentHistory(
          customerId: customerId,
          page: page,
          limit: 50,
        );
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          Future<Map<String, dynamic>> request = load();
          return AlertDialog(
            title: Text('${_displayName(user)} adjustment history'),
            content: SizedBox(
              width: 520,
              child: FutureBuilder<Map<String, dynamic>>(
                future: request,
                builder: (
                  BuildContext context,
                  AsyncSnapshot<Map<String, dynamic>> snapshot,
                ) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const SizedBox(
                      height: 110,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return SizedBox(
                      height: 110,
                      child: Center(
                        child: Text(
                          'Unable to load adjustment history: '
                          '${snapshot.error}',
                        ),
                      ),
                    );
                  }
                  final dynamic rawItems = snapshot.data?['history'];
                  final List<Map<String, dynamic>> items = rawItems is List
                      ? rawItems
                          .whereType<Map>()
                          .map((Map item) => Map<String, dynamic>.from(item))
                          .toList()
                      : <Map<String, dynamic>>[];
                  final dynamic rawPagination = snapshot.data?['pagination'];
                  final int totalPages = rawPagination is Map
                      ? int.tryParse(
                              '${rawPagination['totalPages'] ?? rawPagination['pages'] ?? page}') ??
                          page
                      : page;
                  if (items.isEmpty) {
                    return const SizedBox(
                      height: 110,
                      child:
                          Center(child: Text('No wallet adjustments found.')),
                    );
                  }
                  return SizedBox(
                    height: 360,
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (BuildContext context, int index) {
                              final Map<String, dynamic> item = items[index];
                              final String direction =
                                  '${item['direction'] ?? ''}'.toUpperCase();
                              return ListTile(
                                dense: true,
                                title: Text(
                                  '${direction.isEmpty ? 'Adjustment' : direction} '
                                  '₦${item['amount'] ?? '0'}',
                                ),
                                subtitle: Text(
                                  '${item['narration'] ?? 'No narration'}\n'
                                  'Before: ₦${item['balanceBefore'] ?? '—'}  '
                                  'After: ₦${item['balanceAfter'] ?? '—'}\n'
                                  '${item['date'] ?? ''}  '
                                  'Ref: ${item['reference'] ?? '—'}',
                                ),
                              );
                            },
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            IconButton(
                              tooltip: 'Previous page',
                              onPressed: page > 1
                                  ? () => setDialogState(() => page--)
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text('Page $page of $totalPages'),
                            IconButton(
                              tooltip: 'Next page',
                              onPressed: page < totalPages
                                  ? () => setDialogState(() => page++)
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _changeStatus(
    Map<String, dynamic> user,
    String newStatus,
  ) async {
    final String id = _text(user, '_id', fallback: '');

    if (id.isEmpty) {
      _showSnack(
        'User ID was not found.',
        error: true,
      );
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            'Change Account Status',
          ),
          content: Text(
            'Change ${_displayName(user)} to '
            '$newStatus?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      setState(() {
        _actionLoading = true;
      });

      final String? token = await _getToken();

      if (token == null || token.trim().isEmpty) {
        throw Exception(
          'Admin login token was not found.',
        );
      }

      final Uri uri = Uri.parse(
        '$_apiBaseUrl/api/admin/role-users/$id/status',
      );

      final http.Response response = await http
          .put(
            uri,
            headers: _headers(
              token,
              jsonBody: true,
            ),
            body: jsonEncode(
              <String, dynamic>{
                'status': newStatus,
              },
            ),
          )
          .timeout(
            const Duration(seconds: 30),
          );

      final dynamic body = _decodeBody(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _messageFromBody(
            body,
            fallback: 'Unable to update account status.',
          ),
        );
      }

      if (!mounted) return;

      _showSnack(
        'Account status changed to $newStatus.',
      );

      await _loadUsers();
    } catch (error) {
      if (!mounted) return;

      _showSnack(
        error.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionLoading = false;
        });
      }
    }
  }

  Future<void> _deleteAccount(
    Map<String, dynamic> user,
  ) async {
    final String id = _text(user, '_id', fallback: '');

    if (id.isEmpty) {
      _showSnack(
        'User ID was not found.',
        error: true,
      );
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFB42318),
            size: 40,
          ),
          title: const Text(
            'Delete Account?',
            textAlign: TextAlign.center,
          ),
          content: Text(
            'This will safely remove '
            '${_displayName(user)} from active '
            'ServicePay accounts.\n\n'
            'The account will be blocked and '
            'transaction/audit history will remain '
            'preserved.',
            textAlign: TextAlign.center,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB42318),
              ),
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text(
                'Delete Account',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      setState(() {
        _actionLoading = true;
      });

      final String? token = await _getToken();

      if (token == null || token.trim().isEmpty) {
        throw Exception(
          'Admin login token was not found.',
        );
      }

      final Uri uri = Uri.parse(
        '$_apiBaseUrl/api/admin/role-users/$id',
      );

      final http.Response response = await http
          .delete(
            uri,
            headers: _headers(token),
          )
          .timeout(
            const Duration(seconds: 30),
          );

      final dynamic body = _decodeBody(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _messageFromBody(
            body,
            fallback: 'Unable to delete account.',
          ),
        );
      }

      if (!mounted) return;

      _showSnack(
        'Account safely deleted.',
      );

      await _loadUsers();
    } catch (error) {
      if (!mounted) return;

      _showSnack(
        error.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionLoading = false;
        });
      }
    }
  }

  void _showSnack(
    String message, {
    bool error = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? const Color(0xFFB42318) : _primaryGreen,
        ),
      );
  }

  void _showUserDetails(
    Map<String, dynamic> user,
  ) {
    final String status = _text(
      user,
      'status',
      fallback: 'UNKNOWN',
    ).toUpperCase();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.55,
          maxChildSize: 0.96,
          builder: (
            BuildContext context,
            ScrollController controller,
          ) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD0D5DD),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(22),
                      children: <Widget>[
                        CircleAvatar(
                          radius: 35,
                          backgroundColor: const Color(0xFFEAF7F0),
                          child: Text(
                            _displayName(user)
                                .trim()
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                              color: _primaryGreen,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _displayName(user),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF101828),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _roleLabel(
                            _text(
                              user,
                              'role',
                              fallback: _selectedRole,
                            ),
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _detailsCard(
                          title: 'Account Information',
                          children: <Widget>[
                            _detailRow(
                              'Phone',
                              _text(
                                user,
                                'phone',
                              ),
                            ),
                            _detailRow(
                              'Email',
                              _text(
                                user,
                                'email',
                              ),
                            ),
                            _detailRow(
                              'Role',
                              _roleLabel(
                                _text(
                                  user,
                                  'role',
                                  fallback: _selectedRole,
                                ),
                              ),
                            ),
                            _detailRow(
                              'Status',
                              status,
                            ),
                            _detailRow(
                              'Zone',
                              _text(
                                user,
                                'zone',
                              ),
                            ),
                            _detailRow(
                              'State',
                              _text(
                                user,
                                'state',
                              ),
                            ),
                            _detailRow(
                              'LGA',
                              _text(
                                user,
                                'lga',
                              ),
                            ),
                            _detailRow(
                              'Wallet Balance',
                              '₦${_text(user, 'walletBalance', fallback: '0')}',
                            ),
                            _detailRow(
                              'User ID',
                              _text(
                                user,
                                '_id',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Account Actions',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF101828),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            _actionButton(
                              label: 'Activate',
                              icon: Icons.check_circle_outline,
                              onTap: status == 'ACTIVE'
                                  ? null
                                  : () async {
                                      Navigator.pop(
                                        sheetContext,
                                      );
                                      await _changeStatus(
                                        user,
                                        'ACTIVE',
                                      );
                                    },
                            ),
                            _actionButton(
                              label: 'Suspend',
                              icon: Icons.pause_circle_outline,
                              onTap: status == 'SUSPENDED'
                                  ? null
                                  : () async {
                                      Navigator.pop(
                                        sheetContext,
                                      );
                                      await _changeStatus(
                                        user,
                                        'SUSPENDED',
                                      );
                                    },
                            ),
                            _actionButton(
                              label: 'Block',
                              icon: Icons.block_rounded,
                              onTap: status == 'BLOCKED'
                                  ? null
                                  : () async {
                                      Navigator.pop(
                                        sheetContext,
                                      );
                                      await _changeStatus(
                                        user,
                                        'BLOCKED',
                                      );
                                    },
                            ),
                            _actionButton(
                              label: 'Delete Account',
                              icon: Icons.delete_outline_rounded,
                              danger: true,
                              onTap: () async {
                                Navigator.pop(
                                  sheetContext,
                                );
                                await _deleteAccount(
                                  user,
                                );
                              },
                            ),
                            if (_userRole(user) == 'CUSTOMER' &&
                                _canAdjustWallet) ...[
                              _actionButton(
                                label: 'Credit Wallet',
                                icon: Icons.add_card_rounded,
                                onTap: () async {
                                  Navigator.pop(sheetContext);
                                  await _adjustWallet(user,
                                      initialAction: 'CREDIT');
                                },
                              ),
                              _actionButton(
                                label: 'Debit Wallet',
                                icon: Icons.remove_circle_outline_rounded,
                                onTap: () async {
                                  Navigator.pop(sheetContext);
                                  await _adjustWallet(user,
                                      initialAction: 'DEBIT');
                                },
                              ),
                              _actionButton(
                                label: 'Wallet Adjustment',
                                icon: Icons.history_rounded,
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _adjustWallet(user);
                                },
                              ),
                              _actionButton(
                                label: 'Adjustment History',
                                icon: Icons.receipt_long_rounded,
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _showAdjustmentHistory(user);
                                },
                              ),
                            ],
                            if (_userRole(user) == 'AGENT' ||
                                _userRole(user) == 'AGGREGATOR')
                              _actionButton(
                                label: 'Promote to State Manager',
                                icon: Icons.trending_up_rounded,
                                onTap: () async {
                                  Navigator.pop(sheetContext);
                                  await _promoteUser(user, 'STATE_MANAGER');
                                },
                              ),
                            if (_userRole(user) == 'STATE_MANAGER')
                              _actionButton(
                                label: 'Promote to Zonal Manager',
                                icon: Icons.upgrade_rounded,
                                onTap: () async {
                                  Navigator.pop(sheetContext);
                                  await _promoteUser(user, 'ZONAL_MANAGER');
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailsCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFEAECF0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 7,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF101828),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    return OutlinedButton.icon(
      onPressed: _actionLoading ? null : onTap,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? const Color(0xFFB42318) : _primaryGreen,
        side: BorderSide(
          color: danger ? const Color(0xFFFDA29B) : const Color(0xFFABEFC6),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
      ),
    );
  }

  Widget _roleSelector() {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
        ),
        itemCount: _roles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (
          BuildContext context,
          int index,
        ) {
          final Map<String, dynamic> item = _roles[index];

          final String role = item['role'].toString();

          final bool selected = _selectedRole == role;

          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _changeRole(role),
            child: AnimatedContainer(
              duration: const Duration(
                milliseconds: 180,
              ),
              width: 165,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: selected ? _primaryGreen : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? _primaryGreen
                      : const Color(
                          0xFFEAECF0,
                        ),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: 0.04,
                    ),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(
                              alpha: 0.18,
                            )
                          : const Color(
                              0xFFEAF7F0,
                            ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      item['icon'] as IconData,
                      color: selected ? Colors.white : _primaryGreen,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item['label'].toString(),
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? Colors.white
                            : const Color(
                                0xFF101828,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _userCard(
    Map<String, dynamic> user,
  ) {
    final String status = _text(
      user,
      'status',
      fallback: 'UNKNOWN',
    ).toUpperCase();

    final String phone = _text(
      user,
      'phone',
      fallback: 'No phone',
    );

    final String location = <String>[
      _text(
        user,
        'state',
        fallback: '',
      ),
      _text(
        user,
        'zone',
        fallback: '',
      ),
    ]
        .where(
          (String value) => value.isNotEmpty,
        )
        .join(' • ');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(
          color: Color(0xFFEAECF0),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showUserDetails(user),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 25,
                backgroundColor: const Color(0xFFEAF7F0),
                child: Text(
                  _displayName(user).trim().substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: _primaryGreen,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _displayName(user),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phone,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 13,
                      ),
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        location,
                        style: const TextStyle(
                          color: Color(
                            0xFF98A2B3,
                          ),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(
                        status,
                      ).withValues(
                        alpha: 0.10,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: _statusColor(
                          status,
                        ),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF98A2B3),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _selectedLabel {
    for (final Map<String, dynamic> item in _roles) {
      if (item['role'] == _selectedRole) {
        return item['label'].toString();
      }
    }

    return 'Users';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'User Management',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF101828),
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadUsers,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const SizedBox(height: 16),
          _roleSelector(),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search name, phone, email, state...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                          _loadUsers();
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                        ),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Color(0xFFEAECF0),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Color(0xFFEAECF0),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadUsers,
              child: _buildUsersContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: _primaryGreen,
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const SizedBox(height: 70),
          const Icon(
            Icons.cloud_off_rounded,
            size: 58,
            color: Color(0xFF98A2B3),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _primaryGreen,
              ),
              onPressed: _loadUsers,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text('Try Again'),
            ),
          ),
        ],
      );
    }

    if (_users.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const SizedBox(height: 65),
          const Icon(
            Icons.person_search_rounded,
            size: 62,
            color: Color(0xFF98A2B3),
          ),
          const SizedBox(height: 16),
          Text(
            'No $_selectedLabel found.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 15,
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        32,
      ),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _selectedLabel,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101828),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color(
                  0xFFEAF7F0,
                ),
                borderRadius: BorderRadius.circular(
                  20,
                ),
              ),
              child: Text(
                '${_users.length}',
                style: const TextStyle(
                  color: _primaryGreen,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._users.map(_userCard),
      ],
    );
  }
}
