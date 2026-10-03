import 'dart:typed_data';

class PrivateAssetPrintTarget {
  const PrivateAssetPrintTarget();
}

PrivateAssetPrintTarget? openPrivateAssetPrintTarget() => null;

Future<void> printPrivateAsset(
  PrivateAssetPrintTarget? target,
  Uint8List bytes,
  String mime,
) async {
  throw UnsupportedError('Receipt printing is supported in a web browser.');
}