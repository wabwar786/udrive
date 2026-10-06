import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/ud_kit.dart';

/// What a vehicle is being registered FOR, and the details each answer needs.
///
/// Held by the screen (it outlives rebuilds and owns the text controllers);
/// [VehicleUsePicker] draws it. Sent with the vehicle when it is created, and
/// turned into the vehicle's usage switches when UDrive verifies it.
class VehicleUses {
  bool city = true;
  bool intercity = false;
  bool tour = false;
  bool rent = false;

  /// 'Self', 'Drivers' or 'Both' — asked for rent and tours.
  String drivenBy = 'Self';

  final withDriver = TextEditingController();
  final selfDrive = TextEditingController();
  final pickup = TextEditingController();

  void dispose() {
    withDriver.dispose();
    selfDrive.dispose();
    pickup.dispose();
  }

  bool get any => city || intercity || tour || rent;

  /// Rent and tours ask who drives.
  bool get asksWhoDrives => rent || tour;

  double? _money(TextEditingController c) {
    final value = double.tryParse(c.text.trim().replaceAll(',', ''));
    return value == null || value <= 0 ? null : value;
  }

  /// A sentence for the driver, or null when everything needed is there.
  ///
  /// The same rules the server applies, so the driver hears them before
  /// pressing Save rather than after.
  String? problem() {
    if (!any) return 'Batayein yeh gaari kis ke liye register kar rahe hain.';
    if (rent && _money(withDriver) == null && _money(selfDrive) == null) {
      return 'Rent ke liye din ka kiraya likhein — driver ke saath, '
          'self-drive, ya dono.';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'wantsCity': city,
        'wantsIntercity': intercity,
        'wantsTour': tour,
        'wantsRent': rent,
        if (rent) 'rentWithDriverDaily': _money(withDriver),
        if (rent) 'rentSelfDriveDaily': _money(selfDrive),
        if (rent && pickup.text.trim().isNotEmpty)
          'rentPickupPoint': pickup.text.trim(),
        'drivenBy': asksWhoDrives ? drivenBy : 'Self',
      };
}

/// "Yeh gaari kis ke liye register kar rahe hain?" — four choices and the
/// details they need.
///
/// Rent and the two ride kinds exclude each other: a car out on rent is with
/// somebody else and cannot pick anyone up. Choosing one side clears the
/// other, and says so.
class VehicleUsePicker extends StatelessWidget {
  const VehicleUsePicker({
    required this.uses,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final VehicleUses uses;

  /// Called after [uses] has been changed, so the screen can rebuild.
  final VoidCallback onChanged;
  final bool enabled;

  static const _drivers = <(String, String)>[
    ('Self', 'Main khud'),
    ('Drivers', 'Mere drivers'),
    ('Both', 'Dono'),
  ];

  void _toggle(String which) {
    switch (which) {
      case 'city':
        uses.city = !uses.city;
        if (uses.city) uses.rent = false;
      case 'intercity':
        uses.intercity = !uses.intercity;
        if (uses.intercity) uses.rent = false;
      case 'tour':
        uses.tour = !uses.tour;
      case 'rent':
        uses.rent = !uses.rent;
        if (uses.rent) {
          uses.city = false;
          uses.intercity = false;
        }
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <(String, String, String, bool)>[
      ('city', 'City rides', 'Shehar ke andar', uses.city),
      ('intercity', 'City to city', 'Aik shehar se doosre', uses.intercity),
      ('tour', 'Tours', 'Packages aur tours', uses.tour),
      ('rent', 'Rent a car', 'Driver ke saath ya self-drive', uses.rent),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Yeh gaari kis ke liye register kar rahe hain?',
          style: AppType.h3.copyWith(color: AppText.primary),
        ),
        const SizedBox(height: 4),
        Text(
          'Aik ya zyada chunein. Har kaam ki UDrive commission aap ke wallet '
          'se katti hai.',
          style: AppType.small.copyWith(height: 1.45, color: AppText.secondary),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          children: [
            for (final (key, title, blurb, on) in tiles)
              _UseTile(
                title: title,
                blurb: blurb,
                selected: on,
                onTap: enabled ? () => _toggle(key) : null,
              ),
          ],
        ),
        if (uses.rent) ...[
          const SizedBox(height: 10),
          const UdBanner(
            tone: UdTone.info,
            icon: Icons.info_outline_rounded,
            text: 'Rent wali gaari city rides ya city to city nahi leti — '
                'woh customer ke paas hoti hai.',
          ),
          const SizedBox(height: 12),
          Text('Rent a car',
              style: AppType.listTitle.copyWith(color: AppText.primary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: UdTextField(
                  controller: uses.withDriver,
                  onChanged: (_) => onChanged(),
                  label: 'Driver ke saath / din',
                  hint: 'PKR',
                  keyboardType: TextInputType.number,
                  enabled: enabled,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: UdTextField(
                  controller: uses.selfDrive,
                  onChanged: (_) => onChanged(),
                  label: 'Self-drive / din',
                  hint: 'PKR',
                  keyboardType: TextInputType.number,
                  enabled: enabled,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          UdTextField(
            controller: uses.pickup,
            label: 'Pickup city',
            hint: 'Muzaffarabad',
            enabled: enabled,
          ),
          const SizedBox(height: 6),
          Text(
            'Jo kiraya khaali chhorein woh offer nahi hoga. Rent shuru karne '
            'se pehle gaari ki aik photo bhi chahiye (Vehicles mein).',
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
        ],
        if (uses.tour) ...[
          const SizedBox(height: 12),
          const UdBanner(
            tone: UdTone.gray,
            icon: Icons.landscape_rounded,
            text: 'Tours ke liye neeche gaari ka saaman (4×4, first aid, '
                'heater waghera) sahi bharein — us se gaari ki tour '
                'readiness banti hai.',
          ),
        ],
        if (uses.asksWhoDrives) ...[
          const SizedBox(height: 14),
          Text('Gaari kaun chalayega?',
              style: AppType.listTitle.copyWith(color: AppText.primary)),
          const SizedBox(height: 8),
          UdSegmented(
            options: [for (final (_, label) in _drivers) label],
            index: _drivers
                .indexWhere((entry) => entry.$1 == uses.drivenBy)
                .clamp(0, _drivers.length - 1),
            onChanged: (i) {
              if (!enabled) return;
              uses.drivenBy = _drivers[i].$1;
              onChanged();
            },
          ),
          if (uses.drivenBy != 'Self') ...[
            const SizedBox(height: 6),
            Text(
              'Aap ke drivers bhi apne phone se Driver mode mein register '
              'honge.',
              style: AppType.small.copyWith(color: AppText.secondary),
            ),
          ],
        ],
      ],
    );
  }
}

class _UseTile extends StatelessWidget {
  const _UseTile({
    required this.title,
    required this.blurb,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String blurb;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: title,
        child: Material(
          color: AppColors.surfaceHigh,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.all(AppRadii.tile),
            side: BorderSide(
              color: selected ? AppColors.navy : AppColors.border,
              width: 2,
            ),
          ),
          child: InkWell(
            borderRadius: AppRadii.all(AppRadii.tile),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: AppType.listTitle
                              .copyWith(fontSize: 14.5, color: AppText.primary),
                        ),
                      ),
                      Icon(
                        selected
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 22,
                        color: selected ? AppColors.navy : AppText.caption,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    blurb,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.small.copyWith(color: AppText.secondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
