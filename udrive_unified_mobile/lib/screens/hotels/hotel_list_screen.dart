import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format/money.dart';
import '../../core/hotels/hotel_repository.dart';
import '../../core/maps/ud_map.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/auth_models.dart';
import '../../models/hotel_models.dart';
import 'hotel_bits.dart';
import 'hotel_detail_screen.dart';
import 'hotel_search_screen.dart';
import 'hotel_stays_screen.dart';

/// Hotels — the list, led by photographs.
///
/// Deliberately not the Tours / Car rental shape: a hotel is chosen by how it
/// looks, so the screen is a two-column photo grid, the search sits at the top
/// in the navy header, and a floating Map button shows where they all are.
class HotelListScreen extends StatefulWidget {
  const HotelListScreen({
    this.destination,
    this.checkIn,
    this.checkOut,
    this.guests,
    this.rooms,
    super.key,
  });

  final String? destination;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int? guests;
  final int? rooms;

  @override
  State<HotelListScreen> createState() => _HotelListScreenState();
}

class _HotelListScreenState extends State<HotelListScreen> {
  late HotelQuery _query = _initialQuery();
  HotelRepository? _repo;
  bool _busy = true;
  String? _loadError;
  List<HotelSummary> _items = const [];

  /// Selected city tab, or null for All.
  String? _city;
  bool _transportOnly = false;

  HotelQuery _initialQuery() {
    final today = hotelDay(DateTime.now());
    final checkIn = hotelDay(widget.checkIn ?? today.add(const Duration(days: 1)));
    var checkOut =
        hotelDay(widget.checkOut ?? checkIn.add(const Duration(days: 1)));
    if (!checkOut.isAfter(checkIn)) {
      checkOut = checkIn.add(const Duration(days: 1));
    }
    return HotelQuery(
      query: widget.destination?.trim() ?? '',
      checkIn: checkIn,
      checkOut: checkOut,
      guests: widget.guests ?? 2,
      rooms: widget.rooms ?? 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo != null) return;
    _repo = HotelRepository(AppControllerScope.of(context).apiClient);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null || !mounted) return;
    setState(() {
      _busy = true;
      _loadError = null;
    });
    try {
      final loaded = await repo.search(
        query: _query.query,
        checkIn: _query.checkIn,
        checkOut: _query.checkOut,
        guests: _query.guests,
        rooms: _query.rooms,
      );
      if (!mounted) return;
      setState(() {
        _items = loaded;
        if (_city != null && !_cities.contains(_city)) _city = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loadError = error is ApiException
            ? error.message
            : 'Hotels could not be loaded just now. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> get _cities {
    final seen = <String>{};
    final out = <String>[];
    for (final hotel in _items) {
      final city = hotel.city.trim();
      if (city.isEmpty || !seen.add(city.toLowerCase())) continue;
      out.add(city);
    }
    return out;
  }

  List<HotelSummary> get _shown => _items
      .where((h) =>
          _city == null || h.city.trim().toLowerCase() == _city!.toLowerCase())
      .where((h) => !_transportOnly || h.transportAvailable)
      .toList(growable: false);

  Future<void> _openSearch() async {
    final result = await Navigator.push<HotelQuery>(
      context,
      MaterialPageRoute(
        builder: (_) => HotelSearchScreen(initial: _query, cities: _cities),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _query = result;
      _city = null;
    });
    await _load();
  }

  Future<void> _openHotel(HotelSummary hotel) async {
    final changed = await Navigator.push<HotelQuery>(
      context,
      MaterialPageRoute(
        builder: (_) => HotelDetailScreen(
          hotel: hotel,
          checkIn: _query.checkIn,
          checkOut: _query.checkOut,
          guests: _query.guests,
          rooms: _query.rooms,
        ),
      ),
    );
    // The stay was changed on the hotel's page; the list follows it.
    if (changed != null && mounted) {
      setState(() => _query = changed.copyWith(query: _query.query));
      await _load();
    }
  }

  void _openStays() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HotelStaysScreen()),
      );

  void _openMap(List<HotelSummary> hotels) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _HotelsMapScreen(
            hotels: hotels,
            onOpen: (hotel) {
              Navigator.pop(context);
              _openHotel(hotel);
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final cities = _cities;
    final mappable =
        shown.where((h) => h.latitude != 0 || h.longitude != 0).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              _Header(
                place: _query.query.isEmpty ? 'Anywhere' : _query.query,
                summary: _query.summary,
                onSearch: _openSearch,
                onStays: _openStays,
              ),
              const SizedBox(height: 34),
              _CityTabs(
                cities: cities,
                selected: _city,
                onChanged: (city) => setState(() => _city = city),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _busy
                            ? 'Looking for rooms…'
                            : '${shown.length} '
                                '${shown.length == 1 ? 'hotel' : 'hotels'} '
                                'with rooms free',
                        style: AppType.small.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppText.secondary,
                        ),
                      ),
                    ),
                    _ToggleChip(
                      label: 'Pickup transport',
                      selected: _transportOnly,
                      onTap: () =>
                          setState(() => _transportOnly = !_transportOnly),
                    ),
                  ],
                ),
              ),
              Expanded(child: _body(shown)),
            ],
          ),
          if (!_busy && mappable.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: SafeArea(
                top: false,
                child: Center(
                  child: Material(
                    color: AppColors.navy,
                    elevation: 6,
                    shadowColor: AppColors.navy.withValues(alpha: .4),
                    borderRadius: AppRadii.all(26),
                    child: InkWell(
                      onTap: () => _openMap(mappable),
                      borderRadius: AppRadii.all(26),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: SizedBox(
                          height: 52,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.map_rounded,
                                  size: 19, color: AppColors.brand),
                              const SizedBox(width: 8),
                              Text(
                                'Map',
                                style: AppType.small.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppText.onInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(List<HotelSummary> shown) {
    if (_busy) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.navy),
      );
    }
    if (_loadError != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
        children: [
          UdEmptyState(
            icon: Icons.cloud_off_rounded,
            tone: UdTone.err,
            title: 'Could not load hotels',
            text: _loadError,
            action: UdButton.outline(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              expand: false,
              onPressed: _load,
            ),
          ),
        ],
      );
    }
    if (shown.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
        children: [
          UdEmptyState(
            icon: Icons.hotel_rounded,
            title: 'No rooms free here',
            text: 'Try other dates, another place, or turn off the filters.',
            action: UdButton.outline(
              label: 'Change your stay',
              expand: false,
              onPressed: _openSearch,
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.navy,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14,
          mainAxisExtent: 252,
        ),
        itemCount: shown.length,
        itemBuilder: (context, index) => _HotelTile(
          hotel: shown[index],
          onTap: () => _openHotel(shown[index]),
        ),
      ),
    );
  }
}

/// Navy header with the white search card hanging off its bottom edge.
class _Header extends StatelessWidget {
  const _Header({
    required this.place,
    required this.summary,
    required this.onSearch,
    required this.onStays,
  });

  final String place;
  final String summary;
  final VoidCallback onSearch;
  final VoidCallback onStays;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          color: AppColors.navy,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 50),
              child: Row(
                children: [
                  const HotelBackButton(dark: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'STAY',
                          style: AppType.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: .6,
                            color: AppColors.brand,
                          ),
                        ),
                        Text(
                          'Hotels',
                          style: AppType.h2.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            color: AppText.onInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: AppColors.navyLine,
                    borderRadius: AppRadii.all(12),
                    child: InkWell(
                      onTap: onStays,
                      borderRadius: AppRadii.all(12),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        child: Text(
                          'My stays',
                          style: AppType.small.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppText.onInk,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: -30,
          child: Material(
            color: AppColors.background,
            elevation: 8,
            shadowColor: AppColors.navy.withValues(alpha: .25),
            borderRadius: AppRadii.all(18),
            child: InkWell(
              onTap: onSearch,
              borderRadius: AppRadii.all(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        size: 21, color: AppColors.navy),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.listTitle.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppText.primary,
                            ),
                          ),
                          Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppText.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.brand,
                        borderRadius: AppRadii.all(12),
                      ),
                      child: const Icon(Icons.tune_rounded,
                          size: 19, color: AppColors.navy),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// All · city · city — text tabs with a lime underline.
class _CityTabs extends StatelessWidget {
  const _CityTabs({
    required this.cities,
    required this.selected,
    required this.onChanged,
  });

  final List<String> cities;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final entries = <(String?, String)>[
      (null, 'All'),
      for (final city in cities) (city, city),
    ];
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 22),
        itemBuilder: (context, index) {
          final (value, label) = entries[index];
          final on = value == selected;
          return InkWell(
            onTap: () => onChanged(value),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: on ? AppColors.brand : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                label,
                style: AppType.small.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: on ? AppText.primary : AppText.caption,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brandWash : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(10),
        side: BorderSide(
          color: selected ? AppColors.brandInk : AppColors.border,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(10)),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppType.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: AppText.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One hotel in the grid: a tall photograph, then name, area and price.
class _HotelTile extends StatelessWidget {
  const _HotelTile({required this.hotel, required this.onTap});

  final HotelSummary hotel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rooms = hotel.availableRooms;
    final few = rooms <= 2;
    final tag = rooms <= 0
        ? 'Check rooms'
        : rooms == 1
            ? 'Last room'
            : few
                ? '$rooms rooms left'
                : '$rooms rooms free';
    final area = [hotel.address, hotel.city]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 168,
            child: Stack(
              fit: StackFit.expand,
              children: [
                HotelPhoto(url: hotel.mainImageUrl),
                if (hotel.rating > 0)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: AppRadii.all(9),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 13, color: AppColors.brandInk),
                          const SizedBox(width: 3),
                          Text(
                            hotel.rating.toStringAsFixed(1),
                            style: AppType.caption.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (hotel.transportAvailable)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Semantics(
                      label: 'Pickup transport',
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.brand,
                          borderRadius: AppRadii.all(9),
                        ),
                        child: const Icon(Icons.airport_shuttle_rounded,
                            size: 16, color: AppColors.navy),
                      ),
                    ),
                  ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: few && rooms > 0
                          ? AppColors.navy
                          : AppColors.background,
                      borderRadius: AppRadii.all(8),
                    ),
                    child: Text(
                      tag,
                      style: AppType.caption.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: few && rooms > 0
                            ? AppText.onInk
                            : AppText.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hotel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.listTitle.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                Text(
                  area,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppText.secondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: hotel.startingRate > 0
                            ? Money.amount(hotel.startingRate)
                            : 'See rooms',
                        style: AppType.listTitle.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppText.primary,
                        ),
                      ),
                      if (hotel.startingRate > 0)
                        TextSpan(
                          text: ' / night',
                          style: AppType.caption.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppText.secondary,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Every hotel in the list on one map. Tap a pin's label to open it.
class _HotelsMapScreen extends StatefulWidget {
  const _HotelsMapScreen({required this.hotels, required this.onOpen});

  final List<HotelSummary> hotels;
  final ValueChanged<HotelSummary> onOpen;

  @override
  State<_HotelsMapScreen> createState() => _HotelsMapScreenState();
}

class _HotelsMapScreenState extends State<_HotelsMapScreen> {
  final UdMapController _controller = UdMapController();
  HotelSummary? _picked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final points = [
        for (final h in widget.hotels) LatLng(h.latitude, h.longitude),
      ];
      if (points.length > 1) _controller.fitBounds(points, padding: 70);
    });
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.hotels.first;
    final picked = _picked;
    return Scaffold(
      body: Stack(
        children: [
          UdMap(
            controller: _controller,
            initialCenter: LatLng(first.latitude, first.longitude),
            zoom: 11,
            markers: [
              for (final h in widget.hotels)
                UdMarker(
                  id: h.id,
                  position: LatLng(h.latitude, h.longitude),
                  label: h.name,
                  hue: h.id == picked?.id
                      ? UdMarkerHue.brand
                      : UdMarkerHue.navy,
                  onTap: () => setState(() => _picked = h),
                ),
            ],
          ),
          const Positioned(
            left: 16,
            top: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(top: 12),
                child: HotelBackButton(),
              ),
            ),
          ),
          if (picked != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: Material(
                  color: AppColors.background,
                  elevation: 8,
                  borderRadius: AppRadii.all(20),
                  child: InkWell(
                    onTap: () => widget.onOpen(picked),
                    borderRadius: AppRadii.all(20),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          HotelPhoto(
                            url: picked.mainImageUrl,
                            width: 76,
                            height: 76,
                            radius: 14,
                            iconSize: 30,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  picked.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.listTitle.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppText.primary,
                                  ),
                                ),
                                Text(
                                  picked.city,
                                  style: AppType.caption.copyWith(
                                    color: AppText.secondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  picked.startingRate > 0
                                      ? '${Money.amount(picked.startingRate)} / night'
                                      : 'See rooms',
                                  style: AppType.small.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppText.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.navy),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
