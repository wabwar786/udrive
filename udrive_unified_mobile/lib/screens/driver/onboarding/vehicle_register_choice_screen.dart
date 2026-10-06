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

/// "Kis ke liye register karna chahte hain?" — asked before every vehicle
/// registration in Driver mode.
///
/// Four big choices, nothing else on the screen. City rides / city to city go
/// on to the driver's own vehicle form ([ridesScreen]); tour and rent only go
/// to the same three-step form the customer side used to have.
class VehicleRegisterChoiceScreen extends StatefulWidget {
  const VehicleRegisterChoiceScreen({required this.ridesScreen, super.key});

  /// The vehicle form for city rides / city to city.
  final Widget Function(VehicleChoice choice) ridesScreen;

  @override
  State<VehicleRegisterChoiceScreen> createState() =>
      _VehicleRegisterChoiceScreenState();
}

class _VehicleRegisterChoiceScreenState
    extends State<VehicleRegisterChoiceScreen> {
  bool _city = false;
  bool _intercity = false;
  bool _tour = false;
  bool _rent = false;

  VehicleChoice get _choice => VehicleChoice(
      city: _city, intercity: _intercity, tour: _tour, rent: _rent);

  /// Rent and rides exclude each other: a car out on rent is with somebody
  /// else and cannot pick anyone up. Picking one side clears the other.
  void _toggle(String which) {
    setState(() {
      switch (which) {
        case 'city':
          _city = !_city;
          if (_city) _rent = false;
        case 'intercity':
          _intercity = !_intercity;
          if (_intercity) _rent = false;
        case 'tour':
          _tour = !_tour;
        case 'rent':
          _rent = !_rent;
          if (_rent) {
            _city = false;
            _intercity = false;
          }
      }
    });
  }

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
    final options = <(String, String, String, IconData, bool)>[
      ('city', 'City rides', 'Shehar ke andar', Icons.local_taxi_rounded, _city),
      ('intercity', 'City to city', 'Aik shehar se doosre', Icons.alt_route_rounded, _intercity),
      ('tour', 'Tours', 'Packages aur tours', Icons.landscape_rounded, _tour),
      ('rent', 'Rent a car', 'Gaari kiraye par', Icons.car_rental_rounded, _rent),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(
        title: 'Gaari register karein',
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
                'Kis ke liye register karna chahte hain?',
                style: AppType.h1.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 6),
              Text(
                'Aik ya zyada chunein.',
                style: AppType.body.copyWith(color: AppText.secondary),
              ),
              const SizedBox(height: 18),
              for (final (key, title, blurb, icon, on) in options) ...[
                _ChoiceTile(
                  title: title,
                  blurb: blurb,
                  icon: icon,
                  selected: on,
                  onTap: () => _toggle(key),
                ),
                const SizedBox(height: 10),
              ],
              if (_rent) ...[
                const SizedBox(height: 4),
                Text(
                  'Rent wali gaari city rides / city to city nahi leti.',
                  style: AppType.small.copyWith(color: AppText.secondary),
                ),
              ],
              const Spacer(),
              UdButton.primary(
                label: 'Aagay',
                trailingIcon: Icons.chevron_right_rounded,
                onPressed: _choice.any ? _continue : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.blurb,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String blurb;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => UdListGroup(
        children: [
          UdListRow(
            title: title,
            subtitle: blurb,
            leading: UdIconTile(
              icon: icon,
              tone: selected ? UdIconTone.lime : UdIconTone.neutral,
            ),
            trailing: Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 26,
              color: selected ? AppColors.navy : AppText.caption,
            ),
            onTap: onTap,
          ),
        ],
      );
}
