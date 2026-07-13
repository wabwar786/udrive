import 'package:flutter/material.dart';
import '../../core/localization/app_language.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dummy_data.dart';
import '../../models/models.dart';

class DriverOffersScreen extends StatefulWidget {
  const DriverOffersScreen({required this.customerOffer, super.key});
  final int customerOffer;
  @override
  State<DriverOffersScreen> createState() => _DriverOffersScreenState();
}

class _DriverOffersScreenState extends State<DriverOffersScreen> {
  DriverOffer? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context, 'offers'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 120),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.local_offer_outlined, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text('Your offer', style: const TextStyle(fontWeight: FontWeight.w800))),
                Text('PKR ${widget.customerOffer}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          ...driverOffers.map((offer) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _OfferCard(
              offer: offer,
              selected: _selected == offer,
              onTap: () => setState(() => _selected = offer),
            ),
          )),
        ],
      ),
      bottomSheet: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
          child: FilledButton(
            onPressed: _selected == null ? null : () => _showConfirmed(context, _selected!),
            child: Text(S.of(context, 'selectDriver')),
          ),
        ),
      ),
    );
  }

  void _showConfirmed(BuildContext context, DriverOffer offer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 74, height: 74, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .12), shape: BoxShape.circle), child: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 48)),
          const SizedBox(height: 18),
          Text(S.of(context, 'rideConfirmed'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('${offer.name} · ${offer.vehicle}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 8),
          Text('${offer.etaMinutes} min away · PKR ${offer.price}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 22),
          FilledButton(onPressed: () => Navigator.popUntil(context, (route) => route.isFirst), child: Text(S.of(context, 'driverArriving'))),
        ]),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.selected, required this.onTap});
  final DriverOffer offer; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(22), onTap: onTap,
    child: Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: selected ? AppColors.primary : const Color(0xFFE7ECF3), width: selected ? 2 : 1)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            CircleAvatar(radius: 27, backgroundColor: AppColors.primary.withValues(alpha: .12), child: Text(offer.name.substring(0, 1), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Flexible(child: Text(offer.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))), if (offer.verified) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.verified_rounded, size: 18, color: AppColors.secondary))]),
              const SizedBox(height: 4),
              Text(offer.vehicle, style: const TextStyle(color: AppColors.muted)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('PKR ${offer.price}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
              Text('${offer.etaMinutes} min', style: const TextStyle(color: AppColors.muted)),
            ]),
          ]),
          const Divider(height: 26),
          Row(children: [
            const Icon(Icons.star_rounded, color: AppColors.accent, size: 19), Text(' ${offer.rating}'),
            const SizedBox(width: 16), const Icon(Icons.route_rounded, size: 18, color: AppColors.muted), Text(' ${offer.trips} trips'),
            const Spacer(), if (selected) const Icon(Icons.check_circle_rounded, color: AppColors.primary),
          ]),
        ]),
      ),
    ),
  );
}
