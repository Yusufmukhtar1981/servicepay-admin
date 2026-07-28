import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminDeliveryScreen extends StatefulWidget {
  const AdminDeliveryScreen({super.key});

  @override
  State<AdminDeliveryScreen> createState() =>
      _AdminDeliveryScreenState();
}

class _AdminDeliveryScreenState
    extends State<AdminDeliveryScreen> {
  static const String baseUrl =
      'https://api.servicepay.ng/api';

  final TextEditingController searchController =
      TextEditingController();

  List<Map<String, dynamic>> deliveries = [];

  String selectedStatus = 'ALL';

  bool isLoading = true;
  bool isRefreshing = false;
  bool hasError = false;

  String errorMessage = '';

  int totalDeliveries = 0;
  int pendingDeliveries = 0;
  int acceptedDeliveries = 0;
  int pickedUpDeliveries = 0;
  int inTransitDeliveries = 0;
  int deliveredDeliveries = 0;
  int cancelledDeliveries = 0;
  int failedDeliveries = 0;

  double totalRevenue = 0;

  @override
  void initState() {
    super.initState();
    loadDeliveries();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<String?> getToken() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getString('auth_token') ??
        prefs.getString('token');
  }

  Future<void> loadDeliveries({
    bool showLoading = true,
  }) async {
    if (showLoading) {
      setState(() {
        isLoading = true;
        hasError = false;
        errorMessage = '';
      });
    } else {
      setState(() {
        isRefreshing = true;
      });
    }

    try {
      final token = await getToken();

      if (token == null || token.trim().isEmpty) {
        throw Exception(
          'Admin session has expired. Please sign in again.',
        );
      }

      final queryParameters = <String, String>{
        'page': '1',
        'limit': '100',
      };

      final search =
          searchController.text.trim();

      if (search.isNotEmpty) {
        queryParameters['search'] = search;
      }

      if (selectedStatus != 'ALL') {
        queryParameters['status'] =
            selectedStatus;
      }

      final uri = Uri.parse(
        '$baseUrl/admin/deliveries',
      ).replace(
        queryParameters: queryParameters,
      );

      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(
            const Duration(seconds: 45),
          );

      dynamic decoded;

      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        throw Exception(
          'The server returned an invalid response.',
        );
      }

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        final message = decoded is Map
            ? decoded['message']?.toString()
            : null;

        throw Exception(
          message ??
              'Failed to load deliveries.',
        );
      }

      final root = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};

      final rawData = root['data'];

      final data = rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : <String, dynamic>{};

      final rawDeliveries = data['deliveries'];

      final loadedDeliveries =
          rawDeliveries is List
              ? rawDeliveries
                  .whereType<Map>()
                  .map(
                    (item) =>
                        Map<String, dynamic>.from(
                      item,
                    ),
                  )
                  .toList()
              : <Map<String, dynamic>>[];

      final rawSummary = data['summary'];

      final summary = rawSummary is Map
          ? Map<String, dynamic>.from(
              rawSummary,
            )
          : <String, dynamic>{};

      if (!mounted) return;

      setState(() {
        deliveries = loadedDeliveries;

        totalDeliveries = toInt(
          summary['total'],
        );

        pendingDeliveries = toInt(
          summary['pending'],
        );

        acceptedDeliveries = toInt(
          summary['accepted'] ??
              summary['assigned'],
        );

        pickedUpDeliveries = toInt(
          summary['pickedUp'],
        );

        inTransitDeliveries = toInt(
          summary['inTransit'],
        );

        deliveredDeliveries = toInt(
          summary['delivered'],
        );

        cancelledDeliveries = toInt(
          summary['cancelled'],
        );

        failedDeliveries = toInt(
          summary['failed'],
        );

        totalRevenue = toDouble(
          summary['totalRevenue'],
        );

        isLoading = false;
        isRefreshing = false;
        hasError = false;
        errorMessage = '';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        isRefreshing = false;
        hasError = true;
        errorMessage = cleanError(error);
      });
    }
  }

  Future<void> updateDeliveryStatus({
    required Map<String, dynamic> delivery,
    required String status,
  }) async {
    final deliveryId =
        delivery['_id']?.toString() ?? '';

    if (deliveryId.isEmpty) {
      showMessage(
        'Invalid delivery ID.',
        isError: true,
      );
      return;
    }

    try {
      final token = await getToken();

      if (token == null || token.trim().isEmpty) {
        throw Exception(
          'Admin session has expired. Please sign in again.',
        );
      }

      final response = await http
          .patch(
            Uri.parse(
              '$baseUrl/admin/deliveries/'
              '$deliveryId/status',
            ),
            headers: {
              'Accept': 'application/json',
              'Content-Type':
                  'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'status': status,
            }),
          )
          .timeout(
            const Duration(seconds: 45),
          );

      dynamic decoded;

      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        throw Exception(
          'The server returned an invalid response.',
        );
      }

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        final message = decoded is Map
            ? decoded['message']?.toString()
            : null;

        throw Exception(
          message ??
              'Failed to update delivery status.',
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop();

      showMessage(
        'Delivery status updated successfully.',
      );

      await loadDeliveries(
        showLoading: false,
      );
    } catch (error) {
      if (!mounted) return;

      showMessage(
        cleanError(error),
        isError: true,
      );
    }
  }

  int toInt(dynamic value) {
    if (value is int) return value;

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  double toDouble(dynamic value) {
    if (value is double) return value;

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  String cleanError(Object error) {
    return error
        .toString()
        .replaceFirst(
          'Exception: ',
          '',
        );
  }

  String getCustomerName(
    Map<String, dynamic> delivery,
  ) {
    final customer = delivery['customerId'];

    if (customer is Map) {
      return customer['fullName']
              ?.toString()
              .trim()
              .isNotEmpty ==
          true
          ? customer['fullName'].toString()
          : customer['name']
                      ?.toString()
                      .trim()
                      .isNotEmpty ==
                  true
              ? customer['name'].toString()
              : delivery['senderName']
                      ?.toString() ??
                  'ServicePay Customer';
    }

    return delivery['senderName']
            ?.toString() ??
        'ServicePay Customer';
  }

  String getCustomerPhone(
    Map<String, dynamic> delivery,
  ) {
    final customer = delivery['customerId'];

    if (customer is Map) {
      final phone =
          customer['phone']?.toString();

      if (phone != null &&
          phone.trim().isNotEmpty) {
        return phone;
      }
    }

    return delivery['senderPhone']
            ?.toString() ??
        'Not available';
  }

  String getTrackingNumber(
    Map<String, dynamic> delivery,
  ) {
    return delivery['trackingNumber']
            ?.toString() ??
        delivery['trackingId']?.toString() ??
        'No tracking number';
  }

  String getPackageName(
    Map<String, dynamic> delivery,
  ) {
    final packageName =
        delivery['packageName']?.toString();

    final description =
        delivery['packageDescription']
            ?.toString();

    if (packageName != null &&
        packageName.trim().isNotEmpty) {
      return packageName;
    }

    if (description != null &&
        description.trim().isNotEmpty) {
      return description;
    }

    return 'Package';
  }

  String formatDate(dynamic value) {
    if (value == null) {
      return 'Not available';
    }

    final date =
        DateTime.tryParse(value.toString());

    if (date == null) {
      return value.toString();
    }

    final localDate = date.toLocal();

    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final deliveryDay = DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
    );

    final difference =
        today.difference(deliveryDay).inDays;

    if (difference == 0) {
      return 'Today';
    }

    if (difference == 1) {
      return 'Yesterday';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${localDate.day} '
        '${months[localDate.month - 1]} '
        '${localDate.year}';
  }

  String formatMoney(dynamic value) {
    final amount = toDouble(value);

    return '₦${amount.toStringAsFixed(2)}';
  }

  String formatStatus(String status) {
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}'
                  '${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Color getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ACCEPTED':
        return Colors.blue;

      case 'PICKED_UP':
        return Colors.deepPurple;

      case 'IN_TRANSIT':
        return Colors.orange;

      case 'DELIVERED':
        return Colors.green;

      case 'CANCELLED':
        return Colors.red;

      case 'FAILED':
        return Colors.red.shade900;

      default:
        return Colors.amber.shade800;
    }
  }

  void showMessage(
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? Colors.red.shade700
              : const Color(0xFF0F766E),
        ),
      );
  }

  void showDeliveryDetails(
    Map<String, dynamic> delivery,
  ) {
    final status =
        delivery['status']?.toString() ??
            'PENDING';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.of(context).size.height *
                    0.90,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                20,
                12,
                20,
                30,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 45,
                      height: 5,
                      margin: const EdgeInsets.only(
                        bottom: 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius:
                            BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF0F766E)
                                  .withValues(
                            alpha: 0.10,
                          ),
                          borderRadius:
                              BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.local_shipping_rounded,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              getTrackingNumber(
                                delivery,
                              ),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatDate(
                                delivery['createdAt'],
                              ),
                              style: TextStyle(
                                color:
                                    Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusBadge(
                        text:
                            formatStatus(status),
                        color:
                            getStatusColor(status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _DetailSection(
                    title:
                        'Customer Information',
                    children: [
                      _DetailRow(
                        icon:
                            Icons.person_outline,
                        label: 'Customer',
                        value: getCustomerName(
                          delivery,
                        ),
                      ),
                      _DetailRow(
                        icon:
                            Icons.phone_outlined,
                        label: 'Phone',
                        value: getCustomerPhone(
                          delivery,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _DetailSection(
                    title:
                        'Delivery Information',
                    children: [
                      _DetailRow(
                        icon: Icons
                            .location_on_outlined,
                        label: 'Pickup',
                        value: delivery[
                                    'pickupAddress']
                                ?.toString() ??
                            'Not available',
                      ),
                      _DetailRow(
                        icon:
                            Icons.flag_outlined,
                        label: 'Destination',
                        value: delivery[
                                    'deliveryAddress']
                                ?.toString() ??
                            'Not available',
                      ),
                      _DetailRow(
                        icon: Icons
                            .inventory_2_outlined,
                        label: 'Package',
                        value: getPackageName(
                          delivery,
                        ),
                      ),
                      _DetailRow(
                        icon:
                            Icons.scale_outlined,
                        label: 'Weight',
                        value:
                            '${toDouble(delivery['packageWeight']).toStringAsFixed(2)} kg',
                      ),
                      _DetailRow(
                        icon:
                            Icons.payments_outlined,
                        label: 'Delivery Fee',
                        value: formatMoney(
                          delivery['deliveryFee'],
                        ),
                      ),
                      _DetailRow(
                        icon: Icons
                            .account_balance_wallet_outlined,
                        label: 'Payment Status',
                        value: formatStatus(
                          delivery[
                                      'paymentStatus']
                                  ?.toString() ??
                              'UNPAID',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _DetailSection(
                    title:
                        'Receiver Information',
                    children: [
                      _DetailRow(
                        icon:
                            Icons.person_outline,
                        label: 'Receiver',
                        value: delivery[
                                    'receiverName']
                                ?.toString() ??
                            'Not available',
                      ),
                      _DetailRow(
                        icon:
                            Icons.phone_outlined,
                        label: 'Receiver Phone',
                        value: delivery[
                                    'receiverPhone']
                                ?.toString() ??
                            'Not available',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(
                          bottomSheetContext,
                        ).pop();

                        showStatusDialog(
                          delivery,
                        );
                      },
                      style:
                          ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF0F766E),
                        foregroundColor:
                            Colors.white,
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(
                            14,
                          ),
                        ),
                      ),
                      icon: const Icon(
                        Icons.edit_rounded,
                      ),
                      label: const Text(
                        'Update Delivery Status',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
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

  void showStatusDialog(
    Map<String, dynamic> delivery,
  ) {
    String newStatus =
        delivery['status']
                ?.toString()
                .toUpperCase() ??
            'PENDING';

    const statuses = [
      'PENDING',
      'ACCEPTED',
      'PICKED_UP',
      'IN_TRANSIT',
      'DELIVERED',
      'CANCELLED',
      'FAILED',
    ];

    if (!statuses.contains(newStatus)) {
      newStatus = 'PENDING';
    }

    bool isUpdating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            dialogContext,
            setDialogState,
          ) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(20),
              ),
              title: const Text(
                'Update Delivery Status',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
              content:
                  DropdownButtonFormField<String>(
                initialValue: newStatus,
                decoration: InputDecoration(
                  labelText: 'Delivery Status',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(12),
                  ),
                ),
                items: statuses.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Text(
                      formatStatus(status),
                    ),
                  );
                }).toList(),
                onChanged: isUpdating
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(() {
                          newStatus = value;
                        });
                      },
              ),
              actions: [
                TextButton(
                  onPressed: isUpdating
                      ? null
                      : () {
                          Navigator.of(
                            dialogContext,
                          ).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isUpdating
                      ? null
                      : () async {
                          setDialogState(() {
                            isUpdating = true;
                          });

                          await updateDeliveryStatus(
                            delivery: delivery,
                            status: newStatus,
                          );

                          if (mounted) {
                            setDialogState(() {
                              isUpdating = false;
                            });
                          }
                        },
                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                  ),
                  child: isUpdating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget buildSummaryCard({
    required String title,
    required int value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.04,
            ),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E)
                  .withValues(
                alpha: 0.10,
              ),
              borderRadius:
                  BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF0F766E),
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  value.toString(),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        Colors.grey.shade600,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        color: Color(0xFF0F766E),
      ),
    );
  }

  Widget buildErrorState() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(24),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 70,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            const Text(
              'Unable to load deliveries',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: loadDeliveries,
              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(0xFF0F766E),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildDeliveryContent() {
    return RefreshIndicator(
      onRefresh: () {
        return loadDeliveries(
          showLoading: false,
        );
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount:
                MediaQuery.of(context).size.width >
                        700
                    ? 4
                    : 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.0,
            shrinkWrap: true,
            physics:
                const NeverScrollableScrollPhysics(),
            children: [
              buildSummaryCard(
                title: 'Total Deliveries',
                value: totalDeliveries,
                icon:
                    Icons.local_shipping_outlined,
              ),
              buildSummaryCard(
                title: 'Pending',
                value: pendingDeliveries,
                icon: Icons.schedule_rounded,
              ),
              buildSummaryCard(
                title: 'In Transit',
                value: inTransitDeliveries,
                icon: Icons.route_outlined,
              ),
              buildSummaryCard(
                title: 'Delivered',
                value: deliveredDeliveries,
                icon: Icons
                    .check_circle_outline_rounded,
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: searchController,
            textInputAction:
                TextInputAction.search,
            onSubmitted: (_) {
              loadDeliveries();
            },
            decoration: InputDecoration(
              hintText:
                  'Search tracking ID, customer or phone',
              prefixIcon:
                  const Icon(Icons.search_rounded),
              suffixIcon: searchController
                      .text.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        searchController.clear();
                        loadDeliveries();
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                      ),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              enabledBorder:
                  OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(15),
                borderSide: BorderSide(
                  color: Colors.grey.shade200,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection:
                  Axis.horizontal,
              children: [
                'ALL',
                'PENDING',
                'ACCEPTED',
                'PICKED_UP',
                'IN_TRANSIT',
                'DELIVERED',
                'CANCELLED',
                'FAILED',
              ].map((status) {
                final selected =
                    selectedStatus == status;

                return Padding(
                  padding:
                      const EdgeInsets.only(
                    right: 8,
                  ),
                  child: ChoiceChip(
                    selected: selected,
                    label: Text(
                      status == 'ACCEPTED'
                          ? 'Accepted'
                          : formatStatus(
                              status,
                            ),
                    ),
                    selectedColor:
                        const Color(0xFF0F766E),
                    backgroundColor:
                        Colors.white,
                    labelStyle: TextStyle(
                      color: selected
                          ? Colors.white
                          : Colors.grey.shade700,
                      fontWeight:
                          FontWeight.w700,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: selected
                          ? const Color(
                              0xFF0F766E,
                            )
                          : Colors.grey.shade300,
                    ),
                    onSelected: (_) {
                      setState(() {
                        selectedStatus =
                            status;
                      });

                      loadDeliveries();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Deliveries',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${deliveries.length} records',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (deliveries.isEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(
                vertical: 50,
                horizontal: 20,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons
                        .local_shipping_outlined,
                    size: 60,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'No deliveries found',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'New customer delivery requests will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            )
          else
            ...deliveries.map((delivery) {
              final status =
                  delivery['status']
                          ?.toString() ??
                      'PENDING';

              return Container(
                margin:
                    const EdgeInsets.only(
                  bottom: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(18),
                  border: Border.all(
                    color:
                        Colors.grey.shade200,
                  ),
                ),
                child: InkWell(
                  borderRadius:
                      BorderRadius.circular(18),
                  onTap: () {
                    showDeliveryDetails(
                      delivery,
                    );
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.all(
                      15,
                    ),
                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration:
                              BoxDecoration(
                            color: const Color(
                              0xFF0F766E,
                            ).withValues(
                              alpha: 0.10,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              14,
                            ),
                          ),
                          child: const Icon(
                            Icons
                                .local_shipping_rounded,
                            color: Color(
                              0xFF0F766E,
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 12,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      getTrackingNumber(
                                        delivery,
                                      ),
                                      style:
                                          const TextStyle(
                                        fontSize: 15,
                                        fontWeight:
                                            FontWeight
                                                .w800,
                                      ),
                                    ),
                                  ),
                                  _StatusBadge(
                                    text:
                                        formatStatus(
                                      status,
                                    ),
                                    color:
                                        getStatusColor(
                                      status,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(
                                height: 7,
                              ),
                              Text(
                                getCustomerName(
                                  delivery,
                                ),
                                style:
                                    const TextStyle(
                                  fontWeight:
                                      FontWeight
                                          .w700,
                                ),
                              ),
                              const SizedBox(
                                height: 6,
                              ),
                              Row(
                                children: [
                                  Icon(
                                    Icons
                                        .location_on_outlined,
                                    size: 16,
                                    color: Colors
                                        .grey.shade500,
                                  ),
                                  const SizedBox(
                                    width: 5,
                                  ),
                                  Expanded(
                                    child: Text(
                                      delivery[
                                                  'deliveryAddress']
                                              ?.toString() ??
                                          'Not available',
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow
                                              .ellipsis,
                                      style:
                                          TextStyle(
                                        color: Colors
                                            .grey
                                            .shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(
                                height: 9,
                              ),
                              Row(
                                children: [
                                  Text(
                                    formatMoney(
                                      delivery[
                                          'deliveryFee'],
                                    ),
                                    style:
                                        const TextStyle(
                                      color: Color(
                                        0xFF0F766E,
                                      ),
                                      fontWeight:
                                          FontWeight
                                              .w800,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    formatDate(
                                      delivery[
                                          'createdAt'],
                                    ),
                                    style:
                                        TextStyle(
                                      color: Colors
                                          .grey
                                          .shade500,
                                      fontSize: 11,
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
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor:
            const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Delivery Management',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: isRefreshing
                ? null
                : () {
                    loadDeliveries(
                      showLoading: false,
                    );
                  },
            icon: isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.refresh_rounded,
                  ),
          ),
        ],
      ),
      body: isLoading
          ? buildLoadingState()
          : hasError
              ? buildErrorState()
              : buildDeliveryContent(),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusBadge({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.12,
        ),
        borderRadius:
            BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius:
            BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 12,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 19,
            color:
                const Color(0xFF0F766E),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color:
                        Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}