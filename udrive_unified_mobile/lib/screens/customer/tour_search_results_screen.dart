import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/booking/booking_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/vehicles/nearby_vehicle.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/booking_models.dart';
import 'live_packages_screen.dart';
import 'live_tour_interest_screen.dart';

/// What a Customer gets back when they leave this screen.
enum TourSearchOutcome {
  /// They want their own vehicle for the whole trip — the existing flow, where
  /// they name a price and drivers bid.
  privateVehicle,
}

/// C-11 — the answer to "who is going to Neelum on the 14th with four seats".
///
/// This screen exists because that question had no answer in the app. Tapping
/// Tour on the home screen opened the same destination search a city ride uses,
/// and the Tour panel behind it created a *ride request* — it never looked at
/// tour packages at all. Every departure a Driver had published sat in a drawer
/// screen with no filters: no date, no seats, no destination. A Customer
/// planning a trip for a particular weekend had to open that list and read every
/// card.
///
/// So the two things a Customer might actually want are separated and both
/// shown:
///
/// * **Departures** — packages a Driver has published, filtered on the server by
///   destination, that day, seats genuinely bookable and party type.
/// * **Private vehicle** — the whole vehicle to themselves, which is the flow
///   that already existed.
///
/// And when the day has no departures, the screen offers the one thing that was
/// built and never reachable: Join a tour, which records what they wanted and
/// matches them to a departure later.
class TourSearchResultsScreen extends StatefulWidget {
  const TourSearchResultsScreen({
    required this.destinationName,
    required this.date,
    required this.persons,
    required this.days,
    required this.partyType,
    required this.tourVehicles,
    super.key,
  });

  /// As the Customer typed or tapped it. Resolved to a catalogue id here —
  /// the home screen works in place names and coordinates, not catalogue rows.
  final String destinationName;

  final DateTime date;
  final int persons;
  final int days;

  /// 'Family', 'WomenOnly' or 'Any'.
  final String partyType;

  /// Tour-registered vehicles already loaded by the home screen. Passed in
  /// rather than fetched again: the home screen has them, and a second call for
  /// the same list is a second wait on a mountain connection.
  final List<NearbyVehicle> tourVehicles;

  @override
  State<TourSearchResultsScreen> createState() =>
      _TourSearchResultsScreenState();
}

class _TourSearchResultsScreenState extends State<TourSearchResultsScreen> {
  int _tab = 0;
  bool _busy = true;
  String? _error;

  List<LiveTourPackage> _departures = const [];

  /// The soonest departure to this destination after the chosen day, used only
  /// when the chosen day has none. Offering a date is a better answer than an
  /// empty list.
  LiveTourPackage? _nextBest;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  DateTime get _dayStart =>
      DateTime(widget.date.year, widget.date.month, widget.date.day);

  Future<void> _search() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }

    final controller = AppControllerScope.of(context);
    final repository = BookingRepository(controller.apiClient);

    try {
      final destinationId = await _resolveDestinationId(controller);

      // That day only: from its midnight to the next, which the server treats
      // as an exclusive upper bound.
      final results = await repository.getPublicPackages(
        destinationId: destinationId,
        departureFrom: _dayStart,
        departureTo: _dayStart.add(const Duration(days: 1)),
        minimumSeats: widget.persons,
        partyType: widget.partyType,
      );

      // Nothing that day: find the soonest after it, same destination and
      // party, so the empty state can name a date instead of shrugging.
      LiveTourPackage? next;
      if (results.isEmpty) {
        final later = await repository.getPublicPackages(
          destinationId: destinationId,
          departureFrom: _dayStart.add(const Duration(days: 1)),
          minimumSeats: widget.persons,
          partyType: widget.partyType,
        );
        if (later.isNotEmpty) next = later.first;
      }

      if (!mounted) return;
      setState(() {
        _departures = results;
        _nextBest = next;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  /// Turns the place name the Customer picked into a catalogue id.
  ///
  /// The home screen's destination chips are a local list of places with
  /// coordinates; packages are keyed to catalogue rows. Matching on name is the
  /// honest bridge, and a name that matches nothing simply drops the filter —
  /// a search that silently returned zero because of an id mismatch would be
  /// indistinguishable from a quiet week.
  Future<String?> _resolveDestinationId(AppController controller) async {
    final wanted = widget.destinationName.trim().toLowerCase();
    if (wanted.isEmpty) return null;

    try {
      final response = await controller.apiClient.getJson(
        '/api/v1/catalog/destinations?language=en',
        authenticated: false,
      );
      final raw = response['data'] as List? ?? const [];
      for (final entry in raw.whereType<Map>()) {
        final name = '${entry['name'] ?? ''}'.trim().toLowerCase();
        if (name.isEmpty) continue;
        if (name == wanted || name.contains(wanted) || wanted.contains(name)) {
          return '${entry['id']}';
        }
      }
    } catch (_) {
      // No catalogue, no filter. The list is still correct, only wider.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMM').format(widget.date);
    final vehicles = widget.tourVehicles;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: UdTopBar(
        // One line, because the bar has one. Destination, day and party size
        // are what the Customer asked for, and seeing it on every screen of
        // the result is how they know the list answers their question.
        title: '${widget.destinationName.trim().isEmpty ? 'Tours' : widget.destinationName.trim()}'
            ' · $date · ${widget.persons}',
        onBack: () => Navigator.pop(context),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSizes.sidePadding, 10, AppSizes.sidePadding, 4),
            child: _Tabs(
              index: _tab,
              labels: [
                'Departures${_busy ? '' : ' ${_departures.length}'}',
                'Private vehicle ${vehicles.length}',
              ],
              onChanged: (value) => setState(() => _tab = value),
            ),
          ),
          Expanded(
            child: _tab == 0 ? _departuresTab() : _privateTab(vehicles),
          ),
        ],
      ),
    );
  }

  Widget _departuresTab() {
    if (_busy) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.navy),
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 18, AppSizes.sidePadding, 40),
        children: [
          UdEmptyState(
            icon: Icons.cloud_off_rounded,
            tone: UdTone.err,
            title: 'Could not load departures',
            text: _error,
            action: UdButton.outline(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              expand: false,
              onPressed: _search,
            ),
          ),
        ],
      );
    }

    if (_departures.isEmpty) return _noDepartures();

    return RefreshIndicator(
      onRefresh: _search,
      color: AppColors.navy,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 14, AppSizes.sidePadding, 40),
        itemCount: _departures.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) => _DepartureCard(
          package: _departures[index],
          persons: widget.persons,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  LivePackageDetailScreen(package: _departures[index]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _noDepartures() {
    final next = _nextBest;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 22, AppSizes.sidePadding, 40),
      children: [
        UdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: UdIconTile(
                  icon: Icons.event_busy_rounded,
                  tone: UdIconTone.neutral,
                  size: UdIconTileSize.lg,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'No departure on ${DateFormat('d MMM').format(widget.date)}',
                textAlign: TextAlign.center,
                style: AppType.h3.copyWith(color: AppText.primary),
              ),
              const SizedBox(height: 6),
              Text(
                next == null
                    ? 'Nobody has published a tour to here with '
                        '${widget.persons} '
                        '${widget.persons == 1 ? 'seat' : 'seats'} free yet.'
                    : 'The soonest is '
                        '${DateFormat('EEE, d MMM').format(next.departureAt)}, '
                        'with ${next.bookableSeats} '
                        '${next.bookableSeats == 1 ? 'seat' : 'seats'} free.',
                textAlign: TextAlign.center,
                style: AppType.body2
                    .copyWith(height: 1.45, color: AppText.secondary),
              ),
              if (next != null) ...[
                const SizedBox(height: 16),
                UdButton.outline(
                  label:
                      'See ${DateFormat('d MMM').format(next.departureAt)}',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LivePackageDetailScreen(package: next),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),

              // The screen that was built and never reachable.
              //
              // Join a tour already asks for destination, date, party size,
              // budget and group preference, and the server already matches
              // those against departures. It had a route and no caller, so no
              // Customer has ever seen it. This is the moment it is useful.
              UdButton.primary(
                label: 'Match me to a tour',
                icon: Icons.notifications_active_rounded,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LiveTourInterestScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'We record what you are looking for and tell you when a '
                'driver publishes a matching departure.',
                textAlign: TextAlign.center,
                style:
                    AppType.small.copyWith(height: 1.45, color: AppText.caption),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        UdButton.outline(
          label: 'Take a whole vehicle instead',
          icon: Icons.directions_car_rounded,
          onPressed: () => setState(() => _tab = 1),
        ),
      ],
    );
  }

  Widget _privateTab(List<NearbyVehicle> vehicles) => ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 14, AppSizes.sidePadding, 40),
        children: [
          UdBanner(
            tone: UdTone.info,
            icon: Icons.info_outline_rounded,
            text: 'The whole vehicle to yourself. You name your fare and '
                'drivers accept or counter — the same way a city ride works.',
          ),
          const SizedBox(height: 14),

          if (vehicles.isEmpty)
            const UdEmptyState(
              icon: Icons.directions_car_outlined,
              title: 'No tour vehicles nearby',
              text: 'No driver registered for tours is online around you right '
                  'now. Try again shortly, or look at the departures tab.',
            )
          else ...[
            UdListGroup(
              children: [
                for (final vehicle in vehicles.take(12))
                  UdListRow(
                    title: vehicle.category,
                    subtitle: '${vehicle.passengerCapacity} seats · '
                        '${vehicle.distanceKm.toStringAsFixed(1)} km away',
                    leading: const UdIconTile(
                        icon: Icons.directions_car_filled_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            UdButton.primary(
              label: 'Ask these drivers for a fare',
              icon: Icons.send_rounded,
              // Returns to the home screen, which owns the ride-request flow.
              // Rebuilding it here would be a second copy of the one-ride
              // guard, the quote and the advance rules.
              onPressed: () =>
                  Navigator.pop(context, TourSearchOutcome.privateVehicle),
            ),
          ],
        ],
      );
}

/// Departures / Private vehicle.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.all(AppRadii.chip),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => onChanged(i),
                    borderRadius: AppRadii.all(AppRadii.chip),
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == index
                            ? AppColors.surfaceHigh
                            : Colors.transparent,
                        borderRadius: AppRadii.all(AppRadii.chip),
                        boxShadow: i == index ? AppShadows.card : null,
                      ),
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.small.copyWith(
                          fontWeight: FontWeight.w700,
                          color: i == index
                              ? AppText.primary
                              : AppText.secondary,
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

/// One published departure, said in the order a Customer decides in.
///
/// Seats first, because a departure without room for the party is no departure
/// at all — and the number is seats genuinely bookable, holds already taken off,
/// not the raw column that used to let a full package pass a seat filter.
class _DepartureCard extends StatelessWidget {
  const _DepartureCard({
    required this.package,
    required this.persons,
    required this.onTap,
  });

  final LiveTourPackage package;
  final int persons;
  final VoidCallback onTap;

  static final _money = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    final seats = package.bookableSeats;
    final tight = seats <= persons + 1;

    return UdCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${package.startingCity} → ${package.destination}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.overline.copyWith(color: AppText.caption),
                ),
              ),
              UdBadge(
                label: '$seats ${seats == 1 ? 'seat' : 'seats'} free',
                tone: tight ? UdTone.warn : UdTone.ok,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            package.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.listTitle.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 6),
          Text(
            '${package.vehicle} · ${package.registrationNumber}\n'
            '${package.driverName} · departs '
            '${DateFormat('d MMM, h:mm a').format(package.departureAt)}',
            style: AppType.small.copyWith(height: 1.45, color: AppText.caption),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'PKR ${_money.format(package.pricePerSeat.round())}',
                style: AppType.h3.copyWith(color: AppText.primary),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'per seat',
                  style: AppType.small.copyWith(color: AppText.caption),
                ),
              ),
              const Spacer(),
              Text(
                'PKR ${_money.format(package.wholeVehiclePrice.round())} whole',
                style: AppType.small.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppText.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
