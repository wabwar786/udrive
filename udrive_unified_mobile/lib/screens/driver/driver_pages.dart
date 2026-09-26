import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../data/models.dart';

// Three screens were here and all three were mock-ups that the real screens
// had already replaced:
//
//   DriverRequestsScreen   — read `controller.requests`, the dummy list.
//   DriverPackagesScreen   — dummy packages under a hardcoded "Views 248 ·
//                            Offers 12 · Bookings 5" for every package.
//   DriverEarningsScreen   — "PKR 42,850" over "17 trips" and "4.9" for every
//                            driver, three invented journeys, and a chart
//                            hand-painted from a fixed curve. It was also the
//                            last AppColors.inkDeep in the app.
//
// Each one shared a public class name with the real screen in its own file,
// which is an ambiguous import — main_shell was carrying
// `hide DriverEarningsScreen` to keep the build alive. That is gone with them.
//
// ActiveDriverTripScreen was here too. Hardcoded "18 min · 12.4 km", a Message
// button that opened nothing, an "I have arrived" button that notified
// nobody, and an emergency button whose entire behaviour was a snackbar
// reading "Driver safety alert demo activated". The real one is
// LiveTripNavigationScreen, reached from the driver dashboard.
//
// The older CreatePackageScreen was here, superseded by
// live_create_package_screen.dart.
//
// The mock DriverWalletScreen and DriverDocumentsScreen that used to sit here
// have been removed. The real screens live in driver_wallet_screen.dart and
// driver_documents_screen.dart.
//
// DriverReviewsScreen was here. It showed every driver the same invented
// "4.9" over "846 trips" and three fabricated passenger reviews. The real
// figures live on DriverEarningsScreen.

/// D-45 — which days, which hours, which areas.
///
/// Rendered by `main_shell`, so no `Scaffold` here.
class DriverAvailabilityScreen extends StatefulWidget {
  const DriverAvailabilityScreen({super.key});

  @override
  State<DriverAvailabilityScreen> createState() =>
      _DriverAvailabilityScreenState();
}

class _DriverAvailabilityScreenState extends State<DriverAvailabilityScreen> {
  final Set<int> selected = {1, 2, 3, 4, 5};
  bool nights = false;
  bool multi = true;

  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
        children: [
          Text(
            'Availability',
            style: AppType.h1.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 22),

          const UdSectionHeader(title: 'Available days'),
          const SizedBox(height: 12),
          // Was seven Material `FilterChip`s, which bring their own fill,
          // their own checkmark animation and their own type.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < 7; i++)
                UdChip(
                  label: _names[i],
                  selected: selected.contains(i + 1),
                  onTap: () => setState(() {
                    if (selected.contains(i + 1)) {
                      selected.remove(i + 1);
                    } else {
                      selected.add(i + 1);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 26),

          UdListGroup(
            children: [
              UdListRow(
                title: 'Night driving',
                trailing: UdSwitch(
                  value: nights,
                  onChanged: (value) => setState(() => nights = value),
                  semanticLabel: 'Night driving',
                ),
              ),
              UdListRow(
                title: 'Multi-day tours',
                trailing: UdSwitch(
                  value: multi,
                  onChanged: (value) => setState(() => multi = value),
                  semanticLabel: 'Multi-day tours',
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),

          const UdSectionHeader(title: 'Operating areas'),
          const SizedBox(height: 12),
          // The pencil that sat at the end of this row opened nothing. It is
          // a fact until the screen that edits it exists, so it reads as one.
          UdBanner(
            tone: UdTone.gray,
            icon: Icons.location_on_rounded,
            text: 'Islamabad · Rawalpindi · Muzaffarabad · Neelum Valley',
          ),
          const SizedBox(height: 26),

          UdButton.primary(
            label: context.tr('save'),
            icon: Icons.check_rounded,
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Availability saved.')),
            ),
          ),
        ],
      );
}

/// D-42 — who you are, and the five places the driver side keeps things.
///
/// Rendered by `main_shell`, so no `Scaffold` here.
class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({required this.onNavigate, super.key});

  final ValueChanged<String> onNavigate;

  /// The rows, in the order the artboard has them.
  static const _rows = <(String, IconData, String)>[
    ('vehicles', Icons.directions_car_filled_rounded, 'Vehicle registration'),
    ('documents', Icons.fact_check_rounded, 'Documents & verification'),
    ('availability', Icons.calendar_month_rounded, 'Availability'),
    ('reviews', Icons.star_rounded, 'Ratings & reviews'),
    ('settings', Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = AppControllerScope.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
      children: [
        UdCard(
          tone: UdCardTone.navy,
          child: Column(
            children: [
              UdAvatar(initials: _initials(c.currentUserName), size: 76),
              const SizedBox(height: 14),
              Text(
                c.currentUserName,
                textAlign: TextAlign.center,
                style: AppType.h2.copyWith(color: AppText.onInk),
              ),
              const SizedBox(height: 4),
              Text(
                c.currentUserPhone,
                style: AppType.small.copyWith(color: AppText.onInkMuted),
              ),
              const SizedBox(height: 14),
              UdBadge(
                label: c.driverVerificationStatus,
                tone: c.driverApproved ? UdTone.lime : UdTone.warn,
                icon: c.driverApproved
                    ? Icons.verified_rounded
                    : Icons.pending_actions_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        UdButton.outline(
          label: context.tr('switchCustomer'),
          icon: Icons.person_rounded,
          onPressed: () => c.switchMode(UserMode.customer),
        ),
        const SizedBox(height: 22),
        UdListGroup(
          children: [
            for (final (key, icon, label) in _rows)
              UdListRow(
                title: label,
                leading: UdIconTile(icon: icon),
                showChevron: true,
                onTap: () => onNavigate(key),
              ),
          ],
        ),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    final value = parts.map((part) => part[0].toUpperCase()).join();
    return value.isEmpty ? 'D' : value;
  }
}
