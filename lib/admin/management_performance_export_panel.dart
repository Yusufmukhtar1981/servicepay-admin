import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_control_center_download.dart';
import 'admin_management_performance_api.dart';
import 'management_performance_share.dart' as share_platform;
import 'management_performance_share_flow.dart';

class ManagementPerformanceExportPanel extends StatefulWidget {
  const ManagementPerformanceExportPanel({
    super.key,
    required this.api,
    required this.managerId,
    required this.period,
    required this.from,
    required this.to,
    required this.whatsAppSummary,
  });

  final AdminManagementPerformanceApi api;
  final String managerId;
  final String period;
  final String from;
  final String to;
  final String whatsAppSummary;

  @override
  State<ManagementPerformanceExportPanel> createState() =>
      _ManagementPerformanceExportPanelState();
}

class _ManagementPerformanceExportPanelState
    extends State<ManagementPerformanceExportPanel> {
  AdminManagementPerformanceFile? _pdf;
  AdminManagementPerformanceFile? _xlsx;
  bool _busy = false;
  bool _manualAttachFallback = false;
  String? _notice;
  int _revision = 0;

  @override
  void didUpdateWidget(covariant ManagementPerformanceExportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.managerId != widget.managerId ||
        oldWidget.period != widget.period ||
        oldWidget.from != widget.from ||
        oldWidget.to != widget.to) {
      _revision++;
      _pdf = null;
      _xlsx = null;
      _busy = false;
      _manualAttachFallback = false;
      _notice = null;
    }
  }

  Future<void> _prepare(String format) async {
    if (_busy) return;
    final int revision = _revision;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final AdminManagementPerformanceFile file = await widget.api.export(
        managerId: widget.managerId,
        period: widget.period,
        from: widget.from,
        to: widget.to,
        format: format,
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        if (format == 'pdf') _pdf = file;
        if (format == 'xlsx') _xlsx = file;
        _notice = '${format.toUpperCase()} is ready to download.';
      });
    } catch (error) {
      if (mounted && revision == _revision) {
        _message(error.toString(), error: true);
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  Future<void> _download(AdminManagementPerformanceFile file) async {
    try {
      await downloadControlCenterBytes(
          file.bytes, file.contentType, file.filename);
      if (mounted) _message('${file.format.toUpperCase()} download started.');
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  Future<void> _shareFile(AdminManagementPerformanceFile file) async {
    try {
      final ManagementPerformanceShareResult result =
          await runManagementPerformanceShare(
        supported: share_platform.managementPerformanceFileShareSupported,
        share: () => share_platform.shareManagementPerformanceFile(file),
        download: () => downloadControlCenterBytes(
            file.bytes, file.contentType, file.filename),
      );
      if (!mounted) return;
      switch (result) {
        case ManagementPerformanceShareResult.shared:
          _message('Share sheet opened. Choose WhatsApp to continue.');
          break;
        case ManagementPerformanceShareResult.downloadedForManualAttach:
          setState(() {
            _manualAttachFallback = true;
            _notice =
                '${file.format.toUpperCase()} downloaded. Open WhatsApp and attach the downloaded report manually.';
          });
          break;
        case ManagementPerformanceShareResult.cancelled:
          _message('Sharing cancelled.');
          break;
      }
    } catch (_) {
      if (mounted) {
        _message('Could not open sharing. No report was sent.', error: true);
      }
    }
  }

  Future<void> _openWhatsApp() async {
    final Uri uri = Uri.https(
        'wa.me', '/', <String, String>{'text': widget.whatsAppSummary});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      _message('WhatsApp could not be opened.', error: true);
    }
  }

  void _message(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade800 : null,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _prepare('pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Prepare PDF'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _prepare('xlsx'),
              icon: const Icon(Icons.table_view_outlined),
              label: const Text('Prepare Excel'),
            ),
            if (_xlsx != null) ...<Widget>[
              OutlinedButton.icon(
                onPressed: () => _download(_xlsx!),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download Excel'),
              ),
              OutlinedButton.icon(
                onPressed: () => _shareFile(_xlsx!),
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Share Excel / WhatsApp'),
              ),
            ],
            if (_pdf != null) ...<Widget>[
              OutlinedButton.icon(
                onPressed: () => _download(_pdf!),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download PDF'),
              ),
              OutlinedButton.icon(
                onPressed: () => _shareFile(_pdf!),
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Share PDF / WhatsApp'),
              ),
            ],
            if ((_pdf != null || _xlsx != null) &&
                (!share_platform.managementPerformanceFileShareSupported ||
                    _manualAttachFallback))
              OutlinedButton.icon(
                onPressed: _openWhatsApp,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open WhatsApp'),
              ),
            if (_busy)
              const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator()),
          ],
        ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_notice!, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}
