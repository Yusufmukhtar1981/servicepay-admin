@TestOn('browser')
library;

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as util;

import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/admin_management_performance_api.dart';
import 'package:servicepay_app/admin/management_performance_share_web.dart';
import 'package:servicepay_app/admin/management_performance_share_flow.dart';

void main() {
  tearDown(() => setManagementPerformanceNavigatorForTesting(null));
  for (final format in ['pdf', 'xlsx']) {
    test('$format sharing constructs an original File before awaiting',
        () async {
      final navigator = util.newObject<Object>();
      var shared = 0;
      util.setProperty(navigator, 'canShare', js.allowInterop((Object data) {
        final files = util.getProperty<Object>(data, 'files');
        final file = util.getProperty<Object>(files, 0);
        expect(util.getProperty<String>(file, 'name'),
            'servicepay-management-performance.$format');
        expect(util.getProperty<num>(file, 'size'), 4);
        return true;
      }));
      util.setProperty(navigator, 'share', js.allowInterop((Object data) {
        shared++;
        return util.callMethod<Object>(
            util.getProperty<Object>(html.window, 'Promise'), 'resolve', []);
      }));
      setManagementPerformanceNavigatorForTesting(navigator);
      final pending = shareManagementPerformanceFile(AdminManagementPerformanceFile(
          bytes: const [1, 2, 3, 4],
          contentType: format == 'pdf'
              ? 'application/pdf'
              : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          format: format));
      expect(shared, 1, reason: 'Do not lose the fresh browser user gesture.');
      expect(await pending, true);
    });
  }
  test('browser refusing File sharing downloads for manual WhatsApp attachment',
      () async {
    final navigator = util.newObject<Object>();
    util.setProperty(
        navigator, 'canShare', js.allowInterop((Object data) => false));
    util.setProperty(navigator, 'share', js.allowInterop((Object data) {
      fail('Native share must not run for an unsupported file.');
    }));
    setManagementPerformanceNavigatorForTesting(navigator);
    var downloads = 0;
    final result = await runManagementPerformanceShare(
      supported: managementPerformanceFileShareSupported,
      share: () => shareManagementPerformanceFile(
          const AdminManagementPerformanceFile(
              bytes: [1], contentType: 'application/pdf', format: 'pdf')),
      download: () async {
        downloads++;
      },
    );
    expect(result, ManagementPerformanceShareResult.downloadedForManualAttach);
    expect(downloads, 1);
  });
  test('browser cancellation neither sends a report nor starts a download',
      () async {
    final navigator = util.newObject<Object>();
    util.setProperty(
        navigator, 'canShare', js.allowInterop((Object data) => true));
    util.setProperty(navigator, 'share', js.allowInterop((Object data) {
      final error = util.callConstructor<Object>(
          util.getProperty<Object>(html.window, 'DOMException'),
          ['cancelled', 'AbortError']);
      return util.callMethod<Object>(
          util.getProperty<Object>(html.window, 'Promise'), 'reject', [error]);
    }));
    setManagementPerformanceNavigatorForTesting(navigator);
    final result = await runManagementPerformanceShare(
      supported: true,
      share: () => shareManagementPerformanceFile(
          const AdminManagementPerformanceFile(
              bytes: [1], contentType: 'application/pdf', format: 'pdf')),
      download: () async => fail('Cancellation must not download a report.'),
    );
    expect(result, ManagementPerformanceShareResult.cancelled);
  });
}
