import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// The shared driver-offer card.
///
/// Used in two places by design: the on-demand Driver Offers screen and the
/// Tour Map offers list. On the tour list the left slot shows a non-interactive
/// capacity chip instead of a Decline button — pass [capacityChip] for that.
class RateDriverCard extends StatelessWidget {
  const RateDriverCard({
    required this.fareLabel,
    required this.driverName,
    required this.onAccept,
    this.etaLabel,
    this.rating,
    this.rideCount,
    this.vehicleLabel,
    this.plateLabel,
    this.photoUrl,
    this.verified = false,
    this.capacityChip,
    this.onDecline,
    this.declineLabel = 'Decline',
    this.acceptLabel = 'Accept',
    this.busy = false,
    this.footer,
    super.key,
  });

  final String fareLabel;
  final String? etaLabel;

  final String driverName;
  final double? rating;

  /// Completed trips. Reviews count is deliberately omitted — the API does not
  /// expose it yet, and inventing a number would be worse than leaving it out.
  final int? rideCount;
  final String? vehicleLabel;
  final String? plateLabel;
  final String? photoUrl;
  final bool verified;

  /// Tour list variant: replaces the Decline button with a static chip.
  final String? capacityChip;

  final VoidCallback? onDecline;
  final VoidCallback onAccept;
  final String declineLabel;
  final String acceptLabel;
  final bool busy;

  /// Optional extra row (e.g. a decision countdown) below the buttons.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.card),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Fare and ETA share a baseline.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  fareLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppText.primary,
                    height: 1.1,
                  ),
                ),
              ),
              if (etaLabel != null) ...[
                const SizedBox(width: 8),
                Text(
                  etaLabel!,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppText.secondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 11),

          // 2. Driver row.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DriverAvatar(name: driverName, photoUrl: photoUrl),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            driverName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: AppText.primary,
                            ),
                          ),
                        ),
                        if (verified) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.verified_rounded,
                              size: 15, color: AppColors.info),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (rating != null) ...[
                          const Icon(Icons.star_rounded,
                              size: 14, color: Color(0xFFF5B942)),
                          const SizedBox(width: 3),
                          Text(
                            rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppText.primary,
                            ),
                          ),
                        ],
                        if (rating != null && rideCount != null)
                          const Text(
                            '  ·  ',
                            style: TextStyle(
                                fontSize: 12, color: AppText.secondary),
                          ),
                        if (rideCount != null)
                          Text(
                            '$rideCount rides',
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: AppText.secondary,
                            ),
                          ),
                      ],
                    ),
                    if (vehicleLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        plateLabel == null || plateLabel!.isEmpty
                            ? vehicleLabel!
                            : '$vehicleLabel · $plateLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppText.secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. Action row. Accept is deliberately wider — it is the primary
          //    action, and a solid green fill is enough to signal that.
          Row(
            children: [
              Expanded(
                flex: 10,
                child: capacityChip != null
                    ? _CapacityChip(label: capacityChip!)
                    : _NeutralButton(
                        label: declineLabel,
                        onTap: busy ? null : onDecline,
                      ),
              ),
              const SizedBox(width: 9),
              Expanded(
                flex: 14,
                child: _AcceptButton(
                  label: acceptLabel,
                  busy: busy,
                  onTap: busy ? null : onAccept,
                ),
              ),
            ],
          ),
          if (footer != null) ...[
            const SizedBox(height: 9),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar({required this.name, this.photoUrl});

  final String name;
  final String? photoUrl;

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    if (parts.isEmpty) return 'D';
    return parts.map((part) => part[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    // The offers API does not return a driver photo yet, so initials are the
    // normal case rather than an error state.
    if (photoUrl == null || photoUrl!.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppTint.brand,
          shape: BoxShape.circle,
        ),
        child: Text(
          _initials,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
      );
    }

    return ClipOval(
      child: Image.network(
        photoUrl!,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) =>
            _DriverAvatar(name: name, photoUrl: null),
      ),
    );
  }
}

class _CapacityChip extends StatelessWidget {
  const _CapacityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTint.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppText.secondary,
        ),
      ),
    );
  }
}

class _NeutralButton extends StatelessWidget {
  const _NeutralButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Material(
        color: AppTint.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: onTap == null ? AppText.disabled : AppText.secondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AcceptButton extends StatelessWidget {
  const _AcceptButton({
    required this.label,
    required this.busy,
    this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Material(
        color: onTap == null && !busy
            ? AppColors.border
            : AppColors.secondary,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.navy,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
