import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'home_service.dart';

/// Vector illustrations for the four Home services.
///
/// Drawn with [CustomPainter] rather than bundled as PNGs for three reasons:
/// they stay sharp at any size (the full-bleed hero is far larger than the
/// 400x240 bitmaps in `assets/vehicles/`), they have no baked-in background so
/// the bottom fade blends cleanly, and their colours come from [AppColors] so
/// they follow the brand automatically.
///
/// Every painter draws inside a 400 x 240 design box and is scaled to fit,
/// so proportions never distort.
class ServiceIllustration extends StatelessWidget {
  const ServiceIllustration({required this.service, super.key});

  final HomeService service;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // CustomPaint cannot be given an infinite size. If either axis is
        // unbounded we fall back to the design ratio instead of throwing, so a
        // stray unbounded parent degrades the artwork rather than blanking the
        // screen.
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : _designWidth;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : width * (_designHeight / _designWidth);

        return CustomPaint(
          size: Size(width, height),
          painter: switch (service) {
            HomeService.car => _CarPainter(),
            HomeService.bus => _CoasterPainter(),
            HomeService.bike => _BikePainter(),
            HomeService.hotel => _HotelPainter(),
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------- shared base

const _designWidth = 400.0;
const _designHeight = 240.0;

const _bodyLight = Color(0xFFB6E96A);
const _bodyMid = AppColors.secondary;
const _bodyDeep = Color(0xFF6BA81E);
const _glass = Color(0xFFDCEFF5);
const _glassDeep = Color(0xFFBBDCE8);
const _metal = Color(0xFF1D3444);
const _hub = Color(0xFFF3F7F8);
const _lamp = Color(0xFFFFC53D);

abstract class _ServicePainter extends CustomPainter {
  /// Scales the 400x240 design box into whatever room the hero gives us and
  /// centres it, so the artwork never stretches.
  @override
  void paint(Canvas canvas, Size size) {
    final scale =
        (size.width / _designWidth).clamp(0.0, size.height / _designHeight);
    canvas
      ..save()
      ..translate(
        (size.width - _designWidth * scale) / 2,
        (size.height - _designHeight * scale) / 2,
      )
      ..scale(scale);
    paintDesign(canvas);
    canvas.restore();
  }

  void paintDesign(Canvas canvas);

  void groundShadow(Canvas canvas, {double cx = 200, double cy = 212, double rx = 165}) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: 22),
      Paint()..color = AppColors.navy.withValues(alpha: .10),
    );
  }

  void wheel(Canvas canvas, double cx, double cy, double radius) {
    canvas
      ..drawCircle(Offset(cx, cy), radius, Paint()..color = _metal)
      ..drawCircle(Offset(cx, cy), radius * .44, Paint()..color = _hub)
      ..drawCircle(Offset(cx, cy), radius * .17, Paint()..color = _metal);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ------------------------------------------------------------------- car

class _CarPainter extends _ServicePainter {
  @override
  void paintDesign(Canvas canvas) {
    groundShadow(canvas, rx: 155);

    // Cabin — a soft arch sitting on the lower body.
    final cabin = Path()
      ..moveTo(126, 132)
      ..lineTo(146, 78)
      ..quadraticBezierTo(152, 64, 170, 64)
      ..lineTo(252, 64)
      ..quadraticBezierTo(268, 64, 276, 76)
      ..lineTo(310, 132)
      ..close();
    canvas.drawPath(cabin, Paint()..color = _bodyMid);

    // Windows.
    final front = Path()
      ..moveTo(196, 76)
      ..lineTo(196, 124)
      ..lineTo(152, 124)
      ..lineTo(170, 80)
      ..quadraticBezierTo(173, 76, 180, 76)
      ..close();
    final rear = Path()
      ..moveTo(208, 76)
      ..lineTo(252, 76)
      ..quadraticBezierTo(260, 76, 265, 84)
      ..lineTo(292, 124)
      ..lineTo(208, 124)
      ..close();
    canvas
      ..drawPath(front, Paint()..color = _glass)
      ..drawPath(rear, Paint()..color = _glassDeep);

    // Lower body.
    final body = Path()
      ..moveTo(38, 158)
      ..quadraticBezierTo(34, 130, 62, 126)
      ..lineTo(330, 126)
      ..quadraticBezierTo(366, 132, 368, 158)
      ..quadraticBezierTo(370, 176, 350, 178)
      ..lineTo(56, 178)
      ..quadraticBezierTo(38, 176, 38, 158)
      ..close();
    canvas.drawPath(body, Paint()..color = _bodyMid);

    // Shading along the sill.
    final sill = Path()
      ..moveTo(44, 168)
      ..lineTo(360, 168)
      ..lineTo(354, 178)
      ..lineTo(52, 178)
      ..close();
    canvas.drawPath(sill, Paint()..color = _bodyDeep);

    // Door line and handle.
    final line = Paint()
      ..color = _bodyDeep
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(202, 128), const Offset(202, 166), line)
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(176, 140, 18, 5),
          const Radius.circular(3),
        ),
        Paint()..color = _bodyDeep,
      );

    // Lamps.
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(346, 138, 20, 12),
          const Radius.circular(6),
        ),
        Paint()..color = _lamp,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(38, 138, 16, 12),
          const Radius.circular(6),
        ),
        Paint()..color = AppColors.danger,
      );

    wheel(canvas, 116, 178, 34);
    wheel(canvas, 296, 178, 34);
  }
}

// --------------------------------------------------------------- coaster

class _CoasterPainter extends _ServicePainter {
  @override
  void paintDesign(Canvas canvas) {
    groundShadow(canvas);

    // Main body.
    final body = RRect.fromRectAndCorners(
      const Rect.fromLTWH(42, 52, 316, 128),
      topLeft: const Radius.circular(26),
      topRight: const Radius.circular(18),
      bottomLeft: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
    );
    canvas.drawRRect(body, Paint()..color = _bodyMid);

    // Roof highlight.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(60, 64, 280, 8),
        const Radius.circular(4),
      ),
      Paint()..color = _bodyLight,
    );

    // Windscreen, then the passenger window strip.
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(52, 86, 46, 52),
        topLeft: const Radius.circular(16),
        bottomLeft: const Radius.circular(8),
        topRight: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      ),
      Paint()..color = _glass,
    );

    for (var i = 0; i < 5; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(112 + i * 48.0, 88, 38, 46),
          const Radius.circular(7),
        ),
        Paint()..color = i.isEven ? _glass : _glassDeep,
      );
    }

    // Skirt.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(42, 152, 316, 16),
        const Radius.circular(5),
      ),
      Paint()..color = _bodyDeep,
    );

    // Door seam and lamps.
    canvas
      ..drawRect(
        const Rect.fromLTWH(104, 86, 3, 66),
        Paint()..color = _bodyDeep,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(46, 140, 16, 10),
          const Radius.circular(5),
        ),
        Paint()..color = _lamp,
      );

    wheel(canvas, 116, 180, 30);
    wheel(canvas, 292, 180, 30);
  }
}

// ------------------------------------------------------------------ bike

class _BikePainter extends _ServicePainter {
  static const _rearX = 112.0;
  static const _frontX = 292.0;
  static const _axleY = 172.0;
  static const _radius = 36.0;

  @override
  void paintDesign(Canvas canvas) {
    canvas.drawOval(
      const Rect.fromLTRB(70, 198, 330, 216),
      Paint()..color = AppColors.navy.withValues(alpha: .10),
    );

    final fender = Paint()
      ..color = _bodyDeep
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawArc(
        Rect.fromCircle(center: const Offset(_rearX, _axleY), radius: 43),
        3.40, 2.44, false, fender,
      )
      ..drawArc(
        Rect.fromCircle(center: const Offset(_frontX, _axleY), radius: 43),
        3.58, 2.01, false, fender,
      );

    // Swingarm, lower rail and seat post.
    final tube = Paint()
      ..color = _metal
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(_rearX, _axleY), const Offset(196, 140), tube)
      ..drawLine(const Offset(196, 140), const Offset(252, 142), tube)
      ..drawLine(const Offset(196, 140), const Offset(232, 112), tube);

    // Engine block.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(198, 140, 42, 24),
        const Radius.circular(6),
      ),
      Paint()..color = _metal,
    );

    // Fuel tank with a highlight along the top.
    canvas.drawPath(
      Path()
        ..moveTo(214, 118)
        ..lineTo(232, 106)
        ..lineTo(258, 104)
        ..lineTo(270, 116)
        ..lineTo(266, 132)
        ..lineTo(222, 134)
        ..close(),
      Paint()..color = _bodyMid,
    );
    canvas.drawPath(
      Path()
        ..moveTo(224, 114)
        ..lineTo(240, 109)
        ..lineTo(258, 109)
        ..lineTo(264, 116)
        ..lineTo(262, 120)
        ..lineTo(238, 116)
        ..lineTo(228, 121)
        ..close(),
      Paint()..color = _bodyLight,
    );

    // Seat and rear cowl.
    canvas.drawPath(
      Path()
        ..moveTo(160, 120)
        ..lineTo(206, 116)
        ..lineTo(216, 124)
        ..lineTo(214, 132)
        ..lineTo(164, 132)
        ..close(),
      Paint()..color = _metal,
    );
    canvas.drawPath(
      Path()
        ..moveTo(150, 118)
        ..lineTo(166, 116)
        ..lineTo(168, 128)
        ..lineTo(152, 130)
        ..close(),
      Paint()..color = _bodyMid,
    );

    // Front fork, handlebar and headlamp.
    canvas
      ..drawLine(
        const Offset(268, 118),
        const Offset(_frontX, _axleY),
        Paint()
          ..color = _metal
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round,
      )
      ..drawLine(
        const Offset(262, 108),
        const Offset(294, 98),
        Paint()
          ..color = _metal
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(const Offset(280, 112), 12, Paint()..color = _bodyMid)
      ..drawCircle(const Offset(283, 115), 9, Paint()..color = _lamp);

    // Exhaust.
    canvas.drawLine(
      const Offset(178, 170),
      const Offset(240, 162),
      Paint()
        ..color = const Color(0xFF9AA9B4)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );

    wheel(canvas, _rearX, _axleY, _radius);
    wheel(canvas, _frontX, _axleY, _radius);
  }
}

// ----------------------------------------------------------------- hotel

class _HotelPainter extends _ServicePainter {
  @override
  void paintDesign(Canvas canvas) {
    groundShadow(canvas, cy: 207, rx: 130);

    // Side wing, drawn first so the main block overlaps it.
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(258, 104, 76, 102),
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
      ),
      Paint()..color = _bodyDeep,
    );

    // Main block.
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(84, 52, 190, 154),
        topLeft: const Radius.circular(12),
        topRight: const Radius.circular(12),
      ),
      Paint()..color = _bodyMid,
    );

    // Cornice.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(74, 44, 210, 18),
        const Radius.circular(7),
      ),
      Paint()..color = _metal,
    );

    // Sign board on the roof.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(140, 18, 78, 22),
        const Radius.circular(6),
      ),
      Paint()..color = _metal,
    );
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
        Offset(156 + i * 16.0, 29),
        4,
        Paint()..color = _lamp,
      );
    }

    // Window grid.
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 4; column++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(102 + column * 42.0, 74 + row * 36.0, 28, 24),
            const Radius.circular(5),
          ),
          Paint()..color = (row + column).isEven ? _glass : _glassDeep,
        );
      }
    }

    // Wing windows.
    for (var row = 0; row < 2; row++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(282, 120 + row * 36.0, 28, 22),
          const Radius.circular(5),
        ),
        Paint()..color = _glassDeep,
      );
    }

    // Canopy and entrance.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(132, 184, 94, 10),
        const Radius.circular(5),
      ),
      Paint()..color = _bodyLight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(156, 194, 46, 12),
        const Radius.circular(4),
      ),
      Paint()..color = _glass,
    );
    canvas.drawLine(
      const Offset(179, 194),
      const Offset(179, 206),
      Paint()
        ..color = _metal
        ..strokeWidth = 2.5,
    );

  }
}
