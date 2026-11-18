import 'dart:async';

import 'package:flutter/material.dart';

import 'profit_sharing_api.dart';

class ProfitSharingActivationPanel extends StatefulWidget {
  const ProfitSharingActivationPanel({
    super.key,
    required this.api,
    required this.engine,
    required this.service,
    required this.canManage,
    required this.refreshStatus,
  });

  final ProfitSharingApi api;
  final Map<String, dynamic>? engine;
  final String? service;
  final bool canManage;
  final Future<void> Function() refreshStatus;

  @override
  State<ProfitSharingActivationPanel> createState() =>
      _ProfitSharingActivationPanelState();
}

class _ProfitSharingActivationPanelState
    extends State<ProfitSharingActivationPanel> {
  static const Color ink = Color(0xFF20372F);
  static const Color green = Color(0xFF168A3A);
  static const Map<String, String> _serviceNames = <String, String>{
    'AIRTIME': 'Airtime',
    'DATA': 'Data',
    'ELECTRICITY': 'Electricity',
    'CABLE': 'Cable TV',
    'EXAM_PIN': 'Exam PIN',
    'NIN_VERIFICATION': 'NIN Verification',
    'BVN_VERIFICATION': 'BVN Verification',
    'DELIVERY': 'Delivery',
    'SERVICEPAY_TRANSFER': 'ServicePay Transfer',
  };
  final TextEditingController _transactionController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmationController = TextEditingController();
  Map<String, dynamic>? _receipt;
  String? _message;
  bool _messageDanger = false;
  bool _activationForbidden = false;
  bool _expanded = false;
  bool _dryRunLoading = false;
  bool _activationLoading = false;

  @override
  void didUpdateWidget(covariant ProfitSharingActivationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _clearInputs();
      _receipt = null;
      _message = null;
    } else if (_receipt != null &&
        _currentRuleId != _receipt!['ruleId']) {
      _receipt = null;
      _message = 'The service rule changed. Run a new dry-run before activation.';
      _messageDanger = true;
    }
  }

  @override
  void dispose() {
    _clearInputs();
    _transactionController.dispose();
    _reasonController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _clearInputs() {
    _transactionController.clear();
    _reasonController.clear();
    _passwordController.clear();
    _confirmationController.clear();
  }

  Map<String, dynamic>? get _serviceStatus {
    final dynamic services = widget.engine?['services'];
    if (services is! List || widget.service == null) return null;
    for (final dynamic raw in services) {
      if (raw is Map && raw['serviceType'] == widget.service) {
        return Map<String, dynamic>.from(raw);
      }
    }
    return null;
  }

  dynamic get _currentRuleId => _serviceStatus?['ruleId'];

  List<String> get _blockers {
    final Map<String, dynamic>? engine = widget.engine;
    if (engine == null) return const <String>['Backend engine status unavailable.'];
    final List<String> result = <String>[];
    final dynamic storage = engine['storageBlockers'];
    if (storage is List) {
      result.addAll(storage.map((dynamic value) => value.toString()));
    } else {
      result.add('Backend storage readiness is unknown.');
    }
    final dynamic services = engine['services'];
    if (services is List) {
      for (final dynamic rawService in services) {
        if (rawService is! Map || rawService['blockers'] is! List) continue;
        final String serviceType = rawService['serviceType']?.toString() ?? 'Service';
        for (final dynamic blocker in rawService['blockers'] as List) {
          result.add('$serviceType: ${blocker.toString()}');
        }
      }
    } else {
      result.add('Backend service readiness is unknown.');
    }
    if (engine['ready'] != true && result.isEmpty) {
      result.add('Global engine readiness is not confirmed.');
    }
    return result;
  }

  bool get _canActivate {
    final Map<String, dynamic>? engine = widget.engine;
    final Map<String, dynamic>? service = _serviceStatus;
    final dynamic storage = engine?['storageBlockers'];
    final dynamic serviceBlockers = service?['blockers'];
    return widget.canManage &&
        !_activationForbidden &&
        !_activationLoading &&
        !_dryRunLoading &&
        engine != null &&
        (engine['mode'] == 'PAUSED' || engine['mode'] == 'BLOCKED') &&
        storage is List &&
        storage.isEmpty &&
        widget.service != null &&
        service != null &&
        serviceBlockers is List &&
        serviceBlockers.isEmpty;
  }

  bool get _canPause =>
      widget.canManage &&
      !_activationForbidden &&
      !_activationLoading &&
      widget.engine != null &&
      widget.engine!['revision'] is num &&
      widget.service != null &&
      _serviceStatus != null;

  bool get _eligibleReceipt =>
      _receipt != null &&
      _receipt!['id'] is String &&
      _receipt!['serviceType'] == widget.service &&
      _receipt!['ruleId'] == _currentRuleId &&
      _receipt!['financialWrites'] == 0 &&
      _receipt!['plan'] is Map &&
      (_receipt!['plan'] as Map)['eligible'] == true;

  Future<void> _runDryRun() async {
    if (_dryRunLoading || widget.service == null) return;
    final String transactionId = _transactionController.text.trim();
    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(transactionId)) {
      setState(() {
        _receipt = null;
        _message = 'Enter a valid 24-character transaction ID.';
        _messageDanger = true;
      });
      return;
    }
    setState(() {
      _dryRunLoading = true;
      _receipt = null;
      _message = null;
    });
    try {
      final Map<String, dynamic> response =
          await widget.api.dryRun(transactionId);
      final dynamic raw = response['data'];
      final Map<String, dynamic> receipt =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final dynamic plan = receipt['plan'];
      final Map<String, dynamic> planData =
          plan is Map ? Map<String, dynamic>.from(plan) : <String, dynamic>{};
      if (receipt['id'] is! String ||
          (receipt['id'] as String).isEmpty ||
          receipt['serviceType'] != widget.service ||
          receipt['ruleId'] == null ||
          receipt['ruleId'] != _currentRuleId ||
          receipt['financialWrites'] != 0 ||
          planData['eligible'] != true) {
        throw const ProfitSharingApiException(
          'Dry-run did not return an eligible, zero-write receipt for the selected service and current rule.',
        );
      }
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _message = 'Eligible dry-run receipt verified. No financial writes occurred.';
        _messageDanger = false;
      });
    } on ProfitSharingApiException catch (exception) {
      if (mounted) {
        setState(() {
          _receipt = null;
          _message = exception.message;
          _messageDanger = true;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _receipt = null;
          _message = 'Dry-run timed out. No receipt is available; check status before trying again.';
          _messageDanger = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _receipt = null;
          _message = 'Dry-run could not be verified. No receipt is available.';
          _messageDanger = true;
        });
      }
    } finally {
      if (mounted) setState(() => _dryRunLoading = false);
    }
  }

  Future<void> _submit(String mode) async {
    if (_activationLoading) return;
    final bool activateLive = mode == 'LIVE';
    final String reason = _reasonController.text.trim();
    if ((activateLive ? !_canActivate : !_canPause) ||
        reason.length < 10 ||
        _passwordController.text.isEmpty ||
        (activateLive &&
            (!_eligibleReceipt ||
                _confirmationController.text !=
                    'ACTIVATE FUTURE PROFIT SHARING'))) {
      setState(() {
        _message = activateLive
            ? 'Selected-service readiness, eligible dry-run receipt, typed confirmation, reason, and password are required.'
            : 'Reason, current password, and explicit pause confirmation are required.';
        _messageDanger = true;
      });
      return;
    }
    if (!activateLive) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Pause all future admissions?'),
          content: const Text(
            'Stop new profit-sharing admissions for all active services. '
            'Already admitted settlements and refunds will continue safely. '
            'The backend will re-authenticate this request.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm pause'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final Map<String, dynamic> payload = <String, dynamic>{
      'mode': mode,
      'revision': widget.engine?['revision'],
      'services': <String>[widget.service!],
      'confirmation': true,
      'confirmationText': 'ACTIVATE FUTURE PROFIT SHARING',
      'reason': reason,
      'currentPassword': _passwordController.text,
      if (activateLive)
        'dryRunIds': <String, String>{
          widget.service!: _receipt!['id'] as String,
        },
    };
    setState(() {
      _activationLoading = true;
      _message = null;
    });
    try {
      await widget.api.activate(payload);
      if (!mounted) return;
      setState(() {
        _message = activateLive
            ? 'Activation request was accepted by the backend.'
            : 'Pause request was accepted by the backend.';
        _messageDanger = false;
        _receipt = null;
        _reasonController.clear();
      });
      await widget.refreshStatus();
    } on ProfitSharingApiException catch (exception) {
      if (!mounted) return;
      setState(() {
        _message =
            'Activation outcome was not confirmed (${exception.statusCode ?? 'network'}). '
            '${exception.message} Status is being refreshed; do not resubmit automatically.';
        _messageDanger = true;
        if (exception.isForbidden) _activationForbidden = true;
      });
      await widget.refreshStatus();
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _message =
              'Activation outcome is unknown after timeout. Status is being refreshed; do not resubmit automatically.';
          _messageDanger = true;
        });
      }
      await widget.refreshStatus();
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'Activation outcome is unknown. Status is being refreshed; do not resubmit automatically.';
          _messageDanger = true;
        });
      }
      await widget.refreshStatus();
    } finally {
      if (mounted) {
        _passwordController.clear();
        setState(() {
          _activationLoading = false;
          _receipt = null;
          _confirmationController.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> blockers = _blockers;
    final List<dynamic> selectedBlockers =
        _serviceStatus?['blockers'] is List
            ? _serviceStatus!['blockers'] as List<dynamic>
            : const <dynamic>[];
    final bool eligibleReceipt = _eligibleReceipt;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFB),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE1E9E1)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x080E3018),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.lock_outline_rounded, color: green),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Controlled activation',
                  style: TextStyle(
                    color: ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Backend mode: ${widget.engine?['mode'] ?? 'UNKNOWN'} · revision ${widget.engine?['revision'] ?? '—'}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Selected service: ${_serviceNames[widget.service] ?? widget.service ?? 'None'} · '
            'global readiness ${widget.engine?['ready'] == true ? 'ready' : 'not confirmed'}',
            style: const TextStyle(color: Color(0xFF63736A), height: 1.4),
          ),
          const SizedBox(height: 9),
          Text(
            'Backend blockers${blockers.isEmpty ? '' : ' (${blockers.length})'}',
            style: const TextStyle(fontWeight: FontWeight.w900, color: ink),
          ),
          const SizedBox(height: 4),
          if (widget.engine == null)
            const Text(
              'Status unavailable; activation remains blocked.',
              style: TextStyle(color: Color(0xFF8F352E)),
            )
          else if (blockers.isEmpty)
            const Text(
              'No storage or service blockers reported.',
              style: TextStyle(color: Color(0xFF63736A)),
            )
          else
            ...blockers.map(
              (String blocker) => Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  blocker,
                  style: const TextStyle(
                    color: Color(0xFF754333),
                    height: 1.35,
                  ),
                ),
              ),
            ),
          if (widget.service != null && _serviceStatus == null)
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text(
                'Selected service has no engine readiness record.',
                style: TextStyle(color: Color(0xFF8F352E)),
              ),
            ),
          if (selectedBlockers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'Selected service blockers: ${selectedBlockers.join(' · ')}',
                style: const TextStyle(
                  color: Color(0xFF8F352E),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          TextButton.icon(
            key: const ValueKey<String>('profit-sharing-expand-controls'),
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
            label: Text(
              _expanded
                  ? 'Hide activation controls'
                  : 'Review activation controls',
            ),
          ),
          if (_expanded) ...<Widget>[
            const SizedBox(height: 5),
            const Text(
              'A saved rule is not active. The backend rechecks readiness and authentication before accepting any state change.',
              style: TextStyle(color: Color(0xFF63736A), height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('profit-sharing-transaction-id'),
              controller: _transactionController,
              enabled: !_dryRunLoading && !_activationLoading,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Transaction ID for dry-run',
                hintText: '24-character transaction ID',
                helperText: 'Transaction ID only. No amount or evidence flags are accepted.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.service == null ||
                        _dryRunLoading ||
                        _activationLoading
                    ? null
                    : _runDryRun,
                icon: _dryRunLoading
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check_outlined),
                label: Text(
                  _dryRunLoading
                      ? 'Checking transaction…'
                      : 'Run zero-write dry-run',
                ),
              ),
            ),
            if (_receipt != null) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: eligibleReceipt
                      ? const Color(0xFFE4F3E8)
                      : const Color(0xFFFFE8E5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  eligibleReceipt
                      ? 'Eligible receipt ${_receipt!['id']} · rule ${_receipt!['ruleId']} · 0 financial writes'
                      : 'Dry-run receipt is not eligible for this service.',
                  style: TextStyle(
                    color: eligibleReceipt
                        ? const Color(0xFF27573A)
                        : const Color(0xFF8F352E),
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                  ),
                ),
              ),
              if (_receipt!['plan'] is Map) ...<Widget>[
                const SizedBox(height: 6),
                _financialPlanSummary(
                  Map<String, dynamic>.from(_receipt!['plan'] as Map),
                ),
              ],
            ],
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey<String>('profit-sharing-activation-reason'),
              controller: _reasonController,
              enabled: !_activationLoading,
              maxLength: 240,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Activation or pause reason',
                helperText: 'Required audit reason (at least 10 characters).',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey<String>('profit-sharing-current-password'),
              controller: _passwordController,
              enabled: !_activationLoading,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Current password',
                helperText: 'Used for this request only and cleared after submission.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey<String>(
                'profit-sharing-activation-confirmation',
              ),
              controller: _confirmationController,
              enabled: !_activationLoading,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Type ACTIVATE FUTURE PROFIT SHARING',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 9),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _messageDanger
                      ? const Color(0xFFFFE8E5)
                      : const Color(0xFFE4F3E8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: _messageDanger
                        ? const Color(0xFF8F352E)
                        : const Color(0xFF27573A),
                    height: 1.4,
                  ),
                ),
              ),
            ],
            if (!widget.canManage || _activationForbidden) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                'Your account cannot perform activation or pause actions.',
                style: TextStyle(color: Color(0xFF8F352E)),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey<String>('profit-sharing-activate'),
                onPressed: _canActivate &&
                        eligibleReceipt &&
                        _confirmationController.text ==
                            'ACTIVATE FUTURE PROFIT SHARING'
                    ? () => _submit('LIVE')
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                  disabledBackgroundColor: const Color(0xFFB8C9BC),
                ),
                icon: const Icon(Icons.lock_open_rounded),
                label: Text(
                  _activationLoading
                      ? 'Submitting…'
                      : 'Activate future profit sharing',
                ),
              ),
            ),
            const SizedBox(height: 7),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _canPause ? () => _submit('PAUSED') : null,
                icon: const Icon(Icons.pause_circle_outline_rounded),
                label: const Text('Pause all future admissions'),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'No activation request is sent automatically.',
              style: TextStyle(fontSize: 12, color: Color(0xFF728078)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _financialPlanSummary(Map<String, dynamic> plan) {
    final List<String> lines = <String>[];
    for (final MapEntry<String, String> field in <MapEntry<String, String>>[
      const MapEntry<String, String>('netProfitKobo', 'Verified net profit'),
      const MapEntry<String, String>('poolKobo', 'Profit pool'),
      const MapEntry<String, String>('companyRetainedKobo', 'Company-retained profit'),
      const MapEntry<String, String>('unallocatedKobo', 'Unallocated commission'),
      const MapEntry<String, String>('roundingKobo', 'Rounding'),
    ]) {
      final dynamic amount = plan[field.key];
      if (amount is num) {
        lines.add('${field.value}: ₦${(amount / 100).toStringAsFixed(2)}');
      }
    }
    final dynamic poolPercentage = plan['poolPercentage'];
    if (poolPercentage is num) {
      lines.add('Pool percentage: $poolPercentage%');
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5EF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        lines.join(' · '),
        style: const TextStyle(
          color: Color(0xFF44554A),
          fontSize: 12,
          height: 1.45,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
