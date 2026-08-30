import 'package:flutter/material.dart';

class UDriveMark extends StatelessWidget {
  const UDriveMark({
    this.size = 56,
    this.showBackground = true,
    this.onTap,
    super.key,
  });

  final double size;
  final bool showBackground;

  /// Tapping the logo returns to Home.
  ///
  /// Every app with a logo in the corner behaves this way, so people try it
  /// whether or not it is documented. Leaving it inert is a small broken
  /// promise on every screen it appears.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mark = _buildMark();
    if (onTap == null) return mark;

    return Semantics(
      button: true,
      label: 'Go to home',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size * .22),
        child: mark,
      ),
    );
  }

  Widget _buildMark() {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(size * .22),
      child: Image.asset(
        'assets/images/udrive_icon_v3.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        gaplessPlayback: true,
      ),
    );

    if (!showBackground) {
      return SizedBox(width: size, height: size, child: image);
    }

    return SizedBox(width: size, height: size, child: image);
  }
}

class UDriveWordmark extends StatelessWidget {
  const UDriveWordmark({this.light = false, this.compact = false, super.key});
  final bool light;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 42.0 : 56.0;
    final image = Image.asset(
      'assets/images/udrive_wordmark_v3.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      gaplessPlayback: true,
    );

    if (!light) {
      return image;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 6 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
      ),
      child: image,
    );
  }
}
