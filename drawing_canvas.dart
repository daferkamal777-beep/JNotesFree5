import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/stroke.dart';
import 'page_painter.dart';

enum DrawingTool { pen, highlighter, eraser }

/// لوحة الرسم. تستقبل لمس الإصبع والقلم (S Pen) وتقرأ ضغط القلم.
/// - طرف القلم المعكوس (ممحاة S Pen إن وُجدت) يمحو تلقائيًا.
/// - وضع «قلم فقط» يتجاهل لمس الإصبع لمنع تأثير راحة اليد.
/// تُرسل التغيير للأب مرة واحدة عند رفع القلم (ليعمل التراجع بشكل صحيح).
class DrawingCanvas extends StatefulWidget {
  final List<InkStroke> strokes;
  final PageBackground background;
  final ValueChanged<List<InkStroke>> onChanged;
  final DrawingTool tool;
  final Color color;
  final double strokeWidth;
  final bool stylusOnly;

  const DrawingCanvas({
    super.key,
    required this.strokes,
    required this.background,
    required this.onChanged,
    required this.tool,
    required this.color,
    required this.strokeWidth,
    this.stylusOnly = false,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  InkStroke? _current;
  List<InkStroke>? _working; // نسخة عمل أثناء المحو
  int? _pointer;

  bool _isStylus(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus ||
      e.kind == PointerDeviceKind.invertedStylus;

  bool _allowed(PointerEvent e) {
    if (!widget.stylusOnly) return true;
    return _isStylus(e) || e.kind == PointerDeviceKind.mouse;
  }

  bool _isEraser(PointerEvent e) =>
      widget.tool == DrawingTool.eraser ||
      e.kind == PointerDeviceKind.invertedStylus;

  double _pressureOf(PointerEvent e) {
    if (!_isStylus(e)) return 1.0;
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 1.0;
    final p = ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0).toDouble();
    return p < 0.05 ? 0.05 : p;
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null || !_allowed(e)) return;
    _pointer = e.pointer;
    final p = e.localPosition;
    if (_isEraser(e)) {
      _working = List<InkStroke>.of(widget.strokes);
      _eraseAt(p);
    } else {
      _current = InkStroke(
        points: [StrokePoint(x: p.dx, y: p.dy, pressure: _pressureOf(e))],
        colorValue: widget.color.value,
        width: widget.strokeWidth,
        highlighter: widget.tool == DrawingTool.highlighter,
      );
    }
    setState(() {});
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final p = e.localPosition;
    if (_working != null) {
      _eraseAt(p);
      setState(() {});
      return;
    }
    final cur = _current;
    if (cur == null) return;
    if ((cur.points.last.offset - p).distance < 0.8) return;
    cur.points.add(StrokePoint(x: p.dx, y: p.dy, pressure: _pressureOf(e)));
    setState(() {});
  }

  void _end(PointerEvent e, {required bool commit}) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final working = _working;
    final cur = _current;
    _working = null;
    _current = null;
    if (commit) {
      if (working != null) {
        if (working.length != widget.strokes.length) widget.onChanged(working);
      } else if (cur != null) {
        widget.onChanged([...widget.strokes, cur]);
      }
    }
    setState(() {});
  }

  void _eraseAt(Offset p) {
    const radius = 18.0;
    _working!.removeWhere((s) {
      final w = (s.highlighter ? s.width * 3 : s.width) / 2;
      return _hits(s, p, radius + w);
    });
  }

  bool _hits(InkStroke s, Offset p, double r) {
    final pts = s.points;
    if (pts.length == 1) return (pts.first.offset - p).distance <= r;
    for (var i = 1; i < pts.length; i++) {
      if (_distToSegment(p, pts[i - 1].offset, pts[i].offset) <= r) return true;
    }
    return false;
  }

  double _distToSegment(Offset p, Offset a, Offset b) {
    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final len2 = abx * abx + aby * aby;
    if (len2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / len2)
        .clamp(0.0, 1.0)
        .toDouble();
    return (p - Offset(a.dx + abx * t, a.dy + aby * t)).distance;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: (e) => _end(e, commit: true),
        onPointerCancel: (e) => _end(e, commit: false),
        child: CustomPaint(
          painter: _PagePainter(
            strokes: _working ?? widget.strokes,
            current: _current,
            background: widget.background,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PagePainter extends CustomPainter {
  final List<InkStroke> strokes;
  final InkStroke? current;
  final PageBackground background;

  _PagePainter({
    required this.strokes,
    required this.current,
    required this.background,
  });

  @override
  void paint(Canvas canvas, Size size) {
    paintPageBackground(canvas, size, background);
    paintStrokes(canvas, strokes);
    if (current != null) paintStrokes(canvas, [current!]);
  }

  @override
  bool shouldRepaint(covariant _PagePainter oldDelegate) => true;
}
