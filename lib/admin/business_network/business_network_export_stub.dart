Future<bool> downloadBusinessNetworkCsv(String csv, String filename) async {
  throw UnsupportedError(
    'CSV download is unavailable on this platform.',
  );
}

Future<bool> printBusinessNetworkReport(
  String csv, {
  required String title,
}) async =>
    false;
