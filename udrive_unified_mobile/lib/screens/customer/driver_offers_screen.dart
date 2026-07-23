import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';

class DriverOffersScreen extends StatefulWidget {
  const DriverOffersScreen({required this.pickup, required this.destination, required this.customerOffer, required this.vehicle, super.key});
  final String pickup;
  final String destination;
  final int customerOffer;
  final VehicleCategory vehicle;
  @override
  State<DriverOffersScreen> createState() => _DriverOffersScreenState();
}

class _DriverOffersScreenState extends State<DriverOffersScreen> {
  final List<DriverOffer> _visible = [];
  DriverOffer? _selected;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    var index = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 850), (timer) {
      if (!mounted || index >= driverOffers.length) {
        timer.cancel();
        return;
      }
      setState(() => _visible.add(driverOffers[index++]));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('driverOffers'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
          children: [
            PremiumCard(
              color: const Color(0xFFF1FAF6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const StatusPill(label: 'Searching'), const Spacer(), const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))]),
                const SizedBox(height: 13),
                Text('${widget.pickup} → ${widget.destination}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 8),
                Row(children: [Icon(widget.vehicle.icon, size: 18, color: AppColors.primaryDark), Text('  ${widget.vehicle.name}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)), const Spacer(), Text('Your offer: PKR ${widget.customerOffer}', style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w900))]),
              ]),
            ),
            const SizedBox(height: 18),
            if (_visible.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 50), child: Center(child: Column(children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Finding verified nearby drivers…', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700))])))
            else
              ..._visible.map((offer) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _OfferCard(offer: offer, selected: _selected?.id == offer.id, onTap: () => setState(() => _selected = offer)),
                  )),
          ],
        ),
        bottomSheet: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
            child: FilledButton(onPressed: _selected == null ? null : _confirm, child: Text(context.tr('selectDriver'))),
          ),
        ),
      );

  void _confirm() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 78, height: 78, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .12), shape: BoxShape.circle), child: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 52)),
              const SizedBox(height: 18),
              const Text('Ride confirmed!', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('${_selected!.name} will arrive in ${_selected!.eta} minutes.', style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 18),
              const MapPreview(height: 190),
              const SizedBox(height: 18),
              PremiumCard(child: Row(children: [const CircleAvatar(radius: 25, child: Icon(Icons.person_rounded)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_selected!.name, style: const TextStyle(fontWeight: FontWeight.w900)), Text('${_selected!.vehicle} · ${_selected!.registration}', style: const TextStyle(color: AppColors.muted, fontSize: 12))])), Text('PKR ${_selected!.price}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))])),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.popUntil(context, (route) => route.isFirst), child: const Text('Track driver')),
            ]),
          ),
        ),
      );
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.selected, required this.onTap});
  final DriverOffer offer;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.8 : 1)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                CircleAvatar(radius: 27, backgroundColor: AppColors.primary.withValues(alpha: .12), child: Text(offer.name.substring(0, 1), style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w900, fontSize: 20))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Flexible(child: Text(offer.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))), if (offer.verified) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.verified_rounded, size: 18, color: AppColors.info))]), const SizedBox(height: 4), Text('${offer.vehicle} · ${offer.registration}', style: const TextStyle(color: AppColors.muted, fontSize: 12))])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('PKR ${offer.price}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primaryDark)), Text('${offer.eta} min away', style: const TextStyle(color: AppColors.muted, fontSize: 11))]),
              ]),
              const Divider(height: 26),
              Row(children: [const Icon(Icons.star_rounded, color: AppColors.accent, size: 18), Text(' ${offer.rating}', style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(width: 15), const Icon(Icons.route_rounded, color: AppColors.muted, size: 17), Text(' ${offer.trips} trips', style: const TextStyle(color: AppColors.muted, fontSize: 12)), const Spacer(), if (selected) const Icon(Icons.check_circle_rounded, color: AppColors.primary)]),
            ]),
          ),
        ),
      );
}
