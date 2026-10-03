import 'package:flutter/material.dart';

import 'admin_delivery_api.dart';

class AdminDeliveryManagementScreen extends StatefulWidget {
  const AdminDeliveryManagementScreen({super.key, this.api});

  final AdminDeliveryApiClient? api;

  @override
  State<AdminDeliveryManagementScreen> createState() =>
      _AdminDeliveryManagementScreenState();
}

class _AdminDeliveryManagementScreenState
    extends State<AdminDeliveryManagementScreen> {
  late final AdminDeliveryApiClient _api;
  final List<String> _statuses = const <String>[
    'ALL',
    'PENDING',
    'ASSIGNED',
    'ACCEPTED',
    'PICKED_UP',
    'IN_TRANSIT',
    'DELIVERED',
    'CANCELLED',
    'FAILED',
    'REFUNDED',
  ];
  List<Map<String, dynamic>> _deliveries = <Map<String, dynamic>>[];
  String _status = 'ALL';
  String _error = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? AdminDeliveryApi();
    _loadDeliveries();
  }

  String _text(dynamic value, {String fallback = ''}) {
    final String result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  Map<String, dynamic> _map(dynamic value) => AdminDeliveryApi.mapFrom(value);

  Future<void> _loadDeliveries() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      final List<Map<String, dynamic>> deliveries = await _api.getDeliveries(
        status: _status,
      );
      if (!mounted) return;
      setState(() {
        _deliveries = deliveries;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openAssignment(Map<String, dynamic> delivery) async {
    final Map<String, dynamic>? assigned =
        await showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) => AssignDeliveryRiderDialog(
            api: _api,
            delivery: delivery,
            reassign:
                _text(delivery['status']) == 'ASSIGNED' &&
                _map(delivery['assignedRiderId']).isNotEmpty,
          ),
        );
    if (assigned == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Rider assigned successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    await _loadDeliveries();
  }

  Future<void> _openDetails(Map<String, dynamic> delivery) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) =>
          _DeliveryDetailsDialog(delivery: delivery),
    );
  }

  Widget _messageState({
    required IconData icon,
    required String title,
    String? message,
    VoidCallback? onRetry,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 52, color: const Color(0xFF0F766E)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            if (message?.isNotEmpty == true) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ],
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('delivery-list-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _deliveryCard(Map<String, dynamic> delivery) {
    final Map<String, dynamic> customer = _map(delivery['customerId']);
    final Map<String, dynamic> rider = _map(delivery['assignedRiderId']);
    final String status = _text(delivery['status'], fallback: 'PENDING');
    final String deliveryId = _text(delivery['_id'] ?? delivery['id']);
    final bool canAssign =
        deliveryId.isNotEmpty && status == 'PENDING' && rider.isEmpty;
    final bool canReassign =
        deliveryId.isNotEmpty && status == 'ASSIGNED' && rider.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _text(delivery['trackingNumber'], fallback: 'Delivery'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  label: Text(status.replaceAll('_', ' ')),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DeliveryLine(
              icon: Icons.person_outline,
              text: _text(
                customer['fullName'] ?? customer['name'],
                fallback: _text(delivery['senderName'], fallback: 'Customer'),
              ),
            ),
            _DeliveryLine(
              icon: Icons.trip_origin,
              text: _text(delivery['pickupAddress'], fallback: 'No pickup'),
            ),
            _DeliveryLine(
              icon: Icons.location_on_outlined,
              text: _text(
                delivery['deliveryAddress'],
                fallback: 'No destination',
              ),
            ),
            if (rider.isNotEmpty || _text(delivery['riderName']).isNotEmpty)
              _DeliveryLine(
                icon: Icons.delivery_dining,
                text: _text(
                  rider['fullName'],
                  fallback: _text(delivery['riderName'], fallback: 'Rider'),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key(
                  'delivery-details-${deliveryId.isEmpty ? _text(delivery['trackingNumber'], fallback: 'delivery') : deliveryId}',
                ),
                onPressed: () => _openDetails(delivery),
                icon: const Icon(Icons.info_outline),
                label: const Text('View details'),
              ),
            ),
            if (canAssign || canReassign) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: Key('assign-rider-$deliveryId'),
                  onPressed: () => _openAssignment(delivery),
                  icon: const Icon(Icons.delivery_dining),
                  label: Text(canReassign ? 'Reassign Rider' : 'Assign Rider'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Delivery Management'),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh deliveries',
            onPressed: _loading ? null : _loadDeliveries,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: DropdownButtonFormField<String>(
              key: const Key('delivery-status-filter'),
              value: _status,
              decoration: const InputDecoration(
                labelText: 'Delivery status',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              items: _statuses
                  .map(
                    (String status) => DropdownMenuItem<String>(
                      value: status,
                      child: Text(status.replaceAll('_', ' ')),
                    ),
                  )
                  .toList(),
              onChanged: _loading
                  ? null
                  : (String? value) {
                      if (value == null || value == _status) return;
                      setState(() {
                        _status = value;
                      });
                      _loadDeliveries();
                    },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                ? _messageState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Unable to load deliveries',
                    message: _error,
                    onRetry: _loadDeliveries,
                  )
                : _deliveries.isEmpty
                ? _messageState(
                    icon: Icons.inventory_2_outlined,
                    title: _status == 'ALL'
                        ? 'No deliveries'
                        : 'No ${_status.toLowerCase()} deliveries',
                  )
                : RefreshIndicator(
                    onRefresh: _loadDeliveries,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _deliveries.length,
                      itemBuilder: (BuildContext context, int index) =>
                          _deliveryCard(_deliveries[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryDetailsDialog extends StatelessWidget {
  const _DeliveryDetailsDialog({required this.delivery});

  final Map<String, dynamic> delivery;

  String _text(dynamic value, {String fallback = '—'}) {
    final String result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  Map<String, dynamic> _map(dynamic value) => AdminDeliveryApi.mapFrom(value);

  Widget _section(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F766E),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Text(_text(value))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> customer = _map(delivery['customerId']);
    final Map<String, dynamic> rider = _map(delivery['assignedRiderId']);
    final String status = _text(delivery['status'], fallback: 'PENDING');
    final dynamic rawAssignments = delivery['assignmentHistory'];
    final List<Map<String, dynamic>> assignmentHistory = rawAssignments is List
        ? rawAssignments
            .whereType<Map>()
            .map((Map item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];
    final List<Widget> timestamps = <Widget>[
      _row('Created', delivery['createdAt']),
      _row('Updated', delivery['updatedAt']),
      _row('Assigned', delivery['assignedAt']),
      _row(
        'Accepted',
        delivery['acceptedAt'] ?? delivery['riderAcceptedAt'],
      ),
      _row('Picked up', delivery['pickedUpAt']),
      _row('In transit', delivery['inTransitAt']),
      _row('Delivered', delivery['deliveredAt']),
      _row('Cancelled', delivery['cancelledAt']),
      _row('Failed', delivery['failedAt']),
    ];

    return AlertDialog(
      title: Text(
        _text(delivery['trackingNumber'], fallback: 'Delivery details'),
        key: const Key('delivery-details-title'),
      ),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.68,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _section('Reference', <Widget>[
                  _row('Tracking number', delivery['trackingNumber']),
                ]),
                _section('Pickup', <Widget>[
                  _row('Address', delivery['pickupAddress']),
                  _row('State', delivery['pickupState']),
                ]),
                _section('Sender', <Widget>[
                  _row(
                    'Name',
                    delivery['senderName'] ??
                        customer['fullName'] ??
                        customer['name'],
                  ),
                  _row(
                    'Phone',
                    delivery['senderPhone'] ?? customer['phone'],
                  ),
                ]),
                _section('Receiver', <Widget>[
                  _row('Name', delivery['receiverName']),
                  _row('Phone', delivery['receiverPhone']),
                  _row('Delivery address', delivery['deliveryAddress']),
                  _row('Delivery state', delivery['deliveryState']),
                ]),
                _section('Package', <Widget>[
                  _row('Name', delivery['packageName']),
                  _row('Description', delivery['packageDescription']),
                  _row('Weight', delivery['packageWeight']),
                ]),
                _section('Rider', <Widget>[
                  _row(
                    'Name',
                    rider['fullName'] ?? rider['name'] ?? delivery['riderName'],
                  ),
                  _row('Phone', rider['phone'] ?? delivery['riderPhone']),
                  _row('Rider reference', rider['riderId']),
                ]),
                _section('Status', <Widget>[
                  _row('Delivery status', status.replaceAll('_', ' ')),
                ]),
                _section('Fee & payment', <Widget>[
                  _row('Delivery fee (NGN)', delivery['deliveryFee']),
                  _row('Payment status', delivery['paymentStatus']),
                  _row('Paid at', delivery['paidAt']),
                  _row('Refunded at', delivery['refundedAt']),
                ]),
                _section('Timestamps', timestamps),
                if (assignmentHistory.isNotEmpty)
                  _section(
                    'Assignment history',
                    assignmentHistory.map((Map<String, dynamic> event) {
                      final Map<String, dynamic> eventRider =
                          _map(event['rider'] ?? event['assignedRiderId']);
                      return _row(
                        _text(event['action'] ?? event['event'],
                            fallback: 'Assignment'),
                        '${_text(eventRider['fullName'] ?? event['riderName'] ?? event['riderId'])} · ${_text(event['assignedAt'] ?? event['createdAt'])}',
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class AssignDeliveryRiderDialog extends StatefulWidget {
  const AssignDeliveryRiderDialog({
    super.key,
    required this.api,
    required this.delivery,
    this.reassign = false,
  });

  final AdminDeliveryApiClient api;
  final Map<String, dynamic> delivery;
  final bool reassign;

  @override
  State<AssignDeliveryRiderDialog> createState() =>
      _AssignDeliveryRiderDialogState();
}

class _AssignDeliveryRiderDialogState extends State<AssignDeliveryRiderDialog> {
  List<Map<String, dynamic>> _riders = <Map<String, dynamic>>[];
  String? _selectedRiderId;
  String _error = '';
  bool _loading = true;
  bool _assigning = false;

  String get _deliveryId =>
      (widget.delivery['_id'] ?? widget.delivery['id'])?.toString().trim() ??
      '';

  bool _isOnline(Map<String, dynamic> rider) {
    final dynamic state = rider['availabilityStatus'] ?? rider['availability'];
    return rider['online'] == true ||
        rider['isOnline'] == true ||
        '$state'.toUpperCase() == 'ONLINE';
  }

  @override
  void initState() {
    super.initState();
    _loadRiders();
  }

  Future<void> _loadRiders() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final List<Map<String, dynamic>> riders = await widget.api
          .getAvailableRiders(_deliveryId);
      riders.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        return (_isOnline(b) ? 1 : 0).compareTo(_isOnline(a) ? 1 : 0);
      });
      if (!mounted) return;
      setState(() {
        _riders = riders;
        if (!_riders.any(
          (Map<String, dynamic> rider) =>
              (rider['_id'] ?? rider['id'])?.toString() == _selectedRiderId,
        )) {
          _selectedRiderId = null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _assign() async {
    final String riderId = _selectedRiderId ?? '';
    if (_assigning || riderId.isEmpty) return;
    setState(() {
      _assigning = true;
      _error = '';
    });
    try {
      final Map<String, dynamic> delivery = widget.reassign
          ? await widget.api.reassignRider(
              deliveryId: _deliveryId,
              riderId: riderId,
            )
          : await widget.api.assignRider(
              deliveryId: _deliveryId,
              riderId: riderId,
            );
      if (!mounted) return;
      Navigator.of(context).pop(delivery);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _assigning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.reassign ? 'Reassign Delivery Rider' : 'Assign Delivery Rider',
      ),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: _loading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _error.isNotEmpty && _riders.isEmpty
              ? Column(
                  key: const Key('rider-load-error'),
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 42,
                      color: Color(0xFF0F766E),
                    ),
                    const SizedBox(height: 12),
                    Text(_error, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('rider-load-retry'),
                      onPressed: _loadRiders,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                )
              : _riders.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No verified active riders are available right now. Refresh or try again later.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    if (_error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ..._riders.map((Map<String, dynamic> rider) {
                      final String id =
                          (rider['_id'] ?? rider['id'])?.toString() ?? '';
                      final String name =
                          rider['fullName']?.toString().trim() ?? '';
                      final String riderCode =
                          rider['riderId']?.toString().trim() ?? '';
                      final String vehicle =
                          rider['vehicleType']?.toString().trim() ?? '';
                      final bool online = _isOnline(rider);
                      return RadioListTile<String>(
                        key: Key('available-rider-$id'),
                        value: id,
                        groupValue: _selectedRiderId,
                        onChanged: _assigning
                            ? null
                            : (String? value) {
                                setState(() {
                                  _selectedRiderId = value;
                                });
                              },
                        title: Text(name.isEmpty ? 'Delivery Rider' : name),
                        subtitle: Text(
                          <String>[
                            riderCode,
                            vehicle,
                          ].where((String item) => item.isNotEmpty).join(' • '),
                        ),
                        secondary: Chip(
                          label: Text(online ? 'ONLINE' : 'OFFLINE'),
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    }),
                  ],
                ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _assigning ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm-rider-assignment'),
          onPressed: _selectedRiderId == null || _assigning ? null : _assign,
          child: _assigning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(widget.reassign ? 'Reassign Rider' : 'Assign Rider'),
        ),
      ],
    );
  }
}

class _DeliveryLine extends StatelessWidget {
  const _DeliveryLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: const Color(0xFF64748B)),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
