bool get controlCenterDownloadSupported => false;

Future<void> downloadControlCenterCsv(String csv, String filename) async {
  throw UnsupportedError('CSV download is supported in a web browser only.');
}

Future<void> downloadControlCenterBytes(
  List<int> bytes,
  String contentType,
  String filename,
) async {
  throw UnsupportedError('File download is supported in a web browser only.');
}
