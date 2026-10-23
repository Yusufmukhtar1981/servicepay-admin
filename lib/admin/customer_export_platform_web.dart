import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'customer_export_api.dart';

bool get supportsFileShare {
  final Object navigator = _shareNavigator;
  return js_util.hasProperty(navigator, 'share') &&
      js_util.hasProperty(navigator, 'canShare');
}

Object? _navigatorForTesting;
Object get _shareNavigator => _navigatorForTesting ?? html.window.navigator;

/// Replaces the browser navigator in web adapter tests only.
void setNavigatorForTesting(Object? navigator) {
  _navigatorForTesting = navigator;
}

bool get supportsPrintPopup => true;

Object? openPrintTarget() => html.window.open('about:blank', '_blank');

void closePrintTarget(Object? target) {
  if (target is html.WindowBase) target.close();
}

html.Blob _blob(CustomerExportFile file) => html.Blob(
      <Object>[Uint8List.fromList(file.bytes)],
      file.format == 'pdf'
          ? 'application/pdf'
          : file.format == 'csv'
              ? 'text/csv;charset=utf-8'
              : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );

Future<bool> shareFile(CustomerExportFile file) async {
  final Object blob = _blob(file);
  final Object jsFile = js_util.callConstructor(
    js_util.getProperty<Object>(html.window, 'File'),
    <Object>[
      <Object>[blob],
      file.filename,
      js_util.jsify(
        <String, String>{'type': js_util.getProperty<String>(blob, 'type')},
      ),
    ],
  );
  final Object data = js_util.jsify(<String, Object>{
    'files': <Object>[jsFile]
  });
  final Object navigator = _shareNavigator;
  if (!js_util.callMethod<bool>(navigator, 'canShare', <Object>[data])) {
    return false;
  }
  await js_util.promiseToFuture<void>(
    js_util.callMethod<Object>(navigator, 'share', <Object>[data]),
  );
  return true;
}

Future<void> downloadFile(CustomerExportFile file) async {
  final String url = html.Url.createObjectUrlFromBlob(_blob(file));
  final html.AnchorElement anchor = html.AnchorElement(href: url)
    ..download = file.filename
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  // Keep the Blob alive through the browser's download handoff.
  Future<void>.delayed(const Duration(seconds: 2), () {
    html.Url.revokeObjectUrl(url);
  });
}

Future<void> deliverToPrintTarget(
    Object? target, CustomerExportFile file) async {
  if (target == null) {
    throw StateError('The print window was blocked. Allow pop-ups and retry.');
  }
  final String url = html.Url.createObjectUrlFromBlob(_blob(file));
  final html.WindowBase window = target as html.WindowBase;
  window.location.href = url;
  try {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    js_util.callMethod<void>(window, 'print', <Object>[]);
  } catch (_) {
    // The PDF viewer's own print control remains available.
  }
  // Keep it available while the PDF viewer opens; do not revoke immediately.
  Future<void>.delayed(const Duration(minutes: 2), () {
    html.Url.revokeObjectUrl(url);
  });
}
