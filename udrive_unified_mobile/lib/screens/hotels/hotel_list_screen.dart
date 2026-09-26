import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/hotels/hotel_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/auth_models.dart';
import '../../models/hotel_models.dart';
import '../customer/udrive_route_flow_screen.dart';
import '../hotel_owner/hotel_owner_add_screen.dart';
import 'hotel_detail_screen.dart';

/// C-42 — Hotels & Stays.
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

  /// Optional search values pre-filled from the Home booking card, so the
  /// customer does not re-enter what they already typed.
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int? guests;
  final int? rooms;

  @override
  State<HotelListScreen> createState() => _HotelListScreenState();
}

class _HotelListScreenState extends State<HotelListScreen> {
  final _query = TextEditingController();
  DateTime _checkIn = DateTime.now().add(const Duration(days: 1));
  DateTime _checkOut = DateTime.now().add(const Duration(days: 2));
  int _guests = 2;
  int _rooms = 1;
  bool _busy = true;
  bool _prefilled = false;
  String? _loadError;
  List<HotelSummary> _items = const [];
  HotelRepository? _repo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_query.text.isEmpty && widget.destination != null) {
      _query.text = widget.destination!;
    }
    if (!_prefilled) {
      _prefilled = true;
      if (widget.checkIn != null) _checkIn = widget.checkIn!;
      if (widget.checkOut != null) _checkOut = widget.checkOut!;
      if (widget.guests != null) _guests = widget.guests!;
      if (widget.rooms != null) _rooms = widget.rooms!;
    }
    if (_repo != null) return;
    try {
      _repo = HotelRepository(AppControllerScope.of(context).apiClient);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    } catch (error) {
      _busy = false;
      _loadError = 'Hotels service is not ready yet. Please retry.';
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _loadError = null;
    });
    try {
      final repo = _repo;
      if (repo == null) {
        throw Exception('Hotels service is not ready yet.');
      }
      final loaded = await repo.search(
        query: _query.text,
        checkIn: _checkIn,
        checkOut: _checkOut,
        guests: _guests,
        rooms: _rooms,
      );
      if (!mounted) return;
      setState(() => _items = loaded);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        // Not '$error'. Now that the repository rethrows instead of falling
        // back to a demo list, everything reaches here — including a cast
        // failure on an unexpected payload, which would have shown the
        // customer "type 'List<dynamic>' is not a subtype of type
        // 'Map<dynamic, dynamic>' in type cast". An ApiException carries a
        // message written for a person; anything else gets a plain sentence.
        _loadError = error is ApiException
            ? error.message
            : 'Hotels could not be loaded just now. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _openHotel(HotelSummary hotel) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HotelDetailScreen(
            hotel: hotel,
            checkIn: _checkIn,
            checkOut: _checkOut,
          ),
        ),
      );

  /// Book a vehicle heading to the selected hotel (reuses the ride flow).
  void _rideToHotel(HotelSummary hotel) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UDriveRouteFlowScreen(
            serviceType: UDriveServiceType.city,
            pickupLabel: 'Current location',
            pickupPoint: const LatLng(34.3700, 73.4700),
            initialDestinationLabel: '${hotel.name} — ${hotel.address}',
            initialDestinationLatitude: hotel.latitude,
            initialDestinationLongitude: hotel.longitude,
            skipRouteEntry: true,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(
        title: 'Hotels & Stays',
        onBack: () => Navigator.maybePop(context),
        divider: true,
        actions: [
          UdIconButton(
            icon: Icons.add_business_rounded,
            tooltip: 'Add your hotel',
            onPressed: _openAddHotel,
          ),
          UdIconButton(
            icon: Icons.refresh_rounded,
            variant: UdIconButtonVariant.soft,
            tooltip: 'Refresh',
            onPressed: _busy ? null : _load,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 16, AppSizes.sidePadding, 34),
        children: [
          UdTextField(
            controller: _query,
            hint: 'Destination or hotel',
            icon: Icons.search_rounded,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
          ),
          const SizedBox(height: 12),
          // One layout, not two. The code used to draw a labelled button under
          // 350px and an arrow-only square above it, so the same screen had
          // two different search controls depending on the phone.
          Row(
            children: [
              Expanded(
                child: _DateBox(
                  label: 'Check-in',
                  value: _checkIn,
                  onPick: (date) => setState(() => _checkIn = date),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateBox(
                  label: 'Check-out',
                  value: _checkOut,
                  onPick: (date) => setState(() => _checkOut = date),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          UdButton.dark(
            label: 'Search hotels',
            icon: Icons.search_rounded,
            size: UdButtonSize.small,
            busy: _busy,
            onPressed: _load,
          ),
          const SizedBox(height: 18),
          UdListGroup(
            children: [
              UdListRow(
                title: 'Own a hotel or guest house?',
                subtitle: 'Add it for admin approval and publish it on UDrive.',
                leading: const UdIconTile(
                  icon: Icons.add_business_rounded,
                  tone: UdIconTone.lime,
                ),
                showChevron: true,
                onTap: _openAddHotel,
              ),
            ],
          ),
          if (_loadError != null) ...[
            const SizedBox(height: 14),
            UdBanner(
              tone: UdTone.err,
              icon: Icons.cloud_off_rounded,
              trailing: UdButton.outline(
                label: 'Retry',
                size: UdButtonSize.xs,
                expand: false,
                onPressed: _load,
              ),
              text: _loadError!,
            ),
          ],
          const SizedBox(height: 20),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.navy),
              ),
            )
          else if (_items.isEmpty)
            _EmptyHotels(hasError: _loadError != null)
          else ...[
            UdSectionHeader(
              title: '${_items.length} '
                  '${_items.length == 1 ? 'stay' : 'stays'}',
              caption: '${DateFormat('dd MMM').format(_checkIn)} – '
                  '${DateFormat('dd MMM').format(_checkOut)} · $_guests guests',
            ),
            const SizedBox(height: 14),
            for (final hotel in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _HotelCard(
                  hotel: hotel,
                  onOpen: () => _openHotel(hotel),
                  onRide: () => _rideToHotel(hotel),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _openAddHotel() async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const HotelOwnerAddScreen(standalone: true),
      ),
    );
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hotel submitted. It will appear here after admin approval.',
          ),
        ),
      );
    }
  }
}

/// A field that opens a date picker: the label above the date, inside the box.
class _DateBox extends StatelessWidget {
  const _DateBox({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AppRadii.all(AppRadii.field),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              initialDate: value,
            );
            if (picked != null) onPick(picked);
          },
          child: Container(
            height: AppSizes.field,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: AppRadii.all(AppRadii.field),
              border: Border.all(color: AppColors.borderStrong, width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded,
                    size: 20, color: AppText.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style:
                            AppType.caption.copyWith(color: AppText.secondary),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        DateFormat('dd MMM yyyy').format(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.listTitle.copyWith(
                          fontSize: 15,
                          color: AppText.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// One hotel: a cover with its rating and whether it runs transport, then the
/// nightly rate and the two ways in.
class _HotelCard extends StatelessWidget {
  const _HotelCard({
    required this.hotel,
    required this.onOpen,
    required this.onRide,
  });

  final HotelSummary hotel;
  final VoidCallback onOpen;
  final VoidCallback onRide;

  @override
  Widget build(BuildContext context) => UdCard(
        tone: UdCardTone.raised,
        padding: EdgeInsets.zero,
        onTap: onOpen,
        child: ClipRRect(
          borderRadius: AppRadii.all(AppRadii.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 150,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hotel.mainImageUrl.isEmpty)
                      const _HotelPhotoFallback()
                    else
                      Image.network(
                        hotel.mainImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const _HotelPhotoFallback(),
                      ),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: UdMapChip(
                        label: hotel.rating.toStringAsFixed(1),
                        icon: Icons.star_rounded,
                      ),
                    ),
                    if (hotel.transportAvailable)
                      const Positioned(
                        right: 12,
                        top: 12,
                        child: UdBadge(
                          label: 'Transport',
                          tone: UdTone.lime,
                          icon: Icons.directions_car_rounded,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hotel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.h3.copyWith(color: AppText.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${hotel.city} · ${hotel.address}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.small.copyWith(color: AppText.secondary),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Starts from',
                                style: AppType.small
                                    .copyWith(color: AppText.secondary),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                hotel.startingRate > 0
                                    ? 'PKR ${NumberFormat('#,###').format(hotel.startingRate)}'
                                    : 'Check rooms',
                                style: AppType.priceMd.copyWith(
                                  fontSize: 19,
                                  color: AppColors.brandInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${hotel.availableRooms} rooms',
                          style: AppType.small.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppText.secondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    UdButtonRow(
                      children: [
                        UdButton.outline(
                          label: 'Book ride',
                          icon: Icons.local_taxi_rounded,
                          size: UdButtonSize.small,
                          onPressed: onRide,
                        ),
                        UdButton.primary(
                          label: 'Book room',
                          icon: Icons.bed_rounded,
                          size: UdButtonSize.small,
                          onPressed: onOpen,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _HotelPhotoFallback extends StatelessWidget {
  const _HotelPhotoFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTint.mapPark, AppTint.mapWater],
          ),
        ),
        child: Center(
          child: Icon(Icons.hotel_rounded,
              size: 46, color: AppColors.borderStrong),
        ),
      );
}

/// Nothing matched — or nothing could be fetched. Two different sentences,
/// because they need two different things from the reader.
class _EmptyHotels extends StatelessWidget {
  const _EmptyHotels({required this.hasError});

  final bool hasError;

  @override
  Widget build(BuildContext context) => UdEmptyState(
        icon: hasError ? Icons.cloud_off_rounded : Icons.hotel_rounded,
        title: hasError ? 'Hotels are unavailable' : 'No hotels match',
        text: hasError
            ? 'Hotels could not be loaded just now. Check your connection and '
                'tap Retry.'
            : 'No approved hotels match this search. Clear the destination and '
                'search again.',
      );
}
