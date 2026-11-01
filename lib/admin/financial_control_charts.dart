import 'dart:math' as math;

import 'package:flutter/material.dart';

const Color _chartGreen = Color(0xff167461);
const Color _chartTeal = Color(0xff3c9c91);
const Color _chartGrid = Color(0xffe5ece8);

class FinancialTrendChart extends StatelessWidget {
  const FinancialTrendChart({
    super.key,
    required this.points,
    required this.currency,
    this.height = 220,
  });

  final List<dynamic> points;
  final String currency;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bool partial =
        points.whereType<Map>().any((Map point) => point['partial'] == true);
    final List<_ChartPoint> values = points
        .whereType<Map>()
        .map((Map row) => _ChartPoint(
              row['date']?.toString() ?? '',
              _number(row['revenue']),
            ))
        .toList();
    if (values.isEmpty ||
        values.every((_ChartPoint point) => point.value == null)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (partial) const _PartialRevenueNotice(),
          const _NoChartData(),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (partial) const _PartialRevenueNotice(),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(values),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(currency,
                      style: const TextStyle(
                          color: Color(0xff73847e),
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(values.first.date,
                          style: const TextStyle(
                              color: Color(0xff73847e), fontSize: 10)),
                      Text(values.last.date,
                          style: const TextStyle(
                              color: Color(0xff73847e), fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class FinancialCategoryChart extends StatelessWidget {
  const FinancialCategoryChart({
    super.key,
    required this.rows,
    required this.nameKey,
    required this.valueKey,
    required this.currency,
  });

  final List<dynamic> rows;
  final String nameKey;
  final String valueKey;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final List<_ChartPoint> values = rows
        .whereType<Map>()
        .map((Map row) => _ChartPoint(
              row[nameKey]?.toString() ?? 'Unknown',
              _number(row[valueKey] ??
                  (row['totals'] is Map
                      ? (row['totals'] as Map)[valueKey]
                      : null)),
            ))
        .toList();
    if (values.isEmpty ||
        values.every((_ChartPoint point) => point.value == null)) {
      return const _NoChartData();
    }
    return Column(
      children: values.map((_ChartPoint point) {
        final double? value = point.value;
        final double maximum = values
            .map((_ChartPoint item) => item.value)
            .whereType<double>()
            .fold<double>(0, (double a, double b) => math.max(a, b).toDouble());
        final double fraction = value == null || maximum == 0
            ? 0
            : (value / maximum).clamp(0, 1).toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 112,
                child: Text(point.date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xff52665f), fontSize: 12)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: value == null ? 0 : fraction,
                    minHeight: 9,
                    backgroundColor: const Color(0xffe9efeb),
                    color: _chartGreen,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: Text(
                  value == null
                      ? 'DATA UNAVAILABLE'
                      : '$currency ${_compact(value)}',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xff344e45),
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _NoChartData extends StatelessWidget {
  const _NoChartData();
  @override
  Widget build(BuildContext context) => Container(
        height: 145,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xfff3f7f4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'No verified chart values for this period',
          style: TextStyle(color: Color(0xff71847c), fontSize: 12),
        ),
      );
}

class _PartialRevenueNotice extends StatelessWidget {
  const _PartialRevenueNotice();
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xfffff4de),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xffead5a9)),
        ),
        child: const Text(
          'Partial source coverage · plotted revenue is the known subtotal only.',
          style: TextStyle(
              color: Color(0xff765921),
              fontSize: 10,
              fontWeight: FontWeight.w700),
        ),
      );
}

class _ChartPoint {
  const _ChartPoint(this.date, this.value);
  final String date;
  final double? value;
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.points);
  final List<_ChartPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    const double left = 4;
    const double right = 4;
    const double top = 16;
    const double bottom = 24;
    final double width = size.width - left - right;
    final double height = size.height - top - bottom;
    final Paint grid = Paint()
      ..color = _chartGrid
      ..strokeWidth = 1;
    for (int index = 0; index < 4; index++) {
      final double y = top + height * index / 3;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
    }
    final List<double> known = points
        .map((_ChartPoint point) => point.value)
        .whereType<double>()
        .toList();
    if (known.isEmpty) return;
    final double min = math.min(0, known.reduce(math.min));
    final double max = known.reduce(math.max);
    final double range = (max - min).abs() < 0.000001 ? 1 : max - min;
    final List<Offset?> coords = <Offset?>[];
    for (int index = 0; index < points.length; index++) {
      final double? value = points[index].value;
      if (value == null) {
        coords.add(null);
      } else {
        final double x = points.length < 2
            ? left + width / 2
            : left + width * index / (points.length - 1);
        final double y = top + height * (1 - (value - min) / range);
        coords.add(Offset(x, y));
      }
    }
    final Paint line = Paint()
      ..color = _chartGreen
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final Paint dot = Paint()..color = _chartTeal;
    Offset? previous;
    for (final Offset? point in coords) {
      if (point == null) {
        previous = null;
        continue;
      }
      if (previous != null) canvas.drawLine(previous, point, line);
      canvas.drawCircle(point, 3.5, dot);
      previous = point;
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      !identical(points, oldDelegate.points);
}

double? _number(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

String _compact(double value) {
  if (value.abs() >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(1)}B';
  }
  if (value.abs() >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value.abs() >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
}
