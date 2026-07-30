import 'package:flutter/material.dart';

class UDriveLogo extends StatelessWidget {
  const UDriveLogo({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/udrive_wordmark.png',
      height: compact ? 32 : 44,
      fit: BoxFit.contain,
    );
  }
}
