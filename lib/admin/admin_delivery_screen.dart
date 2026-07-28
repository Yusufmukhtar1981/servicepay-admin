import 'package:flutter/material.dart';

class AdminDeliveryScreen extends StatefulWidget {
  const AdminDeliveryScreen({super.key});

  @override
  State<AdminDeliveryScreen> createState() =>
      _AdminDeliveryScreenState();
}

class _AdminDeliveryScreenState
    extends State<AdminDeliveryScreen> {
  final TextEditingController searchController =
      TextEditingController();

  String selectedStatus = 'ALL';

  final List<Map<String, dynamic>> deliveries = [
    {
      'trackingId': 'SP-DEL-1001',
      'customerName': 'ServicePay Customer',
      'customerPhone': '08000000000',
      'pickupAddress': 'Kano Municipal, Kano',
      'destinationAddress': 'Nassarawa, Kano',
      'packageDescription': 'Small Package',
      'deliveryFee': 1500.0,
      'status': 'PENDING',
      'createdAt': 'Today',
    },
  ];

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get filteredDeliveries {
    final String search =
        searchController.text.trim().toLowerCase();

    return deliveries.where((delivery) {
      final String status =
          delivery['status'].toString().toUpperCase();

      final bool matchesStatus =
          selectedStatus == 'ALL' ||
              status == selectedStatus;

      final bool matchesSearch =
          search.isEmpty ||
              delivery['trackingId']
                  .toString()
                  .toLowerCase()
                  .contains(search) ||
              delivery['customerName']
                  .toString()
                  .toLowerCase()
                  .contains(search) ||
              delivery['customerPhone']
                  .toString()
                  .toLowerCase()
                  .contains(search);

      return matchesStatus && matchesSearch;
    }).toList();
  }

  int countByStatus(String status) {
    return deliveries.where((delivery) {
      return delivery['status']
              .toString()
              .toUpperCase() ==
          status;
    }).length;
  }

  Color getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ASSIGNED':
        return Colors.blue;
      case 'PICKED_UP':
        return Colors.deepPurple;
      case 'IN_TRANSIT':
        return Colors.orange;
      case 'DELIVERED':
        return Colors.green;
      case 'CANCELLED':
        return Colors.red;
      default:
        return Colors.amber.shade800;
    }
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

  void showDeliveryDetails(
    Map<String, dynamic> delivery,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.of(context).size.height * 0.88,
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
                      margin:
                          const EdgeInsets.only(bottom: 20),
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
                          color: const Color(0xFF0F766E)
                              .withValues(alpha: 0.10),
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
                              delivery['trackingId']
                                  .toString(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              delivery['createdAt']
                                  .toString(),
                              style: TextStyle(
                                color:
                                    Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusBadge(
                        text: formatStatus(
                          delivery['status'].toString(),
                        ),
                        color: getStatusColor(
                          delivery['status'].toString(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _DetailSection(
                    title: 'Customer Information',
                    children: [
                      _DetailRow(
                        icon: Icons.person_outline,
                        label: 'Customer',
                        value: delivery['customerName']
                            .toString(),
                      ),
                      _DetailRow(
                        icon: Icons.phone_outlined,
                        label: 'Phone',
                        value: delivery['customerPhone']
                            .toString(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _DetailSection(
                    title: 'Delivery Information',
                    children: [
                      _DetailRow(
                        icon:
                            Icons.location_on_outlined,
                        label: 'Pickup',
                        value: delivery['pickupAddress']
                            .toString(),
                      ),
                      _DetailRow(
                        icon: Icons.flag_outlined,
                        label: 'Destination',
                        value: delivery[
                                'destinationAddress']
                            .toString(),
                      ),
                      _DetailRow(
                        icon:
                            Icons.inventory_2_outlined,
                        label: 'Package',
                        value: delivery[
                                'packageDescription']
                            .toString(),
                      ),
                      _DetailRow(
                        icon:
                            Icons.payments_outlined,
                        label: 'Delivery Fee',
                        value:
                            '₦${delivery['deliveryFee'].toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        showStatusDialog(delivery);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(
                        Icons.edit_rounded,
                      ),
                      label: const Text(
                        'Update Delivery Status',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
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
        delivery['status'].toString().toUpperCase();

    const statuses = [
      'PENDING',
      'ASSIGNED',
      'PICKED_UP',
      'IN_TRANSIT',
      'DELIVERED',
      'CANCELLED',
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Update Delivery Status',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: DropdownButtonFormField<String>(
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
                    child: Text(formatStatus(status)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;

                  setDialogState(() {
                    newStatus = value;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      delivery['status'] = newStatus;
                    });

                    Navigator.pop(context);

                    ScaffoldMessenger.of(context)
                        .showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Delivery status updated.',
                        ),
                        backgroundColor:
                            Color(0xFF0F766E),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Update'),
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
        borderRadius: BorderRadius.circular(18),
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
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
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
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filteredDeliveries;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F766E),
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
            onPressed: () {
              setState(() {});
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
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
                  value: deliveries.length,
                  icon: Icons.local_shipping_outlined,
                ),
                buildSummaryCard(
                  title: 'Pending',
                  value: countByStatus('PENDING'),
                  icon: Icons.schedule_rounded,
                ),
                buildSummaryCard(
                  title: 'In Transit',
                  value: countByStatus('IN_TRANSIT'),
                  icon: Icons.route_outlined,
                ),
                buildSummaryCard(
                  title: 'Delivered',
                  value: countByStatus('DELIVERED'),
                  icon:
                      Icons.check_circle_outline_rounded,
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: searchController,
              onChanged: (_) {
                setState(() {});
              },
              decoration: InputDecoration(
                hintText:
                    'Search tracking ID, customer or phone',
                prefixIcon:
                    const Icon(Icons.search_rounded),
                suffixIcon:
                    searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              searchController.clear();
                              setState(() {});
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
                enabledBorder: OutlineInputBorder(
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
                scrollDirection: Axis.horizontal,
                children: [
                  'ALL',
                  'PENDING',
                  'ASSIGNED',
                  'PICKED_UP',
                  'IN_TRANSIT',
                  'DELIVERED',
                  'CANCELLED',
                ].map((status) {
                  final bool selected =
                      selectedStatus == status;

                  return Padding(
                    padding:
                        const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: selected,
                      label: Text(
                        formatStatus(status),
                      ),
                      selectedColor:
                          const Color(0xFF0F766E),
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        color: selected
                            ? Colors.white
                            : Colors.grey.shade700,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      side: BorderSide(
                        color: selected
                            ? const Color(0xFF0F766E)
                            : Colors.grey.shade300,
                      ),
                      onSelected: (_) {
                        setState(() {
                          selectedStatus = status;
                        });
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
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${filtered.length} records',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 50,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.local_shipping_outlined,
                      size: 60,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No deliveries found',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'New customer delivery requests will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...filtered.map((delivery) {
                final String status =
                    delivery['status'].toString();

                return Container(
                  margin:
                      const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.grey.shade200,
                    ),
                  ),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(18),
                    onTap: () {
                      showDeliveryDetails(delivery);
                    },
                    child: Padding(
                      padding:
                          const EdgeInsets.all(15),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
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
                                  BorderRadius.circular(
                                14,
                              ),
                            ),
                            child: const Icon(
                              Icons
                                  .local_shipping_rounded,
                              color:
                                  Color(0xFF0F766E),
                            ),
                          ),
                          const SizedBox(width: 12),
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
                                        delivery[
                                                'trackingId']
                                            .toString(),
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
                                      text: formatStatus(
                                        status,
                                      ),
                                      color:
                                          getStatusColor(
                                        status,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  delivery['customerName']
                                      .toString(),
                                  style: const TextStyle(
                                    fontWeight:
                                        FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      Icons
                                          .location_on_outlined,
                                      size: 16,
                                      color:
                                          Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        delivery[
                                                'destinationAddress']
                                            .toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow
                                            .ellipsis,
                                        style: TextStyle(
                                          color: Colors
                                              .grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 9),
                                Row(
                                  children: [
                                    Text(
                                      '₦${delivery['deliveryFee'].toStringAsFixed(2)}',
                                      style:
                                          const TextStyle(
                                        color:
                                            Color(0xFF0F766E),
                                        fontWeight:
                                            FontWeight.w800,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      delivery['createdAt']
                                          .toString(),
                                      style: TextStyle(
                                        color: Colors
                                            .grey.shade500,
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
      ),
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
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
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 19,
            color: const Color(0xFF0F766E),
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
                    color: Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
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