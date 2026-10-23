import 'dart:async';

import 'package:flutter/material.dart';

import 'customer_export_api.dart';
import 'customer_export_platform.dart' as export_platform;

class CustomerExportPanel extends StatefulWidget {
  const CustomerExportPanel({
    super.key,
    required this.api,
    required this.searchQuery,
  });

  final CustomerExportApi api;
  final String searchQuery;

  @override
  State<CustomerExportPanel> createState() => _CustomerExportPanelState();
}

class _CustomerExportPanelState extends State<CustomerExportPanel> {
  static const Color _green = Color(0xFF08783E);
  static const Color _ink = Color(0xFF1B3328);
  CustomerExportFile? _file;
  String? _notice;
  String? _error;
  String? _busyAction;
  bool _shareAvailable = false;

  Future<void> _begin(String action) async {
    if (_busyAction != null) return;
    setState(() {
      _busyAction = action;
    });
    Object? printTarget;
    bool printTargetHandedOff = false;
    try {
      final ExportRequest? request = await showDialog<ExportRequest>(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) => _ExportOptionsDialog(
          api: widget.api,
          initialQuery: widget.searchQuery.trim(),
          action: action,
        ),
      );
      if (request == null) return;
      printTarget = request.printTarget;
      if (!mounted) return;
      setState(() {
        _file = null;
        _error = null;
        _notice = null;
      });
      final CustomerExportFile file = await widget.api.generate(
        format: request.format,
        scope: request.scope,
        query: request.scope == 'filtered' ? request.query : '',
        ids: request.scope == 'selected' ? request.ids : <String>[],
        action: action,
      );
      if (!mounted) return;
      if (action == 'download') {
        await export_platform.downloadFile(file);
        if (!mounted) return;
        setState(() {
          _notice = 'Your ${request.format.toUpperCase()} file is ready.';
          _file = file;
        });
      } else if (action == 'print') {
        await export_platform.deliverToPrintTarget(printTarget, file);
        printTargetHandedOff = true;
        if (!mounted) return;
        setState(() {
          _notice = 'PDF opened in a new tab. Use the browser print control '
              'if needed; this does not confirm a physical print.';
          _file = file;
        });
      } else {
        setState(() {
          _file = file;
          _shareAvailable = export_platform.supportsFileShare;
          _notice = _shareAvailable
              ? 'File prepared. Choose Share file to open your device share options.'
              : 'Sharing is unavailable here. Download the prepared file instead.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _notice = action == 'print'
            ? 'The PDF could not be opened. If a new tab appeared, close it.'
            : null;
      });
    } finally {
      if (action == 'print' && !printTargetHandedOff) {
        export_platform.closePrintTarget(printTarget);
      }
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _share() async {
    final CustomerExportFile? file = _file;
    if (file == null) return;
    setState(() {
      _busyAction = 'share-file';
      _error = null;
      _notice = null;
    });
    try {
      final bool shared = await export_platform.shareFile(file);
      if (!mounted) return;
      setState(() {
        _notice = shared
            ? 'Share sheet opened. Choose WhatsApp, Email, or another installed destination.'
            : 'File sharing is not supported by this browser. Download it instead.';
        _shareAvailable = shared;
      });
    } catch (error) {
      if (!mounted) return;
      // A dismissed OS share sheet is a user cancellation, not permission to
      // silently save or upload the customer file.
      setState(() {
        _error = 'Sharing was cancelled or unavailable. No file was sent.';
        _shareAvailable = false;
      });
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _downloadPrepared() async {
    final CustomerExportFile? file = _file;
    if (file == null) return;
    try {
      await export_platform.downloadFile(file);
      if (mounted) {
        setState(() {
          _error = null;
          _notice = 'Download started.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to download the prepared file.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool busy = _busyAction != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD3E6D8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.file_download_outlined, color: _green),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Customer records',
                        style: TextStyle(
                            color: _ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('Prepare a secure file for your next task.',
                        style:
                            TextStyle(color: Color(0xFF5B7063), fontSize: 12)),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: _green),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _ActionButton(
                label: 'Download Customers',
                icon: Icons.download_rounded,
                primary: true,
                onPressed: busy ? null : () => _begin('download'),
              ),
              _ActionButton(
                label: 'Share Customers',
                icon: Icons.ios_share_rounded,
                onPressed: busy ? null : () => _begin('share'),
              ),
              _ActionButton(
                label: 'Print Customers',
                icon: Icons.print_outlined,
                onPressed: busy ? null : () => _begin('print'),
              ),
            ],
          ),
          if (_notice != null || _error != null) ...<Widget>[
            const SizedBox(height: 12),
            if (_notice != null)
              Text(_notice!,
                  style: const TextStyle(
                      color: Color(0xFF345B43), fontSize: 12, height: 1.4)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFF9D3428), fontSize: 12, height: 1.4)),
              ),
            if (_file != null &&
                (_busyAction == 'share-file' || !_shareAvailable) &&
                _busyAction != 'download')
              TextButton.icon(
                onPressed: busy ? null : _downloadPrepared,
                icon: const Icon(Icons.download_rounded, size: 17),
                label: const Text('Download file'),
                style: TextButton.styleFrom(foregroundColor: _green),
              ),
            if (_file != null &&
                _busyAction != 'download' &&
                _shareAvailable &&
                _error == null)
              OutlinedButton.icon(
                onPressed: busy ? null : _share,
                icon: const Icon(Icons.ios_share_rounded, size: 17),
                label: const Text('Share file'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _green,
                  side: const BorderSide(color: Color(0xFF8CB99A)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => primary
      ? FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 17),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF08783E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
        )
      : OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 17),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF276343),
            side: const BorderSide(color: Color(0xFF9ABFA5)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
        );
}

class ExportRequest {
  const ExportRequest({
    required this.format,
    required this.scope,
    required this.query,
    required this.ids,
    this.printTarget,
  });
  final String format;
  final String scope;
  final String query;
  final List<String> ids;
  final Object? printTarget;
}

class _ExportOptionsDialog extends StatefulWidget {
  const _ExportOptionsDialog({
    required this.api,
    required this.initialQuery,
    required this.action,
  });
  final CustomerExportApi api;
  final String initialQuery;
  final String action;

  @override
  State<_ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<_ExportOptionsDialog> {
  String _format = 'csv';
  String _scope = 'all';
  late final String _query = widget.initialQuery;
  final Set<String> _selectedIds = <String>{};

  Future<void> _pickCustomers() async {
    final Set<String>? result = await showDialog<Set<String>>(
      context: context,
      builder: (BuildContext context) => _CustomerPickerDialog(
        api: widget.api,
        initialSelection: _selectedIds,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedIds
          ..clear()
          ..addAll(result);
      });
    }
  }

  void _continue() {
    if (_scope == 'filtered' && _query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter a search before using this scope.')),
      );
      return;
    }
    if (_scope == 'filtered' && _query.length > 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Search text must be 200 characters or fewer.')),
      );
      return;
    }
    if (_scope == 'selected' && _selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one customer.')),
      );
      return;
    }
    final Object? printTarget =
        widget.action == 'print' ? export_platform.openPrintTarget() : null;
    Navigator.pop(
      context,
      ExportRequest(
        format: widget.action == 'print' ? 'pdf' : _format,
        scope: _scope,
        query: _query,
        ids: _selectedIds.toList(growable: false),
        printTarget: printTarget,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFFFBFDFB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          widget.action == 'download'
              ? 'Download customers'
              : widget.action == 'share'
                  ? 'Share customers'
                  : 'Print customers',
          style: const TextStyle(
              color: Color(0xFF1B3328), fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                    'Choose a file format and the customer records to include.',
                    style: TextStyle(color: Color(0xFF64766A), height: 1.45)),
                const SizedBox(height: 18),
                if (widget.action != 'print') ...<Widget>[
                  const _DialogLabel('FILE FORMAT'),
                  const SizedBox(height: 7),
                  SegmentedButton<String>(
                    segments: const <ButtonSegment<String>>[
                      ButtonSegment(value: 'csv', label: Text('CSV')),
                      ButtonSegment(value: 'xlsx', label: Text('Excel')),
                      ButtonSegment(value: 'pdf', label: Text('PDF')),
                    ],
                    selected: <String>{_format},
                    onSelectionChanged: (Set<String> selection) =>
                        setState(() => _format = selection.first),
                  ),
                  const SizedBox(height: 18),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(bottom: 18),
                    child: Text('Print is prepared as a PDF.',
                        style: TextStyle(
                            color: Color(0xFF345B43),
                            fontWeight: FontWeight.w600)),
                  ),
                const _DialogLabel('CUSTOMER SCOPE'),
                const SizedBox(height: 6),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'all',
                  groupValue: _scope,
                  onChanged: (value) => setState(() => _scope = value!),
                  title: const Text('All customers'),
                  subtitle: const Text('The server prepares the full dataset.'),
                  activeColor: const Color(0xFF08783E),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'filtered',
                  groupValue: _scope,
                  onChanged: (value) => setState(() => _scope = value!),
                  title: const Text('Current search'),
                  subtitle: Text(
                      _query.isEmpty ? 'No search entered' : 'Search: $_query'),
                  activeColor: const Color(0xFF08783E),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'selected',
                  groupValue: _scope,
                  onChanged: (value) => setState(() => _scope = value!),
                  title: const Text('Selected customers'),
                  subtitle: Text('${_selectedIds.length} selected'),
                  activeColor: const Color(0xFF08783E),
                ),
                if (_scope == 'selected')
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _pickCustomers,
                      icon: const Icon(Icons.person_search_outlined),
                      label: const Text('Choose customers'),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF08783E)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _continue,
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF08783E)),
            child:
                Text(widget.action == 'print' ? 'Prepare print' : 'Continue'),
          ),
        ],
      );
}

class _DialogLabel extends StatelessWidget {
  const _DialogLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: Color(0xFF697B6F),
          fontSize: 10,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w800));
}

class _CustomerPickerDialog extends StatefulWidget {
  const _CustomerPickerDialog({
    required this.api,
    required this.initialSelection,
  });
  final CustomerExportApi api;
  final Set<String> initialSelection;

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _selected = <String>{};
  final List<String?> _cursorStack = <String?>[null];
  List<ExportCustomer> _customers = <ExportCustomer>[];
  String? _nextCursor;
  String? _error;
  bool _loading = true;
  int _generation = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelection);
    _loadPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadPage() async {
    final int generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> result = await widget.api.customers(
        query: _search.text.trim(),
        after: _cursorStack.last,
        limit: 50,
      );
      final dynamic rows = result['customers'];
      final List<ExportCustomer> customers = rows is List
          ? rows
              .whereType<Map>()
              .map((Map row) =>
                  ExportCustomer.fromJson(Map<String, dynamic>.from(row)))
              .toList(growable: false)
          : <ExportCustomer>[];
      if (!mounted || generation != _generation) return;
      setState(() {
        _customers = customers;
        _nextCursor = result['nextCursor']?.toString();
        if (_nextCursor == 'null' || _nextCursor?.isEmpty == true) {
          _nextCursor = null;
        }
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _cursorStack
        ..clear()
        ..add(null);
      _loadPage();
    });
  }

  void _next() {
    if (_nextCursor == null) return;
    _cursorStack.add(_nextCursor);
    _loadPage();
  }

  void _previous() {
    if (_cursorStack.length <= 1) return;
    _cursorStack.removeLast();
    _loadPage();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFFFBFDFB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: <Widget>[
            const Expanded(
                child: Text('Select customers',
                    style: TextStyle(fontWeight: FontWeight.w800))),
            Text('${_selected.length} selected',
                style: const TextStyle(
                    color: Color(0xFF08783E),
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 430,
          child: Column(
            children: <Widget>[
              TextField(
                controller: _search,
                onChanged: _searchChanged,
                decoration: InputDecoration(
                  hintText: 'Search name, phone, or email',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: const Color(0xFFF3F8F4),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF08783E), strokeWidth: 2.5))
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(_error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Color(0xFF9D3428))),
                                TextButton(
                                    onPressed: _loadPage,
                                    child: const Text('Retry')),
                              ],
                            ),
                          )
                        : _customers.isEmpty
                            ? const Center(
                                child: Text('No customers found.',
                                    style: TextStyle(color: Color(0xFF697B6F))))
                            : ListView.separated(
                                itemCount: _customers.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (BuildContext context, int index) {
                                  final ExportCustomer customer =
                                      _customers[index];
                                  return CheckboxListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 2),
                                    value: _selected.contains(customer.id),
                                    activeColor: const Color(0xFF08783E),
                                    onChanged: (bool? checked) {
                                      if (checked == true &&
                                          _selected.length >= 10000) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'A selection can include up to 10,000 customers.'),
                                          ),
                                        );
                                        return;
                                      }
                                      setState(() {
                                        if (checked == true) {
                                          _selected.add(customer.id);
                                        } else {
                                          _selected.remove(customer.id);
                                        }
                                      });
                                    },
                                    title: Text(
                                        customer.fullName.isEmpty
                                            ? 'Unnamed customer'
                                            : customer.fullName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    subtitle: Text(
                                        '${customer.phone}${customer.email.isEmpty ? '' : '  ·  ${customer.email}'}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  );
                                },
                              ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text('Page ${_cursorStack.length}',
                      style: const TextStyle(
                          color: Color(0xFF697B6F), fontSize: 12)),
                  Row(
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: !_loading && _cursorStack.length > 1
                            ? _previous
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed:
                            !_loading && _nextCursor != null ? _next : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, Set<String>.from(_selected)),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF08783E)),
            child: const Text('Use selection'),
          ),
        ],
      );
}
