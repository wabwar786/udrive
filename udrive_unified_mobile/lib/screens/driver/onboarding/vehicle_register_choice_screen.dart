import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/ud_kit.dart';
import '../../listing/listing_wizard_screen.dart';

/// What a vehicle is being registered for. Sent with the vehicle; UDrive
/// switches the chosen work on when it verifies the vehicle.
class VehicleChoice {
  const VehicleChoice({
    this.city = false,
    this.intercity = false,
    this.tour = false,
    this.rent = false,
  });

  final bool city;
  final bool intercity;
  final bool tour;
  final bool rent;

  bool get rides => city || intercity;
  bool get any => rides || tour || rent;

  /// The fields the vehicle registration sends to the server.
  Map<String, dynamic> toJson() => {
        'wantsCity': city,
        'wantsIntercity': intercity,
        'wantsTour': tour,
        'wantsRent': rent,
      };
}

/// "Yeh gaari kis kaam ke liye hai?" — asked before every vehicle
/// registration in Driver mode.
///
/// One vehicle, one kind of work. City rides covers both inside the city and
/// city to city, and goes on to the driver's own vehicle form ([ridesScreen]);
/// Tour and Rent a car go to the same three-step form the customer side used
/// to have. Changing a vehicle's work later goes through a request.
class VehicleRegisterChoiceScreen extends StatefulWidget {
  const VehicleRegisterChoiceScreen({required this.ridesScreen, super.key});

  /// The vehicle form for city rides (city + city to city).
  final Widget Function(VehicleChoice choice) ridesScreen;

  @override
  State<VehicleRegisterChoiceScreen> createState() =>
      _VehicleRegisterChoiceScreenState();
}

enum _Work { city, tour, rent }

class _VehicleRegisterChoiceScreenState
    extends State<VehicleRegisterChoiceScreen> {
  _Work _work = _Work.city;

  VehicleChoice get _choice => switch (_work) {
        _Work.city => const VehicleChoice(city: true, intercity: true),
        _Work.tour => const VehicleChoice(tour: true),
        _Work.rent => const VehicleChoice(rent: true),
      };

  void _continue() {
    final choice = _choice;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => choice.rides
            ? widget.ridesScreen(choice)
            : ListingWizardScreen(initialRent: choice.rent, initialTour: choice.tour),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const options = <(_Work, String, String)>[
      (
        _Work.city,
        'City rides',
        'Shehar ke andar aur city to city. Customer request bhejta hai, aap '
            'accept karte hain.',
      ),
      (
        _Work.tour,
        'Tour',
        'Departure lagayein — per seat aur poori gaari ka kiraya. Booking '
            'seedhi aati hai.',
      ),
      (
        _Work.rent,
        'Rent a car',
        'Gaari din ke hisaab se kiraye par. Driver ke saath ya self-drive.',
      ),
    ];
    final next = switch (_work) {
      _Work.city => 'Agla step: wohi purana gaari form. Dashboard: City rides.',
      _Work.tour =>
        'Agla step: wohi purana tour form. Dashboard: Tour (gaariyan + departure).',
      _Work.rent =>
        'Agla step: wohi purana rent form (kiraya, kahan se milegi). Dashboard: Rent a car.',
    };

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: '',
        onBack: () => Navigator.maybePop(context),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.sidePadding, 6, AppSizes.sidePadding, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Yeh gaari kis kaam ke liye hai?',
                style: AppType.h1.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 6),
              Text(
                'Aik kaam chunein. Har gaari aik hi kaam karegi — baad mein '
                'badalna ho to request bhej sakte hain.',
                style: AppType.body
                    .copyWith(height: 1.45, color: AppText.secondary),
              ),
              const SizedBox(height: 18),
              for (final (work, title, blurb) in options) ...[
                _ChoiceTile(
                  title: title,
                  blurb: blurb,
                  selected: _work == work,
                  onTap: () => setState(() => _work = work),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 2),
              Text(
                next,
                style: AppType.small.copyWith(color: AppText.secondary),
              ),
              const Spacer(),
              UdButton.primary(
                label: 'Aage barhein',
                onPressed: _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One option: a radio, the name of the work, and one line on what it means.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.blurb,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String blurb;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brandWash : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(16),
        side: BorderSide(
          color: selected ? AppColors.limeLine : AppColors.border,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 26,
                color: selected ? AppColors.brandInk : AppColors.borderStrong,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppType.listTitle.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      blurb,
                      style: AppType.small.copyWith(
                        height: 1.45,
                        color: AppText.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
