import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';


/// A panel that sits collapsed at the bottom of a map and opens on a tap.
///
/// Both live screens — the customer watching a driver arrive and the driver
/// driving to a pickup — used to open with the panel already full height. That
/// covered most of the map, which is the one thing both of them are actually
/// watching: where the other person is, and how far off.
///
/// Collapsed it shows a single line and gently bounces, which is the only
/// reliable way to say "there is more here" without a label explaining itself.
/// The bounce stops once it has been opened: an animation that never settles is
/// a distraction, and after the first tap the person knows.
class CollapsibleMapSheet extends StatefulWidget {
  const CollapsibleMapSheet({
    required this.collapsed,
    required this.expanded,
    this.initiallyExpanded = false,
    super.key,
  });

  /// The one line shown while closed. Kept short — it is a handle, not a
  /// summary.
  final Widget collapsed;

  /// Everything, shown when open.
  final Widget expanded;

  /// Whether to start open. False on the live screens, where the map matters
  /// more than the detail at the moment it opens.
  final bool initiallyExpanded;

  @override
  State<CollapsibleMapSheet> createState() => _CollapsibleMapSheetState();
}

class _CollapsibleMapSheetState extends State<CollapsibleMapSheet>
    with SingleTickerProviderStateMixin {
  late bool _open = widget.initiallyExpanded;

  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// True until the sheet has been opened once.
  ///
  /// The bounce is an invitation, and an invitation that keeps arriving after
  /// it has been accepted is nagging.
  bool _everOpened = false;

  @override
  void initState() {
    super.initState();
    if (!_open) _bounce.repeat(reverse: true);
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  void _setOpen(bool open) {
    setState(() {
      _open = open;
      if (open) {
        _everOpened = true;
        _bounce.stop();
        _bounce.value = 0;
      } else if (!_everOpened) {
        _bounce.repeat(reverse: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: _open ? _openSheet() : _closedPill(),
    );
  }

  Widget _closedPill() {
    return AnimatedBuilder(
      animation: _bounce,
      // Six pixels. Enough to catch the eye at the edge of vision, small
      // enough not to look like something has gone wrong.
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -6 * _bounce.value),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(18),
          elevation: 6,
          shadowColor: AppTint.shadowSoft,
          child: InkWell(
            onTap: () => _setOpen(true),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
              child: Row(
                children: [
                  Expanded(child: widget.collapsed),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 22,
                    color: AppText.secondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _openSheet() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(22),
        elevation: 8,
        shadowColor: AppTint.shadow,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The way back down, in the corner where a close control is
            // expected. Without one the sheet can be opened and not shut, and
            // the map stays covered for the rest of the trip.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Row(
                children: [
                  Expanded(child: widget.collapsed),
                  IconButton(
                    onPressed: () => _setOpen(false),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppText.secondary,
                    tooltip: 'Show the map',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: widget.expanded,
            ),
          ],
        ),
      ),
    );
  }
}
