Future<void> openFinancialPdf(
  List<int> bytes,
  String filename,
  String contentType,
  Future<void> Function(List<int>, String, String) fallback,
) async {
  await fallback(bytes, filename, contentType);
}
