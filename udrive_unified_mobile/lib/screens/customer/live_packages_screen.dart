import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/vehicle_art.dart';
import '../../models/booking_models.dart';
import 'vehicle_live_map.dart';

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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          PremiumCard(
            color: const Color(0xFF0D4337),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.travel_explore_rounded, color: Colors.white, size: 34),
                const SizedBox(height: 12),
                Text(
                  _t(context, 'Verified Kashmir departures', 'تصدیق شدہ کشمیر ٹورز'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
                ),
                const SizedBox(height: 6),
                Text(
                  _t(context, 'Reserve seats for 10 minutes, book the complete vehicle, or send your own offer.', 'نشستیں 10 منٹ کے لیے محفوظ کریں، پوری گاڑی بک کریں یا اپنی آفر بھیجیں۔'),
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (controller.marketplaceBusy && packages.isEmpty)
            const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()))
          else if (packages.isEmpty)
            _empty(context)
          else
            ...packages.map((package) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _PackageCard(package: package, onTap: () => _openPackage(package)),
                )),
          if (controller.liveCustomerPackageOffers.isNotEmpty) ...[
            const SizedBox(height: 8),
            SectionHeader(title: _t(context, 'My package offers', 'میری پیکج آفرز')),
            const SizedBox(height: 8),
            ...controller.liveCustomerPackageOffers.map(
              (offer) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CustomerOfferCard(offer: offer, onConfirmed: _refresh),
              ),
            ),
          ],
          if (controller.liveCustomerPackageWaitlist.isNotEmpty) ...[
            const SizedBox(height: 8),
            SectionHeader(
              title: _t(context, 'My waiting list', 'میری ویٹنگ لسٹ'),
            ),
            const SizedBox(height: 8),
            ...controller.liveCustomerPackageWaitlist.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _WaitlistCard(entry: entry),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 65),
        child: Column(
          children: [
            const Icon(Icons.luggage_rounded, size: 68, color: AppColors.muted),
            const SizedBox(height: 14),
            Text(_t(context, 'No active packages yet', 'ابھی کوئی فعال پیکج نہیں'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
            const SizedBox(height: 8),
            Text(_t(context, 'Admin-approved Driver packages will appear here.', 'ایڈمن سے منظور شدہ ڈرائیور پیکجز یہاں نظر آئیں گے۔'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      );

  Future<void> _openPackage(LiveTourPackage package) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LivePackageDetailScreen(package: package)),
    );
    if (mounted) await _refresh();
  }

  String _t(BuildContext context, String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.package, required this.onTap});
  final LiveTourPackage package;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PremiumCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 150,
              child: Stack(fit: StackFit.expand, children: [
                VehicleBanner(
                  vehicleText: '${package.vehicle} ${package.title} ${package.registrationNumber}',
                  imageUrl: package.coverImageUrl,
                ),
                const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54]))),
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: package.bookableSeats <= 2 ? const Color(0xFFFFE9C7) : const Color(0xFFD9F8E9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${package.bookableSeats} seats free',
                      style: TextStyle(
                        color: package.bookableSeats <= 2 ? const Color(0xFF9A5A00) : const Color(0xFF087A4B),
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFFEAF7F2), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.trip_origin_rounded, size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(package.startingCity, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13))),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 7), child: Icon(Icons.arrow_forward_rounded, size: 17, color: AppColors.primaryDark)),
                      Expanded(child: Text(package.destination, textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w900, fontSize: 13.5))),
                      const SizedBox(width: 5),
                      const Icon(Icons.location_on_rounded, size: 16, color: AppColors.primary),
                    ]),
                  ),
                  const SizedBox(height: 9),
                  Text(package.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  if (package.vehicle.isNotEmpty || package.registrationNumber.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      [package.vehicle, package.registrationNumber].where((value) => value.trim().isNotEmpty).join(' · '),
                      style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _PackageFact(Icons.calendar_month_rounded, DateFormat('dd MMM yyyy').format(package.departureAt)),
                      _PackageFact(Icons.verified_user_rounded, package.driverName),
                      _PackageFact(Icons.shield_rounded, '${package.driverSafetyScore}/100'),
                    ],
                  ),
                  const Divider(height: 25),
                  Row(
                    children: [
                      Expanded(child: _Price(label: 'Per seat', value: package.pricePerSeat)),
                      Expanded(child: _Price(label: 'Whole vehicle', value: package.wholeVehiclePrice, alignEnd: true)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _CustomerOfferCard extends StatelessWidget {
  const _CustomerOfferCard({required this.offer, required this.onConfirmed});
  final LivePackageOffer offer;
  final Future<void> Function() onConfirmed;

  @override
  Widget build(BuildContext context) {
    final amount = offer.counterAmount ?? offer.offeredAmount;
    final confirmable = offer.status == 'Accepted' || offer.status == 'Countered';
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(offer.packageTitle, style: const TextStyle(fontWeight: FontWeight.w900))),
              StatusPill(label: offer.status),
            ],
          ),
          const SizedBox(height: 8),
          Text('${offer.bookingType} · ${offer.seatsRequested} seat(s)', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 8),
          Text('Final offer: PKR ${NumberFormat('#,###').format(amount)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
          if (confirmable) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _confirm(context),
              icon: const Icon(Icons.check_circle_rounded),
              label: const Text('Confirm negotiated package'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    try {
      final booking = await AppControllerScope.of(context).confirmLivePackageOffer(offerId: offer.id);
      await onConfirmed();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking ${booking.bookingReference} confirmed.')));
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _WaitlistCard extends StatelessWidget {
  const _WaitlistCard({required this.entry});

  final LivePackageWaitlist entry;

  @override
  Widget build(BuildContext context) => PremiumCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.hourglass_top_rounded,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.packageTitle,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.bookingType} · ${entry.seatsRequested} seat(s) · ${DateFormat('dd MMM').format(entry.departureAt)}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            StatusPill(label: entry.status, color: AppColors.warning),
          ],
        ),
      );
}

class LivePackageDetailScreen extends StatefulWidget {
  const LivePackageDetailScreen({
    required this.package,
    this.initialBookingType = 'PerSeat',
    super.key,
  });
  final LiveTourPackage package;
  final String initialBookingType;

  @override
  State<LivePackageDetailScreen> createState() => _LivePackageDetailScreenState();
}

class _LivePackageDetailScreenState extends State<LivePackageDetailScreen> {
  late String _bookingType;

  @override
  void initState() {
    super.initState();
    _bookingType = widget.initialBookingType == 'WholeVehicle'
        ? 'WholeVehicle'
        : 'PerSeat';
  }
  int _seats = 1;
  bool _busy = false;

  LiveTourPackage get package => widget.package;

  @override
  Widget build(BuildContext context) {
    final whole = _bookingType == 'WholeVehicle';
    final total = whole ? package.wholeVehiclePrice : package.pricePerSeat * _seats;
    final canHold = whole
        ? package.bookableSeats == package.totalSeats
        : package.bookableSeats >= _seats;
    return Scaffold(
      appBar: AppBar(title: Text(package.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 120),
        children: [
          VehicleLiveMap(package: package),
          const SizedBox(height: 16),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    VehicleThumb(
                      vehicleText: '${package.vehicle} ${package.title} ${package.registrationNumber}',
                      size: 58,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            package.vehicle.isEmpty ? package.title : package.vehicle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                          if (package.registrationNumber.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              package.registrationNumber,
                              style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22),
                Row(children: [Expanded(child: Text('${package.startingCity} → ${package.destination}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))), StatusPill(label: package.status)]),
                const SizedBox(height: 12),
                _Line(Icons.schedule_rounded, DateFormat('dd MMM yyyy · hh:mm a').format(package.departureAt)),
                _Line(Icons.directions_car_rounded, '${package.vehicle} · ${package.registrationNumber}'),
                _Line(Icons.verified_user_rounded, '${package.driverName} · ${package.driverRating.toStringAsFixed(1)}★'),
                _Line(Icons.shield_rounded, 'Safety ${package.driverSafetyScore}/100 · Vehicle readiness ${package.mountainReadinessScore}/100'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Choice(selected: !whole, title: 'Per seat', subtitle: 'PKR ${NumberFormat('#,###').format(package.pricePerSeat)}', onTap: () => setState(() => _bookingType = 'PerSeat'))),
              const SizedBox(width: 10),
              Expanded(child: _Choice(selected: whole, title: 'Whole vehicle', subtitle: 'PKR ${NumberFormat('#,###').format(package.wholeVehiclePrice)}', onTap: () => setState(() => _bookingType = 'WholeVehicle'))),
            ],
          ),
          if (!whole) ...[
            const SizedBox(height: 14),
            PremiumCard(
              child: Row(
                children: [
                  const Expanded(child: Text('Seats to reserve', style: TextStyle(fontWeight: FontWeight.w900))),
                  IconButton(onPressed: _seats > 1 ? () => setState(() => _seats--) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
                  Text('$_seats', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  IconButton(onPressed: _seats < package.bookableSeats ? () => setState(() => _seats++) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Included facilities', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 10),
                if (package.inclusions.isEmpty) const Text('Verified Driver · Route support · Trip safety tools') else ...package.inclusions.map((item) => Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(children: [const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success), const SizedBox(width: 8), Expanded(child: Text(item))]))),
                if (package.itinerary.isNotEmpty) ...[
                  const Divider(height: 26),
                  const Row(
                    children: [
                      Icon(Icons.alt_route_rounded, color: AppColors.primaryDark),
                      SizedBox(width: 8),
                      Text(
                        'Trip itinerary',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ItineraryTimeline(items: package.itinerary),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          PremiumCard(
            color: const Color(0xFFF1FAF6),
            child: Row(children: [const Icon(Icons.lock_clock_rounded, color: AppColors.primaryDark), const SizedBox(width: 10), Expanded(child: Text('Your selected inventory will be locked for 10 minutes before confirmation. Available now: ${package.bookableSeats} seats.', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark, height: 1.35)))]),
          ),
        ],
      ),
      bottomSheet: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          child: Row(
            children: [
              Expanded(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Total', style: TextStyle(color: AppColors.muted, fontSize: 11)), Text('PKR ${NumberFormat('#,###').format(total)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19))])),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton(onPressed: _busy ? null : (canHold ? _reserve : _joinWaitlist), child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(canHold ? 'Hold & confirm' : 'Join waiting list'))),
            ],
          ),
        ),
      ),
      floatingActionButton: package.customerOffersAllowed ? FloatingActionButton.extended(onPressed: _busy ? null : _sendOffer, icon: const Icon(Icons.local_offer_rounded), label: const Text('Make offer')) : null,
    );
  }

  Future<void> _reserve() async {
    setState(() => _busy = true);
    try {
      final controller = AppControllerScope.of(context);
      final passengers = await _collectPassengers(controller);
      if (passengers == null) return;
      final hold = await controller.acquireLivePackageHold(packageId: package.id, bookingType: _bookingType, seats: _bookingType == 'WholeVehicle' ? package.totalSeats : _seats);
      final booking = await controller.confirmLivePackageBooking(packageId: package.id, holdId: hold.holdId, advanceAmount: 0, passengers: passengers);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => AlertDialog(icon: const Icon(Icons.check_circle_rounded, size: 54, color: AppColors.success), title: const Text('Tour booked'), content: Text('Booking ${booking.bookingReference} is confirmed. Trip OTP: ${booking.tripOtp ?? '-'}'), actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))]));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
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
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add tour persons',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter one passenger name per line. Private contact details are never shown publicly.',
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: input,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Passenger names',
                prefixIcon: Icon(Icons.groups_rounded),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(sheetContext, true),
              icon: const Icon(Icons.verified_user_rounded),
              label: const Text('Continue securely'),
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
        SnackBar(
          content: Text(
            'Waiting list registered for ${entry.packageTitle}.',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOffer() async {
    final input = TextEditingController(text: (_bookingType == 'WholeVehicle' ? package.wholeVehiclePrice * .9 : package.pricePerSeat * _seats * .9).round().toString());
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (sheet) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(sheet).bottom + 20), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Send package offer', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)), const SizedBox(height: 14), TextField(controller: input, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Your total offer (PKR)', prefixIcon: Icon(Icons.payments_rounded))), const SizedBox(height: 16), FilledButton(onPressed: () async { try { await AppControllerScope.of(context).createLivePackageOffer(packageId: package.id, bookingType: _bookingType, seats: _bookingType == 'WholeVehicle' ? package.totalSeats : _seats, amount: double.parse(input.text), message: 'Customer tourism package offer'); if (!mounted) return; Navigator.pop(sheet); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer sent to Driver'))); } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); } }, child: const Text('Send offer'))])));
  }
}


class _ItineraryTimeline extends StatelessWidget {
  const _ItineraryTimeline({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
        children: items.asMap().entries.map((entry) {
          final parsed = _parse(entry.value);
          final last = entry.key == items.length - 1;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 30,
                  child: Column(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryDark,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${entry.key + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      if (!last)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: const Color(0xFFDCECE6),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(bottom: last ? 0 : 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F9F8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          parsed.$1,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
                        ),
                        if (parsed.$2.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            parsed.$2,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );

  (String, String) _parse(String raw) {
    final value = raw.trim().replaceFirst(RegExp(r'^\d+[.)-]?\s*'), '');
    for (final separator in const [' — ', ' - ', ': ']) {
      final index = value.indexOf(separator);
      if (index > 0 && index < value.length - separator.length) {
        return (
          value.substring(0, index).trim(),
          value.substring(index + separator.length).trim(),
        );
      }
    }
    final words = value.split(RegExp(r'\s+'));
    if (words.length > 8) {
      return (words.take(5).join(' '), words.skip(5).join(' '));
    }
    return (value, '');
  }
}

class _PackageFact extends StatelessWidget { const _PackageFact(this.icon, this.text); final IconData icon; final String text; @override Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: AppColors.muted), const SizedBox(width: 5), Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700))]); }
class _Price extends StatelessWidget { const _Price({required this.label, required this.value, this.alignEnd=false}); final String label; final double value; final bool alignEnd; @override Widget build(BuildContext context) => Column(crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)), Text('PKR ${NumberFormat('#,###').format(value)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))]); }
class _Line extends StatelessWidget { const _Line(this.icon,this.text); final IconData icon; final String text; @override Widget build(BuildContext context)=>Padding(padding: const EdgeInsets.only(top:8),child:Row(children:[Icon(icon,size:18,color:AppColors.muted),const SizedBox(width:8),Expanded(child:Text(text,style:const TextStyle(color:AppColors.muted,fontWeight:FontWeight.w600)))])); }
class _Choice extends StatelessWidget { const _Choice({required this.selected,required this.title,required this.subtitle,required this.onTap}); final bool selected; final String title; final String subtitle; final VoidCallback onTap; @override Widget build(BuildContext context)=>InkWell(onTap:onTap,borderRadius:BorderRadius.circular(20),child:Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:selected?AppColors.primary.withValues(alpha:.1):Colors.white,borderRadius:BorderRadius.circular(20),border:Border.all(color:selected?AppColors.primary:AppColors.border,width:selected?1.7:1)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:5),Text(subtitle,style:const TextStyle(color:AppColors.primaryDark,fontWeight:FontWeight.w800,fontSize:12))]))); }
