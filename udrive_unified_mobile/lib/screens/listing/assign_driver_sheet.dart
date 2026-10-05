import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/listings/listing_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// "Who will drive?" — the owner picks one of their own drivers.
///
/// Only an approved driver whose licence is still valid can be chosen; the
/// others are listed, greyed, with the reason, so the owner knows why a name
/// they expected cannot be tapped. Returns the chosen driver, or null.
Future<FleetDriver?> showAssignDriverSheet(
  BuildContext context, {
  required List<FleetDriver> drivers,
  required String title,
  String? subtitle,
  String? selectedId,
}) {
  return showUdSheet<FleetDriver>(
    context: context,
    builder: (sheetContext) => _AssignDriverBody(
      drivers: drivers,
      title: title,
      subtitle: subtitle,
      selectedId: selectedId,
    ),
  );
}

class _AssignDriverBody extends StatefulWidget {
  const _AssignDriverBody({
    required this.drivers,
    required this.title,
    required this.subtitle,
    required this.selectedId,
  });

  final List<FleetDriver> drivers;
  final String title;
  final String? subtitle;
  final String? selectedId;

  @override
  State<_AssignDriverBody> createState() => _AssignDriverBodyState();
}

class _AssignDriverBodyState extends State<_AssignDriverBody> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    final wanted = widget.selectedId;
    final valid = widget.drivers.where((d) => d.licenceValid).toList();
    if (wanted != null && valid.any((d) => d.id == wanted)) {
      _selected = wanted;
    } else if (valid.length == 1) {
      _selected = valid.first.id;
    }
  }

  /// The owner first, then valid drivers, then the ones that cannot be chosen.
  List<FleetDriver> get _ordered {
    final list = [...widget.drivers];
    int rank(FleetDriver d) => d.isOwner ? 0 : (d.licenceValid ? 1 : 2);
    list.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.name.compareTo(b.name);
    });
    return list;
  }

  static String _subtitle(FleetDriver d) {
    if (!d.licenceValid) {
      return d.status == 'Approved'
          ? 'Licence expired — cannot be chosen'
          : 'Not approved yet';
    }
    final expiry = d.licenceExpiry;
    if (expiry == null) return d.isOwner ? 'Licence valid' : 'Verified';
    final till = DateFormat('MMM yyyy').format(expiry);
    return d.isOwner
        ? 'Licence valid till $till'
        : 'Verified · licence valid till $till';
  }

  @override
  Widget build(BuildContext context) {
    final overline = AppType.caption.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      letterSpacing: .4,
      color: AppText.secondary,
    );
    FleetDriver? chosen;
    for (final d in widget.drivers) {
      if (d.id == _selected && d.licenceValid) chosen = d;
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(widget.title,
              style: AppType.h2.copyWith(color: AppText.primary)),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.subtitle!,
              style: AppType.small.copyWith(
                fontWeight: FontWeight.w600,
                color: AppText.secondary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('WHO WILL DRIVE?', style: overline),
          const SizedBox(height: 8),
          if (widget.drivers.isEmpty)
            const UdBanner(
              tone: UdTone.warn,
              icon: Icons.info_outline_rounded,
              text: 'No drivers yet. Add a driver from My vehicles first.',
            )
          else
            for (final d in _ordered) ...[
              _DriverRow(
                name: d.isOwner ? 'Me' : d.name,
                subtitle: _subtitle(d),
                enabled: d.licenceValid,
                selected: d.id == _selected,
                onTap: d.licenceValid
                    ? () => setState(() => _selected = d.id)
                    : null,
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 4),
          Text(
            'The customer sees this driver\'s name, photo and number. Only '
            'this driver\'s phone can start the trip.',
            style: AppType.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: AppText.secondary,
            ),
          ),
          const SizedBox(height: 16),
          UdButton.primary(
            label: 'Confirm driver',
            onPressed:
                chosen == null ? null : () => Navigator.pop(context, chosen),
          ),
        ],
      ),
    );
  }
}

class _DriverRow extends StatelessWidget {
  const _DriverRow({
    required this.name,
    required this.subtitle,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.background : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(16),
        side: BorderSide(
          color: selected ? AppColors.navy : AppColors.border,
          width: selected ? 2 : 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.listTitle.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: enabled ? AppText.primary : AppText.secondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppType.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? AppColors.brandInk
                              : AppTint.dangerText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (enabled)
                  UdRadio(
                    selected: selected,
                    onTap: onTap,
                    semanticLabel: name,
                  )
                else
                  const Icon(Icons.block_rounded,
                      size: 20, color: AppTint.dangerText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
