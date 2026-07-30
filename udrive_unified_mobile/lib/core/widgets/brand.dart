import 'package:flutter/material.dart';

class UDriveMark extends StatelessWidget {
  const UDriveMark({this.size = 56, this.showBackground = true, super.key});
  final double size;
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(size * .22),
      child: Image.asset(
        'assets/images/udrive_icon_v2.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );

    if (!showBackground) {
      return SizedBox(width: size, height: size, child: image);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .12),
            blurRadius: size * .18,
            offset: Offset(0, size * .08),
          ),
        ],
      ),
      child: image,
    );
  }
}

class UDriveWordmark extends StatelessWidget {
  const UDriveWordmark({this.light = false, this.compact = false, super.key});
  final bool light;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 34.0 : 48.0;
    final image = Image.asset(
      'assets/images/udrive_wordmark_v2.png',
      height: height,
      fit: BoxFit.contain,
    );

    if (!light) {
      return image;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
      ),
      child: image,
    );
  }
}
