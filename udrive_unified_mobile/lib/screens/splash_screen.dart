import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  late final Animation<double> _scale = CurvedAnimation(parent: _animation, curve: Curves.easeOutBack);
  late final Animation<double> _fade = CurvedAnimation(parent: _animation, curve: Curves.easeIn);

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF073D31), AppColors.primaryDark, AppColors.primary],
            ),
          ),
          child: Stack(
            children: [
              Positioned(top: -80, right: -80, child: _Glow(size: 260, opacity: .12)),
              Positioned(bottom: -110, left: -80, child: _Glow(size: 330, opacity: .09)),
              Center(
                child: FadeTransition(
                  opacity: _fade,
                  child: ScaleTransition(
                    scale: _scale,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        UDriveMark(size: 112),
                        SizedBox(height: 24),
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: 'u', style: TextStyle(color: AppColors.accent)),
                            TextSpan(text: 'Drive'),
                          ]),
                          style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -2),
                        ),
                        SizedBox(height: 8),
                        Text('Explore freely. Ride confidently.', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
              const Positioned(left: 0, right: 0, bottom: 42, child: Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4))),
            ],
          ),
        ),
      );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.opacity});
  final double size;
  final double opacity;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: opacity)),
      );
}
