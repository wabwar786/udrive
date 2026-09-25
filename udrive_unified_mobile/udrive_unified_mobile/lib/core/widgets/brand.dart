import 'package:flutter/material.dart';

/// The UDrive pin, from the brand kit.
///
/// Three colourways, and the rule is the background it sits on:
/// navy on light, lime on dark, white where neither works. The mark has
/// transparent edges, so it is drawn as-is rather than clipped into a rounded
/// square — the old asset was a filled app-icon tile and needed the clip.
enum UDriveMarkTone { navy, lime, white }

class UDriveMark extends StatelessWidget {
  const UDriveMark({
    this.size = 56,
    this.tone = UDriveMarkTone.navy,
    this.onTap,
    super.key,
  });

  final double size;

  /// Which colourway to draw. Defaults to navy, which is right on every light
  /// surface in the app — the light and white variants are for a navy panel
  /// and for sitting over a photograph.
  final UDriveMarkTone tone;

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

  static const _assets = {
    UDriveMarkTone.navy: 'assets/brand/udrive_mark_navy_1024.png',
    UDriveMarkTone.lime: 'assets/brand/udrive_mark_lime_1024.png',
    UDriveMarkTone.white: 'assets/brand/udrive_mark_white_1024.png',
  };

  Widget _buildMark() => SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          _assets[tone]!,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
          gaplessPlayback: true,
        ),
      );
}

/// Pin plus "UDrive", horizontal.
class UDriveWordmark extends StatelessWidget {
  const UDriveWordmark({
    this.light = false,
    this.compact = false,
    this.onDark = false,
    super.key,
  });

  /// Draws the mark on a white plate. For placing it over a photograph or a
  /// map, where the page behind it cannot be relied on.
  final bool light;
  final bool compact;

  /// The dark-background colourway: lime pin, white text.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 42.0 : 56.0;
    final image = Image.asset(
      onDark
          ? 'assets/brand/udrive_logo_horizontal_dark.png'
          : 'assets/brand/udrive_logo_horizontal_light.png',
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
