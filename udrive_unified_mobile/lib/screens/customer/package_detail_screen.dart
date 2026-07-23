import 'package:flutter/material.dart';
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
  bool _favorite = false;
  late final TextEditingController _offer = TextEditingController(text: widget.package.price.toString());
  @override
  void dispose() {
    _offer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 300,
              pinned: true,
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(background: Stack(fit: StackFit.expand, children: [Image.asset(widget.package.image, fit: BoxFit.cover), const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black12, Colors.black54])))])),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 120),
              sliver: SliverList.list(children: [
                Row(children: [StatusPill(label: '${widget.package.days} days'), const SizedBox(width: 8), StatusPill(label: '${widget.package.rating} ★', color: AppColors.accent), const Spacer(), IconButton.filledTonal(
                  onPressed: () {
                    setState(() => _favorite = !_favorite);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_favorite ? 'Package saved to favourites.' : 'Package removed from favourites.')),
                    );
                  },
                  icon: Icon(_favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                )]),
                const SizedBox(height: 14),
                Text(widget.package.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.7)),
                const SizedBox(height: 8),
                Text(widget.package.route, style: const TextStyle(color: AppColors.muted, height: 1.4)),
                const SizedBox(height: 18),
                PremiumCard(child: Row(children: [const CircleAvatar(radius: 27, child: Icon(Icons.person_rounded)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.package.driver, style: const TextStyle(fontWeight: FontWeight.w900)), const Text('Verified tourism driver', style: TextStyle(color: AppColors.muted, fontSize: 12))])), const Icon(Icons.verified_rounded, color: AppColors.info)])),
                const SizedBox(height: 22),
                Text(widget.package.description, style: const TextStyle(height: 1.55, color: AppColors.muted)),
                const SizedBox(height: 22),
                SectionHeader(title: context.tr('included')),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: widget.package.inclusions.map((e) => Chip(avatar: const Icon(Icons.check_circle_rounded, size: 17, color: AppColors.success), label: Text(e))).toList()),
                const SizedBox(height: 22),
                SectionHeader(title: context.tr('itinerary')),
                const SizedBox(height: 10),
                ...widget.package.itinerary.asMap().entries.map((entry) => Padding(padding: const EdgeInsets.only(bottom: 12), child: PremiumCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 32, height: 32, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle), child: Center(child: Text('${entry.key + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)))), const SizedBox(width: 12), Expanded(child: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w800, height: 1.4)))])))),
                const SizedBox(height: 22),
                PremiumCard(color: const Color(0xFFF1FAF6), child: Column(children: [Row(children: [const Text('Listed price', style: TextStyle(fontWeight: FontWeight.w800)), const Spacer(), Text('PKR ${widget.package.price}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.primaryDark))]), if (widget.package.allowOffers) ...[const SizedBox(height: 14), TextField(controller: _offer, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('yourOffer'), prefixText: 'PKR '))]])),
              ]),
            ),
          ],
        ),
        bottomSheet: SafeArea(child: Container(padding: const EdgeInsets.fromLTRB(18, 10, 18, 14), decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))), child: Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => _message(context), icon: const Icon(Icons.chat_bubble_outline_rounded), label: const Text('Message'))), const SizedBox(width: 10), Expanded(flex: 2, child: FilledButton(onPressed: () => _book(context), child: Text(widget.package.allowOffers ? context.tr('sendOffer') : context.tr('bookNow'))))]))),
      );

  void _message(BuildContext context) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demo chat opened with the package driver.')));
  void _book(BuildContext context) => showDialog(context: context, builder: (_) => AlertDialog(icon: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 54), title: const Text('Package request sent'), content: Text('Your offer of PKR ${_offer.text} has been sent to ${widget.package.driver}.'), actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('done')))]));
}
