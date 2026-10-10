import 'dart:ui';

class StrokePoint {
  final double x;
  final double y;
  final double pressure;

  StrokePoint({
    required this.x,
    required this.y,
    this.pressure = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'pressure': pressure,
      };

  factory StrokePoint.fromJson(Map<String, dynamic> json) => StrokePoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        pressure: (json['pressure'] as num?)?.toDouble() ?? 1.0,
      );

  Offset get offset => Offset(x, y);
}

class InkStroke {
  final List<StrokePoint> points;
  final int colorValue;
  final double width;
  final bool highlighter;

  InkStroke({
    required this.points,
    required this.colorValue,
    required this.width,
    this.highlighter = false,
  });

  Map<String, dynamic> toJson() => {
        'points': points.map((p) => p.toJson()).toList(),
        'color': colorValue,
        'width': width,
        'highlighter': highlighter,
      };

  factory InkStroke.fromJson(Map<String, dynamic> json) => InkStroke(
        points: (json['points'] as List)
            .map((p) => StrokePoint.fromJson(Map<String, dynamic>.from(p)))
            .toList(),
        colorValue: json['color'] as int,
        width: (json['width'] as num).toDouble(),
        highlighter: json['highlighter'] as bool? ?? false,
      );
}
