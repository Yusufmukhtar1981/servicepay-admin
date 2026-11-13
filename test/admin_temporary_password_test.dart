import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servicepay_app/admin/admin_change_password_screen.dart';
import 'package:servicepay_app/admin/admin_session_gate.dart';
import 'package:servicepay_app/admin/login_screen.dart';
import 'package:servicepay_app/admin/main_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> enterValidValues(WidgetTester tester) async {
    await tester.enterText(
        find.byKey(const Key('admin-current-password')), 'Temporary123!');
    await tester.enterText(
        find.byKey(const Key('admin-new-password')), 'Replacement123!');
    await tester.enterText(
        find.byKey(const Key('admin-confirm-password')), 'Replacement123!');
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const Key('admin-change-password-submit')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin-change-password-submit')));
  }

  testWidgets('login routes temporary staff directly to the password gate',
      (WidgetTester tester) async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.url.path, '/api/auth/login');
      return http.Response(
        jsonEncode(<String, Object>{
          'success': true,
          'token': 'temporary-admin-token',
          'user': <String, Object>{
            '_id': 'staff-1',
            'role': 'STAFF',
            'status': 'ACTIVE',
            'isStaff': true,
            'mustChangePassword': true,
            'permissions': <String>['operations.workspace.view'],
          },
        }),
        200,
      );
    });
    await tester.pumpWidget(
      MaterialApp(home: AdminLoginScreen(client: client)),
    );
    await tester.enterText(find.byType(TextField).at(0), 'staff@example.ng');
    await tester.enterText(find.byType(TextField).at(1), 'Temporary123!');
    await tester.tap(find.text('Sign in as Admin'));
    await tester.pumpAndSettle();

    expect(find.byType(AdminChangePasswordScreen), findsOneWidget);
    expect(find.text('Set your own password'), findsOneWidget);
    expect(find.byType(AdminMainNavigation), findsNothing);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('auth_token'), 'temporary-admin-token');
    expect(preferences.getBool('must_change_password'), isTrue);
  });

  testWidgets('reload gate shows password form before any staff dashboard',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'temporary-admin-token',
      'must_change_password': true,
    });
    final client = MockClient((request) async => http.Response(
        jsonEncode({'success': false, 'code': 'PASSWORD_CHANGE_REQUIRED'}),
        403));
    await tester
        .pumpWidget(MaterialApp(home: AdminSessionGate(client: client)));
    await tester.pumpAndSettle();

    expect(find.byType(AdminChangePasswordScreen), findsOneWidget);
    expect(find.byType(AdminLoginScreen), findsNothing);
  });

  testWidgets('reload with missing temporary token returns safely to login',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'must_change_password': true,
    });
    await tester.pumpWidget(const MaterialApp(home: AdminSessionGate()));
    await tester.pumpAndSettle();

    expect(find.byType(AdminLoginScreen), findsOneWidget);
    expect(
        (await SharedPreferences.getInstance()).getBool('must_change_password'),
        isNull);
  });

  testWidgets('stale false flag is corrected from PASSWORD_CHANGE_REQUIRED',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'temporary-admin-token',
      'must_change_password': false,
      'user_role': 'STAFF',
    });
    final MockClient client = MockClient((http.Request request) async {
      expect(request.url.path, '/api/auth/profile');
      return http.Response(
        jsonEncode(<String, Object>{
          'success': false,
          'code': 'PASSWORD_CHANGE_REQUIRED',
          'message':
              'You must change your temporary password before continuing.',
        }),
        403,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AdminSessionGate(
          client: client,
          fallback: const Text('Protected staff workspace'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdminChangePasswordScreen), findsOneWidget);
    expect(find.text('Protected staff workspace'), findsNothing);
    expect(
        (await SharedPreferences.getInstance()).getBool('must_change_password'),
        isTrue);
  });

  testWidgets('weak and mismatched passwords do not call the API',
      (WidgetTester tester) async {
    var requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount++;
      return http.Response('{}', 500);
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'temporary-admin-token',
      'must_change_password': true,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AdminChangePasswordScreen(client: client),
      ),
    );
    await tester.enterText(
        find.byKey(const Key('admin-current-password')), 'Temporary123!');
    await tester.enterText(find.byKey(const Key('admin-new-password')), 'weak');
    await tester.enterText(
        find.byKey(const Key('admin-confirm-password')), 'different');
    await tapSubmit(tester);
    await tester.pump();

    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(requestCount, 0);
    await tester.enterText(
        find.byKey(const Key('admin-new-password')), 'Replacement123!');
    await tapSubmit(tester);
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(requestCount, 0);
  });

  testWidgets('wrong temporary password keeps user at the gate',
      (WidgetTester tester) async {
    final MockClient client =
        MockClient((http.Request request) async => http.Response(
              jsonEncode(<String, Object>{
                'success': false,
                'message': 'Current password is incorrect.',
              }),
              401,
            ));
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'temporary-admin-token',
      'must_change_password': true,
    });
    await tester.pumpWidget(
      MaterialApp(home: AdminChangePasswordScreen(client: client)),
    );
    await enterValidValues(tester);
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('Current password is incorrect.'), findsOneWidget);
    expect(find.byType(AdminChangePasswordScreen), findsOneWidget);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('auth_token'), 'temporary-admin-token');
    expect(preferences.getBool('must_change_password'), isTrue);
  });

  testWidgets('successful change persists replacement token and redirects',
      (WidgetTester tester) async {
    String? authorization;
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/auth/change-password');
      authorization = request.headers['authorization'];
      expect(jsonDecode(request.body), <String, String>{
        'currentPassword': 'Temporary123!',
        'newPassword': 'Replacement123!',
        'confirmPassword': 'Replacement123!',
      });
      return http.Response(
        jsonEncode(<String, Object>{
          'success': true,
          'message': 'Password changed successfully.',
          'token': 'replacement-admin-token',
        }),
        200,
      );
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'temporary-admin-token',
      'must_change_password': true,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AdminChangePasswordScreen(
          client: client,
          authenticatedHomeBuilder: (_) => const Text('Authorized workspace'),
        ),
      ),
    );
    await enterValidValues(tester);
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    expect(authorization, 'Bearer temporary-admin-token');
    expect(preferences.getString('auth_token'), 'replacement-admin-token');
    expect(preferences.getString('token'), 'replacement-admin-token');
    expect(preferences.getString('access_token'), 'replacement-admin-token');
    expect(preferences.getBool('must_change_password'), isFalse);
    expect(find.text('Authorized workspace'), findsOneWidget);
  });

  testWidgets('missing replacement token requires safe re-login',
      (WidgetTester tester) async {
    final MockClient client =
        MockClient((http.Request request) async => http.Response(
              jsonEncode(<String, Object>{
                'success': true,
                'message': 'Password changed successfully.',
              }),
              200,
            ));
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'temporary-admin-token',
      'must_change_password': true,
    });
    var reloginCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AdminChangePasswordScreen(
          client: client,
          onRelogin: () => reloginCalled = true,
        ),
      ),
    );
    await enterValidValues(tester);
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('refreshed session was not returned'),
        findsOneWidget);
    expect(find.byKey(const Key('admin-password-relogin')), findsOneWidget);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('auth_token'), isNull);
    expect(preferences.getBool('must_change_password'), isNull);
    await tester.ensureVisible(find.byKey(const Key('admin-password-relogin')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin-password-relogin')));
    expect(reloginCalled, isTrue);
  });

  for (final code in ['', 'TOKEN_REVOKED', 'TOKEN_EXPIRED']) {
    testWidgets('rejected temporary session offers re-login: $code',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_token': 'stale-token',
        'token': 'stale-token',
        'access_token': 'stale-token',
        'must_change_password': true,
      });
      final client = MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.headers['authorization'], 'Bearer stale-token');
        return http.Response(
            jsonEncode({
              'success': false,
              'code': code,
              'message': 'Invalid or expired token.',
            }),
            401);
      });
      var relogin = false;
      await tester.pumpWidget(MaterialApp(
          home: AdminChangePasswordScreen(
        client: client,
        onRelogin: () => relogin = true,
      )));
      await enterValidValues(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Sign in again using your latest'),
          findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      for (final key in ['auth_token', 'token', 'access_token']) {
        expect(prefs.getString(key), isNull);
      }
      expect(prefs.getBool('must_change_password'), isNull);
      await tester
          .ensureVisible(find.byKey(const Key('admin-password-relogin')));
      await tester.tap(find.byKey(const Key('admin-password-relogin')));
      expect(relogin, isTrue);
    });
  }

  testWidgets('cached temporary flag cannot authorize an invalid session',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'invalid-token',
      'must_change_password': true,
    });
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.path, '/api/auth/profile');
      return http.Response(
          '{"success":false,"message":"Invalid or expired token."}', 401);
    });
    await tester.pumpWidget(MaterialApp(
        home: AdminSessionGate(
      client: client,
      fallback: const Text('Privileged fallback'),
    )));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.byType(AdminLoginScreen), findsOneWidget);
    expect(find.byType(AdminChangePasswordScreen), findsNothing);
    expect(find.text('Privileged fallback'), findsNothing);
    expect((await SharedPreferences.getInstance()).getString('auth_token'),
        isNull);
  });

  testWidgets('unreachable verification blocks fallback and permits retry',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'valid-temporary',
      'must_change_password': true,
    });
    var calls = 0;
    final client = MockClient((request) async {
      if (++calls == 1) throw http.ClientException('offline');
      return http.Response(
          '{"success":false,"code":"PASSWORD_CHANGE_REQUIRED"}', 403);
    });
    await tester.pumpWidget(MaterialApp(
        home: AdminSessionGate(
      client: client,
      fallback: const Text('Privileged fallback'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Privileged fallback'), findsNothing);
    expect(find.byType(AdminChangePasswordScreen), findsNothing);
    expect((await SharedPreferences.getInstance()).getString('auth_token'),
        'valid-temporary');
    await tester.tap(find.text('Retry session verification'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminChangePasswordScreen), findsOneWidget);
  });

  testWidgets('server-confirmed completed setup clears a stale local flag',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token': 'current-token',
      'must_change_password': true,
    });
    final client = MockClient((request) async => http.Response(
        '{"success":true,"user":{"role":"STAFF","mustChangePassword":false}}',
        200));
    await tester.pumpWidget(MaterialApp(
        home: AdminSessionGate(
      client: client,
      fallback: const Text('Authorized fallback'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Authorized fallback'), findsOneWidget);
    expect(find.byType(AdminChangePasswordScreen), findsNothing);
    expect(
        (await SharedPreferences.getInstance()).getBool('must_change_password'),
        isNull);
  });

  testWidgets('password page fits a short mobile viewport and desktop',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 500);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 230);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      const MaterialApp(home: AdminChangePasswordScreen()),
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = const FakeViewPadding();
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.pump();
    expect(find.text('Set your own password'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
