import 'customer_export_api.dart';

bool get supportsFileShare => false;
bool get supportsPrintPopup => false;
Object? openPrintTarget() => null;
void closePrintTarget(Object? target) {}
Future<bool> shareFile(CustomerExportFile file) async => false;
Future<void> downloadFile(CustomerExportFile file) async {}
Future<void> deliverToPrintTarget(
    Object? target, CustomerExportFile file) async {
  throw UnsupportedError('Printing is available in a supported browser.');
}
