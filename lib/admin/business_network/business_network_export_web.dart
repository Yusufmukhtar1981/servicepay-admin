// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import '../admin_control_center_download.dart';

Future<bool> downloadBusinessNetworkCsv(String csv, String filename) async {
  await downloadControlCenterCsv(csv, filename);
  return true;
}

String _escapePrintHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

Future<bool> printBusinessNetworkReport(
  String csv, {
  required String title,
}) async {
  final blob = html.Blob(
    <dynamic>[
      '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${_escapePrintHtml(title)}</title>
  <style>
    body { color: #18372a; font: 14px/1.5 sans-serif; margin: 32px; }
    h1 { border-bottom: 2px solid #126a43; padding-bottom: 10px; }
    pre { white-space: pre-wrap; overflow-wrap: anywhere; font: 11px/1.5 monospace; }
    @media print { body { margin: 15mm; } }
  </style>
</head>
<body>
  <h1>${_escapePrintHtml(title)}</h1>
  <pre>${_escapePrintHtml(csv)}</pre>
  <script>window.onload = function () { window.print(); };</script>
</body>
</html>
'''
    ],
    'text/html;charset=utf-8',
  );
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);
  final openedWindow = js_util.callMethod<Object?>(
    html.window,
    'open',
    <Object?>[objectUrl, '_blank'],
  );
  if (openedWindow == null ||
      js_util.getProperty<Object?>(openedWindow, 'closed') == true) {
    html.Url.revokeObjectUrl(objectUrl);
    return false;
  }
  await Future<void>.delayed(const Duration(seconds: 5));
  html.Url.revokeObjectUrl(objectUrl);
  return true;
}
