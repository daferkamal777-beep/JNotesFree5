import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/stroke.dart';

/// يرسم ورقة بيضاء مع الخلفية المختارة (مسطّر / مربعات / نقاط).
void paintPageBackground(Canvas canvas, Size size, PageBackground bg) {
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  const gap = 32.0;
  final line = Paint()
    ..color = const Color(0xFFC5D0E0)
    ..strokeWidth = 1;
  switch (bg) {
    case PageBackground.blank:
      break;
    case PageBackground.ruled:
      for (var y = gap * 1.5; y < size.height; y += gap) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
      break;
    case PageBackground.grid:
      for (var x = gap; x < size.width; x += gap) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      }
      for (var y = gap; y < size.height; y += gap) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
      break;
    case PageBackground.dots:
      final dot = Paint()..color = const Color(0xFF9FB0C8);
      for (var x = gap; x < size.width; x += gap) {
        for (var y = gap; y < size.height; y += gap) {
          canvas.drawCircle(Offset(x, y), 1.4, dot);
        }
      }
      break;
  }
}

/// يرسم الخطوط. الهايلايتر أعرض 3 مرات وشفاف، والقلم يتأثر بضغط S Pen.
void paintStrokes(Canvas canvas, Iterable<InkStroke> strokes) {
  for (final stroke in strokes) {
    final pts = stroke.points;
    if (pts.isEmpty) continue;
    final base = Color(stroke.colorValue);
    final color = stroke.highlighter ? base.withAlpha(72) : base;
    final width = stroke.highlighter ? stroke.width * 3 : stroke.width;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    if (pts.length == 1) {
      final r = width * (0.3 + 0.7 * pts.first.pressure) / 2;
      canvas.drawCircle(
        pts.first.offset,
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      continue;
    }

    final varied = !stroke.highlighter && pts.any((p) => p.pressure != 1.0);
    if (varied) {
      for (var i = 1; i < pts.length; i++) {
        final pr = (pts[i - 1].pressure + pts[i].pressure) / 2;
        paint.strokeWidth = width * (0.3 + 0.7 * pr);
        canvas.drawLine(pts[i - 1].offset, pts[i].offset, paint);
      }
    } else {
      final path = Path()..moveTo(pts.first.x, pts.first.y);
      for (var i = 1; i < pts.length; i++) {
        final a = pts[i - 1].offset;
        final b = pts[i].offset;
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        path.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
      }
      path.lineTo(pts.last.x, pts.last.y);
      canvas.drawPath(path, paint);
    }
  }
}
