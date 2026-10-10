import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/hotels/hotel_owner_repository.dart';
import '../../core/hotels/hotel_wallet_repository.dart';
import '../../core/network/api_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../common/hold_notice.dart';
import 'hotel_owner_profile_screen.dart';
import 'hotel_wallet_screen.dart';
import 'hotel_wizard_screen.dart';

/// The Hotels tab: the owner's hotels, to add and edit. Nothing else.
///
/// Bookings are not managed here — each one goes to the hotel's booking
/// WhatsApp number the moment it is made (HotelService.OwnerNoticeAsync).
/// A customer can book only while the wallet holds at least the minimum
/// balance, so a low wallet is the first thing on this page.
class HotelOwnerHotelsTab extends StatefulWidget {
  const HotelOwnerHotelsTab({required this.changed, super.key});

  /// Bumped by the shell after the wizard or profile closes.
  final ValueNotifier<int> changed;

  @override
  State<HotelOwnerHotelsTab> createState() => _HotelOwnerHotelsTabState();
}

class _HotelOwnerHotelsTabState extends State<HotelOwnerHotelsTab> {
  HotelOwnerHomeData? _data;
  String? _error;

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
      final home = await HotelOwnerRepository(api).home();
      HotelWallet? wallet;
      try {
        wallet = await HotelWalletRepository(api).load();
      } catch (_) {
        wallet = null;
      }
      if (!mounted) return;
      setState(() {
        _data = HotelOwnerHomeData(home, wallet);
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    widget.changed.value++;
  }

  Future<void> _wizard({String? hotelId}) async {
    await openHotelWizard(context, hotelId: hotelId);
    widget.changed.value++;
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
          : ListView(
              padding: const EdgeInsets.all(AppSizes.sidePadding),
              children: [
                UdEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Load nahi ho saka',
                  text: _error,
                  action: UdButton.outline(label: 'Dobara koshish', expand: false, onPressed: _load),
                ),
              ],
            );
    }

    final profile = data.home.profile;
    final hotels = data.home.hotels;
    final wallet = data.wallet;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.navy,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSizes.sidePadding, 10, AppSizes.sidePadding, 40),
        children: [
          if (wallet != null && !wallet.visible) ...[
            UdCard(
              tone: UdCardTone.flat,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTint.warningText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Wallet balance kam hai',
                            style: AppType.h3.copyWith(color: AppTint.warningText)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${Money.amount(wallet.balance)} / minimum ${Money.amount(wallet.minimumBalance)} — '
                    'jab tak top-up nahi, customers aap ka hotel book nahi kar sakte.',
                    style: AppType.small.copyWith(color: AppText.secondary, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  UdButton.primary(
                    label: 'Wallet top-up karein',
                    icon: Icons.account_balance_wallet_outlined,
                    size: UdButtonSize.small,
                    onPressed: () => _open(const HotelWalletScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!profile.complete) ...[
            UdCard(
              tone: UdCardTone.flat,
              selected: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Pehle apna owner profile banayein',
                      style: AppType.h3.copyWith(color: AppText.primary)),
                  const SizedBox(height: 4),
                  Text('2 minute — naam, business, number aur CNIC. Phir hotel admin ko bhej sakte hain.',
                      style: AppType.small.copyWith(color: AppText.secondary, height: 1.4)),
                  const SizedBox(height: 10),
                  UdButton.primary(
                    label: 'Profile banayein',
                    trailingIcon: Icons.arrow_forward_rounded,
                    size: UdButtonSize.small,
                    onPressed: () => _open(const HotelOwnerProfileScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (hotels.isEmpty)
            UdEmptyState(
              icon: Icons.apartment_outlined,
              title: 'Abhi koi hotel nahi',
              text: 'Apna hotel add karein — admin approve kare to customers ko dikhega, '
                  'aur har booking aap ke WhatsApp par aaye gi.',
              action: UdButton.primary(
                label: 'Hotel add karein',
                icon: Icons.add_business_rounded,
                expand: false,
                onPressed: () => _wizard(),
              ),
            )
          else
            for (final hotel in hotels) ...[
              _HotelCard(hotel: hotel, onEdit: () => _wizard(hotelId: hotel.id)),
              if (hotel.status == 'Approved')
                HoldNotice(
                  key: ValueKey('hold-${hotel.id}'),
                  kinds: const {'hotels'},
                  entityId: hotel.id,
                  padding: const EdgeInsets.only(bottom: 12),
                ),
            ],
        ],
      ),
    );
  }
}

class HotelOwnerHomeData {
  const HotelOwnerHomeData(this.home, this.wallet);

  final HotelOwnerHome home;
  final HotelWallet? wallet;
}

class _HotelCard extends StatelessWidget {
  const _HotelCard({required this.hotel, required this.onEdit});

  final OwnerHotelCard hotel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (hotel.status) {
      'Approved' => hotel.isActive ? ('Live', UdTone.lime) : ('Admin ne chhupaya', UdTone.gray),
      'Pending' => ('Admin review mein', UdTone.warn),
      'Rejected' => ('Wapis bheja', UdTone.err),
      _ => ('Draft', UdTone.gray),
    };
    final photo = ApiConfig.absoluteUrl(hotel.photoUrl);
    final place = [hotel.city, hotel.district].where((s) => s.isNotEmpty).join(', ');

    final String line = switch (hotel.status) {
      'Approved' => hotel.contactPhone.isEmpty
          ? 'Booking WhatsApp number add karein'
          : 'Bookings WhatsApp par aati hain · ${hotel.contactPhone}',
      'Pending' => 'Admin dekh raha hai — approve hote hi customers ko dikhega',
      'Rejected' => 'Wajah: ${hotel.rejectionReason ?? '—'}',
      _ => 'Adhoora — wahin se jari rakhein',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: UdCard(
        onTap: onEdit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: AppRadii.all(12),
                  child: SizedBox(
                    width: 64,
                    height: 56,
                    child: photo.isEmpty
                        ? const ColoredBox(
                            color: AppColors.surfaceAlt,
                            child: Icon(Icons.apartment_rounded, color: AppColors.navy),
                          )
                        : Image.network(
                            photo,
                            fit: BoxFit.cover,
                            cacheWidth: 200,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: AppColors.surfaceAlt,
                              child: Icon(Icons.apartment_rounded, color: AppColors.navy),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hotel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.listTitle.copyWith(
                              fontWeight: FontWeight.w800, color: AppText.primary)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          hotel.propertyType,
                          if (place.isNotEmpty) place,
                          '${hotel.roomTypes} room types',
                          '${hotel.photoCount} photos',
                        ].join(' · '),
                        maxLines: 2,
                        style: AppType.caption.copyWith(color: AppText.secondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                UdBadge(label: label, tone: tone),
              ],
            ),
            const SizedBox(height: 8),
            Text(line,
                style: AppType.small.copyWith(
                  color: hotel.status == 'Rejected' ? AppTint.dangerText : AppText.secondary,
                  height: 1.35,
                )),
            const SizedBox(height: 10),
            hotel.status == 'Rejected' || hotel.status == 'Draft'
                ? UdButton.outline(
                    label: hotel.status == 'Rejected' ? 'Theek kar ke dobara bhejein' : 'Jari rakhein',
                    size: UdButtonSize.small,
                    onPressed: onEdit,
                  )
                : UdButton.soft(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    size: UdButtonSize.small,
                    onPressed: onEdit,
                  ),
          ],
        ),
      ),
    );
  }
}
