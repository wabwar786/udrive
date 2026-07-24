import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models.dart';

class PackageDetailScreen extends StatefulWidget {
  const PackageDetailScreen({required this.package, super.key});
  final TourPackage package;

  @override
  State<PackageDetailScreen> createState() => _PackageDetailScreenState();
}

class _PackageDetailScreenState extends State<PackageDetailScreen> {
  BookingType _bookingType = BookingType.perSeat;
  bool _favorite = false;
  late final TextEditingController _offer;

  @override
  void initState() {
    super.initState();
    _offer = TextEditingController(text: (widget.package.pricePerSeat ?? widget.package.price).toString());
  }

  @override
  void dispose() {
    _offer.dispose();
    super.dispose();
  }

  int get _selectedPrice => _bookingType == BookingType.perSeat
      ? widget.package.pricePerSeat ?? widget.package.price
      : widget.package.wholeVehiclePrice ?? widget.package.price;

  void _selectType(BookingType value) {
    setState(() {
      _bookingType = value;
      _offer.text = _selectedPrice.toString();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: CustomScrollView(
          cacheExtent: 700,
          slivers: [
            SliverAppBar(
              expandedHeight: 300,
              pinned: true,
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(widget.package.image, fit: BoxFit.cover, cacheWidth: 900, filterQuality: FilterQuality.medium),
                    const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black12, Colors.black54]))),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 130),
              sliver: SliverList.list(
                children: [
                  Row(children: [StatusPill(label: '${widget.package.days} days'), const SizedBox(width: 8), StatusPill(label: '${widget.package.rating} ★', color: AppColors.accent), const SizedBox(width: 8), StatusPill(label: '${widget.package.safetyScore}/100', color: AppColors.success), const Spacer(), IconButton.filledTonal(onPressed: () { setState(() => _favorite = !_favorite); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_favorite ? 'Package saved to favourites.' : 'Package removed from favourites.'))); }, icon: Icon(_favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: _favorite ? AppColors.danger : null))]),
                  const SizedBox(height: 14),
                  Text(widget.package.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.7)),
                  const SizedBox(height: 8),
                  Text(widget.package.route, style: const TextStyle(color: AppColors.muted, height: 1.4)),
                  const SizedBox(height: 14),
                  PremiumCard(
                    color: const Color(0xFFF0FAF6),
                    child: Column(children: [
                      _DetailLine(icon: Icons.trip_origin_rounded, text: widget.package.pickupPoint),
                      _DetailLine(icon: Icons.schedule_rounded, text: '${widget.package.departureDate} · ${widget.package.departureTime}'),
                      _DetailLine(icon: Icons.event_seat_rounded, text: '${widget.package.availableSeats ?? widget.package.maxGuests} seats available'),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  PremiumCard(child: Row(children: [const CircleAvatar(radius: 27, child: Icon(Icons.person_rounded)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.package.driver, style: const TextStyle(fontWeight: FontWeight.w900)), const Text('Verified tourism driver', style: TextStyle(color: AppColors.muted, fontSize: 12))])), const Icon(Icons.verified_rounded, color: AppColors.info)])),
                  const SizedBox(height: 22),
                  Text(widget.package.description, style: const TextStyle(height: 1.55, color: AppColors.muted)),
                  const SizedBox(height: 20),
                  SectionHeader(title: context.tr('bookingOption')),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _BookingTypeCard(label: context.tr('perSeat'), amount: widget.package.pricePerSeat ?? widget.package.price, icon: Icons.event_seat_rounded, selected: _bookingType == BookingType.perSeat, onTap: () => _selectType(BookingType.perSeat))),
                    const SizedBox(width: 10),
                    Expanded(child: _BookingTypeCard(label: context.tr('wholeVehicle'), amount: widget.package.wholeVehiclePrice ?? widget.package.price, icon: Icons.directions_car_filled_rounded, selected: _bookingType == BookingType.wholeVehicle, onTap: () => _selectType(BookingType.wholeVehicle))),
                  ]),
                  const SizedBox(height: 22),
                  SectionHeader(title: context.tr('included')),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: widget.package.inclusions.map((item) => Chip(avatar: const Icon(Icons.check_circle_rounded, size: 17, color: AppColors.success), label: Text(item))).toList()),
                  if (widget.package.exclusions.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    SectionHeader(title: context.tr('exclusions')),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: widget.package.exclusions.map((item) => Chip(avatar: const Icon(Icons.remove_circle_outline_rounded, size: 17, color: AppColors.danger), label: Text(item))).toList()),
                  ],
                  const SizedBox(height: 18),
                  PremiumCard(
                    color: const Color(0xFFF1FAF6),
                    child: Column(
                      children: [
                        _DetailLine(icon: Icons.privacy_tip_rounded, text: widget.package.passengerPolicy),
                        _DetailLine(icon: Icons.luggage_rounded, text: widget.package.luggageAllowance),
                        _DetailLine(icon: Icons.event_available_rounded, text: widget.package.cancellationPolicy),
                        _DetailLine(icon: Icons.verified_user_rounded, text: widget.package.verifiedPassengers ? 'Verified passenger group and OTP trip start' : 'Passenger verification pending'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SectionHeader(title: context.tr('itinerary')),
                  const SizedBox(height: 10),
                  ...widget.package.itinerary.asMap().entries.map((entry) => Padding(padding: const EdgeInsets.only(bottom: 12), child: PremiumCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 32, height: 32, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle), child: Center(child: Text('${entry.key + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)))), const SizedBox(width: 12), Expanded(child: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w800, height: 1.4)))])))),
                  const SizedBox(height: 20),
                  PremiumCard(
                    color: const Color(0xFFF1FAF6),
                    child: Column(children: [
                      Row(children: [Text(_bookingType == BookingType.perSeat ? context.tr('seatFare') : context.tr('vehicleFare'), style: const TextStyle(fontWeight: FontWeight.w800)), const Spacer(), Text('PKR ${NumberFormat('#,###').format(_selectedPrice)}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.primaryDark))]),
                      if (widget.package.allowOffers) ...[const SizedBox(height: 14), TextField(controller: _offer, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('yourOffer'), prefixText: 'PKR '))],
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomSheet: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => _message(context), icon: const Icon(Icons.chat_bubble_outline_rounded), label: const Text('Message'))), const SizedBox(width: 10), Expanded(flex: 2, child: FilledButton(onPressed: () => _book(context), child: Text(widget.package.allowOffers ? context.tr('sendOffer') : context.tr('bookNow'))))]),
          ),
        ),
      );

  void _message(BuildContext context) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demo chat opened with the package driver.')));

  void _book(BuildContext context) => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 54),
          title: const Text('Package request sent'),
          content: Text('Your ${_bookingType == BookingType.perSeat ? 'seat' : 'whole vehicle'} offer of PKR ${_offer.text} has been sent to ${widget.package.driver}.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('done')))],
        ),
      );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Icon(icon, size: 18, color: AppColors.primaryDark), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)))]));
}

class _BookingTypeCard extends StatelessWidget {
  const _BookingTypeCard({required this.label, required this.amount, required this.icon, required this.selected, required this.onTap});
  final String label;
  final int amount;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: selected ? const Color(0xFFEAF8F2) : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.6 : 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: AppColors.primaryDark), const SizedBox(height: 11), Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)), const SizedBox(height: 3), Text('PKR ${NumberFormat('#,###').format(amount)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))]),
        ),
      );
}
