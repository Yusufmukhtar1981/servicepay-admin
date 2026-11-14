import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> downloadBusinessNetworkCsv(String csv, String filename) async {
  final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final savedPath = await FilePicker.platform.saveFile(
    dialogTitle: 'Save Business Network report',
    fileName: safeName.isEmpty ? 'business-network.csv' : safeName,
    type: FileType.custom,
    allowedExtensions: const <String>['csv'],
    bytes: Uint8List.fromList(utf8.encode(csv)),
  );
  return savedPath != null;
}

Future<bool> printBusinessNetworkReport(
  String csv, {
  required String title,
}) async =>
    false;
