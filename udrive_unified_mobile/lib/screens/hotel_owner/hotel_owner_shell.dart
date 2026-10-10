import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/hotels/hotel_owner_repository.dart';
import '../../core/hotels/hotel_wallet_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../data/models.dart';
import '../feedback/feedback_center_screen.dart';
import 'hotel_owner_home.dart';
import 'hotel_owner_profile_screen.dart';
import 'hotel_wallet_screen.dart';
import 'hotel_wizard_screen.dart';

/// Hotel mode's own shell: Hotels, Add hotel, Profile.
///
/// `main_shell` hands the whole screen over to this when the mode is hotel.
///
/// There is always a way out. The bar has Back and Home on every tab; Back
/// (and the phone's back) goes to the Hotels tab, and from there asks which
/// mode to go to instead of closing the app. Home goes straight to the
/// customer's Home page. Leaving closes every hotel screen above the app's
/// root first — hotel mode used to be opened as a pushed page from driver
/// registration, and switching mode underneath it left that page on top with
/// no way off it.
class HotelOwnerShell extends StatefulWidget {
  const HotelOwnerShell({super.key});

  @override
  State<HotelOwnerShell> createState() => _HotelOwnerShellState();
}

class _HotelOwnerShellState extends State<HotelOwnerShell> {
  int _index = 0;

  /// Bumped after anything that changes the owner's hotels or profile, so the
  /// Hotels and Profile tabs reload.
  final ValueNotifier<int> _changed = ValueNotifier<int>(0);

  static const _titles = ['My hotels', 'Add hotel', 'Profile'];

  @override
  void dispose() {
    _changed.dispose();
    super.dispose();
  }

  void _back() {
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    _askToLeave();
  }

  Future<void> _askToLeave() async {
    final choice = await showUdSheet<UserMode>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Hotel mode se bahar jayein?',
              style: AppType.h3.copyWith(color: AppText.primary)),
          const SizedBox(height: 6),
          Text(
            'Aap ke hotels mehfooz rahenge — left menu → Hotel mode se wapis aa '
            'sakte hain.',
            style: AppType.body.copyWith(color: AppText.secondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          UdButton.primary(
            label: 'Customer mode',
            icon: Icons.person_rounded,
            onPressed: () => Navigator.pop(sheetContext, UserMode.customer),
          ),
          const SizedBox(height: 10),
          UdButton.outline(
            label: 'Driver mode',
            icon: Icons.drive_eta_rounded,
            onPressed: () => Navigator.pop(sheetContext, UserMode.driver),
          ),
          const SizedBox(height: 10),
          UdButton.soft(
            label: 'Yahin rahein',
            onPressed: () => Navigator.pop(sheetContext),
          ),
        ],
      ),
    );
    if (choice != null && mounted) leaveHotelMode(context, choice);
  }

  Future<void> _addHotel() async {
    await openHotelWizard(context);
    _changed.value++;
    if (mounted && _index != 0) setState(() => _index = 0);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: UdTopBar(
          title: _titles[_index],
          onBack: _back,
          actions: [
            UdIconButton(
              icon: Icons.home_rounded,
              tooltip: 'Customer Home',
              small: true,
              onPressed: () => leaveHotelMode(context, UserMode.customer),
            ),
          ],
        ),
        body: IndexedStack(
          index: _index == 2 ? 1 : 0,
          children: [
            HotelOwnerHotelsTab(changed: _changed),
            _OwnerProfileTab(
              changed: _changed,
              onHotels: () => setState(() => _index = 0),
            ),
          ],
        ),
        bottomNavigationBar: UdBottomNav(
          currentIndex: _index,
          onSelected: (value) {
            // "Add hotel" opens the wizard over the shell; the tab itself is
            // never a page of its own.
            if (value == 1) {
              _addHotel();
              return;
            }
            setState(() => _index = value);
          },
          destinations: const [
            UdNavDestination(
              icon: Icons.hotel_outlined,
              activeIcon: Icons.hotel_rounded,
              label: 'Hotels',
            ),
            UdNavDestination(
              icon: Icons.add_business_outlined,
              activeIcon: Icons.add_business_rounded,
              label: 'Add hotel',
            ),
            UdNavDestination(
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// Leaves hotel mode for [mode]. Customer mode always opens on Home.
///
/// Every route above the app's root is closed first, so nothing from hotel
/// mode is left on top of the mode the owner switched to.
void leaveHotelMode(BuildContext context, UserMode mode) {
  final controller = AppControllerScope.of(context);
  Navigator.of(context).popUntil((route) => route.isFirst);
  controller.switchMode(mode);
}

/// The Profile tab: who the owner is, their wallet, and how to leave.
class _OwnerProfileTab extends StatefulWidget {
  const _OwnerProfileTab({required this.changed, required this.onHotels});

  final ValueNotifier<int> changed;
  final VoidCallback onHotels;

  @override
  State<_OwnerProfileTab> createState() => _OwnerProfileTabState();
}

class _OwnerProfileTabState extends State<_OwnerProfileTab> {
  HotelOwnerHome? _home;
  HotelWallet? _wallet;

  @override
  void initState() {
    super.initState();
    widget.changed.addListener(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    widget.changed.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final api = AppControllerScope.of(context).apiClient;
    try {
      final results = await Future.wait<Object?>([
        HotelOwnerRepository(api).home(),
        HotelWalletRepository(api).load().then<Object?>((w) => w, onError: (_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _home = results[0] as HotelOwnerHome;
        _wallet = results[1] as HotelWallet?;
      });
    } catch (_) {
      // The tab still shows the switch buttons; the card fills in on the
      // next pull or the next change.
    }
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    widget.changed.value++;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final profile = _home?.profile;
    final name = (profile?.ownerName.isNotEmpty ?? false)
        ? profile!.ownerName
        : controller.currentUserName;
    final wallet = _wallet;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.navy,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
        children: [
          UdCard(
            tone: UdCardTone.navy,
            child: Column(
              children: [
                UdAvatar(initials: _initials(name), size: 64, lime: true),
                const SizedBox(height: 12),
                Text(name,
                    textAlign: TextAlign.center,
                    style: AppType.h2.copyWith(color: AppText.onInk)),
                const SizedBox(height: 4),
                Text(
                  [
                    if (profile?.businessName.isNotEmpty ?? false) profile!.businessName,
                    (profile?.phone.isNotEmpty ?? false)
                        ? profile!.phone
                        : controller.currentUserPhone,
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: AppType.small.copyWith(color: AppText.onInkMuted),
                ),
                const SizedBox(height: 10),
                if (profile != null) _VerificationBadge(profile: profile),
              ],
            ),
          ),
          const SizedBox(height: 16),
          UdListGroup(
            children: [
              UdListRow(
                title: profile?.complete == true ? 'Profile edit karein' : 'Owner profile banayein',
                subtitle: profile?.complete == true ? null : 'Hotel bhejne se pehle zaroori — CNIC ke saath',
                leading: const UdIconTile(icon: Icons.edit_outlined, size: UdIconTileSize.sm),
                showChevron: true,
                onTap: () => _push(const HotelOwnerProfileScreen()),
              ),
              UdListRow(
                title: 'Mere hotels',
                leading: const UdIconTile(icon: Icons.apartment_rounded, size: UdIconTileSize.sm),
                trailing: Text('${_home?.hotels.length ?? 0}',
                    style: AppType.listTitle.copyWith(color: AppText.secondary)),
                showChevron: true,
                onTap: widget.onHotels,
              ),
              UdListRow(
                title: 'Wallet',
                subtitle: wallet == null
                    ? null
                    : wallet.visible
                        ? 'Minimum ${Money.amount(wallet.minimumBalance)} — bookings chal rahi hain'
                        : 'Balance minimum ${Money.amount(wallet.minimumBalance)} se kam — bookings band',
                leading: UdIconTile(
                  icon: Icons.account_balance_wallet_outlined,
                  size: UdIconTileSize.sm,
                  tone: wallet != null && !wallet.visible ? UdIconTone.warn : UdIconTone.neutral,
                ),
                trailing: wallet == null
                    ? null
                    : Text(Money.amount(wallet.balance),
                        style: AppType.listTitle.copyWith(color: AppText.primary)),
                showChevron: true,
                onTap: () => _push(const HotelWalletScreen()),
              ),
              UdListRow(
                title: 'Help / Contact',
                leading: const UdIconTile(icon: Icons.support_agent_rounded, size: UdIconTileSize.sm),
                showChevron: true,
                onTap: () => _push(Builder(
                  builder: (pageContext) => Scaffold(
                    backgroundColor: AppColors.background,
                    appBar: UdTopBar(
                      title: 'Help / Contact',
                      onBack: () => Navigator.pop(pageContext),
                    ),
                    body: const FeedbackCenterScreen(),
                  ),
                )),
              ),
            ],
          ),
          const SizedBox(height: 20),
          UdButton.primary(
            label: 'Switch to Customer mode',
            icon: Icons.person_rounded,
            onPressed: () => leaveHotelMode(context, UserMode.customer),
          ),
          const SizedBox(height: 10),
          UdButton.outline(
            label: 'Switch to Driver mode',
            icon: Icons.drive_eta_rounded,
            onPressed: () => leaveHotelMode(context, UserMode.driver),
          ),
          const SizedBox(height: 8),
          UdButton.ghost(
            label: 'Logout',
            icon: Icons.logout_rounded,
            size: UdButtonSize.small,
            onPressed: _logout,
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final controller = AppControllerScope.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showUdDialog<bool>(
      context: context,
      title: 'Log out?',
      message: 'Dobara sign in ke liye phone number verify karna hoga.',
      actions: [
        Builder(
          builder: (dialogContext) => UdButton.outline(
            label: 'Signed in rahein',
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
        ),
        Builder(
          builder: (dialogContext) => UdButton(
            label: 'Log out',
            variant: UdButtonVariant.danger,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ),
      ],
    );
    if (confirmed != true) return;
    navigator.popUntil((route) => route.isFirst);
    await controller.switchMode(UserMode.customer);
    await controller.logout();
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).take(2);
    final value = parts.map((e) => e[0].toUpperCase()).join();
    return value.isEmpty ? 'H' : value;
  }
}

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.profile});

  final HotelOwnerProfile profile;

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = switch (profile.verificationStatus) {
      'Verified' => ('Verified owner', UdTone.lime, Icons.verified_rounded),
      'Pending' => ('Verification admin ke paas', UdTone.warn, Icons.hourglass_top_rounded),
      'Rejected' => ('Verification wapis — profile dekhein', UdTone.err, Icons.error_outline_rounded),
      _ => ('Profile adhoora', UdTone.gray, Icons.info_outline_rounded),
    };
    return UdBadge(label: label, tone: tone, icon: icon);
  }
}
