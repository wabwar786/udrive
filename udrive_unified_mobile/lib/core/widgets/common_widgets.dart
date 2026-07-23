import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';

class PagePadding extends StatelessWidget {
  const PagePadding({required this.child, this.bottom = 28, super.key});
  final Widget child;
  final double bottom;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(18, 8, 18, bottom),
        child: child,
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.action, this.onAction, super.key});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.navy),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
        ],
      );
}

class PremiumCard extends StatelessWidget {
  const PremiumCard({required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, super.key});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final card = Card(
      color: color,
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(24), child: card);
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, this.color = AppColors.primary, super.key});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
      );
}

class MetricTile extends StatelessWidget {
  const MetricTile({required this.icon, required this.label, required this.value, required this.color, super.key});
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
        child: PremiumCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(height: 12),
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.navy)),
              const SizedBox(height: 3),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

class MapPreview extends StatelessWidget {
  const MapPreview({this.height = 210, this.showCar = true, super.key});
  final double height;
  final bool showCar;
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.border),
          gradient: const LinearGradient(colors: [Color(0xFFE6F5EE), Color(0xFFE6F0F5)]),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _MapPainter())),
            const Positioned(left: 34, top: 38, child: _MapPin(color: AppColors.primary, icon: Icons.trip_origin_rounded)),
            const Positioned(right: 38, bottom: 35, child: _MapPin(color: AppColors.secondary, icon: Icons.location_on_rounded)),
            if (showCar)
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: .14), blurRadius: 20)],
                  ),
                  child: const Icon(Icons.directions_car_filled_rounded, color: AppColors.navy),
                ),
              ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .94), borderRadius: BorderRadius.circular(15)),
                child: const Row(
                  children: [
                    Icon(Icons.route_rounded, size: 18, color: AppColors.primary),
                    SizedBox(width: 8),
                    Expanded(child: Text('Live route preview · Dummy map data', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = Colors.white.withValues(alpha: .82)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final minor = Paint()
      ..color = Colors.white.withValues(alpha: .52)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(-20, size.height * .72)
      ..cubicTo(size.width * .25, size.height * .35, size.width * .48, size.height * .76, size.width + 30, size.height * .22);
    canvas.drawPath(path, road);
    for (var i = 0; i < 5; i++) {
      final y = size.height * (.18 + i * .17);
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 26), minor);
    }
    for (var i = 0; i < 4; i++) {
      final x = size.width * (.17 + i * .23);
      canvas.drawLine(Offset(x, 0), Offset(x + 34, size.height), minor);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.color, required this.icon});
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        width: 43,
        height: 43,
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withValues(alpha: .2), blurRadius: 14)]),
        child: Icon(icon, color: color),
      );
}

class UploadTile extends StatelessWidget {
  const UploadTile({required this.label, required this.uploaded, required this.onTap, this.icon = Icons.upload_file_rounded, super.key});
  final String label;
  final bool uploaded;
  final VoidCallback onTap;
  final IconData icon;
  @override
  Widget build(BuildContext context) => PremiumCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: (uploaded ? AppColors.success : AppColors.secondary).withValues(alpha: .11), borderRadius: BorderRadius.circular(13)),
              child: Icon(uploaded ? Icons.check_rounded : icon, color: uploaded ? AppColors.success : AppColors.secondary),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(uploaded ? context.tr('uploaded') : context.tr('upload'), style: TextStyle(color: uploaded ? AppColors.success : AppColors.primaryDark, fontSize: 12, fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

Color verificationColor(VerificationStatus status) {
  return switch (status) {
    VerificationStatus.verified => AppColors.success,
    VerificationStatus.pending => AppColors.warning,
    VerificationStatus.draft => AppColors.muted,
    VerificationStatus.rejected => AppColors.danger,
  };
}

String verificationLabel(BuildContext context, VerificationStatus status) {
  return switch (status) {
    VerificationStatus.verified => context.tr('verified'),
    VerificationStatus.pending => context.tr('pending'),
    VerificationStatus.draft => context.tr('draft'),
    VerificationStatus.rejected => 'Rejected',
  };
}
