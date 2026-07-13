import 'package:flutter/material.dart';

import '../localization/app_language.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';

class ModeSwitchCard extends StatelessWidget {
  const ModeSwitchCard({
    required this.targetMode,
    super.key,
  });

  final UserMode targetMode;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final toDriver = targetMode == UserMode.driver;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: toDriver
              ? const [AppColors.primary, AppColors.secondary]
              : const [AppColors.secondary, Color(0xFF4F46E5)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _switchMode(context, controller),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(
                    toDriver
                        ? Icons.local_taxi_rounded
                        : Icons.person_pin_circle_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.of(
                          context,
                          toDriver ? 'switchToDriver' : 'switchToCustomer',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        S.of(
                          context,
                          toDriver
                              ? 'driverModeDescription'
                              : 'customerModeDescription',
                        ),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _switchMode(
    BuildContext context,
    AppController controller,
  ) async {
    if (targetMode == UserMode.driver && !controller.driverApproved) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Driver approval required'),
          content: const Text(
            'Complete driver registration and document verification before using Driver mode.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    controller.switchMode(targetMode);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.of(context, 'modeChanged'))),
    );
  }
}
