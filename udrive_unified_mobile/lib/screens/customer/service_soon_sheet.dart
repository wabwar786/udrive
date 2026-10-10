import 'package:flutter/material.dart';

import '../../core/services/service_availability_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../data/models.dart';
import '../business_owner/business_owner_add_screen.dart';
import '../driver/onboarding/driver_vehicle_type_screen.dart';
import '../listing/listing_wizard_screen.dart';

/// What a closed ("SOON") Home tile does when tapped.
///
/// Customers still cannot use the service — it opens when the Admin switches
/// it on in Services. But the people who make the service possible (a hotel,
/// a car to rent, a coster, a shop) can join now, so the service has supply
/// on the day it opens. Their listing goes through the usual approval.
Future<void> showServiceSoonSheet(
  BuildContext context,
  ServiceAvailability service,
) {
  final join = _joinFor(service.key);
  return showUdSheet<void>(
    context: context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_nameFor(service.key)} jald aa rahe hain',
          style: AppType.h3.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: AppText.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          join == null
              ? service.closedMessage
              : 'Customers ke liye yeh service abhi band hai. ${join.question} '
                  'Abhi add karein — service khulte hi customers aap ko dekh '
                  'sakenge.',
          style: AppType.body.copyWith(color: AppText.secondary, height: 1.45),
        ),
        const SizedBox(height: 18),
        if (join != null) ...[
          UdButton.primary(
            label: join.button,
            icon: join.icon,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              final screen = join.screen;
              if (screen == null) {
                // Hotels are added in Hotel mode, which has its own home, its
                // own Back and Home buttons and the owner profile.
                final controller = AppControllerScope.of(context);
                Navigator.of(context).popUntil((route) => route.isFirst);
                controller.switchMode(UserMode.hotel);
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: screen),
              );
            },
          ),
          const SizedBox(height: 10),
        ],
        UdButton.outline(
          label: 'Theek hai',
          onPressed: () => Navigator.of(sheetContext).pop(),
        ),
      ],
    ),
  );
}

class _Join {
  const _Join(this.question, this.button, this.icon, this.screen);

  final String question;
  final String button;
  final IconData icon;

  /// Null: switch to Hotel mode instead of opening a screen.
  final WidgetBuilder? screen;
}

String _nameFor(String key) => switch (key) {
      'hotels' => 'Hotels',
      'carRental' => 'Car rental',
      'tour' => 'Tours',
      'cityRides' => 'City rides',
      'cityToCity' => 'City to city',
      'coster' => 'Coster',
      'explore' => 'Explore',
      _ => 'Yeh service',
    };

/// Who can join a closed service, and where they go to do it.
_Join? _joinFor(String key) => switch (key) {
      'hotels' => _Join(
          'Aap ka hotel ya guest house hai?',
          'Apna hotel add karein',
          Icons.apartment_rounded,
          null,
        ),
      'carRental' => _Join(
          'Aap ki gaari hai jo rent par de sakte hain?',
          'Apni gaari rent par lagayein',
          Icons.car_rental_rounded,
          (_) => const ListingWizardScreen(initialRent: true),
        ),
      'tour' => _Join(
          'Aap ki gaari tour par ja sakti hai?',
          'Apni gaari tour par lagayein',
          Icons.terrain_rounded,
          (_) => const ListingWizardScreen(initialTour: true),
        ),
      'cityRides' || 'cityToCity' || 'coster' => _Join(
          'Aap gaari, bike, rickshaw ya coster chalate hain?',
          'Driver banein',
          Icons.badge_outlined,
          (routeContext) => Scaffold(
            backgroundColor: AppColors.background,
            appBar: UdTopBar(
              title: 'Driver registration',
              onBack: () => Navigator.pop(routeContext),
            ),
            body: const DriverVehicleTypeScreen(),
          ),
        ),
      'explore' => _Join(
          'Aap ki dukaan, restaurant ya koi business hai?',
          'Apna business add karein',
          Icons.storefront_rounded,
          (_) => const BusinessOwnerAddScreen(),
        ),
      _ => null,
    };
