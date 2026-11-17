import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepay_app/admin/management_performance_dates.dart';

void main() {
  test('selected CUSTOM dates stay inclusive Lagos calendar days', () {
    final DateTimeRange selected = DateTimeRange(
      start: DateTime(2026, 6, 4),
      end: DateTime(2026, 6, 17),
    );
    expect(
      managementPerformanceDateParams(
        period: 'CUSTOM',
        lagosNow: DateTime(2026, 6, 18, 1),
        customRange: selected,
      ),
      ('2026-06-04', '2026-06-17'),
    );
  });

  test('calendar presets pass inclusive Lagos boundaries', () {
    expect(
      managementPerformanceDateParams(
        period: 'LAST_WEEK',
        lagosNow: DateTime(2026, 6, 17),
      ),
      ('2026-06-08', '2026-06-14'),
    );
    expect(
      managementPerformanceDateParams(
        period: 'LAST_30_DAYS',
        lagosNow: DateTime(2026, 6, 17),
      ),
      ('2026-05-19', '2026-06-17'),
    );
  });
}
