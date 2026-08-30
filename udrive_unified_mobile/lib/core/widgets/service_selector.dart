import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'home_service.dart';
import 'service_illustration.dart';

export 'home_service.dart';

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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: HomeService.values
          .map((service) => Expanded(
                child: _ServiceColumn(
                  service: service,
                  selected: service == selected,
                  onTap: () => onChanged(service),
                ),
              ))
          .toList(growable: false),
    );
  }
}

class _ServiceColumn extends StatelessWidget {
  const _ServiceColumn({
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3.5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.tile),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 104,
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            decoration: BoxDecoration(
              color: selected ? AppTint.brand : Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.tile),
              border: Border.all(
                color: selected ? AppColors.secondary : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
              boxShadow: selected ? AppShadows.card : const [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // The picture lives inside the block, above its name.
                Expanded(
                  child: ServiceIllustration(service: service),
                ),
                const SizedBox(height: 6),
                Text(
                  service.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: selected ? AppColors.navy : AppText.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
