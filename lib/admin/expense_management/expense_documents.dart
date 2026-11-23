import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'expense_api.dart';
import 'expense_common.dart';

/// One upload slot. The idempotency key and bytes are retained until the
/// server returns a definitive answer, so a manual retry cannot duplicate.
class PendingExpenseDocument {
  PendingExpenseDocument({required this.name, required this.bytes, required this.key});
  final String name;
  final List<int> bytes;
  final String key;
  bool uploading = false;
  String? error;
  bool outcomeUnknown = false;
}

String fileSize(dynamic bytes) {
  final int? b = asInt(bytes);
  if (b == null) return '';
  if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MiB';
  if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KiB';
  return '$b B';
}

/// Lets the user upload PDF/JPEG/PNG evidence and lists stored documents.
/// [documents] holds server document maps that are READY or ATTACHED.
class ExpenseDocumentPicker extends StatefulWidget {
  const ExpenseDocumentPicker({
    super.key,
    required this.api,
    required this.documents,
    required this.onChanged,
    required this.maxBytes,
    required this.maxDocuments,
    this.enabled = true,
  });
  final ExpenseManagementApi api;
  final List<Map<String, dynamic>> documents;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final int maxBytes;
  final int maxDocuments;
  final bool enabled;

  @override
  State<ExpenseDocumentPicker> createState() => _ExpenseDocumentPickerState();
}

class _ExpenseDocumentPickerState extends State<ExpenseDocumentPicker> {
  final List<PendingExpenseDocument> _pending = <PendingExpenseDocument>[];
  String? _pickError;

  Future<void> _pick() async {
    setState(() => _pickError = null);
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
        allowMultiple: false,
      );
      if (result == null || !mounted) return;
      final PlatformFile file = result.files.single;
      final String ext = file.name.split('.').last.toLowerCase();
      if (!ExpenseManagementApi.allowedDocumentTypes.containsKey(ext)) {
        setState(() => _pickError = 'Only PDF, JPEG and PNG files are accepted.');
        return;
      }
      if (file.bytes == null || file.bytes!.isEmpty) {
        setState(() => _pickError = 'The selected file could not be read or is empty.');
        return;
      }
      if (file.size > widget.maxBytes || file.bytes!.length > widget.maxBytes) {
        setState(() => _pickError = '${file.name} is ${fileSize(file.size)}. The limit is ${fileSize(widget.maxBytes)}.');
        return;
      }
      if (widget.documents.length + _pending.length >= widget.maxDocuments) {
        setState(() => _pickError = 'A maximum of ${widget.maxDocuments} documents can be attached.');
        return;
      }
      final PendingExpenseDocument doc = PendingExpenseDocument(
        name: file.name,
        bytes: file.bytes!,
        key: ExpenseIdempotency.newKey('doc'),
      );
      setState(() => _pending.add(doc));
      await _upload(doc);
    } catch (_) {
      if (mounted) setState(() => _pickError = 'The file picker is unavailable on this device.');
    }
  }

  Future<void> _upload(PendingExpenseDocument doc) async {
    setState(() {
      doc.uploading = true;
      doc.error = null;
    });
    try {
      final Map<String, dynamic> stored = await widget.api.uploadDocument(
        ExpenseDocumentUpload(bytes: doc.bytes, filename: doc.name, idempotencyKey: doc.key),
        maxBytes: widget.maxBytes,
      );
      if (!mounted) return;
      if (text(stored['state']) != 'READY' && text(stored['state']) != 'ATTACHED') {
        setState(() {
          doc.uploading = false;
          doc.outcomeUnknown = true;
          doc.error = 'The server has not confirmed this file as stored (state ${text(stored['state'], fallback: 'unknown')}). It will not be linked. Retry to check again.';
        });
        return;
      }
      setState(() => _pending.remove(doc));
      widget.onChanged(<Map<String, dynamic>>[...widget.documents, stored]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        doc.uploading = false;
        doc.outcomeUnknown = e is ExpenseApiException && e.outcomeUnknown;
        doc.error = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
        OutlinedButton.icon(
          key: const Key('expense-upload-document'),
          onPressed: widget.enabled ? _pick : null,
          icon: const Icon(Icons.upload_file_outlined, size: 18),
          label: const Text('Upload receipt or invoice'),
        ),
        Text('PDF, JPEG or PNG, up to ${fileSize(widget.maxBytes)} each, max ${widget.maxDocuments}. Stored privately.',
            style: const TextStyle(color: expMuted, fontSize: 11.5)),
      ]),
      if (_pickError != null) Padding(padding: const EdgeInsets.only(top: 8), child: ExpenseNotice(_pickError!, tone: 'error')),
      for (final Map<String, dynamic> d in widget.documents)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(text(d['mimeType']) == 'application/pdf' ? Icons.picture_as_pdf_outlined : Icons.image_outlined, color: expGreen),
          title: Text(text(d['name'], fallback: 'Document'), overflow: TextOverflow.ellipsis),
          subtitle: Text('${fileSize(d['size'])} · stored'),
          trailing: IconButton(
            tooltip: 'Remove from this expense',
            onPressed: widget.enabled
                ? () => widget.onChanged(widget.documents.where((Map<String, dynamic> x) => x != d).toList())
                : null,
            icon: const Icon(Icons.close),
          ),
        ),
      for (final PendingExpenseDocument p in _pending)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              const Icon(Icons.cloud_upload_outlined, size: 18, color: expMuted),
              const SizedBox(width: 8),
              Expanded(child: Text('${p.name} · ${p.uploading ? 'uploading' : 'not linked'}', overflow: TextOverflow.ellipsis)),
              if (!p.uploading)
                TextButton(onPressed: () => _upload(p), child: const Text('Retry upload')),
              if (!p.uploading && !p.outcomeUnknown)
                TextButton(onPressed: () => setState(() => _pending.remove(p)), child: const Text('Discard')),
            ]),
            if (p.uploading) const LinearProgressIndicator(minHeight: 3, color: expGreen),
            if (p.error != null) ExpenseNotice(p.error!, tone: p.outcomeUnknown ? 'warn' : 'error'),
          ]),
        ),
    ]);
  }
}
