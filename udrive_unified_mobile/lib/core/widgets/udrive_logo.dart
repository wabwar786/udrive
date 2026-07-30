import 'package:flutter/material.dart';

class UDriveLogo extends StatelessWidget {
  const UDriveLogo({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/udrive_wordmark_v3.png',
      height: compact ? 38 : 52,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      gaplessPlayback: true,
    );
  }
}
