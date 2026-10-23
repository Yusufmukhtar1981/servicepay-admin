@TestOn('browser')
library;

import 'dart:js' as js;
import 'dart:js_util' as js_util;

import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/customer_export_api.dart';
import 'package:servicepay_app/admin/customer_export_platform_web.dart'
    as platform;

Object _promise({bool reject = false}) {
  final Object promiseConstructor =
      js_util.getProperty<Object>(js_util.globalThis, 'Promise');
  return js_util.callConstructor<Object>(
    promiseConstructor,
    <Object>[
      js.allowInterop((dynamic resolve, dynamic rejectPromise) {
        if (reject) {
          rejectPromise(
            js_util.callConstructor<Object>(
              js_util.getProperty<Object>(js_util.globalThis, 'Error'),
              <Object>['Share cancelled'],
            ),
          );
        } else {
          resolve(null);
        }
      }),
    ],
  );
}

Object _mockNavigator({
  required bool canShare,
  void Function(Object data)? onShare,
  bool rejectShare = false,
}) =>
    js_util.jsify(<String, Object>{
      'canShare': js.allowInterop((Object data) => canShare),
      'share': js.allowInterop((Object data) {
        onShare?.call(data);
        return _promise(reject: rejectShare);
      }),
    })!;

void main() {
  tearDown(() => platform.setNavigatorForTesting(null));

  test('shares a browser File with expected name, MIME type, and content',
      () async {
    Object? sharedFile;
    platform.setNavigatorForTesting(
      _mockNavigator(
        canShare: true,
        onShare: (Object data) {
          final Object files = js_util.getProperty<Object>(data, 'files');
          sharedFile = js_util.getProperty<Object>(files, '0');
        },
      ),
    );
    const CustomerExportFile file = CustomerExportFile(
      bytes: <int>[70, 117, 108, 108, 32, 78, 97, 109, 101],
      filename: 'Servicepay-Customers.csv',
      format: 'csv',
    );

    expect(platform.supportsFileShare, isTrue);
    expect(await platform.shareFile(file), isTrue);
    expect(js_util.getProperty<String>(sharedFile!, 'name'),
        'Servicepay-Customers.csv');
    expect(js_util.getProperty<String>(sharedFile!, 'type'),
        'text/csv;charset=utf-8');
    expect(
      await js_util.promiseToFuture<String>(
        js_util.callMethod<Object>(sharedFile!, 'text', <Object>[]),
      ),
      'Full Name',
    );
  });

  test('returns unsupported when browser cannot share files', () async {
    bool shareWasCalled = false;
    platform.setNavigatorForTesting(
      _mockNavigator(
        canShare: false,
        onShare: (_) => shareWasCalled = true,
      ),
    );

    expect(platform.supportsFileShare, isTrue);
    expect(
      await platform.shareFile(
        const CustomerExportFile(
          bytes: <int>[1],
          filename: 'Servicepay-Customers.pdf',
          format: 'pdf',
        ),
      ),
      isFalse,
    );
    expect(shareWasCalled, isFalse);
  });

  test('propagates a cancelled share sheet without triggering a download',
      () async {
    bool shareWasCalled = false;
    platform.setNavigatorForTesting(
      _mockNavigator(
        canShare: true,
        rejectShare: true,
        onShare: (_) => shareWasCalled = true,
      ),
    );

    await expectLater(
      platform.shareFile(
        const CustomerExportFile(
          bytes: <int>[0x25, 0x50, 0x44, 0x46, 0x2D],
          filename: 'Servicepay-Customers.pdf',
          format: 'pdf',
        ),
      ),
      throwsA(anything),
    );
    expect(shareWasCalled, isTrue);
  });
}
