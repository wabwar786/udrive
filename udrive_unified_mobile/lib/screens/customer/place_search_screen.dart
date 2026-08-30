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
  });

  final String label;
  final LatLng? point;
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
    required this.pickupLabel,
    this.initialQuery = '',
    this.bias,
    this.onChooseOnMap,
    super.key,
  });

  final String title;
  final String pickupLabel;
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

  List<PlaceSuggestion> _results = const [];
  bool _searching = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
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

  void _pick(PlaceSuggestion place) {
    Navigator.pop(
      context,
      PlacePickResult(label: place.title, point: place.point),
    );
  }

  /// Lets the customer proceed with whatever they typed, even if no geocoder
  /// knows it. The booking flow resolves coordinates later, or falls back to
  /// the full route screen.
  void _useTyped() {
    final text = _query.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, PlacePickResult(label: text, point: null));
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

            // Both ends stay visible while typing, so the customer can see the
            // route they are building rather than one field in isolation.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
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
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'From',
                                style: TextStyle(
                                    fontSize: 11, color: AppText.disabled),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.pickupLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppText.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(height: 1, color: AppColors.border),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'To',
                                style: TextStyle(
                                    fontSize: 11, color: AppColors.secondary),
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
                                decoration: const InputDecoration(
                                  isDense: true,
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 4),
                                  hintText: 'Search any address or landmark',
                                  hintStyle: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppText.disabled,
                                  ),
                                ),
                              ),
                              Container(
                                height: 1.6,
                                color: AppColors.secondary,
                              ),
                            ],
                          ),
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
                  if (_searching)
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
