import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class UDriveLogo extends StatelessWidget {
  const UDriveLogo({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 36 : 44,
          height: compact ? 36 : 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primary, AppColors.secondary]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.route_rounded, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Text(
          'UDrive',
          style: TextStyle(
            fontSize: compact ? 22 : 27,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }
}
