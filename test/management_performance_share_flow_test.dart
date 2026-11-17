import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/management_performance_share_flow.dart';

void main() {
  test('supported sharing invokes share and does not download', () async {
    final List<String> calls = <String>[];
    final Future<ManagementPerformanceShareResult> pending =
        runManagementPerformanceShare(
      supported: true,
      share: () async {
        calls.add('share');
        return true;
      },
      download: () async => calls.add('download'),
    );
    // The share callback is invoked before the asynchronous flow yields.
    expect(calls, <String>['share']);
    final result = await pending;
    expect(result, ManagementPerformanceShareResult.shared);
    expect(calls, <String>['share']);
  });

  test('unsupported sharing downloads for manual attachment', () async {
    final List<String> calls = <String>[];
    final result = await runManagementPerformanceShare(
      supported: false,
      share: () async => fail('must not share'),
      download: () async => calls.add('download'),
    );
    expect(result, ManagementPerformanceShareResult.downloadedForManualAttach);
    expect(calls, <String>['download']);
  });

  test('user cancellation is not treated as success or download fallback',
      () async {
    int downloads = 0;
    final result = await runManagementPerformanceShare(
      supported: true,
      share: () => Future<bool>.error(StateError('AbortError: user cancelled')),
      download: () async => downloads++,
    );
    expect(result, ManagementPerformanceShareResult.cancelled);
    expect(downloads, 0);
  });
}
