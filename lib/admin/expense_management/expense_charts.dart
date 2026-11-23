import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'expense_common.dart';

const Color _bar = Color(0xff61a9bd);

String _compactNaira(double v) {
  if (v >= 1e9) return 'NGN ${(v / 1e9).toStringAsFixed(1)}B';
  if (v >= 1e6) return 'NGN ${(v / 1e6).toStringAsFixed(1)}M';
  if (v >= 1e3) return 'NGN ${(v / 1e3).toStringAsFixed(1)}K';
  return 'NGN ${v.toStringAsFixed(0)}';
}

/// Ranked horizontal bars of genuine returned amountMinor values (top 8,
/// truncation disclosed). Zero-based scale bounded by the actual maximum.
class ExpenseBreakdownChart extends StatelessWidget {
  const ExpenseBreakdownChart({super.key, required this.rows, required this.emptyLabel});
  final List<dynamic> rows;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> items = rows
        .map(asMap)
        .where((Map<String, dynamic> r) => asInt(r['amountMinor']) != null)
        .toList()
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
          asInt(b['amountMinor'])!.compareTo(asInt(a['amountMinor'])!));
    if (items.isEmpty) {
      return ExpenseNotice(emptyLabel);
    }
    final List<Map<String, dynamic>> shown = items.take(8).toList();
    final double maxValue = shown
        .map((Map<String, dynamic> r) => asInt(r['amountMinor'])! / 100)
        .fold<double>(0, math.max);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      for (final Map<String, dynamic> r in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Semantics(
            label: '${text(r['label'], fallback: 'Unlabelled')}: ${money(r['amountMinor'])}, ${count(r['count'])} expenses',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Expanded(
                  child: Text(text(r['label'], fallback: 'Unlabelled'),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: expInk, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('${money(r['amountMinor'])} · ${count(r['count'])}',
                      textAlign: TextAlign.right,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: expMuted, fontSize: 11.5, fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
                ),
              ]),
              const SizedBox(height: 4),
              LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
                final double v = asInt(r['amountMinor'])! / 100;
                final double ratio = maxValue <= 0 ? 0 : (v / maxValue).clamp(0, 1);
                return Stack(children: <Widget>[
                  Container(height: 9, width: c.maxWidth, decoration: BoxDecoration(color: const Color(0xffe4ece7), borderRadius: BorderRadius.circular(3))),
                  Container(height: 9, width: c.maxWidth * ratio, decoration: BoxDecoration(color: _bar, borderRadius: BorderRadius.circular(3))),
                ]);
              }),
            ]),
          ),
        ),
      if (items.length > shown.length)
        Text('Top ${shown.length} of ${items.length} shown, ranked by amount.',
            style: const TextStyle(color: expMuted, fontSize: 11)),
    ]);
  }
}

/// Daily column chart, zero-based, fixed height.
class ExpenseDailyChart extends StatelessWidget {
  const ExpenseDailyChart({super.key, required this.points});
  final List<dynamic> points;

  @override
  Widget build(BuildContext context) {
    final List<MapEntry<String, double>> values = points
        .map(asMap)
        .where((Map<String, dynamic> p) => asInt(p['amountMinor']) != null && text(p['date']).isNotEmpty)
        .map((Map<String, dynamic> p) => MapEntry<String, double>(text(p['date']), asInt(p['amountMinor'])! / 100))
        .toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) => a.key.compareTo(b.key));
    if (values.isEmpty) {
      return const ExpenseNotice('No daily recorded expense values were returned for this period.');
    }
    final double maxV = values.map((MapEntry<String, double> e) => e.value).fold<double>(0, math.max);
    return Semantics(
      label: 'Daily recorded expenses chart, ${values.length} days, highest ${_compactNaira(maxV)}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('Peak ${_compactNaira(maxV)}', style: const TextStyle(color: expMuted, fontSize: 11)),
        const SizedBox(height: 6),
        SizedBox(
          height: 160,
          width: double.infinity,
          child: CustomPaint(painter: _ColumnPainter(values.map((MapEntry<String, double> e) => e.value).toList(), maxV)),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
          Text(values.first.key, style: const TextStyle(color: expMuted, fontSize: 11)),
          Text(values.last.key, style: const TextStyle(color: expMuted, fontSize: 11)),
        ]),
      ]),
    );
  }
}

class _ColumnPainter extends CustomPainter {
  _ColumnPainter(this.values, this.maxValue);
  final List<double> values;
  final double maxValue;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint axis = Paint()
      ..color = expLine
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), axis);
    if (maxValue <= 0 || values.isEmpty) return;
    final double slot = size.width / values.length;
    final double w = math.max(1, math.min(22, slot * 0.7));
    final Paint p = Paint()..color = _bar;
    for (int i = 0; i < values.length; i++) {
      final double h = (values[i] / maxValue).clamp(0, 1) * (size.height - 4);
      final double x = slot * i + (slot - w) / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(x, size.height - h, w, h), topLeft: const Radius.circular(2), topRight: const Radius.circular(2)),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ColumnPainter old) => old.values != values || old.maxValue != maxValue;
}
