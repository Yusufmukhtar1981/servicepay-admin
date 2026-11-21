import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_customer_360_api.dart';

typedef PhoneLauncher = Future<bool> Function(Uri uri);

/// Paged customer directory backed by [AdminCustomer360Api.directory].
///
/// Used below Customer 360 search (profile + individual virtual-account
/// actions) and inside Virtual Account Management (multi-select). The
/// directory never triggers generation itself.
class AdminCustomer360Directory extends StatefulWidget {
  const AdminCustomer360Directory({
    super.key,
    required this.api,
    this.onOpenProfile,
    this.onOpenVirtualAccount,
    this.selectedIds,
    this.onToggleSelected,
    this.initialAccount = '',
    this.pageSize = 20,
    this.phoneLauncher,
    this.title = 'Customer directory',
  });

  final AdminCustomer360Api api;
  final ValueChanged<Map<String, dynamic>>? onOpenProfile;
  final ValueChanged<Map<String, dynamic>>? onOpenVirtualAccount;
  final Set<String>? selectedIds;
  final void Function(Map<String, dynamic> item, bool selected)?
      onToggleSelected;
  final String initialAccount;
  final int pageSize;
  final PhoneLauncher? phoneLauncher;
  final String title;

  @override
  State<AdminCustomer360Directory> createState() =>
      _AdminCustomer360DirectoryState();
}

class _AdminCustomer360DirectoryState extends State<AdminCustomer360Directory> {
  static const _ink = Color(0xff173b40);
  static const _teal = Color(0xff087f78);
  static const _muted = Color(0xff708783);

  final _search = TextEditingController();
  Timer? _debounce;
  String _status = '';
  late String _account = widget.initialAccount;
  int _page = 1;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _pagination = {};
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim();
  bool get _queryTooShort => _query.isNotEmpty && _query.length < 2;

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    setState(() {});
    if (_queryTooShort) return;
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(1));
  }

  Future<void> _load(int page) async {
    if (_queryTooShort) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.directory(
        page: page,
        limit: widget.pageSize,
        search: _query,
        status: _status,
        account: _account,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = result.items;
        _pagination = result.pagination;
        _page = page;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  int _int(String key) {
    final v = _pagination[key];
    return v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  }

  int get _pages => _int('pages') > 0 ? _int('pages') : _int('totalPages');
  int get _total => _int('total');

  String _text(dynamic v, [String fallback = '—']) {
    final t = v?.toString().trim() ?? '';
    return t.isEmpty ? fallback : t;
  }

  Map<String, dynamic> _eligibility(Map<String, dynamic> item) =>
      item['eligibility'] is Map
          ? Map<String, dynamic>.from(item['eligibility'])
          : {};

  Future<void> _call(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: digits);
    final launcher = widget.phoneLauncher ?? launchUrl;
    final ok = await launcher(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open the phone dialler.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('customer-directory'),
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xffdce9e5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 4,
          children: [
            Text(widget.title,
                style: const TextStyle(
                    color: _ink, fontWeight: FontWeight.w800, fontSize: 15)),
            if (!_loading && _error == null)
              Text('$_total customers',
                  key: const Key('directory-total'),
                  style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        _filters(),
        if (_queryTooShort)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Enter at least 2 characters to search.',
                key: Key('directory-search-min'),
                style: TextStyle(color: Color(0xff9b3d32), fontSize: 12)),
          ),
        const SizedBox(height: 10),
        if (_loading)
          ...List.generate(
              3,
              (_) => Container(
                  height: 64,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xffe4eeea),
                      borderRadius: BorderRadius.circular(12))))
        else if (_error != null)
          _errorBox()
        else if (_items.isEmpty)
          const Padding(
            key: Key('directory-empty'),
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: Text('No customers match these filters.',
                  style: TextStyle(color: _muted)),
            ),
          )
        else
          ..._items.map(_row),
        if (!_loading && _error == null && _items.isNotEmpty) _pager(),
      ]),
    );
  }

  Widget _filters() => LayoutBuilder(builder: (context, c) {
        final half = c.maxWidth < 540 ? c.maxWidth : (c.maxWidth - 12) / 3;
        InputDecoration deco(String label) => InputDecoration(
            labelText: label,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)));
        return Wrap(spacing: 12, runSpacing: 10, children: [
          SizedBox(
            width: half,
            child: TextField(
              key: const Key('directory-search'),
              controller: _search,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _load(1),
              decoration: deco('Name, phone or email')
                  .copyWith(prefixIcon: const Icon(Icons.search, size: 18)),
            ),
          ),
          SizedBox(
            width: half,
            child: DropdownButtonFormField<String>(
              key: const Key('directory-status'),
              value: _status,
              isExpanded: true,
              decoration: deco('Status'),
              items: const [
                DropdownMenuItem(value: '', child: Text('All statuses')),
                DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                DropdownMenuItem(value: 'INACTIVE', child: Text('Inactive')),
              ],
              onChanged: (v) {
                setState(() => _status = v ?? '');
                _load(1);
              },
            ),
          ),
          SizedBox(
            width: half,
            child: DropdownButtonFormField<String>(
              key: const Key('directory-account'),
              value: _account,
              isExpanded: true,
              decoration: deco('Virtual account'),
              items: const [
                DropdownMenuItem(value: '', child: Text('All customers')),
                DropdownMenuItem(value: 'WITH', child: Text('With account')),
                DropdownMenuItem(
                    value: 'WITHOUT', child: Text('Without account')),
              ],
              onChanged: (v) {
                setState(() => _account = v ?? '');
                _load(1);
              },
            ),
          ),
        ]);
      });

  Widget _errorBox() => Container(
        key: const Key('directory-error'),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: const Color(0xfffff1ef),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Color(0xffbb4a3b)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(_error!,
                  style: const TextStyle(color: Color(0xff8d3d33)))),
          TextButton(
              key: const Key('directory-retry'),
              onPressed: () => _load(_page),
              child: const Text('Retry')),
        ]),
      );

  Widget _row(Map<String, dynamic> item) {
    final id = _text(item['id'], '');
    final name = _text(item['fullName']);
    final phone = _text(item['phone'], '');
    final elig = _eligibility(item);
    final hasAccount = item['hasVirtualAccount'] == true;
    final selectable = widget.onToggleSelected != null;
    final selected = widget.selectedIds?.contains(id) ?? false;
    final eligible = elig['canGenerate'] == true || elig['canRetry'] == true;
    final reconcile = elig['requiresReconciliation'] == true;
    final accountLabel = hasAccount
        ? 'Account ${_text(item['accountStatus'], 'recorded').replaceAll('_', ' ').toLowerCase()}'
        : 'No account';
    return Container(
      key: Key('directory-row-$id'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? const Color(0xffe7f4ef) : const Color(0xfff7faf8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (selectable)
          Checkbox(
            key: Key('directory-select-$id'),
            value: selected,
            onChanged: id.isEmpty || !eligible || reconcile
                ? null
                : (v) => widget.onToggleSelected!(item, v == true),
          )
        else
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xffe7f4ef),
            foregroundColor: _teal,
            child: Text(name.substring(0, 1).toUpperCase()),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style:
                    const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Wrap(spacing: 10, runSpacing: 2, children: [
              if (phone.isNotEmpty)
                InkWell(
                  key: Key('directory-call-$id'),
                  onTap: () => _call(phone),
                  child: Text(phone,
                      style: const TextStyle(
                          color: _teal,
                          fontSize: 12,
                          decoration: TextDecoration.underline)),
                ),
              Text(_text(item['email']),
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _pill(item['active'] == false
                  ? 'Inactive'
                  : _text(item['status'], 'Unknown').toLowerCase()),
              _pill(accountLabel, warn: !hasAccount),
              if (reconcile) _pill('Reconciliation required', warn: true),
            ]),
            if (_text(elig['reason'], '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_text(elig['reason']),
                  style: const TextStyle(color: _muted, fontSize: 11)),
            ],
            if ((widget.onOpenProfile != null ||
                    widget.onOpenVirtualAccount != null))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 4, children: [
                  if (widget.onOpenProfile != null)
                    TextButton.icon(
                      key: Key('directory-open-$id'),
                      onPressed:
                          id.isEmpty ? null : () => widget.onOpenProfile!(item),
                      icon: const Icon(Icons.person_search_outlined, size: 16),
                      label: const Text('Open profile'),
                    ),
                  if (widget.onOpenVirtualAccount != null)
                    TextButton.icon(
                      key: Key('directory-va-$id'),
                      onPressed: id.isEmpty
                          ? null
                          : () => widget.onOpenVirtualAccount!(item),
                      icon: const Icon(Icons.account_balance_outlined,
                          size: 16),
                      label: const Text('Virtual account'),
                    ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _pill(String text, {bool warn = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: warn ? const Color(0xfffff3dc) : const Color(0xffe7f4ef),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                color: warn ? const Color(0xff73521a) : _teal,
                fontSize: 11,
                fontWeight: FontWeight.w800)),
      );

  Widget _pager() => Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text(_pages > 0 ? 'Page $_page of $_pages' : 'Page $_page',
            key: const Key('directory-page'),
            style: const TextStyle(color: _muted, fontSize: 12)),
        IconButton(
            key: const Key('directory-prev'),
            tooltip: 'Previous page',
            onPressed: _page > 1 ? () => _load(_page - 1) : null,
            icon: const Icon(Icons.chevron_left)),
        IconButton(
            key: const Key('directory-next'),
            tooltip: 'Next page',
            onPressed: _page < _pages ? () => _load(_page + 1) : null,
            icon: const Icon(Icons.chevron_right)),
      ]);
}
