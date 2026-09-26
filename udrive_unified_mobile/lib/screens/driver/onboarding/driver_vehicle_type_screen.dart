import 'package:flutter/material.dart';

import '../../../core/state/app_controller.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/ud_kit.dart';
import '../../../data/models.dart';
import '../../hotel_owner/hotel_owner_shell.dart';
import 'driver_signup_screen.dart';

/// D-01 — the first question: what are you offering?
///
/// Asked on its own, before anything else, because it is the one decision
/// somebody can make without looking anything up — and because it changes what
/// the rest of the form asks for. Buried at step four next to the number plate
/// it would be a setting; here it is the door.
///
/// A hotel is not a vehicle, and this screen used to say "Choose your vehicle".
/// Putting a hotel on that list would have been a small lie, so the question
/// widened instead: everything here is a way to earn on the platform, and the
/// shape of the form follows from which one you pick.
///
/// No `Scaffold` and no `AppBar`. `main_shell` renders this as the driver
/// verification gate and draws a white bar above it, so its own navy bar was a
/// second bar on the same screen.
class DriverVehicleTypeScreen extends StatelessWidget {
  const DriverVehicleTypeScreen({super.key});

  /// The options, in the order they are common here.
  ///
  /// Motorcycles outnumber cars on most of these roads and rickshaws do the
  /// short runs, so a list that opened with saloons and SUVs would be a list
  /// written for somewhere else.
  static const _types = <(String, String, IconData)>[
    ('Car', 'Four seats, air conditioned', Icons.directions_car_rounded),
    ('Motorcycle', 'One passenger, quickest through traffic',
        Icons.two_wheeler_rounded),
    ('Rickshaw', 'Three passengers, short runs', Icons.electric_rickshaw_rounded),
    ('Coster', 'Up to 22 seats, groups and tours', Icons.airport_shuttle_rounded),
    ('Hotel', 'Rooms and guest houses', Icons.apartment_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 4, AppSizes.sidePadding, 34),
      children: [
        Text(
          'How do you want to earn?',
          style: AppType.h1.copyWith(color: AppText.primary),
        ),
        const SizedBox(height: 8),
        Text(
          'You can add another later.',
          style: AppType.body.copyWith(height: 1.45, color: AppText.secondary),
        ),
        const SizedBox(height: 22),
        UdListGroup(
          children: [
            for (final (name, blurb, icon) in _types)
              UdListRow(
                title: name,
                subtitle: blurb,
                leading: UdIconTile(icon: icon),
                showChevron: true,
                // A hotel goes somewhere else entirely.
                //
                // It has no licence, no number plate and no CNIC-with-selfie
                // — sending it through the driver steps would mean four
                // screens of questions with nothing to answer.
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => name == 'Hotel'
                        ? const HotelOwnerShell()
                        : DriverSignUpScreen(vehicleCategory: name),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 26),
        // Was a "Close" button in the app bar calling `Navigator.pop`.
        //
        // This screen is not pushed — `main_shell` renders it as the driver
        // verification gate, and `MainShell` is `app.dart`'s `home:`, the root
        // route. So `pop` had nothing to pop and the button did precisely
        // nothing, on the first screen a new driver ever sees.
        //
        // Leaving the gate means going back to being a customer, so that is
        // what the button does now.
        UdButton.ghost(
          label: 'Not now — back to customer',
          icon: Icons.arrow_back_rounded,
          onPressed: () => controller.switchMode(UserMode.customer),
        ),
      ],
    );
  }
}
