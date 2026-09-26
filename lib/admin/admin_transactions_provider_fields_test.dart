// ignore_for_file: depend_on_referenced_packages, invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';

import 'admin_transactions_screen.dart';

void main() {
  test('provider details render only exact transaction response fields', () {
    final List<MapEntry<String, String>> fields =
        transactionProviderDetailFields(<String, dynamic>{
      'provider': 'NELLOBYTES',
      'providerReference': 'provider-ref-17',
      'providerStatus': 'SUCCESS',
      'status': 'SUCCESSFUL',
      'fallbackProvider': 'BACKUP_A',
      'reconciliationStatus': 'MATCHED',
      'providerResponse': <String, dynamic>{
        'provider': 'MUST_NOT_BE_INFERRED',
        'reference': 'DO_NOT_ALIAS',
      },
      'providerName': 'DO_NOT_ALIAS',
      'fallback': 'DO_NOT_ALIAS',
    });

    expect(
      fields.map((MapEntry<String, String> field) => '${field.key}=${field.value}').toList(),
      <String>[
        'Provider=NELLOBYTES',
        'Provider Reference=provider-ref-17',
        'Provider Status=SUCCESS',
        'ServicePay Status=SUCCESSFUL',
        'Fallback Provider=BACKUP_A',
        'Reconciliation Status=MATCHED',
      ],
    );
  });

  test('omits absent, null, or blank provider fields without defaults', () {
    final List<MapEntry<String, String>> fields =
        transactionProviderDetailFields(<String, dynamic>{
      'provider': null,
      'providerReference': '  ',
      'providerResponse': <String, dynamic>{'provider': 'nested-only'},
      'status': 'FAILED',
    });

    expect(
      fields.map((MapEntry<String, String> field) => '${field.key}=${field.value}').toList(),
      <String>['ServicePay Status=FAILED'],
    );
  });
}