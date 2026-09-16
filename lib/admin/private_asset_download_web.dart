// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> savePrivateAsset(Uint8List bytes, String filename, String mime) async {
  final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], mime));
  html.AnchorElement(href: url)
    ..download = filename
    ..target = '_blank'
    ..click();
  await Future<void>.delayed(const Duration(milliseconds: 100));
  html.Url.revokeObjectUrl(url);
}