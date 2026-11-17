import 'package:flutter/material.dart';

/// API date parameters are calendar dates in Africa/Lagos; callers supply the
/// current Lagos wall time and the selected inclusive calendar range.
(String, String) managementPerformanceDateParams({
  required String period,
  required DateTime lagosNow,
  DateTimeRange? customRange,
}) {
  String date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
  final DateTime today = DateTime(lagosNow.year, lagosNow.month, lagosNow.day);
  if (period == 'CUSTOM' && customRange != null) {
    return (date(customRange.start), date(customRange.end));
  }
  late DateTime from;
  late DateTime to;
  switch (period) {
    case 'YESTERDAY':
      from = today.subtract(const Duration(days: 1));
      to = from;
      break;
    case 'THIS_WEEK':
      from = today.subtract(Duration(days: today.weekday - 1));
      to = today;
      break;
    case 'LAST_WEEK':
      to = today.subtract(Duration(days: today.weekday));
      from = to.subtract(const Duration(days: 6));
      break;
    case 'LAST_MONTH':
      to = DateTime(today.year, today.month, 1)
          .subtract(const Duration(days: 1));
      from = DateTime(to.year, to.month, 1);
      break;
    case 'LAST_30_DAYS':
      from = today.subtract(const Duration(days: 29));
      to = today;
      break;
    case 'THIS_MONTH':
      from = DateTime(today.year, today.month, 1);
      to = today;
      break;
    default:
      from = today;
      to = today;
      break;
  }
  return (date(from), date(to));
}

DateTime managementPerformanceLagosNow() =>
    DateTime.now().toUtc().add(const Duration(hours: 1));
