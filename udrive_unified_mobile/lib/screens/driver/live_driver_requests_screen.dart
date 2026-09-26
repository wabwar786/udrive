import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/booking_models.dart';

/// D-13 — the Driver's own queue of pending Customer requests.
///
/// The dashboard shows the handful that are live within a fifteen-second
/// window; this is the whole list, with no clock on it. Rendered by
/// `main_shell`, so no `Scaffold` here.
class LiveDriverRequestsScreen extends StatefulWidget {
  const LiveDriverRequestsScreen({super.key});

  @override
  State<LiveDriverRequestsScreen> createState() => _LiveDriverRequestsScreenState();
}

class _LiveDriverRequestsScreenState extends State<LiveDriverRequestsScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) =>
      AppControllerScope.of(context).loadDriverMarketplace(notify: !silent);

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final requests = controller.liveDriverRideRequests;
    final verifiedVehicles = controller.liveVehicles.where((vehicle) {
      final status = vehicle.status.trim().toLowerCase();
      return status == 'verified' || status == 'approved';
    }).toList(growable: false);

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 34),
        children: [
          UdSectionHeader(
            title: _t(context, 'Pending Customer requests',
                'زیر التوا کسٹمر درخواستیں'),
            caption: requests.isEmpty ? null : '${requests.length} live',
          ),
          const SizedBox(height: 4),
          Text(
            _t(context, 'Accept with your fare or reject from your own queue.',
                'اپنے کرایے کے ساتھ قبول کریں یا اپنی فہرست سے مسترد کریں۔'),
            style: AppType.small.copyWith(color: AppText.secondary),
          ),
          const SizedBox(height: 16),
          if (verifiedVehicles.isEmpty) ...[
            UdBanner(
              tone: UdTone.warn,
              icon: Icons.directions_car_outlined,
              text: _t(
                  context,
                  'Verify at least one vehicle before accepting requests.',
                  'درخواست قبول کرنے سے پہلے کم از کم ایک گاڑی کی تصدیق کروائیں۔'),
            ),
            const SizedBox(height: 16),
          ],
          if (requests.isEmpty)
            UdEmptyState(
              icon: Icons.inbox_rounded,
              title: _t(context, 'No pending request right now',
                  'اس وقت کوئی زیر التوا درخواست نہیں'),
              text: _t(
                  context,
                  'This screen refreshes automatically every 20 seconds.',
                  'یہ اسکرین ہر 20 سیکنڈ بعد خود ریفریش ہوتی ہے۔'),
              action: UdButton.outline(
                label: _t(context, 'Refresh now', 'ابھی ریفریش کریں'),
                icon: Icons.refresh_rounded,
                expand: false,
                onPressed: _refresh,
              ),
            )
          else
            ...requests.map(
              (request) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RequestCard(
                  request: request,
                  enabled: verifiedVehicles.isNotEmpty && !controller.marketplaceBusy,
                  onAccept: () => _showOffer(request, verifiedVehicles),
                  onReject: () => _rejectRequest(request),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showOffer(LiveRideRequest request, List<dynamic> vehicles) async {
    final suitable = vehicles.where((vehicle) => vehicle.passengerCapacity >= request.seatsRequested).toList();
    if (suitable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No verified vehicle has enough seats for this request.')),
      );
      return;
    }

    dynamic selectedVehicle = suitable.first;
    final amount = TextEditingController(text: request.customerOffer.round().toString());
    final eta = TextEditingController(text: '20');
    final message = TextEditingController();
    final money = NumberFormat('#,###');

    await showUdSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                _t(context, 'Accept & send fare', 'قبول کریں اور کرایہ بھیجیں'),
                style: AppType.h2.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 4),
              Text(
                '${request.customerName} · ${request.pickupLabel} → '
                '${request.destinationLabel}',
                style: AppType.small.copyWith(color: AppText.secondary),
              ),
              const SizedBox(height: 18),

              // Was a `DropdownButtonFormField`. With one eligible vehicle it
              // was a menu of one; with three it painted itself in Material's
              // colours over the sheet. Rows with a radio say the same thing
              // and stay inside this design.
              const UdLabel('Verified vehicle'),
              const SizedBox(height: 8),
              if (suitable.length == 1)
                UdBanner(
                  tone: UdTone.gray,
                  icon: Icons.directions_car_rounded,
                  text: '${suitable.first.make} ${suitable.first.model} · '
                      '${suitable.first.registrationNumber}',
                )
              else
                UdListGroup(
                  children: [
                    for (final vehicle in suitable)
                      UdListRow(
                        title: '${vehicle.make} ${vehicle.model}',
                        subtitle: '${vehicle.registrationNumber} · '
                            '${vehicle.passengerCapacity} seats',
                        leading: UdRadio(
                          selected: identical(vehicle, selectedVehicle),
                          onTap: () =>
                              setSheetState(() => selectedVehicle = vehicle),
                        ),
                        onTap: () =>
                            setSheetState(() => selectedVehicle = vehicle),
                      ),
                  ],
                ),
              const SizedBox(height: 16),

              UdTextField(
                controller: amount,
                label: 'Your fare (PKR)',
                icon: Icons.payments_rounded,
                keyboardType: TextInputType.number,
                // The floor is stated before the driver types, not after
                // the API refuses the offer. A driver who is told his number
                // is too low only once he has sent it learns to distrust the
                // screen, not the rule.
                helper: request.quotedMinimum == null
                    ? 'Customer offered PKR ${money.format(request.customerOffer)}'
                    : 'Customer offered PKR ${money.format(request.customerOffer)}'
                        ' · lowest allowed PKR '
                        '${money.format(request.quotedMinimum!)}',
              ),
              const SizedBox(height: 14),
              UdTextField(
                controller: eta,
                label: 'Pickup ETA (minutes)',
                icon: Icons.schedule_rounded,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              UdTextField(
                controller: message,
                label: 'Message',
                labelSuffix: '(optional)',
                icon: Icons.message_rounded,
                minLines: 2,
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              UdButton.primary(
                label: 'Accept & send offer',
                icon: Icons.check_circle_rounded,
                onPressed: () async {
                  final parsedAmount = double.tryParse(amount.text.trim());
                  if (parsedAmount == null || parsedAmount <= 0) return;

                  // The same floor the customer was held to.
                  //
                  // UDrive parts company with inDrive here on purpose: there
                  // a driver may undercut the customer's number, and what
                  // that produced in this market was drivers bidding below
                  // their own running costs.
                  final floor = request.quotedMinimum;
                  if (floor != null && parsedAmount < floor) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                        'The lowest fare for this trip is PKR '
                        '${money.format(floor)}.',
                      ),
                    ));
                    return;
                  }

                  try {
                    await AppControllerScope.of(context).submitLiveDriverOffer(
                      rideRequestId: request.id,
                      vehicleId: selectedVehicle.id as String,
                      amount: parsedAmount,
                      etaMinutes: int.tryParse(eta.text.trim()) ?? 20,
                      message: message.text.trim(),
                    );
                    if (!mounted) return;
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fare offer sent to Customer.')));
                  } catch (error) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rejectRequest(LiveRideRequest request) async {
    final confirmed = await showUdDialog<bool>(
      context: context,
      title: 'Reject this request?',
      message: 'It will be hidden only for your Driver account. Other Drivers '
          'may still respond.',
      actions: [
        Builder(
          builder: (dialogContext) => UdButtonRow(
            children: [
              UdButton.outline(
                label: 'Cancel',
                onPressed: () => Navigator.pop(dialogContext, false),
              ),
              UdButton(
                label: 'Reject',
                variant: UdButtonVariant.dangerSolid,
                onPressed: () => Navigator.pop(dialogContext, true),
              ),
            ],
          ),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    try {
      await AppControllerScope.of(context).rejectLiveDriverRequest(
        rideRequestId: request.id,
        reason: 'Driver rejected from live request list.',
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  String _t(BuildContext context, String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;
}

/// One queued request.
///
/// The two 35×32 icon squares it ended with — a red cross and a green tick —
/// were the whole decision, unlabelled, eight pixels apart. They are two
/// buttons that say what they do now.
class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.enabled,
    required this.onAccept,
    required this.onReject,
  });

  final LiveRideRequest request;
  final bool enabled;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => UdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                UdAvatar(initials: _initials(request.customerName), size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    request.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.listTitle
                        .copyWith(fontSize: 16, color: AppText.primary),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'PKR ${NumberFormat('#,###').format(request.customerOffer)}',
                  style: AppType.priceMd.copyWith(color: AppText.primary),
                ),
              ],
            ),
            const SizedBox(height: 14),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const UdRouteRail(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          request.pickupLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.listTitle.copyWith(
                              fontSize: 15.5, color: AppText.primary),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          request.destinationLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.listTitle.copyWith(
                              fontSize: 15.5, color: AppText.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${DateFormat('d MMM · h:mm a').format(request.pickupAt)} · '
              '${request.seatsRequested} passenger'
              '${request.seatsRequested == 1 ? '' : 's'}',
              style: AppType.small.copyWith(color: AppText.secondary),
            ),
            const SizedBox(height: 16),
            UdButtonRow(
              children: [
                UdButton.outline(
                  label: 'Reject',
                  size: UdButtonSize.small,
                  onPressed: enabled ? onReject : null,
                ),
                UdButton.primary(
                  label: 'Accept & send fare',
                  size: UdButtonSize.small,
                  onPressed: enabled ? onAccept : null,
                ),
              ],
            ),
          ],
        ),
      );

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).take(2);
    final value = parts.map((part) => part[0].toUpperCase()).join();
    return value.isEmpty ? 'CU' : value;
  }
}
