// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'admin_management_performance_api.dart';

Object? _navigatorForTesting;
Object get _navigator => _navigatorForTesting ?? html.window.navigator;

bool get managementPerformanceFileShareSupported {
  final Object navigator = _navigator;
  return js_util.hasProperty(navigator, 'share') &&
      js_util.hasProperty(navigator, 'canShare');
}

void setManagementPerformanceNavigatorForTesting(Object? navigator) {
  _navigatorForTesting = navigator;
}

Future<bool> shareManagementPerformanceFile(
    AdminManagementPerformanceFile file) async {
  final html.Blob blob =
      html.Blob(<Object>[Uint8List.fromList(file.bytes)], file.contentType);
  final Object fileObject = js_util.callConstructor(
    js_util.getProperty<Object>(html.window, 'File'),
    <Object>[
      <Object>[blob],
      file.filename,
      js_util.jsify(<String, String>{'type': file.contentType}),
    ],
  );
  final Object data = js_util.jsify(<String, Object>{
    'files': <Object>[fileObject],
  });
  final Object navigator = _navigator;
  if (!js_util.callMethod<bool>(navigator, 'canShare', <Object>[data])) {
    return false;
  }
  // Invoke share before the first await so a fresh click keeps user activation.
  final Object promise =
      js_util.callMethod<Object>(navigator, 'share', <Object>[data]);
  await js_util.promiseToFuture<void>(promise);
  return true;
}
