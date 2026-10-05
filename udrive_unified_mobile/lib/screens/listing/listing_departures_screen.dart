import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/explore/explore_repository.dart';
import '../../core/format/money.dart';
import '../../core/listings/listing_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import 'assign_driver_sheet.dart';
import 'rent_tour_kit.dart';

/// Tour departures — one vehicle, one month, a departure per day.
///
/// The owner taps a date, says where to and when, and it is live. Price,
/// seats, pickup point and driver carry over from the last departure, so a
/// daily run is two taps; the first departure ever opens those up front.
class ListingDeparturesScreen extends StatefulWidget {
  const ListingDeparturesScreen({
    required this.vehicle,
    required this.drivers,
    super.key,
  });

  final ListingVehicle vehicle;
  final List<FleetDriver> drivers;

  @override
  State<ListingDeparturesScreen> createState() =>
      _ListingDeparturesScreenState();
}

class _ListingDeparturesScreenState extends State<ListingDeparturesScreen> {
  ListingRepository? _repository;
  ExploreRepository? _explore;

  late DateTime _month = _firstOfMonth(DateTime.now());
  late DateTime _selected = rentDayOnly(DateTime.now());

  DepartureMonth? _data;
  List<ExplorePlace>? _places;

  bool _loading = true;
  bool _saving = false;
  bool _loadingPlaces = false;
  String? _error;
  String? _notice;

  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();
  final TextEditingController _time = TextEditingController();
  final TextEditingController _perSeat = TextEditingController();
  final TextEditingController _whole = TextEditingController();
  final TextEditingController _pickup = TextEditingController();

  String? _destinationId;
  TimeOfDay _timeOfDay = const TimeOfDay(hour: 6, minute: 0);
  int _days = 1;
  String? _driverId;
  String? _driverName;
  bool _editOpen = false;

  static DateTime _firstOfMonth(DateTime value) =>
      DateTime(value.year, value.month, 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository == null) {
      final api = AppControllerScope.of(context).apiClient;
      _repository = ListingRepository(api);
      _explore = ExploreRepository(api);
      _load();
    }
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _time.dispose();
    _perSeat.dispose();
    _whole.dispose();
    _pickup.dispose();
    super.dispose();
  }

  // ── data ──────────────────────────────────────────────────────────────────

  DepartureDay? _dayFor(DateTime day) {
    final days = _data?.days ?? const <DepartureDay>[];
    for (final d in days) {
      final date = d.date;
      if (date != null && rentDayOnly(date) == day) return d;
    }
    return null;
  }

  DepartureDay? get _current => _dayFor(_selected);
  bool get _isSet => _current != null;
  int get _sold => _current?.seatsSold ?? 0;
  bool get _locked => _sold > 0;
  bool get _perSeatAllowed => _data?.perSeatAllowed ?? true;

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await repository.departures(widget.vehicle.id, _month);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        final today = rentDayOnly(DateTime.now());
        if (_selected.month != _month.month ||
            _selected.year != _month.year ||
            _selected.isBefore(today)) {
          _selected = _month.isAfter(today) ? _month : today;
        }
        _prefill();
      });
    } on ListingRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _error = refusal.message;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  static String _price(double value) =>
      value > 0 ? value.round().toString() : '';

  /// Fills the card for [_selected]: that day's departure, else the last
  /// one's price, pickup and driver with an empty destination.
  void _prefill() {
    final day = _current;
    final template = _data?.template;
    final source = day ?? template;

    final from = (day?.from ?? template?.from ?? '').trim();
    _from.text = from.isEmpty ? 'Muzaffarabad' : from;

    _destinationId =
        (day?.destinationId ?? '').isEmpty ? null : day!.destinationId;
    _to.text = day?.destination ?? '';

    _timeOfDay = _parseTime(source?.time) ?? const TimeOfDay(hour: 6, minute: 0);
    _time.text = _display(_timeOfDay);

    _days = (source?.durationDays ?? 1).clamp(1, 4);
    _perSeat.text = _price(source?.pricePerSeat ?? 0);
    _whole.text = _price(source?.wholeVehiclePrice ?? 0);
    _pickup.text = source?.pickupPoint ?? '';
    _driverId = source?.fleetDriverId;
    _driverName = source?.driverName;
    if (_driverId != null && _driverName == null) {
      for (final d in widget.drivers) {
        if (d.id == _driverId) _driverName = d.isOwner ? 'Me' : d.name;
      }
    }

    // Nothing to carry over: the first departure needs its prices now.
    _editOpen = template == null && day == null;
    _notice = null;
  }

  static TimeOfDay? _parseTime(String? value) {
    final parts = (value ?? '').split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  static String _display(TimeOfDay t) =>
      DateFormat('h:mm a').format(DateTime(2000, 1, 1, t.hour, t.minute));

  static String _wire(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  String get _title {
    final today = rentDayOnly(DateTime.now());
    final dayMonth = DateFormat('d MMM').format(_selected);
    if (_selected == today) return 'Today, $dayMonth';
    if (_selected == today.add(const Duration(days: 1))) {
      return 'Tomorrow, $dayMonth';
    }
    return DateFormat('EEE, d MMM').format(_selected);
  }

  // ── actions ───────────────────────────────────────────────────────────────

  void _pick(DateTime day) {
    setState(() {
      _selected = day;
      _error = null;
      _prefill();
    });
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _notice = null;
    });
    _load();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOfDay,
      helpText: 'Leaves at',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _timeOfDay = picked;
      _time.text = _display(picked);
    });
  }

  Future<void> _pickDestination() async {
    final explore = _explore;
    if (explore == null || _loadingPlaces) return;
    if (_places == null) {
      setState(() => _loadingPlaces = true);
      try {
        final places = await explore.places();
        if (!mounted) return;
        setState(() {
          _places = places;
          _loadingPlaces = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loadingPlaces = false;
          _error = 'Could not load places. Pull down and try again.';
        });
        return;
      }
    }
    if (!mounted) return;

    final place = await showUdSheet<ExplorePlace>(
      context: context,
      builder: (_) => _PlacePicker(places: _places ?? const []),
    );
    if (place == null || !mounted) return;
    setState(() {
      _destinationId = place.id;
      _to.text = place.name;
    });
  }

  Future<void> _pickDriver() async {
    final driver = await showAssignDriverSheet(
      context,
      drivers: widget.drivers,
      title: '$_title · ${_to.text.trim().isEmpty ? 'tour' : _to.text.trim()}',
      subtitle: widget.vehicle.name,
      selectedId: _driverId,
    );
    if (driver == null || !mounted) return;
    setState(() {
      _driverId = driver.id;
      _driverName = driver.isOwner ? 'Me' : driver.name;
    });
  }

  double _amount(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  Future<void> _goLive() async {
    final repository = _repository;
    if (repository == null || _saving) return;

    final from = _from.text.trim();
    final destinationId = _destinationId;
    final perSeat = _perSeatAllowed ? _amount(_perSeat) : 0.0;
    final whole = _amount(_whole);

    String? problem;
    if (from.isEmpty) {
      problem = 'Say where the tour leaves from.';
    } else if (destinationId == null) {
      problem = 'Choose where it goes.';
    } else if (whole <= 0 && perSeat <= 0) {
      problem = 'Set a price for the whole vehicle'
          '${_perSeatAllowed ? ' or per seat' : ''}.';
    }
    if (problem != null) {
      setState(() {
        _error = problem;
        if (whole <= 0 && perSeat <= 0) _editOpen = true;
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await repository.saveDeparture(
        widget.vehicle.id,
        _selected,
        from: from,
        destinationId: destinationId!,
        time: _wire(_timeOfDay),
        durationDays: _days,
        pricePerSeat: perSeat,
        wholeVehiclePrice: whole,
        pickupPoint: _pickup.text.trim(),
        fleetDriverId: _driverId,
      );
      if (!mounted) return;
      final wasSet = _isSet;
      setState(() => _saving = false);
      await _load();
      if (!mounted) return;
      setState(() => _notice = wasSet
          ? 'Updated. Customers see the change now.'
          : 'Live. Customers can book it now.');
    } on ListingRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = refusal.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  Future<void> _cancelDay() async {
    final repository = _repository;
    if (repository == null || _saving || _locked) return;

    final go = await showUdDialog<bool>(
      context: context,
      title: 'Cancel $_title?',
      message: 'The departure comes off the tour list straight away.',
      actions: [
        Builder(
          builder: (dialogContext) => UdButton.dark(
            label: 'Cancel this day',
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ),
        Builder(
          builder: (dialogContext) => UdButton.ghost(
            label: 'Keep it',
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
        ),
      ],
    );
    if (go != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await repository.cancelDeparture(widget.vehicle.id, _selected);
      if (!mounted) return;
      setState(() => _saving = false);
      await _load();
      if (!mounted) return;
      setState(() => _notice = 'Cancelled.');
    } on ListingRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = refusal.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    final today = rentDayOnly(DateTime.now());
    final current = _firstOfMonth(today);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          RentNavyHeader(
            title: 'Departures',
            subtitle:
                '${v.year > 0 ? '${v.name} ${v.year}' : v.name} · tap a date',
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  RentMonthBar(
                    month: _month,
                    onPrevious: _loading || !_month.isAfter(current)
                        ? null
                        : () => _shiftMonth(-1),
                    onNext: _loading ? null : () => _shiftMonth(1),
                  ),
                  const SizedBox(height: 10),
                  Stack(
                    children: [
                      RentMonthGrid(
                        month: _month,
                        cell: (day) => _DepartureCell(
                          day: day,
                          past: day.isBefore(today),
                          today: day == today,
                          selected: day == _selected,
                          hasDeparture: _dayFor(day) != null,
                          onTap: day.isBefore(today) || _loading
                              ? null
                              : () => _pick(day),
                        ),
                      ),
                      if (_loading)
                        const Positioned.fill(
                          child: Center(
                            child: CircularProgressIndicator(
                                color: AppColors.navy),
                          ),
                        ),
                    ],
                  ),
                  const Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      RentLegendItem(
                          label: 'Departure set', fill: AppColors.limeLine),
                      RentLegendItem(
                          label: 'Nothing yet', fill: AppColors.borderStrong),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) ...[
                    UdBanner(tone: UdTone.err, text: _error),
                    const SizedBox(height: 12),
                  ],
                  if (_notice != null) ...[
                    UdBanner(
                      tone: UdTone.ok,
                      icon: Icons.check_rounded,
                      text: _notice,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _dayCard(),
                ],
              ),
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _dayCard() {
    final lockedNote = _locked
        ? '$_sold ${_sold == 1 ? 'seat' : 'seats'} sold — route and time '
            'can\'t change'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: AppRadii.all(18),
            border: Border.all(color: AppColors.navy, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      style: AppType.listTitle.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppText.primary,
                      ),
                    ),
                  ),
                  if (_isSet)
                    const RentTag(
                      'Live',
                      background: AppColors.brandWash,
                      ink: AppColors.brandInk,
                    ),
                ],
              ),
              if (lockedNote != null) ...[
                const SizedBox(height: 10),
                UdBanner(
                  tone: UdTone.warn,
                  icon: Icons.lock_outline_rounded,
                  text: lockedNote,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: UdTextField(
                      controller: _from,
                      label: 'FROM',
                      enabled: !_locked,
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: UdTextField(
                      controller: _to,
                      label: 'TO',
                      hint: _loadingPlaces ? 'Loading…' : 'Where to',
                      readOnly: true,
                      enabled: !_locked,
                      onTap: _locked ? null : _pickDestination,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              UdTextField(
                controller: _time,
                label: 'TIME',
                icon: Icons.schedule_rounded,
                readOnly: true,
                enabled: !_locked,
                onTap: _locked ? null : _pickTime,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Semantics(
          button: true,
          label: _editOpen ? 'Hide price and seats' : 'Edit price and seats',
          child: InkWell(
            onTap: () => setState(() => _editOpen = !_editOpen),
            borderRadius: AppRadii.all(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _editOpen
                            ? 'Price, seats, pickup and driver · '
                            : 'Price, seats and pickup point stay as last '
                                'time · ',
                      ),
                      TextSpan(
                        text: _editOpen ? 'Hide' : 'Edit',
                        style: AppType.caption.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandInk,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                  style: AppType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppText.secondary,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_editOpen) _editSection(),
      ],
    );
  }

  Widget _editSection() {
    final money = [FilteringTextInputFormatter.digitsOnly];
    final seats = _data?.totalSeats ?? widget.vehicle.seats;
    final perSeat = _amount(_perSeat);

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_perSeatAllowed) ...[
            UdTextField(
              controller: _perSeat,
              label: 'Price per seat',
              hint: 'PKR',
              keyboardType: TextInputType.number,
              inputFormatters: money,
              enabled: !_locked,
              onChanged: (_) => setState(() {}),
              helper: perSeat > 0 && seats > 0
                  ? '$seats seats · ${Money.amount(perSeat * seats)} when full'
                  : '$seats seats',
            ),
            const SizedBox(height: 12),
          ],
          UdTextField(
            controller: _whole,
            label: 'Whole vehicle price',
            hint: 'PKR',
            keyboardType: TextInputType.number,
            inputFormatters: money,
            enabled: !_locked,
            helper: _perSeatAllowed
                ? 'For a family or group taking every seat'
                : 'Sold whole only — $seats seats',
          ),
          const SizedBox(height: 12),
          UdTextField(
            controller: _pickup,
            label: 'Pickup point',
            hint: 'e.g. Chattar Klas chowk',
            enabled: !_locked,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          const UdLabel('Days'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var d = 1; d <= 4; d++)
                UdChip(
                  label: d == 1 ? '1 day' : '$d days',
                  selected: _days == d,
                  onTap: _locked ? null : () => setState(() => _days = d),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const UdLabel('Driver'),
          const SizedBox(height: 6),
          UdListGroup(
            children: [
              UdListRow(
                title: _driverName ?? 'Choose driver',
                subtitle: 'Only needed when you don\'t drive yourself',
                leading: const UdIconTile(
                  icon: Icons.person_outline_rounded,
                  tone: UdIconTone.neutral,
                ),
                showChevron: true,
                onTap: _pickDriver,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_isSet) ...[
              Material(
                color: AppTint.danger,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.all(18),
                  side:
                      const BorderSide(color: AppTint.dangerBorder, width: 1.5),
                ),
                child: InkWell(
                  onTap: _saving || _locked || _loading ? null : _cancelDay,
                  customBorder:
                      RoundedRectangleBorder(borderRadius: AppRadii.all(18)),
                  child: Container(
                    height: 58,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    child: Text(
                      'Cancel day',
                      style: AppType.small.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _locked
                            ? AppText.disabled
                            : AppTint.dangerText,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: UdButton.primary(
                label: _isSet ? 'Update' : 'Go live',
                busy: _saving,
                onPressed: _loading ? null : _goLive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartureCell extends StatelessWidget {
  const _DepartureCell({
    required this.day,
    required this.past,
    required this.today,
    required this.selected,
    required this.hasDeparture,
    required this.onTap,
  });

  final DateTime day;
  final bool past;
  final bool today;
  final bool selected;
  final bool hasDeparture;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color fill = selected
        ? AppColors.navy
        : hasDeparture && !past
            ? AppColors.brandWash
            : AppColors.background;
    final Color ink = past
        ? AppText.disabled
        : selected
            ? AppText.onInk
            : AppText.primary;
    final Color line = selected
        ? AppColors.navy
        : today
            ? AppColors.limeLine
            : AppColors.surfaceAlt;
    final Color? dot = past
        ? null
        : hasDeparture
            ? AppColors.limeLine
            : AppColors.borderStrong;

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '${day.day}${hasDeparture ? ', departure set' : ''}',
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(12),
          side: BorderSide(color: line, width: today ? 2 : 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(12)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: AppType.small.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: dot ?? Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searchable list of destinations for "To".
class _PlacePicker extends StatefulWidget {
  const _PlacePicker({required this.places});

  final List<ExplorePlace> places;

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _search.text.trim().toLowerCase();
    final shown = needle.isEmpty
        ? widget.places
        : widget.places
            .where((p) =>
                p.name.toLowerCase().contains(needle) ||
                p.district.toLowerCase().contains(needle))
            .toList(growable: false);
    final height = MediaQuery.sizeOf(context).height * 0.55;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Text('Where to?', style: AppType.h2.copyWith(color: AppText.primary)),
        const SizedBox(height: 12),
        UdTextField(
          controller: _search,
          hint: 'Search places',
          icon: Icons.search_rounded,
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: height,
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    widget.places.isEmpty
                        ? 'No places available right now.'
                        : 'Nothing matches "${_search.text.trim()}".',
                    style: AppType.small.copyWith(color: AppText.secondary),
                  ),
                )
              : ListView.separated(
                  itemCount: shown.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    final place = shown[index];
                    return UdListRow(
                      title: place.name,
                      subtitle:
                          place.district.trim().isEmpty ? null : place.district,
                      onTap: () => Navigator.pop(context, place),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
