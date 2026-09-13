import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import 'driver_signup_screen.dart';

/// The first question: what do you drive?
///
/// Asked on its own, before anything else, because it is the one decision a
/// driver can make without looking anything up — and because it changes what
/// the rest of the form asks for. Buried at step four next to the number plate
/// it would be a setting; here it is the door.
class DriverVehicleTypeScreen extends StatelessWidget {
  const DriverVehicleTypeScreen({super.key});

  /// The categories, in the order they are common here.
  ///
  /// Motorcycles outnumber cars on most of these roads and rickshaws do the
  /// short runs, so a list that opened with saloons and SUVs would be a list
  /// written for somewhere else.
  static const _types = <(String, String, IconData)>[
    ('Car', 'Four seats, air conditioned', Icons.directions_car_rounded),
    ('Motorcycle', 'One passenger, quickest through traffic',
        Icons.two_wheeler_rounded),
    ('Rickshaw', 'Three passengers, short runs', Icons.electric_rickshaw_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Choose your vehicle'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: [
          const Text(
            'You can add another vehicle later.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppText.secondary,
            ),
          ),
          const SizedBox(height: 18),
          for (final (name, blurb, icon) in _types)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriverSignUpScreen(vehicleCategory: name),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(icon,
                              size: 28, color: AppColors.secondary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppText.primary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                blurb,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppText.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppText.disabled),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
