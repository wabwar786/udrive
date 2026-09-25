import 'package:flutter/material.dart';

/// A steering wheel.
///
/// Material has no steering-wheel glyph — `drive_eta` is a car seen from the
/// side, which reads as "a vehicle" rather than "you are driving it". The
/// distinction is the whole point of the control it sits on, so the shape is
/// drawn rather than approximated with the nearest available icon.
class SteeringWheelIcon extends StatelessWidget {
  const SteeringWheelIcon({this.size = 22, this.color, super.key});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SteeringWheelPainter(
        color ?? IconTheme.of(context).color ?? Colors.black,
      ),
    );
  }
}

class _SteeringWheelPainter extends CustomPainter {
  const _SteeringWheelPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Stroke width scales with the icon so it stays a wheel at 16px and at 40,
    // rather than a thin ring at one size and a blob at the other.
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .09
      ..strokeCap = StrokeCap.round;

    final fill = Paint()..color = color;

    // Rim.
    canvas.drawCircle(centre, radius * .92, stroke);

    // Hub.
    canvas.drawCircle(centre, radius * .22, fill);

    // Three spokes: one down, two up and out. The asymmetry is what makes it
    // read as a steering wheel rather than a wheel or a target.
    canvas.drawLine(
      centre + Offset(0, radius * .22),
      centre + Offset(0, radius * .92),
      stroke,
    );
    canvas.drawLine(
      centre + Offset(-radius * .21, -radius * .09),
      centre + Offset(-radius * .88, -radius * .30),
      stroke,
    );
    canvas.drawLine(
      centre + Offset(radius * .21, -radius * .09),
      centre + Offset(radius * .88, -radius * .30),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_SteeringWheelPainter oldDelegate) =>
      oldDelegate.color != color;
}
