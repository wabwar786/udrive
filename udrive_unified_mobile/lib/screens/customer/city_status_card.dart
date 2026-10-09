import 'package:flutter/material.dart';

import '../../core/partner/partner_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// The card that appears on Home when UDrive is not running where you are.
///
/// It exists because of a gap that had been there from the beginning: the app
/// had no idea which city it was in. Somebody opening it in Rawalakot saw the
/// same home screen as somebody in Muzaffarabad, picked a destination, and
/// waited for a car in a city with no drivers.
///
/// Three decisions worth keeping:
///
/// **It appears only when there is something to say.** If the city is live, or
/// we cannot tell which city this is, this widget renders nothing at all and the
/// home screen is exactly as it was. A gate that fires when it is unsure is worse
/// than no gate — it tells people the service is unavailable in a city they are
/// not standing in.
///
/// **Registration stays open.** Nobody is locked out. The point of counting the
/// people waiting is that somebody who registered comes back on the day the city
/// opens; somebody turned away at the door does not.
class CityStatusCard extends StatefulWidget {
  const CityStatusCard({required this.status, this.onChanged, super.key});

  final CityStatus status;

  /// Called after the waiting-list switch is used, so the parent can refresh.
  final VoidCallback? onChanged;

  @override
  State<CityStatusCard> createState() => _CityStatusCardState();
}

class _CityStatusCardState extends State<CityStatusCard> {
  late bool _notify = widget.status.onWaitlist;
  bool _busy = false;
  String? _error;

  PartnerRepository get _partners =>
      PartnerRepository(AppControllerScope.of(context).apiClient);

  @override
  void didUpdateWidget(CityStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The switch has to follow the server's answer when it arrives.
    //
    // Home builds this card before the city lookup has returned, with the empty
    // status — so `_notify` is initialised to false. Without this, somebody
    // already on the waiting list would open the app and see the switch off, and
    // reasonably conclude they had been dropped from the list.
    //
    // Guarded on the value actually changing, so a rebuild in the middle of a
    // tap does not flick the switch back under the person's finger.
    if (!_busy && oldWidget.status.onWaitlist != widget.status.onWaitlist) {
      _notify = widget.status.onWaitlist;
    }
  }

  Future<void> _setNotify(bool value) async {
    final cityId = widget.status.cityId;
    if (cityId == null || _busy) return;

    setState(() {
      _notify = value;
      _busy = true;
      _error = null;
    });

    try {
      await _partners.waitlist(cityId, notify: value);
      widget.onChanged?.call();
    } on PartnerRefused catch (error) {
      if (!mounted) return;
      // Put the switch back. A switch that stays on while the server said no is
      // a promise the app cannot keep, and the person finds out on the day the
      // city opens and nothing arrives.
      setState(() {
        _notify = !value;
        _error = error.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    if (!status.shouldWarn) return const SizedBox.shrink();

    final live = status.cities.where((city) => city.isLive).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          UdCard(
            tone: UdCardTone.plain,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (status.cityName ?? '').toUpperCase(),
                  style: AppType.overline.copyWith(color: AppText.caption),
                ),
                const SizedBox(height: 8),
                Text(
                  'UDrive is not running here yet',
                  style: AppType.h3.copyWith(color: AppText.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  'You are registered. The day we start in '
                  '${status.cityName ?? 'your city'}, you will be among the first '
                  'to know.',
                  style: AppType.small.copyWith(
                    color: AppText.secondary,
                    height: 1.5,
                  ),
                ),
                if (status.waitingCount > 1) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${status.waitingCount} people here are waiting with you.',
                    style: AppType.small.copyWith(
                      color: AppColors.brandInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadii.all(AppRadii.row),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Tell me when it opens',
                              style: AppType.listTitle
                                  .copyWith(color: AppText.primary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'One message, on the day',
                              style: AppType.caption
                                  .copyWith(color: AppText.caption),
                            ),
                          ],
                        ),
                      ),
                      UdSwitch(
                        value: _notify,
                        onChanged: _busy ? null : _setNotify,
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: AppType.caption.copyWith(color: AppColors.danger),
                  ),
                ],
              ],
            ),
          ),
          if (live.isNotEmpty) ...[
            const SizedBox(height: 12),
            UdCard(
              tone: UdCardTone.tint,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'WHERE WE ARE RUNNING',
                    style: AppType.overline.copyWith(color: AppText.caption),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    live.map((city) => city.name).join(' · '),
                    style: AppType.body2.copyWith(
                      color: AppText.primary,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
