import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/main_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _MountProbeState.mounts.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'user_role': 'STAFF',
      'staff_permissions': <String>[
        'dashboard.view',
        'operations.workspace.view',
      ],
    });
  });

  testWidgets(
      'staff destinations mount on visit and keep state without mounting protected pages early',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminMainNavigation(
          pageOverrides: <String, Widget>{
            'Dashboard': const _MountProbe(label: 'Dashboard'),
            'Operations overview': const _MountProbe(label: 'Operations'),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_MountProbeState.mounts['Dashboard'] ?? 0, 0);
    expect(_MountProbeState.mounts['Operations'], 1);
    expect(find.byKey(const ValueKey<String>('dashboard-probe')), findsNothing);
    expect(find.byKey(const ValueKey<String>('operations-probe')), findsOneWidget);

    await tester.tap(find.text('Dashboard').last);
    await tester.pumpAndSettle();
    expect(_MountProbeState.mounts['Dashboard'], 1);
    expect(find.text('Dashboard state: 0'), findsOneWidget);
    await tester.tap(find.text('Advance Dashboard'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Operations overview').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dashboard').last);
    await tester.pumpAndSettle();

    expect(_MountProbeState.mounts['Dashboard'], 1);
    expect(find.text('Dashboard state: 1'), findsOneWidget);
  });
}

class _MountProbe extends StatefulWidget {
  const _MountProbe({required this.label});

  final String label;

  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  static final Map<String, int> mounts = <String, int>{};
  int state = 0;

  @override
  void initState() {
    super.initState();
    mounts.update(widget.label, (int count) => count + 1, ifAbsent: () => 1);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: ValueKey<String>(
          '${widget.label.toLowerCase()}-probe',
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('${widget.label} state: $state'),
              FilledButton(
                onPressed: () => setState(() => state++),
                child: Text('Advance ${widget.label}'),
              ),
            ],
          ),
        ),
      );
}
