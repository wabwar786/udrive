import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/services/place_search_service.dart';
import '../../core/places/place_name.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// What the search screen hands back when the customer picks somewhere.
class PlacePickResult {
  const PlacePickResult({
    required this.label,
    required this.point,
    this.useCurrentLocation = false,
    this.forPickup = false,
  });

  final String label;
  final LatLng? point;

  /// Set when the customer chose "Use my current location" rather than an
  /// address. The caller re-reads GPS instead of using [label].
  final bool useCurrentLocation;

  /// Which end the customer ended up choosing. They can switch ends inside the
  /// screen, so the caller cannot assume it got back what it asked for.
  final bool forPickup;
}

/// Full-screen address entry — screen C-02.
///
/// A dedicated screen rather than a dropdown squeezed between a text field and
/// a map: suggestions get room to breathe, and the keyboard does not cover the
/// results. "Choose on map" is deliberately part of the list — plenty of
/// villages in Neelum and Bagh are not named in any geocoder, and a customer who
/// cannot find their village must still be able to book.
class PlaceSearchScreen extends StatefulWidget {
  const PlaceSearchScreen({
    required this.title,
    required this.editingPickup,
    required this.pickupLabel,
    required this.destinationLabel,
    this.initialQuery = '',
    this.bias,
    this.onChooseOnMap,
    super.key,
  });

  final String title;

  /// Which end the customer is editing. The other end stays visible but
  /// static, so the route being built is always readable.
  final bool editingPickup;

  final String pickupLabel;
  final String destinationLabel;
  final String initialQuery;

  /// Biases results towards the customer, so "bazaar" finds the near one.
  final LatLng? bias;

  final Future<PlacePickResult?> Function()? onChooseOnMap;

  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  final _places = PlaceSearchService();
  late final TextEditingController _query =
      TextEditingController(text: widget.initialQuery);
  final _focus = FocusNode();

  /// Which end is being edited. Starts where the caller pointed it, but the
  /// customer can switch without leaving the screen — having to go back just to
  /// fix the other end is needless.
  late bool _editingPickup = widget.editingPickup;

  List<PlaceSuggestion> _results = const [];
  bool _searching = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      // Opening from a product tap carries the previous destination in. It is
      // selected rather than left after the cursor, so the first keystroke
      // replaces it — the customer tapping a product is starting again, and
      // clearing an old address by hand is the step this was meant to remove.
      final text = _query.text;
      if (text.isNotEmpty) {
        _query.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
      }
    });
    if (widget.initialQuery.trim().length >= 2) _run(widget.initialQuery);
  }

  @override
  void dispose() {
    _places.dispose();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _run(String value) {
    setState(() {
      _searching = value.trim().length >= 2;
      if (value.trim().length < 2) {
        _results = const [];
        _searched = false;
      }
    });
    _places.searchDebounced(
      value,
      bias: widget.bias,
      onResults: (results) {
        if (!mounted) return;
        setState(() {
          _results = results;
          _searching = false;
          _searched = true;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _searching = false;
          _searched = true;
        });
      },
    );
  }

  void _switchTo(bool pickup) {
    if (_editingPickup == pickup) return;
    setState(() {
      _editingPickup = pickup;
      _query.text = pickup
          ? widget.pickupLabel.trim()
          : widget.destinationLabel.trim();
      _results = const [];
      _searched = false;
    });
    _focus.requestFocus();
    if (_query.text.trim().length >= 2) _run(_query.text);
  }

  bool _resolving = false;

  /// Autocomplete predictions carry no coordinates, so a chosen one is looked
  /// up before returning. Without this the caller receives a name with no
  /// position and silently falls back to the slow route screen.
  Future<void> _pick(PlaceSuggestion place) async {
    if (_resolving) return;
    setState(() => _resolving = true);

    final resolved = await _places.resolve(place);
    if (!mounted) return;
    setState(() => _resolving = false);

    Navigator.pop(
      context,
      PlacePickResult(
        // Fall back to the name alone if the lookup failed: the customer can
        // still proceed, and the booking flow geocodes it again later.
        label: place.title,
        point: resolved?.point,
        forPickup: _editingPickup,
      ),
    );
  }

  /// Lets the customer proceed with whatever they typed, even if no geocoder
  /// knows it. The booking flow resolves coordinates later, or falls back to
  /// the full route screen.
  void _useTyped() {
    final text = _query.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(
      context,
      PlacePickResult(label: text, point: null, forPickup: _editingPickup),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typed = _query.text.trim();
    final busy = _resolving || _searching;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UdTopBar(
            title: widget.title,
            divider: true,
            onBack: () => Navigator.pop(context),
          ),

          // Both ends stay visible while typing, so the customer can see the
          // route they are building rather than one field in isolation.
          // Whichever end is being edited becomes the input; the other is
          // read-only but still tappable to switch.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSizes.sidePadding, 14, AppSizes.sidePadding, 6),
            child: UdCard(
              tone: UdCardTone.tint,
              radius: 18,
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(width: 22, child: UdRouteRail()),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _EndRow(
                            caption: 'From',
                            editable: _editingPickup,
                            // The place name, not the postal address.
                            //
                            // This showed "MV62+76W, Rd B, Margalla View Block
                            // B D-17, Islama…" — a Plus Code, three qualifiers
                            // and an ellipsis, in a row whose whole job is to
                            // confirm where the customer is standing. The home
                            // screen already shortened it; this screen did not.
                            staticValue: shortPlaceName(widget.pickupLabel),
                            hint: 'Search a pickup point',
                            controller: _query,
                            focusNode: _focus,
                            onChanged: _run,
                            onSubmitted: _useTyped,
                            onClear: () {
                              _query.clear();
                              _run('');
                            },
                            onSwitch: () => _switchTo(true),
                          ),
                          const SizedBox(height: 4),
                          _EndRow(
                            caption: 'To',
                            editable: !_editingPickup,
                            staticValue: widget.destinationLabel,
                            hint: 'Search any address or landmark',
                            controller: _query,
                            focusNode: _focus,
                            onChanged: _run,
                            onSubmitted: _useTyped,
                            onClear: () {
                              _query.clear();
                              _run('');
                            },
                            onSwitch: () => _switchTo(false),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.sidePadding, 8, AppSizes.sidePadding, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 26),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),

                if (_results.isNotEmpty) ...[
                  UdSectionHeader(
                    title: 'Results',
                    caption: _results.length == 1
                        ? '1 place'
                        : '${_results.length} places',
                  ),
                  const SizedBox(height: 10),
                  UdListGroup(
                    children: [
                      for (var i = 0; i < _results.length; i++)
                        UdListRow(
                          // The top match gets the lime tile. It is the one the
                          // geocoder is most confident about, and on a list of
                          // near-identical village names that is the only
                          // signal the customer has.
                          leading: UdIconTile(
                            icon: Icons.place_outlined,
                            tone: i == 0
                                ? UdIconTone.soft
                                : UdIconTone.neutral,
                            size: UdIconTileSize.sm,
                          ),
                          title: _results[i].title,
                          subtitle: _results[i].subtitle.isEmpty
                              ? null
                              : _results[i].subtitle,
                          onTap: () => _pick(_results[i]),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],

                if (_searched && _results.isEmpty && !_searching)
                  UdEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Nothing found for "$typed"',
                    text: 'Small villages are often unmapped. Use the typed '
                        'name or pick the spot on the map.',
                  ),

                // The ways forward when the list cannot help. A lime-tinted
                // group, because on this screen these are not a footnote —
                // for an unmapped village they are the whole route through.
                if (_actions(typed).isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: AppTint.success,
                      borderRadius: AppRadii.all(AppRadii.card),
                      border: Border.all(color: AppTint.successBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _actions(typed),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The action rows, in the order the design puts them: what the customer
  /// typed first, because that is the one they most often mean.
  List<Widget> _actions(String typed) {
    final rows = <Widget>[];

    void add(Widget row) {
      if (rows.isNotEmpty) {
        rows.add(const UdDashedDivider(color: AppTint.successBorder));
      }
      rows.add(row);
    }

    if (typed.isNotEmpty) {
      add(_ActionRow(
        icon: Icons.edit_location_alt_outlined,
        label: 'Use "$typed"',
        onTap: _useTyped,
      ));
    }

    if (_editingPickup) {
      add(_ActionRow(
        icon: Icons.my_location_rounded,
        label: 'Use my current location',
        onTap: () => Navigator.pop(
          context,
          const PlacePickResult(
            label: '',
            point: null,
            useCurrentLocation: true,
            forPickup: true,
          ),
        ),
      ));
    }

    if (widget.onChooseOnMap != null) {
      add(_ActionRow(
        icon: Icons.map_outlined,
        label: 'Choose on map',
        subtitle: 'Pin a spot with no address',
        onTap: () async {
          final result = await widget.onChooseOnMap!();
          if (result != null && mounted) {
            Navigator.pop(context, result);
          }
        },
      ));
    }

    return rows;
  }
}

/// One end of the route: either a static line you tap to switch to, or the
/// live field.
class _EndRow extends StatelessWidget {
  const _EndRow({
    required this.caption,
    required this.editable,
    required this.staticValue,
    required this.hint,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onSwitch,
  });

  final String caption;
  final bool editable;
  final String staticValue;
  final String hint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    if (!editable) {
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onSwitch,
          borderRadius: AppRadii.all(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  caption.toUpperCase(),
                  style: AppType.overline.copyWith(color: AppText.secondary),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        staticValue.isEmpty ? 'Tap to set' : staticValue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.listTitle.copyWith(
                          fontSize: 16.5,
                          color: staticValue.isEmpty
                              ? AppText.caption
                              : AppText.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit_outlined,
                        size: 18, color: AppText.secondary),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            caption.toUpperCase(),
            // The active end's key is lime ink, so which field the keyboard is
            // pointed at is readable without watching the cursor.
            style: AppType.overline.copyWith(color: AppColors.brandInk),
          ),
          const SizedBox(height: 6),
          Container(
            height: 52,
            padding: const EdgeInsets.only(left: 14, right: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: AppRadii.all(AppRadii.field),
              border: Border.all(color: AppColors.navy, width: 2),
              boxShadow: const [
                BoxShadow(color: AppColors.limeGlow, spreadRadius: 3),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    onSubmitted: (_) => onSubmitted(),
                    textInputAction: TextInputAction.search,
                    cursorColor: AppColors.navy,
                    style: AppType.listTitle.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: AppText.primary,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: hint,
                      hintStyle: AppType.body2.copyWith(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                        color: AppText.caption,
                      ),
                    ),
                  ),
                ),
                if (controller.text.isNotEmpty)
                  UdIconButton(
                    icon: Icons.close_rounded,
                    variant: UdIconButtonVariant.soft,
                    small: true,
                    tooltip: 'Clear',
                    onPressed: onClear,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A way forward that is not one of the search results.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.listRow),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 22, color: AppColors.brandInk),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.listTitle.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandInk,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.small.copyWith(
                            color: AppTint.successText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
