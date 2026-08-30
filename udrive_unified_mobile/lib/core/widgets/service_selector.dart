import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'home_service.dart';

export 'home_service.dart';

/// Horizontal pill row for choosing a service.
///
/// Pills rather than the boxed tiles this used to draw: four bordered blocks
/// each with their own illustration dominated the panel and pushed the
/// addresses below the fold. A single scrollable row of pills reads as one
/// control instead of four cards, and leaves the map visible behind the sheet.
class ServiceSelector extends StatelessWidget {
  const ServiceSelector({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final HomeService selected;
  final ValueChanged<HomeService> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: HomeService.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final service = HomeService.values[index];
          return _ServicePill(
            service: service,
            selected: service == selected,
            onTap: () => onChanged(service),
          );
        },
      ),
    );
  }
}

class _ServicePill extends StatelessWidget {
  const _ServicePill({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  final HomeService service;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: service.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.secondary : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                service.icon,
                size: 17,
                color: selected ? AppText.onBrand : AppText.secondary,
              ),
              const SizedBox(width: 7),
              Text(
                service.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  color: selected ? AppText.onBrand : AppText.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
