// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> openFinancialPdf(
  List<int> bytes,
  String filename,
  String contentType,
  Future<void> Function(List<int>, String, String) fallback,
) async {
  final html.Blob blob =
      html.Blob(<Object>[Uint8List.fromList(bytes)], contentType);
  final String url = html.Url.createObjectUrlFromBlob(blob);
  final dynamic opened = html.window.open(url, '_blank');
  if (opened == null) {
    html.Url.revokeObjectUrl(url);
    await fallback(bytes, filename, contentType);
  } else {
    unawaited(Future<void>.delayed(const Duration(minutes: 10), () {
      html.Url.revokeObjectUrl(url);
    }));
  }
}
