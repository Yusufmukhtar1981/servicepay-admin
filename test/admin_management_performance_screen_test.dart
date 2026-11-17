import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/admin_management_performance_api.dart';
import 'package:servicepay_app/admin/admin_management_performance_screen.dart';
import 'package:servicepay_app/admin/admin_permissions.dart';
import 'package:servicepay_app/admin/management_performance_export_panel.dart';

class _PerformanceApi extends AdminManagementPerformanceApi {
  _PerformanceApi() : super(baseUrl: 'https://unused.test/api');

  final List<String> reportManagers = <String>[];
  final List<String> reportPeriods = <String>[];
  String? lastRole;

  @override
  Future<Map<String, dynamic>> managers({
    required String role,
    String search = '',
    int page = 1,
    int limit = 25,
  }) async {
    lastRole = role;
    return <String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            '_id': 'm1',
            'fullName': 'Amina Manager With A Long Name',
            'role': role,
            'status': 'SUSPENDED',
            'state': 'Lagos',
          },
          <String, dynamic>{
            '_id': 'm2',
            'fullName': 'Bola Manager',
            'role': role,
            'status': 'ACTIVE',
            'zone': 'West',
          },
        ],
        'total': 2,
        'totalPages': 1,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> report({
    required String managerId,
    required String period,
    required String from,
    required String to,
  }) async {
    reportManagers.add(managerId);
    reportPeriods.add(period);
    return <String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'manager': <String, dynamic>{
          '_id': managerId,
          'fullName': managerId == 'm1'
              ? 'Amina Manager With A Long Name'
              : 'Bola Manager',
          'roleLabel': 'Aggregator',
          'status': 'ACTIVE',
        },
        'overview': <String, dynamic>{
          'period': <String, dynamic>{
            'from': '${from}T00:00:00.000Z',
            'to': DateTime.parse(to)
                .add(const Duration(days: 1))
                .toIso8601String(),
          },
          'kpis': <String, dynamic>{
            'totalCustomers': 14,
            'newCustomers': 2,
            'totalTransactions': 5,
            'ownRecordedCommission': 120.75,
          },
        },
        'weekly': <dynamic>[
          <String, dynamic>{
            'at': from,
            'transactions': 3,
            'successful': 2,
            'successfulValue': 450,
          },
        ],
        'monthly': <dynamic>[],
        'definitions': <String, dynamic>{
          'legacy': 'Older records may lack verified attribution.'
        },
      },
    };
  }

  @override
  Future<AdminManagementPerformanceFile> export({
    required String managerId,
    required String period,
    required String from,
    required String to,
    required String format,
  }) async =>
      AdminManagementPerformanceFile(
        bytes: <int>[1, 2, 3],
        format: format,
        contentType: format == 'pdf'
            ? 'application/pdf'
            : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
}

void main() {
  testWidgets('manager selection and period changes reload real report data',
      (WidgetTester tester) async {
    final _PerformanceApi api = _PerformanceApi();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminManagementPerformanceScreen(
          initialAccess: const AdminAccess(
            role: 'HEAD_OFFICE',
            permissions: <String>{},
          ),
          api: api,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Management Performance'), findsOneWidget);
    expect(find.text('Amina Manager With A Long Name'), findsWidgets);
    expect(find.textContaining('SUSPENDED'), findsWidgets);
    expect(api.reportManagers.first, 'm1');

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('State Manager').last);
    await tester.pumpAndSettle();
    expect(api.lastRole, 'STATE_MANAGER');

    await tester.tap(find.text('Bola Manager').first);
    await tester.pumpAndSettle();
    expect(api.reportManagers.last, 'm2');

    await tester.tap(find.text('This month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();
    expect(api.reportPeriods.last, 'TODAY');
    expect(find.textContaining('Gross transaction value'), findsOneWidget);
    expect(find.textContaining('Legacy attribution'), findsOneWidget);
  });

  testWidgets('unauthorized roles do not call the report API', (tester) async {
    final _PerformanceApi api = _PerformanceApi();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminManagementPerformanceScreen(
          initialAccess: const AdminAccess(
            role: 'OPERATIONS_MANAGER',
            permissions: <String>{'*', AdminPermissions.usersView},
          ),
          api: api,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('requires Head Office'), findsOneWidget);
    expect(api.reportManagers, isEmpty);
    expect(api.lastRole, isNull);
  });

  for (final Size size in <Size>[const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('performance layout fits ${size.width}px viewport',
        (WidgetTester tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdminManagementPerformanceScreen(
            initialAccess: const AdminAccess(
              role: 'HEAD_OFFICE',
              permissions: <String>{AdminPermissions.hierarchyManage},
            ),
            api: _PerformanceApi(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Customer assignments'), findsOneWidget);
    });
  }

  testWidgets('prepared export disappears as soon as manager selection changes',
      (WidgetTester tester) async {
    final _PerformanceApi api = _PerformanceApi();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ManagementPerformanceExportPanel(
          api: api,
          managerId: 'm1',
          period: 'TODAY',
          from: '2026-11-17',
          to: '2026-11-17',
          whatsAppSummary: 'Safe local summary',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prepare PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Download PDF'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ManagementPerformanceExportPanel(
        api: api,
        managerId: 'm2',
        period: 'TODAY',
        from: '2026-11-17',
        to: '2026-11-17',
        whatsAppSummary: 'Another safe local summary',
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Download PDF'), findsNothing);
  });
}
