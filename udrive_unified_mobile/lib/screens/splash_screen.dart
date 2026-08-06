import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
  late final Animation<double> _fade = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeIn,
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, .16),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0E171C),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF18303A), Color(0xFF0E171C), Color(0xFF080D10)],
                ),
              ),
            ),
            Positioned(top: -90, right: -80, child: _Glow(size: 290, opacity: .09)),
            SafeArea(
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      const UDriveMark(size: 84),
                      const SizedBox(height: 14),
                      const Text.rich(
                        TextSpan(children: [
                          TextSpan(text: 'u', style: TextStyle(color: Color(0xFFB7F20B))),
                          TextSpan(text: 'Drive'),
                        ]),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Local rides. Luxury Kashmir journeys.',
                        style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 245,
                        width: double.infinity,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Positioned(
                              left: 2,
                              bottom: 20,
                              child: Transform.rotate(
                                angle: -.06,
                                child: Image.asset('assets/vehicles_photo/private_car_photo.png', width: 220, fit: BoxFit.contain),
                              ),
                            ),
                            Positioned(
                              right: -4,
                              bottom: 0,
                              child: Transform.rotate(
                                angle: .035,
                                child: Image.asset('assets/vehicles_photo/car_photo.png', width: 245, fit: BoxFit.contain),
                              ),
                            ),
                            Positioned(
                              bottom: 6,
                              child: Container(
                                width: 260,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .30),
                                  borderRadius: BorderRadius.circular(99),
                                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 22)],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          color: Color(0xFFB7F20B),
                          strokeWidth: 2.6,
                        ),
                      ),
                      const SizedBox(height: 34),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withValues(alpha: opacity),
        ),
      );
}
