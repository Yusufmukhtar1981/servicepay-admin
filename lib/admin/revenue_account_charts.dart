part of 'revenue_account_screen.dart';

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});
  final List<dynamic> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const _EmptyState(
          title: 'Trend data is not available',
          message: 'No trend observations were returned for this period.');
    }
    final String chartDetail = points.whereType<Map>().map((Map row) {
      final String date = '${row['date'] ?? 'Date unavailable'}';
      String value(String key) {
        final dynamic raw = row[key];
        return raw is num ? '₦${raw.toStringAsFixed(2)}' : 'unresolved';
      }

      return '$date: revenue ${value('grossRevenue')}, provider costs ${value('providerCosts')}, known-cost profit ${value('netProfit')}';
    }).join('; ');
    return Column(children: <Widget>[
      const SizedBox(height: 8),
      Expanded(
        child: Semantics(
          container: true,
          label:
              'Daily financial trend, values in Nigerian naira. $chartDetail',
          child: CustomPaint(
            painter: _TrendPainter(points),
            child: const SizedBox.expand(),
          ),
        ),
      ),
      const SizedBox(height: 7),
      const Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        children: <Widget>[
          _LegendDot(color: Color(0xff176b58), label: 'Gross revenue'),
          _LegendDot(color: Color(0xffd39039), label: 'Provider costs'),
          _LegendDot(color: Color(0xff3e7087), label: 'Known-cost profit'),
        ],
      ),
    ]);
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.points);
  final List<dynamic> points;

  @override
  void paint(Canvas canvas, Size size) {
    final double left = 38;
    final double right = size.width - 8;
    final double top = 12;
    final double bottom = size.height - 22;
    final List<Map<String, dynamic>> rows = points
        .whereType<Map>()
        .map((Map row) => Map<String, dynamic>.from(row))
        .toList();
    double maximum = 0;
    double minimum = 0;
    for (final Map<String, dynamic> row in rows) {
      for (final String key in const <String>[
        'grossRevenue',
        'providerCosts',
        'netProfit',
      ]) {
        final dynamic value = row[key];
        if (value is num) {
          if (value > maximum) maximum = value.toDouble();
          if (value < minimum) minimum = value.toDouble();
        }
      }
    }
    if (maximum <= minimum) maximum = minimum + 1;
    final Paint grid = Paint()
      ..color = const Color(0xffe8ede9)
      ..strokeWidth = 1;
    final TextPainter labels = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    for (int i = 0; i < 4; i++) {
      final double y = top + (bottom - top) * i / 3;
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
      final double tickValue = maximum - (maximum - minimum) * i / 3;
      labels.text = TextSpan(
        text: _compact(tickValue),
        style: const TextStyle(color: Color(0xff84918b), fontSize: 9),
      );
      labels.layout();
      labels.paint(canvas, Offset(0, y - labels.height / 2));
    }
    _drawSeries(canvas, rows, 'grossRevenue', minimum, maximum, left, right,
        top, bottom, const Color(0xff176b58),
        area: true);
    _drawSeries(canvas, rows, 'providerCosts', minimum, maximum, left, right,
        top, bottom, const Color(0xffd39039));
    _drawSeries(canvas, rows, 'netProfit', minimum, maximum, left, right, top,
        bottom, const Color(0xff3e7087));
    if (rows.isNotEmpty) {
      for (final int index in <int>{0, rows.length - 1}) {
        final String date = '${rows[index]['date'] ?? ''}';
        labels.text = TextSpan(
          text: date.length >= 10 ? date.substring(5, 10) : date,
          style: const TextStyle(color: Color(0xff84918b), fontSize: 9),
        );
        labels.layout();
        final double x =
            left + (right - left) * index / (rows.length - 1).clamp(1, 999999);
        labels.paint(canvas, Offset(x - labels.width / 2, bottom + 5));
      }
    }
  }

  void _drawSeries(
    Canvas canvas,
    List<Map<String, dynamic>> rows,
    String key,
    double min,
    double max,
    double left,
    double right,
    double top,
    double bottom,
    Color color, {
    bool area = false,
  }) {
    final List<Offset> coords = <Offset>[];
    for (int i = 0; i < rows.length; i++) {
      final dynamic value = rows[i][key];
      if (value is! num) continue;
      final double x = rows.length < 2
          ? (left + right) / 2
          : left + (right - left) * i / (rows.length - 1);
      final double y =
          bottom - ((value.toDouble() - min) / (max - min)) * (bottom - top);
      coords.add(Offset(x, y));
    }
    if (coords.isEmpty) return;
    final Path path = Path()..moveTo(coords.first.dx, coords.first.dy);
    for (final Offset point in coords.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (area && coords.length > 1) {
      final Path fill = Path.from(path)
        ..lineTo(
            coords.last.dx, bottom - ((0 - min) / (max - min)) * (bottom - top))
        ..lineTo(coords.first.dx,
            bottom - ((0 - min) / (max - min)) * (bottom - top))
        ..close();
      canvas.drawPath(fill, Paint()..color = color.withValues(alpha: .09));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  String _compact(double value) {
    final String sign = value < 0 ? '-₦' : '₦';
    final double magnitude = value.abs();
    if (magnitude >= 1000000) {
      return '$sign${(magnitude / 1000000).toStringAsFixed(1)}m';
    }
    if (magnitude >= 1000) {
      return '$sign${(magnitude / 1000).toStringAsFixed(0)}k';
    }
    return '$sign${magnitude.toStringAsFixed(0)}';
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _ServiceBars extends StatelessWidget {
  const _ServiceBars({required this.services});
  final List<dynamic> services;

  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) {
      return const _EmptyState(
          title: 'No service mix available',
          message: 'No revenue was returned for the selected range.');
    }
    final List<Map<String, dynamic>> rows = services
        .whereType<Map>()
        .map((Map row) => Map<String, dynamic>.from(row))
        .toList();
    double maximum = 0;
    for (final Map<String, dynamic> row in rows) {
      final dynamic value = row['grossRevenue'];
      if (value is num && value > maximum) maximum = value.toDouble();
    }
    if (maximum == 0) maximum = 1;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: rows.map((Map<String, dynamic> row) {
          final double value = row['grossRevenue'] is num
              ? (row['grossRevenue'] as num).toDouble()
              : 0;
          return Row(children: <Widget>[
            SizedBox(
              width: 84,
              child: Text(_serviceName('${row['serviceType'] ?? ''}'),
                  style: const TextStyle(
                      color: Color(0xff53665d),
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (value / maximum).clamp(0.0, 1.0),
                  minHeight: 12,
                  backgroundColor: const Color(0xffe6ece8),
                  color: const Color(0xff61a9bd),
                ),
              ),
            ),
            SizedBox(
              width: 116,
              child: Text(_formatMoney(value),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: Color(0xff30453d),
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]);
        }).toList(),
      ),
    );
  }

  String _serviceName(String value) => switch (value.toUpperCase()) {
        'DATA' => 'Data',
        'AIRTIME' => 'Airtime',
        'ELECTRICITY' => 'Electricity',
        'CABLE' || 'CABLE_TV' => 'Cable TV',
        _ => value.replaceAll('_', ' '),
      };

  String _formatMoney(double value) => '₦${value.toStringAsFixed(2)}';
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(color: Color(0xff6f7d76), fontSize: 10)),
        ],
      );
}
