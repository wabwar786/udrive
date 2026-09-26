import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/booking_models.dart';
import 'live_create_package_screen.dart';

/// D-30 — the Driver's own tour packages, and the offers customers have made
/// on them.
///
/// Rendered by `main_shell`, so no `Scaffold` here.
class LiveDriverPackagesScreen extends StatefulWidget {
  const LiveDriverPackagesScreen({super.key});
  @override
  State<LiveDriverPackagesScreen> createState() =>
      _LiveDriverPackagesScreenState();
}

class _LiveDriverPackagesScreenState extends State<LiveDriverPackagesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() =>
      AppControllerScope.of(context).loadDriverMarketplace();

  @override
  Widget build(BuildContext context) {
    final c = AppControllerScope.of(context);

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
        children: [
          Text(
            _t(context, 'Packages', 'پیکجز'),
            style: AppType.h1.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 6),
          Text(
            _t(
                context,
                'Create packages, manage approvals, inventory and customer '
                    'offers.',
                'پیکجز بنائیں، منظوری، نشستیں اور کسٹمر آفرز منظم کریں۔'),
            style: AppType.body.copyWith(height: 1.45, color: AppText.secondary),
          ),
          const SizedBox(height: 18),
          UdButton.primary(
            label: _t(context, 'Create live tour package',
                'لائیو ٹور پیکج بنائیں'),
            icon: Icons.add_rounded,
            onPressed: () => _create(context),
          ),
          const SizedBox(height: 26),

          UdSectionHeader(
            title: _t(context, 'My live packages', 'میرے لائیو پیکجز'),
            caption: c.liveDriverPackages.isEmpty
                ? null
                : '${c.liveDriverPackages.length}',
          ),
          const SizedBox(height: 12),
          if (c.liveDriverPackages.isEmpty)
            UdEmptyState(
              icon: Icons.luggage_outlined,
              title: _t(context, 'No package yet', 'ابھی کوئی پیکج نہیں'),
              text: _t(
                  context,
                  'Create a package and submit it for Admin approval.',
                  'پیکج بنائیں اور ایڈمن منظوری کے لیے جمع کریں۔'),
            )
          else
            ...c.liveDriverPackages.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DriverPackageCard(package: p, onRefresh: _refresh),
              ),
            ),

          const SizedBox(height: 26),
          UdSectionHeader(
            title: _t(context, 'Customer package offers', 'کسٹمر پیکج آفرز'),
            caption: c.liveDriverPackageOffers.isEmpty
                ? null
                : '${c.liveDriverPackageOffers.length}',
          ),
          const SizedBox(height: 12),
          if (c.liveDriverPackageOffers.isEmpty)
            UdEmptyState(
              icon: Icons.local_offer_outlined,
              title: _t(context, 'No open offers', 'کوئی کھلی آفر نہیں'),
              text: _t(
                  context,
                  'Offers customers make on your packages appear here.',
                  'آپ کے پیکجز پر کسٹمر کی آفرز یہاں آئیں گی۔'),
            )
          else
            ...c.liveDriverPackageOffers.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _OfferCard(offer: o, onReviewed: _refresh),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LiveCreatePackageScreen()));
    if (mounted) await _refresh();
  }

  String _t(BuildContext context, String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

/// One package, with whatever it is waiting on.
class _DriverPackageCard extends StatelessWidget {
  const _DriverPackageCard({required this.package, required this.onRefresh});

  final LiveTourPackage package;
  final Future<void> Function() onRefresh;

  /// The status word and the badge behind it, from one place.
  ///
  /// "Pending approval" is amber and not grey on purpose: it is a state the
  /// Driver is waiting *in*, not one they have finished with.
  static (String, UdTone) _status(String raw) => switch (raw) {
        'Active' => ('Active', UdTone.ok),
        'Rejected' => ('Rejected', UdTone.err),
        'ChangesRequired' => ('Changes Required', UdTone.err),
        'PendingApproval' => ('Pending Approval', UdTone.warn),
        'Paused' => ('Paused', UdTone.gray),
        _ => (raw, UdTone.info),
      };

  @override
  Widget build(BuildContext context) {
    final (label, tone) = _status(package.status);
    final money = NumberFormat('#,###');
    final needsSubmit =
        const ['Draft', 'ChangesRequired', 'Rejected'].contains(package.status);

    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  package.title,
                  style: AppType.h3.copyWith(color: AppText.primary),
                ),
              ),
              const SizedBox(width: 10),
              UdBadge(label: label, tone: tone),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${package.startingCity} → ${package.destination}',
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _Fact(Icons.calendar_month_rounded,
                  DateFormat('d MMM yyyy').format(package.departureAt)),
              _Fact(Icons.event_seat_rounded,
                  '${package.availableSeats}/${package.totalSeats} available'),
              _Fact(Icons.payments_rounded,
                  'PKR ${money.format(package.pricePerSeat)}/seat'),
            ],
          ),

          // What the reviewer actually asked for, on a red banner. It used to
          // be one line of small red text under the facts, which is where a
          // caption goes, not an instruction.
          if (package.reviewNotes?.isNotEmpty == true) ...[
            const SizedBox(height: 14),
            UdBanner(
              tone: UdTone.err,
              icon: Icons.assignment_late_outlined,
              text: package.reviewNotes,
            ),
          ],

          if (needsSubmit) ...[
            const SizedBox(height: 16),
            UdButton.primary(
              label: 'Submit approval',
              icon: Icons.send_rounded,
              size: UdButtonSize.small,
              onPressed: () => _submit(context),
            ),
          ] else if (package.status == 'Active') ...[
            const SizedBox(height: 16),
            UdButton.outline(
              label: 'Pause',
              icon: Icons.pause_rounded,
              size: UdButtonSize.small,
              onPressed: () => _toggle(context, false),
            ),
          ] else if (package.status == 'Paused') ...[
            const SizedBox(height: 16),
            UdButton.primary(
              label: 'Activate',
              icon: Icons.play_arrow_rounded,
              size: UdButtonSize.small,
              onPressed: () => _toggle(context, true),
            ),
          ] else if (package.status == 'PendingApproval') ...[
            const SizedBox(height: 14),
            Text(
              'Admin review in progress',
              textAlign: TextAlign.center,
              style: AppType.small.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTint.warningText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    try {
      await AppControllerScope.of(context).submitLiveDriverPackage(package.id);
      await onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Package submitted for Admin approval.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _toggle(BuildContext context, bool active) async {
    try {
      await AppControllerScope.of(context)
          .toggleLiveDriverPackage(package.id, active);
      await onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

/// One customer's offer on one package.
class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.onReviewed});

  final LivePackageOffer offer;
  final Future<void> Function() onReviewed;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,###');
    final open = const ['Pending', 'Countered'].contains(offer.status);

    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  offer.packageTitle,
                  style: AppType.listTitle
                      .copyWith(fontSize: 16, color: AppText.primary),
                ),
              ),
              const SizedBox(width: 10),
              UdBadge(
                label: offer.status,
                tone: offer.status == 'Pending'
                    ? UdTone.warn
                    : offer.status == 'Countered'
                        ? UdTone.info
                        : UdTone.gray,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${offer.customerName} · ${offer.bookingType} · '
            '${offer.seatsRequested} seat(s)',
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 12),
          UdKeyValue(
            label: 'Customer offer',
            value: 'PKR ${money.format(offer.offeredAmount)}',
            showDivider: offer.counterAmount != null,
          ),
          if (offer.counterAmount != null)
            UdKeyValue(
              label: 'Your counter',
              value: 'PKR ${money.format(offer.counterAmount)}',
              showDivider: false,
            ),
          if (open) ...[
            const SizedBox(height: 16),
            UdButtonRow(
              children: [
                UdButton.outline(
                  label: 'Reject',
                  size: UdButtonSize.small,
                  onPressed: () => _review(context, 'reject'),
                ),
                UdButton.primary(
                  label: 'Accept',
                  size: UdButtonSize.small,
                  onPressed: () => _review(context, 'accept'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Was an unlabelled swap-arrows icon button squeezed beside the
            // other two. A third choice deserves a third label.
            UdButton.ghost(
              label: 'Counter with your own price',
              icon: Icons.swap_horiz_rounded,
              size: UdButtonSize.small,
              onPressed: () => _counter(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _review(BuildContext context, String decision,
      {double? counter}) async {
    try {
      await AppControllerScope.of(context).reviewLivePackageOffer(
          offerId: offer.id,
          decision: decision,
          counterAmount: counter,
          message: decision == 'counter' ? 'Driver counteroffer' : null);
      await onReviewed();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _counter(BuildContext context) async {
    final input = TextEditingController(
        text: (offer.offeredAmount * 1.1).round().toString());
    await showUdDialog<void>(
      context: context,
      title: 'Counteroffer',
      message: 'They offered PKR '
          '${NumberFormat('#,###').format(offer.offeredAmount)}.',
      content: UdTextField(
        controller: input,
        label: 'Counter amount (PKR)',
        icon: Icons.payments_rounded,
        keyboardType: TextInputType.number,
        autofocus: true,
      ),
      actions: [
        Builder(
          builder: (dialog) => UdButtonRow(
            children: [
              UdButton.outline(
                label: 'Cancel',
                onPressed: () => Navigator.pop(dialog),
              ),
              UdButton.primary(
                label: 'Send',
                onPressed: () async {
                  Navigator.pop(dialog);
                  await _review(context, 'counter',
                      counter: double.tryParse(input.text));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// An icon and a fact, for the row of three under a package title.
class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppText.caption),
          const SizedBox(width: 6),
          Text(
            text,
            style: AppType.small.copyWith(
              fontWeight: FontWeight.w700,
              color: AppText.secondary,
            ),
          ),
        ],
      );
}
