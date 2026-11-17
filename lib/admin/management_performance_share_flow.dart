enum ManagementPerformanceShareResult {
  shared,
  downloadedForManualAttach,
  cancelled,
}

/// The PDF must already be prepared before entering this flow. [share] is
/// invoked synchronously before the first await to retain browser activation.
Future<ManagementPerformanceShareResult> runManagementPerformanceShare({
  required bool supported,
  required Future<bool> Function() share,
  required Future<void> Function() download,
}) async {
  if (!supported) {
    await download();
    return ManagementPerformanceShareResult.downloadedForManualAttach;
  }
  try {
    final Future<bool> shareAttempt = share();
    if (await shareAttempt) return ManagementPerformanceShareResult.shared;
    await download();
    return ManagementPerformanceShareResult.downloadedForManualAttach;
  } catch (error) {
    final String message = error.toString().toLowerCase();
    if (message.contains('abort') || message.contains('cancel')) {
      return ManagementPerformanceShareResult.cancelled;
    }
    rethrow;
  }
}
