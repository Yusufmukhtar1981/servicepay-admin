Future<void> downloadRevenueFile(
  List<int> bytes,
  String filename,
  String contentType,
) async {
  // Native and VM tests can inject a download adapter. The browser implementation
  // is selected conditionally in revenue_account_api.dart.
  throw UnsupportedError('File downloads are available in the Admin browser.');
}
