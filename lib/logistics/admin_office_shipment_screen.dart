import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../admin/private_asset_download.dart';
import '../admin/private_asset_print.dart';
import 'logistics_api.dart';

class AdminOfficeShipmentScreen extends StatefulWidget {
  const AdminOfficeShipmentScreen(
      {super.key, required this.api, this.onCreated, this.scope = 'admin'});

  final LogisticsApi api;
  final VoidCallback? onCreated;
  final String scope;

  @override
  State<AdminOfficeShipmentScreen> createState() =>
      _AdminOfficeShipmentScreenState();
}

class _AdminOfficeShipmentScreenState extends State<AdminOfficeShipmentScreen> {
  final Map<String, TextEditingController> _fields = <String, TextEditingController>{
    for (final String name in <String>[
      'search', 'senderName', 'senderPhone', 'senderEmail', 'senderLga',
      'senderAddress', 'receiverName', 'receiverPhone', 'receiverLga',
      'receiverAddress', 'description', 'quantity', 'weight', 'value',
    ])
      name: TextEditingController(),
  };
  List<Map<String, dynamic>> _routes = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _customers = <Map<String, dynamic>>[];
  Map<String, dynamic>? _customer;
  Map<String, dynamic>? _route;
  Map<String, dynamic>? _quote;
  Map<String, dynamic>? _created;
  bool _loading = true;
  bool _busy = false;
  String _error = '';
  String _category = 'DOCUMENTS';
  String _service = 'STANDARD';
  String _method = 'DOOR_DELIVERY';
  bool _fragile = false;
  bool _acknowledged = false;
  late final String _idempotencyKey;

  String _value(String name) => _fields[name]!.text.trim();
  String _id(Map<String, dynamic> value) =>
      '${value['_id'] ?? value['id'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _idempotencyKey =
        'office-${DateTime.now().microsecondsSinceEpoch}';
    for (final TextEditingController controller in _fields.values) {
      controller.addListener(_invalidateQuote);
    }
    _loadRoutes();
  }

  void _invalidateQuote() {
    if (_quote != null && mounted) setState(() => _quote = null);
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final List<Map<String, dynamic>> routes =
          await widget.api.officeRoutes(scope: widget.scope);
      if (!mounted) return;
      setState(() {
        _routes = routes
            .where((Map<String, dynamic> route) =>
                route['active'] != false &&
                '${route['status'] ?? ''}'.toUpperCase() != 'INACTIVE')
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() { _error = '$error'; _loading = false; });
    }
  }

  Future<void> _searchCustomers(String text) async {
    if (text.trim().length < 2) {
      setState(() => _customers = <Map<String, dynamic>>[]);
      return;
    }
    try {
      final List<Map<String, dynamic>> found =
          await widget.api.searchCustomers(text, scope: widget.scope);
      if (mounted && text == _fields['search']!.text) {
        setState(() => _customers = found.take(20).toList());
      }
    } catch (_) {
      if (mounted) setState(() => _customers = <Map<String, dynamic>>[]);
    }
  }

  void _selectCustomer(Map<String, dynamic> customer) {
    setState(() {
      _customer = customer;
      _customers = <Map<String, dynamic>>[];
      _fields['search']!.text = '${customer['fullName'] ?? ''}';
      _fields['senderName']!.text = '${customer['fullName'] ?? ''}';
      _fields['senderPhone']!.text = '${customer['phone'] ?? ''}';
      _fields['senderEmail']!.text = '${customer['email'] ?? ''}';
    });
  }

  Map<String, dynamic> _payload() {
    return <String, dynamic>{
      if (_customer != null) 'customerId': _id(_customer!),
      'sender': <String, dynamic>{
        'name': _value('senderName'),
        'phone': _value('senderPhone'),
        'email': _value('senderEmail'),
        'state': _route?['originState'],
        'lga': _value('senderLga'),
        'address': _value('senderAddress'),
      },
      'receiver': <String, dynamic>{
        'name': _value('receiverName'),
        'phone': _value('receiverPhone'),
        'state': _route?['destinationState'],
        'lga': _value('receiverLga'),
        'address': _value('receiverAddress'),
      },
      'routeId': _id(_route ?? <String, dynamic>{}),
      'parcel': <String, dynamic>{
        'category': _category,
        'description': _value('description'),
        'quantity': int.tryParse(_value('quantity')),
        'weightKg': num.tryParse(_value('weight')),
        'declaredValue': num.tryParse(_value('value')),
        'fragile': _fragile,
      },
      'serviceType': _service,
      'deliveryMethod': _method,
      'pickupMethod': 'BRANCH_DROP_OFF',
      'prohibitedItemsAcknowledged': _acknowledged,
      'idempotencyKey': _idempotencyKey,
    };
  }

  String? _validate() {
    if (_route == null) return 'Choose an active origin-to-destination route.';
    if (_value('senderName').isEmpty ||
        _value('senderPhone').isEmpty ||
        _value('senderEmail').isEmpty) {
      return 'Enter sender name, phone and email.';
    }
    if (_value('receiverName').isEmpty ||
        _value('receiverPhone').isEmpty ||
        _value('receiverAddress').isEmpty ||
        _value('description').isEmpty ||
        (int.tryParse(_value('quantity')) ?? 0) < 1 ||
        (num.tryParse(_value('weight')) ?? 0) <= 0) {
      return 'Complete receiver and parcel details, including quantity and weight.';
    }
    if (!_acknowledged) return 'Acknowledge the prohibited-items policy.';
    return null;
  }

  Future<void> _getQuote() async {
    final String? issue = _validate();
    if (issue != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(issue)));
      return;
    }
    setState(() { _busy = true; _error = ''; });
    try {
      final Map<String, dynamic> response =
          await widget.api.officeQuote(_payload(), scope: widget.scope);
      final Map<String, dynamic> quote = LogisticsApi.map(response['quote']);
      if (quote.isEmpty) throw const LogisticsApiException('No charge quote was returned.');
      setState(() => _quote = quote);
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_quote == null || _busy) return;
    setState(() { _busy = true; _error = ''; });
    try {
      final Map<String, dynamic> response =
          await widget.api.createOfficeShipment(
              _payload(), scope: widget.scope);
      final Map<String, dynamic> shipment =
          LogisticsApi.map(response['shipment']);
      if (shipment.isEmpty || '${shipment['trackingNumber'] ?? ''}'.isEmpty) {
        throw const LogisticsApiException(
            'Shipment confirmation did not include a tracking number.');
      }
      if (!mounted) return;
      setState(() { _created = shipment; _quote = null; });
      widget.onCreated?.call();
      await _showReceipt(shipment);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showReceipt(Map<String, dynamic> shipment) async {
    final String tracking = '${shipment['trackingNumber']}';
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Shipment registered'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const Text('TRACKING NUMBER', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          SelectableText(tracking, key: const Key('office-created-tracking'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text('${_route?['originState']} → ${_route?['destinationState']}'),
          Text('Charge: ₦${LogisticsApi.map(shipment['quote'])['total'] ?? _quote?['total'] ?? ''}'),
          const Text('Payment status: UNPAID'),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          OutlinedButton.icon(
            onPressed: () => _openReceipt(dialogContext, shipment),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print receipt'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                _openReceipt(dialogContext, shipment, download: true),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download receipt'),
          ),
        ],
      ),
    );
  }

  Future<void> _openReceipt(
    BuildContext context,
    Map<String, dynamic> shipment, {
    bool download = false,
  }) {
    // Open the tab synchronously within the user gesture. Browsers block
    // top-level data: navigation and often block popups after awaited fetches.
    final PrivateAssetPrintTarget? printTarget =
        download ? null : openPrivateAssetPrintTarget();
    return _loadReceipt(context, shipment, printTarget, download: download);
  }

  Future<void> _loadReceipt(
    BuildContext context,
    Map<String, dynamic> shipment,
    PrivateAssetPrintTarget? printTarget, {
    required bool download,
  }) async {
    final String id = _id(shipment);
    if (id.isEmpty) return;
    try {
      final Map<String, dynamic> response = await widget.api.request(
        'GET',
        '/${widget.scope == 'branch' ? 'branches' : 'admin'}'
        '/logistics/interstate/shipments/${Uri.encodeComponent(id)}/receipt',
      );
      String html = '${response['html'] ?? response['receipt'] ?? ''}';
      if (html.isEmpty) {
        throw const LogisticsApiException('Receipt content is unavailable.');
      }
      final String trackingNumber =
          '${response['trackingNumber'] ?? shipment['trackingNumber'] ?? 'ServicePay-Interstate'}'
              .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      if (download) {
        if (!kIsWeb) {
          throw UnsupportedError(
              'Receipt download is currently supported in a web browser.');
        }
        await savePrivateAsset(
          Uint8List.fromList(utf8.encode(html)),
          '$trackingNumber.html',
          'text/html',
        );
      } else {
        final String printAction =
            '<script>window.addEventListener("load",()=>setTimeout(()=>window.print(),250));</script>';
        final int bodyEnd = html.toLowerCase().lastIndexOf('</body>');
        html = bodyEnd < 0
            ? '$printAction$html'
            : html.replaceRange(bodyEnd, bodyEnd, printAction);
        await printPrivateAsset(
          printTarget,
          Uint8List.fromList(utf8.encode(html)),
          'text/html',
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Widget _field(String key, String label, {TextInputType? type, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          key: Key('office-field-$key'),
          controller: _fields[key],
          keyboardType: type,
          minLines: lines,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(widget.scope == 'branch'
          ? 'Register branch shipment'
          : 'Register office shipment')),
      body: _error.isNotEmpty && _routes.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[Text(_error), TextButton(onPressed: _loadRoutes, child: const Text('Retry'))]))
          : ListView(padding: const EdgeInsets.all(18), children: <Widget>[
              if (_created != null) Card(color: Theme.of(context).colorScheme.primaryContainer, child: ListTile(title: const Text('Shipment registered'), subtitle: Text('Tracking: ${_created!['trackingNumber']}'), trailing: IconButton(tooltip: 'Show receipt', icon: const Icon(Icons.receipt_long_outlined), onPressed: () => _showReceipt(_created!)))),
              TextField(controller: _fields['search'], onChanged: _searchCustomers, decoration: const InputDecoration(labelText: 'Find existing customer', helperText: 'Leave unselected to register a guest sender', prefixIcon: Icon(Icons.search), border: OutlineInputBorder())),
              ..._customers.map((Map<String, dynamic> customer) => ListTile(key: Key('office-customer-${_id(customer)}'), title: Text('${customer['fullName'] ?? 'Customer'}'), subtitle: Text('${customer['phone'] ?? ''} · ${customer['email'] ?? ''}'), onTap: () => _selectCustomer(customer))),
              if (_customer != null) Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => setState(() => _customer = null), child: const Text('Clear customer selection'))),
              const SizedBox(height: 16),
              Text('Sender', style: Theme.of(context).textTheme.titleLarge),
              _field('senderName', 'Sender name'),
              _field('senderPhone', 'Sender phone', type: TextInputType.phone),
              _field('senderEmail', 'Sender email', type: TextInputType.emailAddress),
              _field('senderLga', 'Sender LGA'),
              _field('senderAddress', 'Office drop-off / sender address', lines: 2),
              const SizedBox(height: 12),
              Text('Route & receiver', style: Theme.of(context).textTheme.titleLarge),
              DropdownButtonFormField<Map<String, dynamic>>(
                value: _route,
                decoration: const InputDecoration(labelText: 'Active route', border: OutlineInputBorder()),
                items: _routes.map((Map<String, dynamic> route) => DropdownMenuItem<Map<String, dynamic>>(value: route, child: Text('${route['originState']} → ${route['destinationState']}'))).toList(),
                onChanged: (Map<String, dynamic>? value) => setState(() { _route = value; _quote = null; }),
              ),
              const SizedBox(height: 12),
              _field('receiverName', 'Receiver name'),
              _field('receiverPhone', 'Receiver phone', type: TextInputType.phone),
              _field('receiverLga', 'Receiver LGA'),
              _field('receiverAddress', 'Receiver address', lines: 2),
              const SizedBox(height: 12),
              Text('Parcel', style: Theme.of(context).textTheme.titleLarge),
              DropdownButtonFormField<String>(value: _category, decoration: const InputDecoration(labelText: 'Category'), items: const <String>['DOCUMENTS', 'CLOTHING', 'ELECTRONICS', 'FOOD', 'OTHER'].map((String v) => DropdownMenuItem<String>(value: v, child: Text(v))).toList(), onChanged: (String? v) => setState(() => _category = v ?? _category)),
              _field('description', 'Parcel description', lines: 2),
              _field('quantity', 'Quantity', type: TextInputType.number),
              _field('weight', 'Weight (kg)', type: const TextInputType.numberWithOptions(decimal: true)),
              _field('value', 'Declared value (NGN)', type: const TextInputType.numberWithOptions(decimal: true)),
              DropdownButtonFormField<String>(value: _service, decoration: const InputDecoration(labelText: 'Service'), items: const <String>['STANDARD', 'EXPRESS'].map((String v) => DropdownMenuItem<String>(value: v, child: Text(v))).toList(), onChanged: (String? v) => setState(() { _service = v ?? _service; _quote = null; })),
              DropdownButtonFormField<String>(value: _method, decoration: const InputDecoration(labelText: 'Delivery method'), items: const <String>['DOOR_DELIVERY', 'BRANCH_COLLECTION'].map((String v) => DropdownMenuItem<String>(value: v, child: Text(v.replaceAll('_', ' ')))).toList(), onChanged: (String? v) => setState(() { _method = v ?? _method; _quote = null; })),
              SwitchListTile(title: const Text('Fragile parcel'), value: _fragile, onChanged: (bool value) => setState(() { _fragile = value; _quote = null; })),
              CheckboxListTile(value: _acknowledged, onChanged: (bool? value) => setState(() => _acknowledged = value ?? false), title: const Text('I confirm this parcel contains no prohibited items.')),
              if (_quote != null) Card(child: ListTile(leading: const Icon(Icons.payments_outlined), title: const Text('Computed delivery charge'), subtitle: Text('₦${_quote!['total'] ?? _quote!['totalAmount'] ?? _quote!['amount'] ?? '—'} · Payment is not collected during office registration.'), key: const Key('office-shipment-quote'))),
              if (_error.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              Wrap(spacing: 10, runSpacing: 8, children: <Widget>[
                OutlinedButton.icon(onPressed: _busy ? null : _getQuote, icon: const Icon(Icons.calculate_outlined), label: Text(_busy ? 'Working…' : 'Calculate charge')),
                if (_quote != null) FilledButton.icon(key: const Key('office-create-shipment'), onPressed: _busy ? null : _create, icon: const Icon(Icons.inventory_2_outlined), label: const Text('Register parcel')),
              ]),
            ]),
    );
  }
}