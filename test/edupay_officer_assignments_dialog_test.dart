import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/edupay_api.dart';
import 'package:servicepay_app/admin/edupay_control_center_screen.dart';

class _FakeEduPayApi extends EduPayApi {
  _FakeEduPayApi({
    this.eligibleFailure,
    this.eligibleCompleter,
  });

  final Object? eligibleFailure;
  final Completer<Map<String, dynamic>>? eligibleCompleter;
  Map<String, String>? savedAssignments;

  @override
  Future<Map<String, dynamic>> eligibleDutyUsers() async {
    if (eligibleCompleter != null) return eligibleCompleter!.future;
    if (eligibleFailure != null) throw eligibleFailure!;
    return _eligibleOfficers;
  }

  @override
  Future<Map<String, dynamic>> configureDuties(
    Map<String, String> assignments,
  ) async {
    savedAssignments = Map<String, String>.from(assignments);
    return <String, dynamic>{'success': true};
  }
}

const _eligibleOfficers = <String, dynamic>{
  'success': true,
  'users': <Map<String, dynamic>>[
    {
      'id': '000000000000000000000001',
      'name': 'Officer One',
      'role': 'HEAD_OFFICE',
      'status': 'ACTIVE',
    },
    {
      'id': '000000000000000000000002',
      'name': 'Officer Two',
      'role': 'HEAD_OFFICE',
      'status': 'ACTIVE',
    },
    {
      'id': '000000000000000000000003',
      'name': 'Officer Three',
      'role': 'HEAD_OFFICE',
      'status': 'ACTIVE',
    },
  ],
};

Widget _harness(_FakeEduPayApi api) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => EduPayOfficerAssignmentsDialog(
                api: api,
                currentHolders: const <String, dynamic>{},
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

Future<void> _choose(
  WidgetTester tester,
  String duty,
  String officer,
) async {
  await tester.tap(find.byKey(Key('edupay-officer-$duty')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(officer).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens immediately and shows officer loading on mobile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final completer = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      _harness(_FakeEduPayApi(eligibleCompleter: completer)),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(find.text('Configure officers'), findsOneWidget);
    expect(find.text('Loading active Head Office officers…'), findsOneWidget);

    completer.complete(_eligibleOfficers);
    await tester.pumpAndSettle();
    expect(find.text('Account Management Officer'), findsOneWidget);
    expect(find.text('Account Verification Officer'), findsOneWidget);
    expect(find.text('Settlement Processing Officer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejects duplicates and atomically saves three officers on desktop',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _FakeEduPayApi();
    await tester.pumpWidget(_harness(api));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await _choose(tester, 'account.manage', 'Officer One');
    await _choose(tester, 'account.verify', 'Officer One');
    expect(find.byKey(const Key('edupay-officer-duplicate')), findsOneWidget);
    expect(
      tester.widget<FilledButton>(
        find.byKey(const Key('save-edupay-officer-assignments')),
      ).onPressed,
      isNull,
    );

    await _choose(tester, 'account.verify', 'Officer Two');
    await _choose(tester, 'settlement.process', 'Officer Three');
    await tester.tap(
      find.byKey(const Key('save-edupay-officer-assignments')),
    );
    await tester.pumpAndSettle();

    expect(api.savedAssignments, <String, String>{
      'account.manage': '000000000000000000000001',
      'account.verify': '000000000000000000000002',
      'settlement.process': '000000000000000000000003',
    });
    expect(find.text('Configure officers'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows eligible-officer API errors instead of blocking the dialog',
      (tester) async {
    await tester.pumpWidget(
      _harness(_FakeEduPayApi(
        eligibleFailure: Exception('Permission denied for duty configuration.'),
      )),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Configure officers'), findsOneWidget);
    expect(
      find.text('Permission denied for duty configuration.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });
}