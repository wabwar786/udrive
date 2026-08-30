import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// iOS-style switch, green when on, matching the redesign's toggle rows.
class UdToggleSwitch extends StatelessWidget {
  const UdToggleSwitch({
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Padding(
          // Keeps the visual switch small while the tap target stays comfortable.
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 44,
            height: 26,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? AppColors.secondary : const Color(0xFFD7DEE0),
              borderRadius: BorderRadius.circular(99),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Labelled −/+ counter used for passengers, guests, rooms and seats.
class UdStepper extends StatelessWidget {
  const UdStepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 50,
    this.caption,
    super.key,
  });

  final String label;
  final String? caption;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final canDecrease = value > min;
    final canIncrease = value < max;

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 9, 9, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadii.all(AppRadii.field),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppText.secondary,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppText.disabled,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _StepButton(
            icon: Icons.remove_rounded,
            enabled: canDecrease,
            semanticLabel: 'Decrease $label',
            onTap: () => onChanged(value - 1),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppText.primary,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            enabled: canIncrease,
            semanticLabel: 'Increase $label',
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? AppTint.surface : const Color(0xFFF7F9F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(
            icon,
            size: 17,
            color: enabled ? AppColors.navy : AppText.disabled,
          ),
        ),
      ),
    );
  }
}

/// Two-option segmented control (per-seat vs whole vehicle).
class UdSegmented<T> extends StatelessWidget {
  const UdSegmented({
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final T value;
  final List<({T value, String label})> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTint.surface,
        borderRadius: AppRadii.all(AppRadii.field),
      ),
      child: Row(
        children: options.map((option) {
          final selected = option.value == value;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(option.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: selected ? AppShadows.card : const [],
                ),
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? AppText.primary : AppText.secondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}
