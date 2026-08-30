import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/services/place_search_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';

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

/// Full-screen address entry.
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

  Widget _endRow({
    required String caption,
    required bool editable,
    required String staticValue,
    required String hint,
    required VoidCallback onSwitch,
  }) {
    if (!editable) {
      return InkWell(
        onTap: onSwitch,
        child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              caption,
              style: const TextStyle(fontSize: 11, color: AppText.disabled),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    staticValue.isEmpty ? 'Tap to set' : staticValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: staticValue.isEmpty
                          ? AppText.disabled
                          : AppText.primary,
                    ),
                  ),
                ),
                const Icon(Icons.edit_rounded,
                    size: 15, color: AppText.disabled),
              ],
            ),
          ],
        ),
      ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption,
            style: const TextStyle(fontSize: 11, color: AppColors.secondary),
          ),
          TextField(
            controller: _query,
            focusNode: _focus,
            onChanged: _run,
            onSubmitted: (_) => _useTyped(),
            textInputAction: TextInputAction.search,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppText.disabled,
              ),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _query.clear();
                        _run('');
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: AppText.disabled,
                      tooltip: 'Clear',
                    ),
            ),
          ),
          Container(height: 1.6, color: AppColors.secondary),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typed = _query.text.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppText.primary,
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Both ends stay visible while typing, so the customer can see
            // the route they are building rather than one field in isolation.
            // Whichever end is being edited becomes the input; the other is
            // read-only but still tappable to switch.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Column(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: AppColors.secondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 1.5,
                          height: 34,
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          color: AppColors.border,
                        ),
                        Container(
                          width: 8,
                          height: 8,
                          color: AppText.primary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _endRow(
                          caption: 'From',
                          editable: _editingPickup,
                          staticValue: widget.pickupLabel,
                          hint: 'Search a pickup point',
                          onSwitch: () => _switchTo(true),
                        ),
                        Container(height: 1, color: AppColors.border),
                        _endRow(
                          caption: 'To',
                          editable: !_editingPickup,
                          staticValue: widget.destinationLabel,
                          hint: 'Search any address or landmark',
                          onSwitch: () => _switchTo(false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (_resolving)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 26),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (_searching)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 26),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),

                  ..._results.map(
                    (place) => _ResultRow(
                      title: place.title,
                      subtitle: place.subtitle,
                      onTap: () => _pick(place),
                    ),
                  ),

                  if (_searched && _results.isEmpty && !_searching)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      child: Column(
                        children: [
                          const Icon(Icons.search_off_rounded,
                              size: 28, color: AppText.disabled),
                          const SizedBox(height: 10),
                          Text(
                            'Nothing found for "$typed"',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppText.primary,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Small villages are often unmapped. Use the typed '
                            'name or pick the spot on the map.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: AppText.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_editingPickup)
                    _ActionRow(
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
                    ),

                  if (typed.isNotEmpty)
                    _ActionRow(
                      icon: Icons.edit_location_alt_outlined,
                      label: 'Use "$typed"',
                      onTap: _useTyped,
                    ),

                  if (widget.onChooseOnMap != null)
                    _ActionRow(
                      icon: Icons.map_outlined,
                      label: 'Choose on map',
                      onTap: () async {
                        final result = await widget.onChooseOnMap!();
                        if (result != null && context.mounted) {
                          Navigator.pop(context, result);
                        }
                      },
                    ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              children: [
                const Icon(Icons.place_outlined,
                    size: 20, color: AppText.secondary),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppText.primary,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppText.secondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.surfaceAlt),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.secondary),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
