// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class PrivateAssetPrintTarget {
  const PrivateAssetPrintTarget(this.window);

  final html.WindowBase? window;
}

PrivateAssetPrintTarget? openPrivateAssetPrintTarget() =>
    PrivateAssetPrintTarget(html.window.open('about:blank', '_blank'));

Future<void> printPrivateAsset(
  PrivateAssetPrintTarget? target,
  Uint8List bytes,
  String mime,
) async {
  final html.WindowBase? window = target?.window;
  if (window == null) throw StateError('The receipt window was blocked.');
  final String url =
      html.Url.createObjectUrlFromBlob(html.Blob(<Object>[bytes], mime));
  window.location.href = url;
  Timer(const Duration(minutes: 2), () => html.Url.revokeObjectUrl(url));
}