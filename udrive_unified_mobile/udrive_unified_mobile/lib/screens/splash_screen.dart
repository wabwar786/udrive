import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The first thing the app shows while it restores the session.
///
/// The brand kit's splash: white ground, the navy pin and wordmark stacked and
/// centred, "DISCOVER KASHMIR" beneath it, and a pale range of mountains along
/// the bottom edge.
///
/// This is the screen the app draws. The one *before* it — the window the OS
/// paints between tapping the icon and Flutter starting — is a different thing
/// entirely, drawn from `android/app/src/main/res` and matching this one so the
/// hand-off is invisible: same white, same pin, same position.
///
/// The mountains are painted rather than shipped as an image. A silhouette is
/// nine straight lines, and a PNG of it would need three densities and would
/// stop matching [AppColors.brandWash] the moment the brand colour moved.
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
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    // The logo is a fraction of the width so it holds its proportions from a
    // small phone to a tablet, with a ceiling so it does not become a poster.
    final logoWidth = (size.width * .46).clamp(150.0, 240.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: (size.height * .22).clamp(120.0, 260.0),
            child: const _MountainRidge(),
          ),
          Positioned.fill(
            child: Center(
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/brand/udrive_logo_stacked_light.png',
                        width: logoWidth,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        isAntiAlias: true,
                        gaplessPlayback: true,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'DISCOVER KASHMIR',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          // Wide tracking is what makes a short line of caps
                          // read as a mark rather than as a sentence.
                          letterSpacing: 4.2,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Sits over the mountains, where the kit puts it.
          Positioned(
            left: 0,
            right: 0,
            bottom: (size.height * .085).clamp(48.0, 110.0),
            child: const Center(child: _SplashProgress()),
          ),
        ],
      ),
    );
  }
}

/// A short determinate-looking bar that never claims a percentage.
///
/// Restoring a session takes as long as it takes; a bar that filled to 90% and
/// stopped would be a lie told on the first screen of the app.
class _SplashProgress extends StatelessWidget {
  const _SplashProgress();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 120,
        height: 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: const LinearProgressIndicator(
            minHeight: 3,
            backgroundColor: AppColors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(AppColors.navy),
          ),
        ),
      );
}

class _MountainRidge extends StatelessWidget {
  const _MountainRidge();

  @override
  Widget build(BuildContext context) => const CustomPaint(
        painter: _MountainPainter(
          rock: AppColors.brandWash,
          snow: AppColors.background,
        ),
        size: Size.infinite,
      );
}

class _MountainPainter extends CustomPainter {
  const _MountainPainter({required this.rock, required this.snow});

  final Color rock;
  final Color snow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Three peaks, the middle one tallest, drawn as fractions of the box so
    // the range re-proportions itself on any screen.
    final ridge = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * .72)
      ..lineTo(w * .15, h * .24)
      ..lineTo(w * .27, h * .58)
      ..lineTo(w * .36, h * .45)
      ..lineTo(w * .52, h * .04)
      ..lineTo(w * .66, h * .52)
      ..lineTo(w * .74, h * .40)
      ..lineTo(w * .84, h * .18)
      ..lineTo(w, h * .55)
      ..lineTo(w, h)
      ..close();

    canvas.drawPath(ridge, Paint()..color = rock);

    // Snow caps: the same white as the page, so they read as sky showing
    // through rather than as a fourth colour.
    //
    // Clipped to the ridge rather than fitted to it. A cap is a triangle and a
    // peak is two slopes of different steepness, so on the outer peaks one
    // corner always lands outside the mountain — a white notch cut into the
    // skyline. Clipping makes that impossible at any screen proportion, which
    // tuning the numbers for one phone would not.
    canvas.save();
    canvas.clipPath(ridge);

    final caps = Paint()..color = snow;
    void cap(double peakX, double peakY, double baseY, double halfWidth) {
      canvas.drawPath(
        Path()
          ..moveTo(w * (peakX - halfWidth), h * baseY)
          ..lineTo(w * peakX, h * peakY)
          ..lineTo(w * (peakX + halfWidth), h * baseY)
          ..close(),
        caps,
      );
    }

    // Each base sits below where the steeper of the peak's two slopes reaches
    // that half-width, so the cap is a cap and not a wedge. The clip above
    // only has to catch rounding.
    cap(.15, .24, .36, .035);
    cap(.52, .04, .22, .050);
    cap(.84, .18, .28, .040);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MountainPainter oldDelegate) =>
      oldDelegate.rock != rock || oldDelegate.snow != snow;
}
