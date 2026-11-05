import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_manual_refunds_api.dart';

@visibleForTesting
List<MapEntry<String, String>> transactionProviderDetailFields(
  Map<String, dynamic> transaction,
) {
  const List<MapEntry<String, String>> fields = <MapEntry<String, String>>[
    MapEntry<String, String>('Provider', 'provider'),
    MapEntry<String, String>('Provider Reference', 'providerReference'),
    MapEntry<String, String>('Provider Status', 'providerStatus'),
    MapEntry<String, String>('ServicePay Status', 'status'),
    MapEntry<String, String>('Fallback Provider', 'fallbackProvider'),
    MapEntry<String, String>(
      'Reconciliation Status',
      'reconciliationStatus',
    ),
  ];
  return fields
      .where((MapEntry<String, String> field) {
        final dynamic value = transaction[field.value];
        return transaction.containsKey(field.value) &&
            value != null &&
            value.toString().trim().isNotEmpty;
      })
      .map(
        (MapEntry<String, String> field) => MapEntry<String, String>(
          field.key,
          transaction[field.value].toString(),
        ),
      )
      .toList(growable: false);
}

class AdminTransactionsScreen extends StatefulWidget {
  const AdminTransactionsScreen({super.key, this.refundsApi});

  @visibleForTesting
  final AdminManualRefundsApi? refundsApi;

  @override
  State<AdminTransactionsScreen> createState() =>
      _AdminTransactionsScreenState();
}

class _AdminTransactionsScreenState extends State<AdminTransactionsScreen> {
  late final AdminManualRefundsApi refundsApi =
      widget.refundsApi ?? AdminManualRefundsApi();
  bool showingRefundHistory = false;
  bool historyLoading = false;
  bool historyError = false;
  String historyErrorMessage = '';
  int historyPage = 1;
  int historyPages = 1;
  List<dynamic> refundHistoryItems = <dynamic>[];

  final TextEditingController searchController = TextEditingController();

  bool isLoading = true;
  bool isRefreshing = false;
  bool hasError = false;

  String errorMessage = '';
  String selectedStatus = 'ALL';
  String selectedService = 'ALL';

  int currentPage = 1;
  int totalPages = 1;
  int totalTransactions = 0;

  List<dynamic> transactions = [];

  final List<String> statuses = const [
    'ALL',
    'SUCCESSFUL',
    'PENDING',
    'FAILED',
    'REVERSED',
    'REFUNDED',
  ];

  final List<String> services = const [
    'ALL',
    'AIRTIME',
    'DATA',
    'CABLE',
    'ELECTRICITY',
    'EXAM_PIN',
    'WALLET_FUNDING',
    'TRANSFER',
    'BANK_TRANSFER',
    'ID_VERIFICATION',
    'DELIVERY',
  ];

  Timer? searchTimer;

  @override
  void initState() {
    super.initState();
    loadTransactions();
  }

  @override
  void dispose() {
    searchTimer?.cancel();
    searchController.dispose();
    if (widget.refundsApi == null) refundsApi.close();
    super.dispose();
  }

  Map<String, dynamic> toMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
  }

  int toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  double toDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  dynamic decodeResponse(String body) {
    if (body.trim().isEmpty) {
      return null;
    }

    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  String extractMessage(
    dynamic data, {
    required String fallback,
  }) {
    if (data is Map) {
      final dynamic message =
          data['message'] ?? data['error'] ?? data['detail'];

      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }

    return fallback;
  }

  Future<String?> getToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    return prefs.getString('auth_token') ??
        prefs.getString('token') ??
        prefs.getString('admin_token');
  }

  Future<void> loadTransactions({
    bool refresh = false,
    int? page,
  }) async {
    if (!mounted) return;

    final int requestedPage = page ?? currentPage;

    setState(() {
      if (refresh) {
        isRefreshing = true;
      } else {
        isLoading = true;
      }

      hasError = false;
      errorMessage = '';
    });

    try {
      final String? token = await getToken();

      if (token == null || token.trim().isEmpty) {
        throw Exception(
          'Admin login token was not found. Please log in again.',
        );
      }

      final Map<String, String> queryParameters = {
        'page': requestedPage.toString(),
        'limit': '20',
      };

      final String search = searchController.text.trim();

      if (search.isNotEmpty) {
        queryParameters['search'] = search;
      }

      if (selectedStatus != 'ALL') {
        queryParameters['status'] = selectedStatus;
      }

      if (selectedService != 'ALL') {
        queryParameters['serviceType'] = selectedService;
      }

      final String baseUrl = const String.fromEnvironment(
        'SERVICEPAY_API_BASE_URL',
        defaultValue: 'https://api.servicepay.ng/api',
      ).replaceFirst(RegExp(r'/$'), '');
      final Uri uri = Uri.parse(
        '$baseUrl/admin/transactions',
      ).replace(
        queryParameters: queryParameters,
      );

      final http.Response response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${token.trim()}',
        },
      ).timeout(
        const Duration(seconds: 30),
      );

      final dynamic decoded = decodeResponse(response.body);

      if (response.statusCode == 401) {
        throw Exception(
          extractMessage(
            decoded,
            fallback: 'Your login session has expired.',
          ),
        );
      }

      if (response.statusCode == 403) {
        throw Exception(
          extractMessage(
            decoded,
            fallback: 'You are not allowed to view transactions.',
          ),
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          extractMessage(
            decoded,
            fallback:
                'Unable to load transactions. Server error ${response.statusCode}.',
          ),
        );
      }

      final Map<String, dynamic> body = toMap(decoded);

      final Map<String, dynamic> data = toMap(body['data']);

      dynamic transactionList = data['transactions'] ??
          body['transactions'] ??
          data['items'] ??
          body['items'];

      if (transactionList is! List && data['docs'] is List) {
        transactionList = data['docs'];
      }

      final Map<String, dynamic> pagination = toMap(
        data['pagination'] ?? body['pagination'],
      );

      final int serverCurrentPage = toInt(
        pagination['currentPage'] ??
            pagination['page'] ??
            data['currentPage'] ??
            body['currentPage'] ??
            requestedPage,
      );

      final int serverTotalPages = toInt(
        pagination['totalPages'] ??
            pagination['pages'] ??
            data['totalPages'] ??
            body['totalPages'] ??
            1,
      );

      final int serverTotalTransactions = toInt(
        pagination['total'] ??
            pagination['totalItems'] ??
            data['total'] ??
            data['totalTransactions'] ??
            body['total'] ??
            body['totalTransactions'] ??
            (transactionList is List ? transactionList.length : 0),
      );

      if (!mounted) return;

      setState(() {
        transactions = transactionList is List
            ? List<dynamic>.from(
                transactionList,
              )
            : <dynamic>[];

        currentPage =
            serverCurrentPage <= 0 ? requestedPage : serverCurrentPage;

        totalPages = serverTotalPages <= 0 ? 1 : serverTotalPages;

        totalTransactions = serverTotalTransactions;

        isLoading = false;
        isRefreshing = false;
        hasError = false;
      });
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        isRefreshing = false;
        hasError = true;
        errorMessage =
            'The request timed out. Check your internet connection and try again.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        isRefreshing = false;
        hasError = true;
        errorMessage = error
            .toString()
            .replaceFirst(
              'Exception: ',
              '',
            )
            .trim();
      });
    }
  }

  void onSearchChanged(String value) {
    searchTimer?.cancel();

    searchTimer = Timer(
      const Duration(milliseconds: 700),
      () {
        currentPage = 1;
        loadTransactions(page: 1);
      },
    );
  }

  void clearFilters() {
    searchController.clear();

    setState(() {
      selectedStatus = 'ALL';
      selectedService = 'ALL';
      currentPage = 1;
    });

    loadTransactions(page: 1);
  }

  String formatMoney(double amount) {
    final String fixed = amount.toStringAsFixed(2);

    final List<String> parts = fixed.split('.');

    final String whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );

    return '₦$whole.${parts.last}';
  }

  String formatDate(dynamic value) {
    final DateTime? date = DateTime.tryParse(
      value?.toString() ?? '',
    );

    if (date == null) {
      return 'Unknown date';
    }

    final DateTime localDate = date.toLocal();

    final String day = localDate.day.toString().padLeft(2, '0');

    final String month = localDate.month.toString().padLeft(2, '0');

    final String hour = localDate.hour.toString().padLeft(2, '0');

    final String minute = localDate.minute.toString().padLeft(2, '0');

    return '$day/$month/${localDate.year} '
        '$hour:$minute';
  }

  String formatText(dynamic value) {
    final String text = value?.toString().trim() ?? '';

    if (text.isEmpty) {
      return 'Not available';
    }

    return text
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map(
          (String word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}'
                  '${word.substring(1)}',
        )
        .join(' ');
  }

  String transactionId(
    Map<String, dynamic> transaction,
  ) {
    return (transaction['_id'] ?? transaction['id'] ?? '').toString();
  }

  String transactionReference(
    Map<String, dynamic> transaction,
  ) {
    return (transaction['reference'] ??
            transaction['transactionReference'] ??
            transaction['paymentReference'] ??
            transaction['ref'] ??
            transactionId(transaction))
        .toString();
  }

  Map<String, dynamic> transactionCustomer(
    Map<String, dynamic> transaction,
  ) {
    return toMap(
      transaction['customerId'] ??
          transaction['userId'] ??
          transaction['customer'] ??
          transaction['user'],
    );
  }

  String customerName(
    Map<String, dynamic> transaction,
  ) {
    final Map<String, dynamic> customer = transactionCustomer(transaction);

    final String name = (customer['fullName'] ??
            customer['name'] ??
            transaction['customerName'] ??
            transaction['userName'] ??
            'Unknown User')
        .toString();

    return name.trim().isEmpty ? 'Unknown User' : name;
  }

  String customerPhone(
    Map<String, dynamic> transaction,
  ) {
    final Map<String, dynamic> customer = transactionCustomer(transaction);

    return (customer['phone'] ??
            transaction['phone'] ??
            transaction['customerPhone'] ??
            '')
        .toString();
  }

  String customerEmail(
    Map<String, dynamic> transaction,
  ) {
    final Map<String, dynamic> customer = transactionCustomer(transaction);

    return (customer['email'] ??
            transaction['email'] ??
            transaction['customerEmail'] ??
            '')
        .toString();
  }

  String transactionStatus(
    Map<String, dynamic> transaction,
  ) {
    return (transaction['status'] ?? 'PENDING').toString().toUpperCase();
  }

  String transactionService(
    Map<String, dynamic> transaction,
  ) {
    return (transaction['serviceType'] ??
            transaction['service'] ??
            transaction['type'] ??
            'TRANSACTION')
        .toString()
        .toUpperCase();
  }

  double transactionAmount(
    Map<String, dynamic> transaction,
  ) {
    return toDouble(
      transaction['amount'] ??
          transaction['value'] ??
          transaction['totalAmount'],
    );
  }

  Color statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'SUCCESS':
      case 'SUCCESSFUL':
      case 'COMPLETED':
      case 'APPROVED':
        return const Color(0xFF059669);

      case 'FAILED':
      case 'CANCELLED':
      case 'REJECTED':
        return const Color(0xFFDC2626);

      case 'REVERSED':
      case 'REFUNDED':
        return const Color(0xFF2563EB);

      default:
        return const Color(0xFFD97706);
    }
  }

  IconData serviceIcon(String service) {
    switch (service.toUpperCase()) {
      case 'AIRTIME':
        return Icons.phone_android_rounded;

      case 'DATA':
        return Icons.wifi_rounded;

      case 'CABLE':
        return Icons.tv_rounded;

      case 'ELECTRICITY':
        return Icons.electric_bolt_rounded;

      case 'EXAM_PIN':
        return Icons.school_rounded;

      case 'WALLET_FUNDING':
        return Icons.account_balance_wallet_rounded;

      case 'TRANSFER':
      case 'BANK_TRANSFER':
        return Icons.swap_horiz_rounded;

      case 'ID_VERIFICATION':
        return Icons.verified_user_rounded;

      case 'DELIVERY':
        return Icons.local_shipping_rounded;

      default:
        return Icons.receipt_long_rounded;
    }
  }

  Color serviceColor(String service) {
    switch (service.toUpperCase()) {
      case 'AIRTIME':
        return const Color(0xFF2563EB);

      case 'DATA':
        return const Color(0xFF7C3AED);

      case 'CABLE':
        return const Color(0xFFDB2777);

      case 'ELECTRICITY':
        return const Color(0xFFD97706);

      case 'WALLET_FUNDING':
        return const Color(0xFF059669);

      case 'TRANSFER':
      case 'BANK_TRANSFER':
        return const Color(0xFF0F766E);

      case 'ID_VERIFICATION':
        return const Color(0xFF4F46E5);

      case 'DELIVERY':
        return const Color(0xFFEA580C);

      default:
        return const Color(0xFF64748B);
    }
  }

  void showMessage(
    String message, {
    required bool isError,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? const Color(0xFFDC2626) : const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void showLegacyTransactionDetails(
    dynamic rawTransaction,
  ) {
    final Map<String, dynamic> transaction = toMap(rawTransaction);

    final String service = transactionService(transaction);

    showDialog<void>(
      context: context,
      builder: (
        BuildContext dialogContext,
      ) {
        return Dialog(
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 560,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: serviceColor(service).withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(
                            16,
                          ),
                        ),
                        child: Icon(
                          serviceIcon(service),
                          color: serviceColor(service),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatText(service),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(
                              height: 4,
                            ),
                            Text(
                              customerName(
                                transaction,
                              ),
                              style: const TextStyle(
                                color: Color(
                                  0xFF64748B,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(
                            dialogContext,
                          );
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    formatMoney(
                      transactionAmount(
                        transaction,
                      ),
                    ),
                    style: const TextStyle(
                      color: Color(0xFF0F766E),
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ...transactionProviderDetailFields(transaction).map(
                    (MapEntry<String, String> field) => detailRow(
                      field.key,
                      field.key == 'ServicePay Status'
                          ? formatText(field.value)
                          : field.value,
                      valueColor: field.key == 'ServicePay Status'
                          ? statusColor(field.value)
                          : null,
                    ),
                  ),
                  detailRow(
                    'Reference',
                    transactionReference(
                      transaction,
                    ),
                  ),
                  detailRow(
                    'Customer',
                    customerName(transaction),
                  ),
                  detailRow(
                    'Phone',
                    customerPhone(transaction),
                  ),
                  detailRow(
                    'Email',
                    customerEmail(transaction),
                  ),
                  detailRow(
                    'Service',
                    formatText(service),
                  ),
                  detailRow(
                    'Description',
                    (transaction['description'] ??
                            transaction['narration'] ??
                            '')
                        .toString(),
                  ),
                  detailRow(
                    'Created',
                    formatDate(
                      transaction['createdAt'],
                    ),
                  ),
                  detailRow(
                    'Updated',
                    formatDate(
                      transaction['updatedAt'],
                    ),
                  ),
                  detailRow(
                    'Transaction ID',
                    transactionId(transaction),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(
                          dialogContext,
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(
                          0xFF0F766E,
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> showTransactionDetails(dynamic rawTransaction) async {
    final Map<String, dynamic> summary = toMap(rawTransaction);
    final String id = transactionId(summary);
    if (id.isEmpty) {
      showMessage('This transaction has no usable ID.', isError: true);
      return;
    }
    try {
      final Map<String, dynamic> response = await refundsApi.transaction(id);
      final Map<String, dynamic> transaction = toMap(response['transaction']);
      if (!mounted || transaction.isEmpty) return;
      final ManualRefundIntent? pendingIntent = await refundsApi.loadIntent(id);
      if (!mounted) return;
      final bool? completed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => ManualRefundDialog(
          transaction: transaction,
          canExecute: response['canExecute'] == true,
          initialReason: pendingIntent?.reason ?? '',
          reasonLocked: pendingIntent != null,
          initialProviderRiskAcknowledged:
              pendingIntent?.providerRiskAcknowledged ?? false,
          formatMoney: formatMoney,
          formatText: formatText,
          formatDate: formatDate,
          onSubmit: (String reason, bool providerRiskAcknowledged) async {
            try {
              await refundsApi.submitRefund(
                id,
                reason: reason,
                providerRiskAcknowledged: providerRiskAcknowledged,
              );
              if (mounted) {
                await loadTransactions(refresh: true, page: currentPage);
              }
              return null;
            } on ManualRefundApiException catch (error) {
              return error.message;
            } catch (_) {
              return 'The request could not be confirmed. Retry using the same request; do not start another refund.';
            }
          },
        ),
      );
      if (completed == true) {
        showMessage('Refund request confirmed by Servicepay.', isError: false);
      }
    } on ManualRefundApiException catch (error) {
      if (error.statusCode == 403) {
        // Staff who may view the existing Transactions list must not lose its
        // read-only details merely because refund investigation is Head Office
        // only. This uses only the already-authorized list payload, never
        // exposes refund controls, and never weakens backend permissions.
        if (!mounted) return;
        showLegacyTransactionDetails(rawTransaction);
        showMessage(
          'Refund investigation is restricted. Showing existing read-only transaction details.',
          isError: false,
        );
        return;
      }
      showMessage(error.message, isError: true);
    } catch (_) {
      showMessage(
        'Transaction details could not be loaded. Please retry.',
        isError: true,
      );
    }
  }

  Widget detailRow(
    String label,
    String value, {
    Color? valueColor,
  }) {
    if (value.trim().isEmpty || value == 'Unknown date') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 115,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: valueColor ??
                    const Color(
                      0xFF334155,
                    ),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search customer, phone or reference',
              prefixIcon: const Icon(
                Icons.search_rounded,
              ),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        searchController.clear();

                        setState(() {});

                        loadTransactions(
                          page: 1,
                        );
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                      ),
                    ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (
              BuildContext context,
              BoxConstraints constraints,
            ) {
              final bool compact = constraints.maxWidth < 600;

              final Widget statusDropdown = DropdownButtonFormField<String>(
                value: selectedStatus,
                decoration: InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      14,
                    ),
                  ),
                ),
                items: statuses
                    .map(
                      (String status) => DropdownMenuItem<String>(
                        value: status,
                        child: Text(
                          formatText(status),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) {
                  if (value == null) return;

                  setState(() {
                    selectedStatus = value;
                    currentPage = 1;
                  });

                  loadTransactions(page: 1);
                },
              );

              final Widget serviceDropdown = DropdownButtonFormField<String>(
                value: selectedService,
                decoration: InputDecoration(
                  labelText: 'Service',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      14,
                    ),
                  ),
                ),
                items: services
                    .map(
                      (String service) => DropdownMenuItem<String>(
                        value: service,
                        child: Text(
                          formatText(service),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) {
                  if (value == null) return;

                  setState(() {
                    selectedService = value;
                    currentPage = 1;
                  });

                  loadTransactions(page: 1);
                },
              );

              if (compact) {
                return Column(
                  children: [
                    statusDropdown,
                    const SizedBox(height: 12),
                    serviceDropdown,
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: clearFilters,
                        icon: const Icon(
                          Icons.filter_alt_off_rounded,
                        ),
                        label: const Text(
                          'Clear Filters',
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: statusDropdown,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: serviceDropdown,
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: clearFilters,
                    icon: const Icon(
                      Icons.filter_alt_off_rounded,
                    ),
                    label: const Text(
                      'Clear',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget buildTransactionCard(
    dynamic rawTransaction,
  ) {
    final Map<String, dynamic> transaction = toMap(rawTransaction);

    final String service = transactionService(transaction);

    final String status = transactionStatus(transaction);

    final Color currentServiceColor = serviceColor(service);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => showTransactionDetails(
          transaction,
        ),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE8EDF3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 49,
                height: 49,
                decoration: BoxDecoration(
                  color: currentServiceColor.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  serviceIcon(service),
                  color: currentServiceColor,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatText(service),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(
                                0xFF0F172A,
                              ),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor(
                              status,
                            ).withValues(
                              alpha: 0.10,
                            ),
                            borderRadius: BorderRadius.circular(
                              20,
                            ),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: statusColor(
                                status,
                              ),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      customerName(transaction),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      transactionReference(
                        transaction,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatDate(
                              transaction['createdAt'],
                            ),
                            style: const TextStyle(
                              color: Color(
                                0xFF94A3B8,
                              ),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Text(
                          formatMoney(
                            transactionAmount(
                              transaction,
                            ),
                          ),
                          style: const TextStyle(
                            color: Color(
                              0xFF0F766E,
                            ),
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> loadRefundHistory({int page = 1}) async {
    setState(() {
      historyLoading = true;
      historyError = false;
      historyErrorMessage = '';
    });
    try {
      final Map<String, dynamic> response =
          await refundsApi.history(page: page);
      if (!mounted) return;
      final dynamic items = response['items'];
      setState(() {
        refundHistoryItems =
            items is List ? List<dynamic>.from(items) : <dynamic>[];
        historyPage =
            response['page'] is num ? (response['page'] as num).toInt() : page;
        historyPages = response['pages'] is num
            ? (response['pages'] as num).toInt().clamp(1, 1 << 31).toInt()
            : 1;
        historyLoading = false;
      });
    } on ManualRefundApiException catch (error) {
      if (!mounted) return;
      setState(() {
        historyLoading = false;
        historyError = true;
        historyErrorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        historyLoading = false;
        historyError = true;
        historyErrorMessage = 'Refund history could not be loaded.';
      });
    }
  }

  Widget buildRefundHistory() {
    if (historyLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0F766E)),
      );
    }
    if (historyError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 42, color: Color(0xFFB45309)),
              const SizedBox(height: 12),
              Text(historyErrorMessage, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => loadRefundHistory(page: historyPage),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const Text(
          'Refund History',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 14),
        if (refundHistoryItems.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 55),
            child: Column(
              children: [
                Icon(Icons.history_rounded, size: 50, color: Color(0xFF94A3B8)),
                SizedBox(height: 12),
                Text('No refunds recorded',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(height: 5),
                Text('Completed refunds will appear here.',
                    style: TextStyle(color: Color(0xFF64748B))),
              ],
            ),
          )
        else
          ...refundHistoryItems.map((dynamic raw) {
            final Map<String, dynamic> item = toMap(raw);
            return Card(
              color: Colors.white,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE8EDF3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item['customerName'] ?? 'Customer'} · ${item['reference'] ?? '—'}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A)),
                          ),
                        ),
                        Text(
                          formatMoney(toDouble(item['amount'])),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F766E)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                        'Original: ${item['originalReference'] ?? 'Not available'}'),
                    Text(
                        'Status: ${formatText(item['status'])}  ·  ${formatDate(item['createdAt'])}'),
                    Text('Reason: ${item['reason'] ?? 'Not available'}'),
                    Text(
                        'Administrator: ${item['administrator'] ?? 'Not available'}'),
                  ],
                ),
              ),
            );
          }),
        if (historyPages > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: historyPage > 1
                    ? () => loadRefundHistory(page: historyPage - 1)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('Page $historyPage of $historyPages'),
              IconButton(
                tooltip: 'Next page',
                onPressed: historyPage < historyPages
                    ? () => loadRefundHistory(page: historyPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
      ],
    );
  }

  Widget buildPagination() {
    if (totalPages <= 1) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous page',
            onPressed: currentPage > 1
                ? () {
                    loadTransactions(
                      page: currentPage - 1,
                    );
                  }
                : null,
            icon: const Icon(
              Icons.chevron_left_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Page $currentPage of $totalPages',
            style: const TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Next page',
            onPressed: currentPage < totalPages
                ? () {
                    loadTransactions(
                      page: currentPage + 1,
                    );
                  }
                : null,
            icon: const Icon(
              Icons.chevron_right_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildErrorState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        Icon(
          Icons.cloud_off_rounded,
          size: 68,
          color: Colors.red.shade300,
        ),
        const SizedBox(height: 18),
        const Text(
          'Unable to load transactions',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          errorMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF64748B),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: FilledButton.icon(
            onPressed: () => loadTransactions(page: 1),
            icon: const Icon(
              Icons.refresh_rounded,
            ),
            label: const Text('Try Again'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 25,
        vertical: 45,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFE8EDF3),
        ),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            color: Color(0xFF94A3B8),
            size: 55,
          ),
          SizedBox(height: 15),
          Text(
            'No transactions found',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'Try changing the search or filters.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildTransactionsBody() {
    if (showingRefundHistory) return buildRefundHistory();
    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double horizontalPadding = constraints.maxWidth >= 800 ? 28 : 16;

        return RefreshIndicator(
          color: const Color(0xFF0F766E),
          onRefresh: () => loadTransactions(
            refresh: true,
            page: currentPage,
          ),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              30,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 950,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      buildFilters(),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'All Transactions',
                              style: TextStyle(
                                color: Color(
                                  0xFF0F172A,
                                ),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            '$totalTransactions total',
                            style: const TextStyle(
                              color: Color(
                                0xFF64748B,
                              ),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      if (transactions.isEmpty)
                        buildEmptyState()
                      else
                        ...transactions.map(
                          (dynamic transaction) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: 13,
                            ),
                            child: buildTransactionCard(
                              transaction,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      buildPagination(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Admin Transactions',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: showingRefundHistory
                ? 'Return to transactions'
                : 'Refund history',
            onPressed: () {
              setState(() {
                showingRefundHistory = !showingRefundHistory;
              });
              if (showingRefundHistory) loadRefundHistory(page: 1);
            },
            icon: Icon(showingRefundHistory
                ? Icons.receipt_long_outlined
                : Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: isRefreshing
                ? null
                : () {
                    loadTransactions(
                      refresh: true,
                      page: currentPage,
                    );
                  },
            icon: isRefreshing
                ? const SizedBox(
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.refresh_rounded,
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0F766E),
              ),
            )
          : hasError
              ? RefreshIndicator(
                  onRefresh: () => loadTransactions(
                    refresh: true,
                    page: 1,
                  ),
                  child: buildErrorState(),
                )
              : buildTransactionsBody(),
    );
  }
}

typedef ManualRefundSubmit = Future<String?> Function(
  String reason,
  bool providerRiskAcknowledged,
);

class ManualRefundDialog extends StatefulWidget {
  const ManualRefundDialog({
    super.key,
    required this.transaction,
    required this.canExecute,
    this.initialReason = '',
    this.reasonLocked = false,
    this.initialProviderRiskAcknowledged = false,
    required this.formatMoney,
    required this.formatText,
    required this.formatDate,
    required this.onSubmit,
  });

  final Map<String, dynamic> transaction;
  final bool canExecute;
  final String initialReason;
  final bool reasonLocked;
  final bool initialProviderRiskAcknowledged;
  final String Function(double) formatMoney;
  final String Function(dynamic) formatText;
  final String Function(dynamic) formatDate;
  final ManualRefundSubmit onSubmit;

  @override
  State<ManualRefundDialog> createState() => _ManualRefundDialogState();
}

class _ManualRefundDialogState extends State<ManualRefundDialog> {
  late final TextEditingController reasonController =
      TextEditingController(text: widget.initialReason);
  bool confirmed = false;
  bool providerRiskAcknowledged = false;
  bool submitting = false;
  bool hasAttempted = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    providerRiskAcknowledged = widget.initialProviderRiskAcknowledged;
  }

  Map<String, dynamic> get customer {
    final dynamic value = widget.transaction['customer'];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  Map<String, dynamic> get refund {
    final dynamic value = widget.transaction['refund'];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  String get providerStatus =>
      (widget.transaction['providerStatus'] ?? '').toString().trim();

  bool get providerSuccessConfirmed => const <String>{
        'SUCCESS',
        'SUCCESSFUL',
        'SUCCEEDED',
        'COMPLETED',
        'DELIVERED',
        'ORDER_COMPLETED',
      }.contains(providerStatus.toUpperCase());

  @override
  void dispose() {
    reasonController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final String reason = reasonController.text.trim();
    if (reason.length < 10 ||
        reason.length > 500 ||
        !confirmed ||
        !providerRiskAcknowledged) {
      setState(() => error =
          'Enter a reason of 10–500 characters, confirm the refund, and acknowledge the provider outcome risk.');
      return;
    }
    if (submitting) return;
    setState(() {
      submitting = true;
      hasAttempted = true;
      error = '';
    });
    final String? failure =
        await widget.onSubmit(reason, providerRiskAcknowledged);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        submitting = false;
        error = failure;
      });
    }
  }

  Widget detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 142,
            child: Text(label,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          ),
          Expanded(
            child: SelectableText(value.isEmpty ? 'Not available' : value,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dynamic rawBlockers = refund['blockers'];
    final List<String> blockers = rawBlockers is List
        ? rawBlockers.map((dynamic value) => value.toString()).toList()
        : <String>[];
    final bool eligible = refund['eligible'] == true;
    final bool pendingTransaction =
        (widget.transaction['status'] ?? '').toString().toUpperCase() ==
            'PENDING';
    final bool knownSuccessfulProviderOutcome = providerSuccessConfirmed;
    final bool permitted = eligible &&
        widget.canExecute &&
        blockers.isEmpty &&
        pendingTransaction &&
        !knownSuccessfulProviderOutcome;
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Payment investigation',
                        style: TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: submitting ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                  widget.formatMoney(
                    (widget.transaction['amount'] as num?)?.toDouble() ??
                        double.tryParse('${widget.transaction['amount']}') ??
                        0,
                  ),
                  style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F766E))),
              const SizedBox(height: 16),
              detail('Transaction ID',
                  '${widget.transaction['id'] ?? 'Not available'}'),
              detail('Reference',
                  '${widget.transaction['reference'] ?? 'Not available'}'),
              detail('Service',
                  widget.formatText(widget.transaction['serviceType'])),
              detail('Status', widget.formatText(widget.transaction['status'])),
              detail('Created',
                  widget.formatDate(widget.transaction['createdAt'])),
              detail('Customer', '${customer['name'] ?? 'Not available'}'),
              detail('Phone', '${customer['phone'] ?? 'Not available'}'),
              detail('Wallet debit status',
                  widget.formatText(widget.transaction['walletDebitStatus'])),
              detail(
                  'Verified debit amount',
                  widget.transaction['verifiedDebitAmount'] == null
                      ? 'Not available'
                      : widget.formatMoney(double.tryParse(
                              '${widget.transaction['verifiedDebitAmount']}') ??
                          0)),
              detail('Provider status',
                  providerStatus.isEmpty ? 'Not available' : providerStatus),
              detail(
                  'Refund eligibility', eligible ? 'Eligible' : 'Not eligible'),
              if (blockers.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text('Eligibility blockers',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                ...blockers.map((String blocker) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('• $blocker',
                          style: const TextStyle(color: Color(0xFF9A3412))),
                    )),
              ],
              if (!permitted) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Text(
                    !pendingTransaction
                            ? 'Only a transaction currently marked PENDING can be refunded. Successful and already-refunded transactions cannot be refunded again.'
                            : !widget.canExecute
                                ? 'Your account does not have the explicit transactions.refund permission required to execute refunds. Ask a Head Office access administrator to assign it.'
                                : !eligible
                                    ? 'This transaction is not eligible for a refund.'
                                : blockers.isNotEmpty
                                    ? 'This transaction has refund eligibility blockers. Resolve them before any refund.'
                                    : knownSuccessfulProviderOutcome
                                        ? 'The provider outcome confirms successful delivery. This transaction cannot be refunded.'
                                        : 'Refund execution is unavailable for this transaction.',
                    style:
                        const TextStyle(color: Color(0xFF9A3412), height: 1.35),
                  ),
                ),
              ],
              if (permitted) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: const Text(
                      'Provider outcome has not been confirmed. This manual refund may result in a financial loss if the service was delivered.',
                      style: TextStyle(color: Color(0xFF9A3412), height: 1.35),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Refund Customer',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'The original wallet debit is determined by Servicepay. No refund amount can be entered here.',
                  style: TextStyle(color: Color(0xFF64748B), height: 1.35),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 500,
                  readOnly: submitting || widget.reasonLocked || hasAttempted,
                  decoration: const InputDecoration(
                    labelText: 'Reason for refund',
                    hintText: 'Document the investigation outcome',
                    helperText:
                        '10–500 characters. Locked once a request is first submitted.',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                CheckboxListTile(
                  value: confirmed,
                  onChanged: submitting
                      ? null
                      : (bool? value) =>
                          setState(() => confirmed = value == true),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I confirm this refund is authorized and should return the original debit.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                CheckboxListTile(
                  value: providerRiskAcknowledged,
                  onChanged: submitting
                      ? null
                      : (bool? value) => setState(
                            () => providerRiskAcknowledged = value == true,
                          ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I acknowledge the financial risk of this manual refund if the service was delivered.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                if (error.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(error,
                        style: const TextStyle(color: Color(0xFFB91C1C))),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: submitting ? null : submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: submitting
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.replay_rounded),
                    label: Text(
                        submitting ? 'Submitting securely' : 'Refund Customer'),
                  ),
                ),
              ],
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
