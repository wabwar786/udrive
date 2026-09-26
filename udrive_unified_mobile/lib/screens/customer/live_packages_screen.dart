import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ud_controls.dart';
import '../../core/widgets/ud_kit.dart';
import '../../core/widgets/vehicle_art.dart';
import '../../models/booking_models.dart';
import 'vehicle_live_map.dart';

final _money = NumberFormat('#,###');

String _pkr(num value) => 'PKR ${_money.format(value)}';

/// C-27 — the tour marketplace.
///
/// A bottom-nav tab root: `main_shell` supplies the top bar, so there is no
/// `Scaffold` and no app bar here.
class LivePackagesScreen extends StatefulWidget {
  const LivePackagesScreen({super.key});

  @override
  State<LivePackagesScreen> createState() => _LivePackagesScreenState();
}

class _LivePackagesScreenState extends State<LivePackagesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final controller = AppControllerScope.of(context);
    await controller.refreshPhase9Marketplace();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final packages = controller.liveMarketplacePackages;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 34),
        children: [
          UdCard(
            tone: UdCardTone.navy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const UdIconTile(
                  icon: Icons.travel_explore_rounded,
                  tone: UdIconTone.lime,
                ),
                const SizedBox(height: 14),
                Text(
                  _t(context, 'Verified Kashmir departures',
                      'تصدیق شدہ کشمیر ٹورز'),
                  style: AppType.h2.copyWith(color: AppText.onInk),
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    context,
                    'Reserve seats for 10 minutes, book the complete vehicle, '
                        'or send your own offer.',
                    'نشستیں 10 منٹ کے لیے محفوظ کریں، پوری گاڑی بک کریں یا اپنی آفر بھیجیں۔',
                  ),
                  // Was AppText.secondary — a grey picked for white pages,
                  // which on navy is about 2.3:1. This one is 10.8:1.
                  style: AppType.body2.copyWith(color: AppText.onInkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (controller.marketplaceBusy && packages.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 70),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.navy),
              ),
            )
          else if (packages.isEmpty)
            UdEmptyState(
              icon: Icons.luggage_rounded,
              title: _t(context, 'No active packages yet',
                  'ابھی کوئی فعال پیکج نہیں'),
              text: _t(
                context,
                'Admin-approved Driver packages will appear here.',
                'ایڈمن سے منظور شدہ ڈرائیور پیکجز یہاں نظر آئیں گے۔',
              ),
            )
          else
            for (final package in packages)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _PackageCard(
                  package: package,
                  onTap: () => _openPackage(package),
                ),
              ),
          if (controller.liveCustomerPackageOffers.isNotEmpty) ...[
            const SizedBox(height: 6),
            UdSectionHeader(
              title: _t(context, 'My package offers', 'میری پیکج آفرز'),
            ),
            const SizedBox(height: 12),
            for (final offer in controller.liveCustomerPackageOffers)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CustomerOfferCard(offer: offer, onConfirmed: _refresh),
              ),
          ],
          if (controller.liveCustomerPackageWaitlist.isNotEmpty) ...[
            const SizedBox(height: 6),
            UdSectionHeader(
              title: _t(context, 'My waiting list', 'میری ویٹنگ لسٹ'),
            ),
            const SizedBox(height: 12),
            for (final entry in controller.liveCustomerPackageWaitlist)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _WaitlistCard(entry: entry),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _openPackage(LiveTourPackage package) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LivePackageDetailScreen(package: package)),
    );
    if (mounted) await _refresh();
  }
}

String _t(BuildContext context, String en, String ur) =>
    AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

/// One marketplace package: a cover band, then the route and the two prices.
class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.package, required this.onTap});

  final LiveTourPackage package;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tight = package.bookableSeats <= 2;
    final vehicleLine = [package.vehicle, package.registrationNumber]
        .where((value) => value.trim().isNotEmpty)
        .join(' · ');

    return UdCard(
      tone: UdCardTone.raised,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppRadii.all(AppRadii.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 150,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VehicleBanner(
                    vehicleText:
                        '${package.vehicle} ${package.title} ${package.registrationNumber}',
                    imageUrl: package.coverImageUrl,
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: UdBadge(
                      label: '${package.bookableSeats} seats free',
                      tone: tight ? UdTone.warn : UdTone.ok,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RoutePill(
                    from: package.startingCity,
                    to: package.destination,
                    rating: package.destinationRating,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    package.title,
                    style: AppType.h3.copyWith(color: AppText.primary),
                  ),
                  if (vehicleLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            vehicleLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.small
                                .copyWith(color: AppText.secondary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _Stars(package.vehicleRating),
                      ],
                    ),
                  ],
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Fact(Icons.trip_origin_rounded, package.pickupPoint),
                      _Fact(
                        Icons.calendar_month_rounded,
                        DateFormat('dd MMM yyyy').format(package.departureAt),
                      ),
                      _Fact(
                        Icons.shield_rounded,
                        '${package.driverName} · '
                            '${package.driverSafetyScore}/100',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(
                      height: 1, thickness: 1, color: AppColors.border),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _Price(
                          label: 'Per seat',
                          value: package.pricePerSeat,
                        ),
                      ),
                      Expanded(
                        child: _Price(
                          label: 'Whole vehicle',
                          value: package.wholeVehiclePrice,
                          alignEnd: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `from → to` on a pale lime strip, with the destination's rating on the end.
class _RoutePill extends StatelessWidget {
  const _RoutePill({
    required this.from,
    required this.to,
    this.rating,
  });

  final String from;
  final String to;
  final double? rating;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.brandWash,
          borderRadius: AppRadii.all(AppRadii.row),
        ),
        child: Row(
          children: [
            const Icon(Icons.route_rounded, size: 17, color: AppColors.navy),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                from,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.small.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppText.primary,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.arrow_forward_rounded,
                  size: 16, color: AppColors.navy),
            ),
            Flexible(
              child: Text(
                to,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.small.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandInk,
                ),
              ),
            ),
            if (rating != null) ...[
              const SizedBox(width: 8),
              _Stars(rating!),
            ],
          ],
        ),
      );
}

/// A gold star and a rating to one decimal. Gold is this app's only use of
/// that hue, so a rating never has to be labelled.
class _Stars extends StatelessWidget {
  const _Stars(this.rating);

  final double rating;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 16, color: AppTint.star),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: AppType.caption.copyWith(
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
          ),
        ],
      );
}

/// An outlined pill carrying one fact about a package.
class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadii.all(AppRadii.chip),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppText.secondary),
            const SizedBox(width: 6),
            Text(
              text,
              style: AppType.caption.copyWith(color: AppText.primary),
            ),
          ],
        ),
      );
}

/// A label over a price. Deep lime, which is 7.9:1 on white — the lime itself
/// is 1.28:1 and cannot carry text.
class _Price extends StatelessWidget {
  const _Price({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final double value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 3),
          Text(
            _pkr(value),
            style: AppType.priceMd.copyWith(
              fontSize: 19,
              color: AppColors.brandInk,
            ),
          ),
        ],
      );
}

/// An offer this customer has sent, and its answer.
class _CustomerOfferCard extends StatelessWidget {
  const _CustomerOfferCard({required this.offer, required this.onConfirmed});

  final LivePackageOffer offer;
  final Future<void> Function() onConfirmed;

  @override
  Widget build(BuildContext context) {
    final amount = offer.counterAmount ?? offer.offeredAmount;
    final confirmable = offer.status == 'Accepted' || offer.status == 'Countered';

    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  offer.packageTitle,
                  style: AppType.h3.copyWith(color: AppText.primary),
                ),
              ),
              const SizedBox(width: 10),
              UdBadge(label: offer.status, tone: _statusTone(offer.status)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${offer.bookingType} · ${offer.seatsRequested} seat(s)',
            style: AppType.body2.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 10),
          Text(
            'Final offer: ${_pkr(amount)}',
            style: AppType.priceMd.copyWith(
              fontSize: 19,
              color: AppColors.brandInk,
            ),
          ),
          if (confirmable) ...[
            const SizedBox(height: 14),
            UdButton.primary(
              label: 'Confirm negotiated package',
              trailingIcon: Icons.check_circle_rounded,
              onPressed: () => _confirm(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    try {
      final booking = await AppControllerScope.of(context)
          .confirmLivePackageOffer(offerId: offer.id);
      await onConfirmed();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking ${booking.bookingReference} confirmed.')),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

UdTone _statusTone(String status) => switch (status) {
      'Accepted' || 'Confirmed' || 'Approved' => UdTone.ok,
      'Rejected' || 'Declined' || 'Cancelled' || 'Expired' => UdTone.err,
      'Countered' => UdTone.info,
      _ => UdTone.warn,
    };

/// A departure this customer is queued for.
class _WaitlistCard extends StatelessWidget {
  const _WaitlistCard({required this.entry});

  final LivePackageWaitlist entry;

  @override
  Widget build(BuildContext context) => UdCard(
        child: Row(
          children: [
            const UdIconTile(
              icon: Icons.hourglass_top_rounded,
              tone: UdIconTone.warn,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.packageTitle,
                    style: AppType.listTitle.copyWith(
                      fontSize: 16,
                      color: AppText.primary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${entry.bookingType} · ${entry.seatsRequested} seat(s) · '
                    '${DateFormat('dd MMM').format(entry.departureAt)}',
                    style: AppType.small.copyWith(color: AppText.secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            UdBadge(label: entry.status, tone: UdTone.warn),
          ],
        ),
      );
}

/// C-28 — one package, and the two ways to book it.
class LivePackageDetailScreen extends StatefulWidget {
  const LivePackageDetailScreen({
    required this.package,
    this.initialBookingType = 'PerSeat',
    super.key,
  });

  final LiveTourPackage package;
  final String initialBookingType;

  @override
  State<LivePackageDetailScreen> createState() =>
      _LivePackageDetailScreenState();
}

class _LivePackageDetailScreenState extends State<LivePackageDetailScreen> {
  late String _bookingType;
  int _seats = 1;
  bool _busy = false;

  LiveTourPackage get package => widget.package;

  @override
  void initState() {
    super.initState();
    _bookingType =
        widget.initialBookingType == 'WholeVehicle' ? 'WholeVehicle' : 'PerSeat';
  }

  @override
  Widget build(BuildContext context) {
    final whole = _bookingType == 'WholeVehicle';
    final total = whole ? package.wholeVehiclePrice : package.pricePerSeat * _seats;
    final canHold = whole
        ? package.bookableSeats == package.totalSeats
        : package.bookableSeats >= _seats;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(
        title: package.title,
        onBack: () => Navigator.maybePop(context),
        divider: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 14, AppSizes.sidePadding, 30),
        children: [
          VehicleLiveMap(package: package),
          const SizedBox(height: 16),
          _DetailCard(package: package),
          const SizedBox(height: 16),
          // IntrinsicHeight, and it is not optional. `stretch` makes the two
          // cards the same height whichever one has the longer label, but it
          // takes that height from the row's own constraints — and inside a
          // ListView those are unbounded. Debug trips an assert; release
          // strips asserts, the row becomes infinitely tall, and everything
          // below it is pushed past the end of the scroll view.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Choice(
                    selected: !whole,
                    title: 'Per seat',
                    subtitle: _pkr(package.pricePerSeat),
                    onTap: () => setState(() => _bookingType = 'PerSeat'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Choice(
                    selected: whole,
                    title: 'Whole vehicle',
                    subtitle: _pkr(package.wholeVehiclePrice),
                    onTap: () => setState(() => _bookingType = 'WholeVehicle'),
                  ),
                ),
              ],
            ),
          ),
          if (!whole) ...[
            const SizedBox(height: 14),
            UdStepper(
              label: 'Seats to reserve',
              value: _seats,
              min: 1,
              // The bound the code already enforced, kept exactly.
              max: package.bookableSeats < 1 ? 1 : package.bookableSeats,
              onChanged: (value) => setState(() => _seats = value),
            ),
          ],
          const SizedBox(height: 16),
          _FacilitiesCard(package: package),
          if (package.displayReviews.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ReviewsCard(reviews: package.displayReviews),
          ],
          const SizedBox(height: 16),
          UdBanner(
            tone: UdTone.info,
            icon: Icons.lock_clock_rounded,
            child: Text.rich(
              TextSpan(
                text: 'Your selected inventory will be locked for 10 minutes '
                    'before confirmation. Available now: ',
                children: [
                  TextSpan(
                    text: '${package.bookableSeats} seats',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
          if (package.customerOffersAllowed) ...[
            const SizedBox(height: 16),
            UdButton.dark(
              label: 'Make offer',
              icon: Icons.local_offer_rounded,
              onPressed: _busy ? null : _sendOffer,
            ),
          ],
        ],
      ),
      bottomNavigationBar: UdBottomBar(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total',
                      style: AppType.small.copyWith(color: AppText.secondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _pkr(total),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.priceMd.copyWith(color: AppText.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: UdButton.primary(
                  label: canHold ? 'Hold & confirm' : 'Join waiting list',
                  busy: _busy,
                  onPressed: canHold ? _reserve : _joinWaitlist,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _reserve() async {
    setState(() => _busy = true);
    try {
      final controller = AppControllerScope.of(context);
      final passengers = await _collectPassengers(controller);
      if (passengers == null) return;
      final hold = await controller.acquireLivePackageHold(
        packageId: package.id,
        bookingType: _bookingType,
        seats: _bookingType == 'WholeVehicle' ? package.totalSeats : _seats,
      );
      final booking = await controller.confirmLivePackageBooking(
        packageId: package.id,
        holdId: hold.holdId,
        advanceAmount: 0,
        passengers: passengers,
      );
      if (!mounted) return;
      await showUdDialog<void>(
        context: context,
        title: 'Tour booked',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Centred, not stretched: the dialog's content column is
            // `stretch`, which would hand a fixed-size tile a tight full-width
            // constraint and turn the 56px square into a 56px-tall band.
            const Center(
              child: UdIconTile(
                icon: Icons.check_circle_rounded,
                tone: UdIconTone.lime,
                size: UdIconTileSize.lg,
              ),
            ),
            const SizedBox(height: 16),
            UdKeyValue(label: 'Booking', value: booking.bookingReference),
            UdKeyValue(
              label: 'Trip OTP',
              value: booking.tripOtp ?? '-',
              showDivider: false,
            ),
          ],
        ),
        actions: [
          UdButton.primary(
            label: 'Done',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<Map<String, dynamic>>?> _collectPassengers(
    AppController controller,
  ) async {
    final expected = _bookingType == 'WholeVehicle' ? 1 : _seats;
    final input = TextEditingController(
      text: [
        controller.currentUserName,
        for (var index = 1; index < expected; index++)
          'Tour passenger ${index + 1}',
      ].join('\n'),
    );

    final accepted = await showUdSheet<bool>(
      context: context,
      builder: (sheetContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add tour persons',
              style: AppType.h2.copyWith(color: AppText.primary),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter one passenger name per line. Private contact details are '
              'never shown publicly.',
              style: AppType.body2.copyWith(color: AppText.secondary),
            ),
            const SizedBox(height: 18),
            UdTextField(
              controller: input,
              label: 'Passenger names',
              icon: Icons.groups_rounded,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 18),
            UdButton.primary(
              label: 'Continue securely',
              icon: Icons.verified_user_rounded,
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return null;

    final names = input.text
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (names.isEmpty) return null;

    return names
        .asMap()
        .entries
        .map(
          (entry) => <String, dynamic>{
            'fullName': entry.value,
            'gender': null,
            'ageGroup': entry.key == 0 ? 'Adult' : 'Unspecified',
            'phoneNumber': entry.key == 0 ? controller.currentUserPhone : null,
            'emergencyContact': entry.key == 0,
          },
        )
        .toList();
  }

  Future<void> _joinWaitlist() async {
    setState(() => _busy = true);
    try {
      final entry = await AppControllerScope.of(context).joinLivePackageWaitlist(
        packageId: package.id,
        bookingType: _bookingType,
        seats: _bookingType == 'WholeVehicle' ? package.totalSeats : _seats,
        notes: 'Notify me when this Kashmir departure has availability.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Waiting list registered for ${entry.packageTitle}.')),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOffer() async {
    final suggested = (_bookingType == 'WholeVehicle'
            ? package.wholeVehiclePrice * .9
            : package.pricePerSeat * _seats * .9)
        .round();
    final input = TextEditingController(text: '$suggested');

    await showUdSheet<void>(
      context: context,
      builder: (sheetContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Send package offer',
              style: AppType.h2.copyWith(color: AppText.primary),
            ),
            const SizedBox(height: 8),
            Text(
              'The Driver can accept your figure, answer with one of their '
              'own, or decline.',
              style: AppType.body2.copyWith(color: AppText.secondary),
            ),
            const SizedBox(height: 18),
            UdTextField(
              controller: input,
              label: 'Your total offer (PKR)',
              icon: Icons.payments_rounded,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 18),
            UdButton.primary(
              label: 'Send offer',
              onPressed: () => _submitOffer(sheetContext, input.text),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitOffer(BuildContext sheetContext, String raw) async {
    try {
      await AppControllerScope.of(context).createLivePackageOffer(
        packageId: package.id,
        bookingType: _bookingType,
        seats: _bookingType == 'WholeVehicle' ? package.totalSeats : _seats,
        amount: double.parse(raw),
        message: 'Customer tourism package offer',
      );
      if (!mounted) return;
      Navigator.pop(sheetContext);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offer sent to Driver')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

/// Vehicle, route, ratings, pickup point and the four detail lines.
class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.package});

  final LiveTourPackage package;

  @override
  Widget build(BuildContext context) => UdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                VehicleThumb(
                  vehicleText:
                      '${package.vehicle} ${package.title} ${package.registrationNumber}',
                  size: 56,
                  radius: AppRadii.tile,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        package.vehicle.isEmpty ? package.title : package.vehicle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.listTitle.copyWith(
                          fontSize: 16,
                          color: AppText.primary,
                        ),
                      ),
                      if (package.registrationNumber.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          package.registrationNumber,
                          style: AppType.small.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppText.secondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${package.startingCity} → ${package.destination}',
                    style: AppType.h3.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                UdBadge(
                  label: package.status,
                  tone: _statusTone(package.status),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _RatingPill(
                  label: 'Destination',
                  rating: package.destinationRating,
                  count: package.destinationReviewCount,
                ),
                _RatingPill(
                  label: 'Vehicle',
                  rating: package.vehicleRating,
                  count: package.vehicleReviewCount,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.brandWash,
                borderRadius: AppRadii.all(AppRadii.row),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.route_rounded,
                      size: 20, color: AppColors.navy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Pickup point',
                          style: AppType.small
                              .copyWith(color: AppText.secondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          package.pickupPoint,
                          style: AppType.listTitle.copyWith(
                            fontSize: 15.5,
                            color: AppText.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _Line(
              Icons.calendar_month_rounded,
              DateFormat('dd MMM yyyy · hh:mm a').format(package.departureAt),
            ),
            _Line(
              Icons.directions_car_rounded,
              '${package.vehicle} · ${package.registrationNumber}',
            ),
            _Line(
              Icons.verified_user_rounded,
              '${package.driverName} · ${package.driverRating.toStringAsFixed(1)}★',
            ),
            _Line(
              Icons.shield_rounded,
              'Safety ${package.driverSafetyScore}/100 · '
                  'Vehicle readiness ${package.mountainReadinessScore}/100',
            ),
          ],
        ),
      );
}

/// What the package includes, then its itinerary.
class _FacilitiesCard extends StatelessWidget {
  const _FacilitiesCard({required this.package});

  final LiveTourPackage package;

  @override
  Widget build(BuildContext context) {
    // Unchanged: the code's own fallback when a Driver listed nothing.
    final inclusions = package.inclusions.isEmpty
        ? const ['Verified Driver', 'Route support', 'Trip safety tools']
        : package.inclusions;

    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Included facilities',
            style: AppType.section.copyWith(
              fontSize: 17,
              color: AppText.primary,
            ),
          ),
          const SizedBox(height: 12),
          for (final item in inclusions)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 19, color: AppColors.brandInk),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: AppType.body2.copyWith(color: AppText.primary),
                    ),
                  ),
                ],
              ),
            ),
          if (package.itinerary.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.alt_route_rounded,
                    size: 20, color: AppColors.navy),
                const SizedBox(width: 9),
                Text(
                  'Trip itinerary',
                  style: AppType.section.copyWith(
                    fontSize: 17,
                    color: AppText.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            UdTimeline(
              steps: [
                for (final leg in package.itinerary) _parseLeg(leg),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Splits "1. Muzaffarabad pickup — hotel check-in" into a title and a
  /// subtitle. Unchanged from the version this replaces.
  static UdTimelineStep _parseLeg(String raw) {
    final value = raw.trim().replaceFirst(RegExp(r'^\d+[.)-]?\s*'), '');
    for (final separator in const [' — ', ' - ', ': ']) {
      final index = value.indexOf(separator);
      if (index > 0 && index < value.length - separator.length) {
        return UdTimelineStep(
          title: value.substring(0, index).trim(),
          subtitle: value.substring(index + separator.length).trim(),
        );
      }
    }
    final words = value.split(RegExp(r'\s+'));
    if (words.length > 8) {
      return UdTimelineStep(
        title: words.take(5).join(' '),
        subtitle: words.skip(5).join(' '),
      );
    }
    return UdTimelineStep(title: value);
  }
}

class _ReviewsCard extends StatelessWidget {
  const _ReviewsCard({required this.reviews});

  final List<String> reviews;

  @override
  Widget build(BuildContext context) => UdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reviews',
              style: AppType.section.copyWith(
                fontSize: 17,
                color: AppText.primary,
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < reviews.length; i++)
              Padding(
                padding:
                    EdgeInsets.only(bottom: i == reviews.length - 1 ? 0 : 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const UdIconTile(
                      icon: Icons.person_rounded,
                      tone: UdIconTone.navy,
                      size: UdIconTileSize.sm,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.star_rounded,
                                  size: 15, color: AppTint.star),
                              Icon(Icons.star_rounded,
                                  size: 15, color: AppTint.star),
                              Icon(Icons.star_rounded,
                                  size: 15, color: AppTint.star),
                              Icon(Icons.star_rounded,
                                  size: 15, color: AppTint.star),
                              Icon(Icons.star_rounded,
                                  size: 15, color: AppTint.star),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            reviews[i],
                            style: AppType.body2.copyWith(
                              fontSize: 14,
                              color: AppText.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

/// A gold-star rating chip: "Destination 4.9 · 128 reviews".
class _RatingPill extends StatelessWidget {
  const _RatingPill({
    required this.label,
    required this.rating,
    required this.count,
  });

  final String label;
  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadii.all(AppRadii.chip),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, size: 16, color: AppTint.star),
            const SizedBox(width: 6),
            Text(
              '$label ${rating.toStringAsFixed(1)} · $count reviews',
              style: AppType.caption.copyWith(color: AppText.primary),
            ),
          ],
        ),
      );
}

/// An icon and one line of package detail.
class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppText.secondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: AppType.body2.copyWith(color: AppText.primary),
              ),
            ),
          ],
        ),
      );
}

/// Per seat or whole vehicle. Selected takes `.card.sel` — a 2px navy border
/// and a pale lime fill, the same treatment every other choice in the app uses.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => UdCard(
        selected: selected,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: AppType.listTitle.copyWith(
                fontSize: 15.5,
                color: AppText.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: AppType.priceMd.copyWith(
                fontSize: 17,
                color: AppColors.brandInk,
              ),
            ),
          ],
        ),
      );
}
