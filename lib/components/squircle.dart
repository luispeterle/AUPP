import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A superellipse |x|^n + |y|^n = 1 filling [rect], between a circle (n = 2)
/// and a square: [_exponent] keeps it round, with no straight sides.
Path squirclePath(Rect rect) {
  const exponent = 2.5;
  const steps = 128;
  final a = rect.width / 2, b = rect.height / 2;
  final cx = rect.center.dx, cy = rect.center.dy;
  final path = Path();
  for (var i = 0; i < steps; i++) {
    final t = 2 * math.pi * i / steps;
    final c = math.cos(t), s = math.sin(t);
    final x = cx + a * c.sign * math.pow(c.abs(), 2 / exponent);
    final y = cy + b * s.sign * math.pow(s.abs(), 2 / exponent);
    i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
  }
  return path..close();
}

/// Clips its child to [squirclePath].
class SquircleClipper extends CustomClipper<Path> {
  const SquircleClipper();

  @override
  Path getClip(Size size) => squirclePath(Offset.zero & size);

  @override
  bool shouldReclip(SquircleClipper oldClipper) => false;
}

/// [squirclePath] as a shape, for a [ShapeDecoration] with an outline.
class SquircleBorder extends ShapeBorder {
  final BorderSide side;

  const SquircleBorder({this.side = BorderSide.none});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      squirclePath(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      squirclePath(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(
      squirclePath(rect.deflate(side.width / 2)),
      side.toPaint(),
    );
  }

  @override
  ShapeBorder scale(double t) => SquircleBorder(side: side.scale(t));
}
