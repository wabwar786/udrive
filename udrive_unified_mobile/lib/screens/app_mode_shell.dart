import 'package:flutter/material.dart';

import '../core/state/app_controller.dart';
import 'customer_shell.dart';
import 'driver/driver_shell.dart';

class AppModeShell extends StatelessWidget {
  const AppModeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: controller.mode == UserMode.customer
          ? const CustomerShell(key: ValueKey('customer-mode'))
          : const DriverShell(key: ValueKey('driver-mode')),
    );
  }
}
