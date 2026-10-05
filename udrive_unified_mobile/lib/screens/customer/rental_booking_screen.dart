import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/network/api_config.dart';
import '../../core/rental/rental_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/demo_tag.dart';
import '../../core/widgets/ud_kit.dart';
import 'rental_waiting_screen.dart';

/// C-32 to C-35 — taking one car for a set of days.
///
/// One screen: the car, how it goes out, which days, what it costs, the
/// documents if the customer is driving, and the terms. The action is pinned
/// to the bottom so it never scrolls away.
///
/// Every figure on this screen comes from the server. Days × rate looks like
/// arithmetic the app could do, and the three things around it — the advance
/// percentage, the owner's minimum-days rule, and whether those days are even
/// free — are not. An app that worked out its own total would show a number the
/// booking then refuses.
class RentalBookingScreen extends StatefulWidget {
  const RentalBookingScreen({
    required this.vehicle,
    this.dates,
    this.mode,
    super.key,
  });

  final RentalVehicle vehicle;
  final DateTimeRange? dates;

  /// 'WithDriver' or 'SelfDrive', as chosen on the list. Ignored when this car
  /// does not offer it.
  final String? mode;

  @override
  State<RentalBookingScreen> createState() => _RentalBookingScreenState();
}

class _RentalBookingScreenState extends State<RentalBookingScreen> {
  late final RentalRepository _repository =
      RentalRepository(AppControllerScope.of(context).apiClient);

  DateTimeRange? _dates;
  late String _mode = _initialMode();

  List<RentalBlockedDay> _blocked = const [];
  RentalTerms _terms = RentalTerms.fallback;
  RentalQuote? _quote;
  CustomerDocuments _documents = CustomerDocuments.empty;

  bool _papersChecked = false;
  bool _liabilityAccepted = false;
  bool _conditionPhotos = false;

  bool _busy = false;
  String? _error;

  /// How many days the strip shows. Further dates go through the calendar.
  static const int _stripDays = 21;

  String _initialMode() {
    final wanted = widget.mode;
    final v = widget.vehicle;
    if (wanted == 'SelfDrive' && v.offersSelfDrive) return 'SelfDrive';
    if (wanted == 'WithDriver' && v.offersWithDriver) return 'WithDriver';
    return v.offersWithDriver ? 'WithDriver' : 'SelfDrive';
  }

  @override
  void initState() {
    super.initState();
    _dates = widget.dates;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  /// Whether Book can be pressed.
  ///
  /// `_terms.version > 0`: when the settings call fails the screen falls back
  /// to terms written into the app, carrying version 0 — and the server
  /// refuses any booking whose accepted version is not the current one.
  bool get _ready =>
      !widget.vehicle.isDemo &&
      _quote != null &&
      !_quote!.documentsMissing &&
      _papersChecked &&
      _liabilityAccepted &&
      _conditionPhotos &&
      _terms.version > 0 &&
      !_busy;

  bool get _termsUnavailable => _terms.version <= 0;

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final blocked = await _repository.blockedDays(widget.vehicle.vehicleId);
      final documents = await _repository.documents();
      final terms = await _repository.terms();
      if (!mounted) return;
      setState(() {
        _blocked = blocked;
        _documents = documents;
        _terms = terms;
        _busy = false;
      });
      if (_dates != null) await _refreshQuote();
    } catch (error) {
      if (!mounted) return;
      // `_blocked` stays empty here, so every day looks free. `_error` is
      // shown and Book stays off, which is the honest state.
      setState(() {
        _error = '$error';
        _busy = false;
      });
    }
  }

  Future<void> _refreshQuote() async {
    final dates = _dates;
    if (dates == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final quote = await _repository.quote(
        widget.vehicle.vehicleId,
        from: dates.start,
        to: dates.end,
        mode: _mode,
      );
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _busy = false;
      });
    } on RentalRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _quote = null;
        _error = refusal.message;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _quote = null;
        _error = '$error';
        _busy = false;
      });
    }
  }

  static DateTime _dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Set<DateTime> get _taken => {
        for (final day in _blocked) _dayOnly(day.date),
      };

  /// The full calendar, with the taken days closed.
  Future<void> _pickDates() async {
    final now = DateTime.now();
    final taken = _taken;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 120)),
      initialDateRange: _dates,
      selectableDayPredicate: (day, start, end) =>
          !taken.contains(_dayOnly(day)),
      helpText: _t('When do you need it?', 'کب چاہیے؟'),
    );

    if (picked == null || !mounted) return;
    setState(() => _dates = picked);
    await _refreshQuote();
  }

  /// A tap on the day strip.
  ///
  /// First tap picks a single day. A later day then stretches the range to it,
  /// as long as nothing taken sits in between; otherwise that day starts a new
  /// range. A tap on the only selected day clears it.
  Future<void> _tapDay(DateTime day) async {
    final taken = _taken;
    if (taken.contains(day)) return;

    final current = _dates;
    DateTimeRange? next;
    if (current == null) {
      next = DateTimeRange(start: day, end: day);
    } else {
      final start = _dayOnly(current.start);
      final end = _dayOnly(current.end);
      if (start == end && day == start) {
        next = null;
      } else if (start == end && day.isAfter(start)) {
        var clear = true;
        for (var d = start.add(const Duration(days: 1));
            !d.isAfter(day);
            d = d.add(const Duration(days: 1))) {
          if (taken.contains(d)) {
            clear = false;
            break;
          }
        }
        next = clear
            ? DateTimeRange(start: start, end: day)
            : DateTimeRange(start: day, end: day);
      } else {
        next = DateTimeRange(start: day, end: day);
      }
    }

    setState(() {
      _dates = next;
      if (next == null) _quote = null;
    });
    if (next != null) await _refreshQuote();
  }

  Future<void> _setMode(String mode) async {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    await _refreshQuote();
  }

  Future<void> _uploadDocument(String kind) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final files = picked?.files ?? const <PlatformFile>[];
    if (files.isEmpty || !mounted) return;
    final file = files.first;

    setState(() => _busy = true);
    try {
      final documents = await _repository.uploadDocument(kind, file);
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _busy = false;
      });
      await _refreshQuote();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _busy = false;
      });
    }
  }

  Future<void> _book() async {
    final dates = _dates;
    final quote = _quote;
    if (dates == null || quote == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final booking = await _repository.book(
        vehicleId: widget.vehicle.vehicleId,
        from: dates.start,
        to: dates.end,
        mode: _mode,
        // The version belonging to the text on screen.
        disclaimerVersion: _terms.version,
      );
      if (!mounted) return;
      // The owner now has a fixed time to confirm. The waiting screen takes
      // this one's place, so Back from it lands on the rental list.
      await Navigator.pushReplacement<void, void>(
        context,
        MaterialPageRoute(
          builder: (_) => RentalWaitingScreen(booking: booking),
        ),
      );
    } on RentalRefused catch (refusal) {
      if (!mounted) return;
      setState(() {
        _error = refusal.message;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _busy = false;
      });
    }
  }

  String get _buttonLabel {
    if (_busy) return _t('Working…', 'کام ہو رہا ہے…');
    if (widget.vehicle.isDemo) {
      return _t('Demo · not bookable', 'ڈیمو · بک نہیں ہو سکتی');
    }
    final quote = _quote;
    if (quote == null) return _t('Choose your dates first', 'پہلے تاریخیں چنیں');
    if (quote.documentsMissing) {
      return _t('Add your documents first', 'پہلے کاغذات دیں');
    }
    return _t(
      'Pay advance · ${Money.amount(quote.advanceAmount)}',
      'ایڈوانس دیں · ${Money.amount(quote.advanceAmount)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    final overline = AppType.caption.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: .3,
      color: AppText.secondary,
    );
    final dates = _dates;
    final dayCount =
        dates == null ? 0 : dates.end.difference(dates.start).inDays + 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _Hero(
                    url: v.photoUrl,
                    onBack: () => Navigator.maybePop(context),
                    backLabel: _t('Back', 'واپس'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _titleBlock(v),
                        const SizedBox(height: 16),
                        if (v.isDemo) ...[
                          UdBanner(
                            tone: UdTone.warn,
                            icon: Icons.info_outline_rounded,
                            text: _t(
                              demoListingMessage,
                              'یہ ڈیمو گاڑی ہے جو دکھاتی ہے کہ UDrive کیسے کام کرتا ہے۔ اسے بک نہیں کیا جا سکتا۔',
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _specs(v),
                        const SizedBox(height: 16),

                        if (_error != null) ...[
                          UdBanner(tone: UdTone.err, text: _error),
                          const SizedBox(height: 14),
                        ],
                        if (_termsUnavailable) ...[
                          UdBanner(
                            tone: UdTone.warn,
                            icon: Icons.wifi_off_rounded,
                            text: _t(
                              'The current rental terms could not be loaded, '
                              'so a booking cannot be made right now. Pull '
                              'down to try again.',
                              'کرائے کی موجودہ شرائط نہیں آ سکیں، اس لیے ابھی '
                                  'بکنگ نہیں ہو سکتی۔ دوبارہ کوشش کے لیے نیچے '
                                  'کھینچیں۔',
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        _modeToggle(v),
                        const SizedBox(height: 18),

                        // ── dates
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                dayCount == 0
                                    ? _t('DATES', 'تاریخیں')
                                    : _t('DATES · $dayCount DAY(S)',
                                        'تاریخیں · $dayCount دن'),
                                style: overline,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _busy ? null : _pickDates,
                              icon: const Icon(Icons.calendar_month_rounded,
                                  size: 16, color: AppColors.navy),
                              label: Text(
                                _t('Calendar', 'کیلنڈر'),
                                style: AppType.small.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navy,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _dayStrip(),
                        const SizedBox(height: 8),
                        Text(
                          dates == null
                              ? _t(
                                  'Tap a day, then the last day. Minimum '
                                  '${v.minimumDays} day(s). Taken days are '
                                  'crossed out.',
                                  'پہلا دن، پھر آخری دن چنیں۔ کم از کم '
                                      '${v.minimumDays} دن۔ بک شدہ دن کٹے '
                                      'ہوئے ہیں۔',
                                )
                              : '${_d(dates.start)} — ${_d(dates.end)}',
                          style: AppType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppText.secondary,
                          ),
                        ),
                        const SizedBox(height: 18),

                        // ── the money
                        if (_quote != null) ...[
                          _Money(quote: _quote!, t: _t),
                          const SizedBox(height: 18),
                        ],

                        // ── documents, self-drive only
                        if (_quote?.requiresCustomerDocuments == true) ...[
                          Text(_t('YOUR DOCUMENTS', 'آپ کے کاغذات'),
                              style: overline),
                          const SizedBox(height: 10),
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 3.6,
                            children: [
                              _DocTile(
                                label: _t('CNIC front', 'کارڈ سامنے'),
                                done: _documents.cnicFront,
                                onTap: _busy
                                    ? null
                                    : () => _uploadDocument('cnic-front'),
                              ),
                              _DocTile(
                                label: _t('CNIC back', 'کارڈ پیچھے'),
                                done: _documents.cnicBack,
                                onTap: _busy
                                    ? null
                                    : () => _uploadDocument('cnic-back'),
                              ),
                              _DocTile(
                                label: _t('Licence', 'لائسنس'),
                                done: _documents.drivingLicence,
                                onTap: _busy
                                    ? null
                                    : () => _uploadDocument('driving-licence'),
                              ),
                              _DocTile(
                                label: _t('Selfie', 'تصویر'),
                                done: _documents.selfie,
                                onTap: _busy
                                    ? null
                                    : () => _uploadDocument('selfie'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _t(
                              'Needed because you are driving. Asked once — '
                              'only the owner of the car you book sees them.',
                              'آپ خود چلائیں گے اس لیے ضروری۔ ایک بار — صرف '
                                  'اسی گاڑی کا مالک دیکھ سکتا ہے۔',
                            ),
                            style: AppType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppText.secondary,
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],

                        // ── the terms
                        Text(_t('TERMS', 'شرائط'), style: overline),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadii.all(14),
                          ),
                          child: Text(
                            _terms.text(AppControllerScope.of(context)
                                .locale
                                .languageCode),
                            style: AppType.small.copyWith(
                              height: 1.45,
                              color: AppText.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _Check(
                          value: _papersChecked,
                          onChanged: (value) =>
                              setState(() => _papersChecked = value),
                          text: _t(
                            'I will check the vehicle\'s papers — '
                            'registration, insurance, fitness — myself. UDrive '
                            'has not checked them.',
                            'گاڑی کے کاغذات — رجسٹریشن، انشورنس، فٹنس — میں خود '
                                'دیکھوں گا۔ UDrive نے یہ نہیں جانچے۔',
                          ),
                        ),
                        _Check(
                          value: _liabilityAccepted,
                          onChanged: (value) =>
                              setState(() => _liabilityAccepted = value),
                          text: _t(
                            'A fine, a crash or damage during the rental is my '
                            'responsibility.',
                            'کرائے کی مدت میں چالان، حادثہ یا نقصان میری ذمہ '
                                'داری ہے۔',
                          ),
                        ),
                        _Check(
                          value: _conditionPhotos,
                          onChanged: (value) =>
                              setState(() => _conditionPhotos = value),
                          text: _t(
                            'I will photograph the car\'s condition at '
                            'collection — for both sides\' protection.',
                            'گاڑی لیتے وقت اس کی حالت کی تصویریں لوں گا — '
                                'دونوں طرف کے تحفظ کے لیے۔',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── the action, pinned
          Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SafeArea(
              top: false,
              child: Material(
                color: _ready ? AppColors.brand : AppColors.surfaceAlt,
                borderRadius: AppRadii.all(18),
                child: InkWell(
                  onTap: _ready ? _book : null,
                  borderRadius: AppRadii.all(18),
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_busy) ...[
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            _buttonLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.button.copyWith(
                              fontWeight: FontWeight.w800,
                              color: _ready ? AppColors.navy : AppText.disabled,
                            ),
                          ),
                        ),
                        if (_ready) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right_rounded,
                              size: 22, color: AppColors.navy),
                        ],
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

  Widget _titleBlock(RentalVehicle v) {
    final sub = [
      v.colour,
      v.registrationNumber,
      _t('Owner ${v.ownerName}', 'مالک ${v.ownerName}'),
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    final pickup = (v.pickupPoint ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                v.year > 0 ? '${v.name} ${v.year}' : v.name,
                style: AppType.h2.copyWith(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: AppText.primary,
                ),
              ),
            ),
            if (v.isDemo) ...[
              const DemoTag(),
              const SizedBox(width: 6),
            ],
            if (v.ownerRating <= 0) const NewRatingTag(),
            if (v.ownerRating > 0)
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.brandWash,
                  borderRadius: AppRadii.all(9),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 14, color: AppColors.brandInk),
                    const SizedBox(width: 3),
                    Text(
                      v.ownerRating.toStringAsFixed(1),
                      style: AppType.small.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandInk,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          style: AppType.small.copyWith(
            fontWeight: FontWeight.w600,
            color: AppText.secondary,
          ),
        ),
        if (pickup.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.place_rounded,
                  size: 16, color: AppColors.brandInk),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _t('Pickup: $pickup', 'گاڑی یہاں سے: $pickup'),
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppText.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _specs(RentalVehicle v) {
    final yes = _t('Yes', 'ہاں');
    final no = _t('No', 'نہیں');
    final cells = <(String, String)>[
      ('${v.passengerCapacity}', _t('seats', 'سیٹیں')),
      ('${v.luggageCapacity}', _t('bags', 'بیگ')),
      (v.hasAirConditioning ? 'AC' : no, _t('cooling', 'اے سی')),
      (
        v.kmPerDay == null ? _t('Open', 'کھلا') : '${v.kmPerDay} km',
        _t('per day', 'فی دن'),
      ),
      (v.fuelIncluded ? yes : no, _t('fuel incl.', 'پٹرول شامل')),
      (
        _t('${v.minimumDays} day(s)', '${v.minimumDays} دن'),
        _t('minimum', 'کم از کم'),
      ),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.75,
      children: [
        for (final cell in cells)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.all(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  cell.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.listTitle.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                Text(
                  cell.$2,
                  maxLines: 1,
                  style: AppType.caption.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppText.secondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _modeToggle(RentalVehicle v) {
    Widget option(String id, String title, double? rate) {
      final on = _mode == id;
      return Expanded(
        child: Material(
          color: on ? AppColors.background : Colors.transparent,
          borderRadius: AppRadii.all(11),
          child: InkWell(
            onTap: _busy ? null : () => _setMode(id),
            borderRadius: AppRadii.all(11),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: on
                  ? BoxDecoration(
                      borderRadius: AppRadii.all(11),
                      boxShadow: AppShadows.card,
                    )
                  : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: AppType.small.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                  Text(
                    _t('${Money.amount(rate ?? 0)} / day',
                        '${Money.amount(rate ?? 0)} / دن'),
                    style: AppType.caption.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: on ? AppColors.brandInk : AppText.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadii.all(14),
      ),
      child: Row(
        children: [
          if (v.offersWithDriver)
            option('WithDriver', _t('With driver', 'ڈرائیور کے ساتھ'),
                v.withDriverDaily),
          if (v.offersWithDriver && v.offersSelfDrive) const SizedBox(width: 4),
          if (v.offersSelfDrive)
            option('SelfDrive', _t('Self drive', 'خود چلائیں'),
                v.selfDriveDaily),
        ],
      ),
    );
  }

  Widget _dayStrip() {
    final today = _dayOnly(DateTime.now());
    final taken = _taken;
    final dates = _dates;
    final start = dates == null ? null : _dayOnly(dates.start);
    final end = dates == null ? null : _dayOnly(dates.end);

    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _stripDays,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final day = today.add(Duration(days: index));
          final blocked = taken.contains(day);
          final isEnd = day == start || day == end;
          final inside = start != null &&
              end != null &&
              day.isAfter(start) &&
              day.isBefore(end);

          final Color fill = blocked
              ? AppColors.surfaceAlt
              : isEnd
                  ? AppColors.navy
                  : inside
                      ? AppColors.brand
                      : AppColors.background;
          final Color ink = blocked
              ? AppText.disabled
              : isEnd
                  ? AppText.onInk
                  : AppText.primary;
          final Color label = blocked
              ? AppText.disabled
              : isEnd
                  ? AppColors.onInkMuted
                  : inside
                      ? AppColors.brandInk
                      : AppText.secondary;

          return Material(
            color: fill,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.all(12),
              side: isEnd || inside
                  ? BorderSide.none
                  : BorderSide(
                      color: blocked
                          ? AppColors.borderStrong
                          : AppColors.border,
                      width: 1.5,
                    ),
            ),
            child: InkWell(
              onTap: blocked || _busy ? null : () => _tapDay(day),
              customBorder:
                  RoundedRectangleBorder(borderRadius: AppRadii.all(12)),
              child: SizedBox(
                width: 46,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _weekdays[day.weekday - 1],
                      style: AppType.caption.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: label,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${day.day}',
                      style: AppType.listTitle.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: ink,
                        decoration:
                            blocked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  static String _d(DateTime value) => '${value.day} ${_months[value.month - 1]}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

/// The owner's photograph across the top, with the back button on it.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.url,
    required this.onBack,
    required this.backLabel,
  });

  final String? url;
  final VoidCallback onBack;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final link = ApiConfig.absoluteUrl(url);
    final Widget fallback = Container(
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: const Icon(Icons.directions_car_rounded,
          size: 64, color: AppColors.navy),
    );

    return SizedBox(
      height: 230,
      child: Stack(
        fit: StackFit.expand,
        children: [
          link.isEmpty
              ? fallback
              : Image.network(
                  link,
                  fit: BoxFit.cover,
                  cacheWidth: 900,
                  errorBuilder: (_, __, ___) => fallback,
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : fallback,
                ),
          Positioned(
            left: 16,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  button: true,
                  label: backLabel,
                  child: Material(
                    color: AppColors.background,
                    borderRadius: AppRadii.all(14),
                    child: InkWell(
                      onTap: onBack,
                      borderRadius: AppRadii.all(14),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.chevron_left_rounded,
                            size: 26, color: AppColors.navy),
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
}

/// One identity document: lime with a tick when on file, dashed to add.
class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.label,
    required this.done,
    required this.onTap,
  });

  final String label;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: done ? AppColors.brandWash : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(12),
        side: done
            ? BorderSide.none
            : const BorderSide(color: AppColors.borderStrong, width: 1.5),
      ),
      child: InkWell(
        onTap: done ? null : onTap,
        customBorder: RoundedRectangleBorder(borderRadius: AppRadii.all(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              done ? Icons.check_rounded : Icons.add_rounded,
              size: 16,
              color: done ? AppColors.brandInk : AppColors.navy,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.small.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: done ? AppColors.brandInk : AppText.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The money, with the deposit on its own line.
///
/// The deposit is the line this screen exists to get right. Folded into a total
/// it looks like a price and turns into an argument at handover; on its own
/// line, marked refundable, it is what it is.
class _Money extends StatelessWidget {
  const _Money({required this.quote, required this.t});

  final RentalQuote quote;
  final String Function(String, String) t;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: AppRadii.all(18),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row(
              t('${quote.days} day(s) × ${Money.amount(quote.dailyRate)}',
                  '${quote.days} دن × ${Money.amount(quote.dailyRate)}'),
              Money.amount(quote.subtotal),
            ),
            _row(
              t('Security deposit (refundable)',
                  'سیکیورٹی ڈیپازٹ (واپس ہونے والا)'),
              Money.amount(quote.securityDeposit),
            ),
            _row(
              t('Fuel', 'پٹرول'),
              quote.fuelIncluded ? t('Included', 'شامل') : t('Yours', 'آپ کا'),
            ),
            if (quote.kmIncluded != null)
              _row(
                t('Kilometres included', 'شامل کلومیٹر'),
                '${quote.kmIncluded} km',
              ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    t('Pay now (advance)', 'ابھی (ایڈوانس)'),
                    style: AppType.body2.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppText.primary,
                    ),
                  ),
                ),
                Text(
                  Money.amount(quote.advanceAmount),
                  style: AppType.h3.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
              ],
            ),
            _row(
              t('Balance at pickup', 'گاڑی لیتے وقت باقی'),
              Money.amount(quote.balanceDue),
            ),
            const SizedBox(height: 4),
            Text(
              t(
                'The balance and the deposit are paid to the owner in cash '
                'when you collect the car. UDrive never holds the deposit.',
                'باقی رقم اور ڈیپازٹ گاڑی لیتے وقت مالک کو نقد دیے جاتے ہیں۔ '
                    'ڈیپازٹ UDrive کے پاس کبھی نہیں آتا۔',
              ),
              style: AppType.caption.copyWith(color: AppText.caption),
            ),
          ],
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppType.small.copyWith(color: AppText.secondary)),
            ),
            Text(
              value,
              style: AppType.body2.copyWith(
                fontWeight: FontWeight.w800,
                color: AppText.primary,
              ),
            ),
          ],
        ),
      );
}

class _Check extends StatelessWidget {
  const _Check({
    required this.value,
    required this.onChanged,
    required this.text,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: UdCheckboxRow(
          value: value,
          onChanged: onChanged,
          semanticLabel: text,
          child: Text(
            text,
            style: AppType.small.copyWith(color: AppText.primary),
          ),
        ),
      );
}
