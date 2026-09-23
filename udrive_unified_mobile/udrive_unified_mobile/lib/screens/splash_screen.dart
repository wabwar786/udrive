import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';

/// The first thing the app shows while it restores the session.
///
/// One mark, centred, on the app's own dark background. It used to carry the
/// wordmark, a tagline and three photographs of vehicles, which is a lot of
/// screen to build and throw away in under a second — and the photographs
/// stacked at odd angles were the first impression the app made.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  late final Animation<double> _fade =
      CurvedAnimation(parent: _animation, curve: Curves.easeOut);

  // Barely there. A mark that swings in draws attention to the wait rather
  // than covering it.
  late final Animation<double> _scale = Tween(begin: .94, end: 1.0).animate(
    CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: const UDriveMark(size: 76),
            ),
          ),
        ),
      );
}
