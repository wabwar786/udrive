import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class UDriveMark extends StatelessWidget {
  const UDriveMark({this.size = 56, this.showBackground = true, super.key});
  final double size;
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: showBackground
          ? BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF21CE91), AppColors.primaryDark],
              ),
              borderRadius: BorderRadius.circular(size * .27),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: .28),
                  blurRadius: size * .32,
                  offset: Offset(0, size * .12),
                ),
              ],
            )
          : null,
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * .28, size.height * .30)
      ..lineTo(size.width * .28, size.height * .48)
      ..cubicTo(
        size.width * .28,
        size.height * .73,
        size.width * .72,
        size.height * .73,
        size.width * .72,
        size.height * .45,
      )
      ..lineTo(size.width * .72, size.height * .28);
    canvas.drawPath(path, paint);
    final arrow = Path()
      ..moveTo(size.width * .62, size.height * .32)
      ..lineTo(size.width * .72, size.height * .22)
      ..lineTo(size.width * .82, size.height * .32);
    canvas.drawPath(arrow, paint);
    canvas.drawCircle(
      Offset(size.width * .5, size.height * .72),
      size.width * .055,
      Paint()..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class UDriveWordmark extends StatelessWidget {
  const UDriveWordmark({this.light = false, this.compact = false, super.key});
  final bool light;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = light ? Colors.white : AppColors.navy;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UDriveMark(size: compact ? 38 : 48),
        SizedBox(width: compact ? 10 : 12),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'u', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900)),
              TextSpan(text: 'Drive', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
            ],
          ),
          style: TextStyle(fontSize: compact ? 22 : 29, letterSpacing: -1.1),
        ),
      ],
    );
  }
}
