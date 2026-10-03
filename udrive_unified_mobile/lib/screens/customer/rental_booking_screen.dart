import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_config.dart';
import '../../core/rental/rental_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// C-32 to C-35 — taking one car for a set of days.
///
/// Four questions in one screen rather than four pushed screens: which days,
/// with a driver or self-drive, your documents if you are driving, and who
/// carries the risk. They are one decision, and splitting them across pages
/// means a Customer who changes the dates at the end walks the whole path
/// again.
///
/// Every figure on this screen comes from the server. Days × rate looks like
/// arithmetic the app could do, and the three things around it — the advance
/// percentage, the owner's minimum-days rule, and whether those days are even
/// free — are not. An app that worked out its own total would show a number the
/// booking then refuses.
class RentalBookingScreen extends StatefulWidget {
  const RentalBookingScreen({required this.vehicle, this.dates, super.key});

  final RentalVehicle vehicle;
  final DateTimeRange? dates;

  @override
  State<RentalBookingScreen> createState() => _RentalBookingScreenState();
}

class _RentalBookingScreenState extends State<RentalBookingScreen> {
  late final RentalRepository _repository =
      RentalRepository(AppControllerScope.of(context).apiClient);

  DateTimeRange? _dates;
  late String _mode = widget.vehicle.offersWithDriver ? 'WithDriver' : 'SelfDrive';

  List<RentalBlockedDay> _blocked = const [];
  RentalTerms _terms = RentalTerms.fallback;
  RentalQuote? _quote;
  CustomerDocuments _documents = CustomerDocuments.empty;

  bool _papersChecked = false;
  bool _liabilityAccepted = false;
  bool _conditionPhotos = false;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dates = widget.dates;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _t(String en, String ur) =>
      AppControllerScope.of(context).locale.languageCode == 'ur' ? ur : en;

  bool get _ready =>
      _quote != null &&
      !_quote!.documentsMissing &&
      _papersChecked &&
      _liabilityAccepted &&
      _conditionPhotos &&
      !_busy;

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

  /// The date picker, with the taken days closed.
  ///
  /// Closed rather than refused afterwards: the days this car is already out
  /// are known before the Customer touches anything, and letting them pick a
  /// day that cannot work only to say so at the end is the version of this
  /// screen people complain about.
  Future<void> _pickDates() async {
    final now = DateTime.now();
    final taken = <DateTime>{
      for (final day in _blocked) DateTime(day.date.year, day.date.month, day.date.day),
    };

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 120)),
      initialDateRange: _dates,
      selectableDayPredicate: (day, start, end) =>
          !taken.contains(DateTime(day.year, day.month, day.day)),
      helpText: _t('When do you need it?', 'کب چاہیے؟'),
    );

    if (picked == null || !mounted) return;
    setState(() => _dates = picked);
    await _refreshQuote();
  }

  Future<void> _setMode(String mode) async {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    await _refreshQuote();
  }

  Future<void> _uploadDocument(String kind, String label) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    // `.firstOrNull` is from package:collection, which nothing in this app
    // imports — adding it for one call would pull a dependency into the whole
    // tree for no gain.
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
      await _repository.book(
        vehicleId: widget.vehicle.vehicleId,
        from: dates.start,
        to: dates.end,
        mode: _mode,
        // The version belonging to the text on screen, not the one the
        // quote happened to carry. If an Admin edits the terms while this
        // screen is open the server refuses the booking, which is right: the
        // Customer agreed to words that are no longer the words.
        disclaimerVersion: _terms.version,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
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

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: '${vehicle.name} ${vehicle.year}',
        onBack: () => Navigator.maybePop(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 12, AppSizes.sidePadding, 40),
        children: [
          if (vehicle.photoUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.card),
              child: Image.network(
                ApiConfig.absoluteUrl(vehicle.photoUrl),
                height: 190,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            UdBanner(tone: UdTone.err, text: _error),
            const SizedBox(height: 14),
          ],

          // ── dates
          UdSectionHeader(title: _t('When', 'کب')),
          const SizedBox(height: 10),
          UdListGroup(
            children: [
              UdListRow(
                title: _dates == null
                    ? _t('Choose your dates', 'تاریخیں چنیں')
                    : '${_d(_dates!.start)} — ${_d(_dates!.end)}',
                subtitle: _t(
                  'Minimum ${vehicle.minimumDays} day(s). Days already taken '
                  'are closed.',
                  'کم از کم ${vehicle.minimumDays} دن۔ جو دن پہلے سے بُک ہیں وہ '
                      'بند ہیں۔',
                ),
                leading: const UdIconTile(
                  icon: Icons.event_rounded,
                  tone: UdIconTone.soft,
                ),
                onTap: _pickDates,
                showChevron: true,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── how it goes out
          UdSectionHeader(title: _t('How you take it', 'کیسے لیں گے')),
          const SizedBox(height: 10),
          if (vehicle.offersWithDriver)
            _ModeTile(
              icon: Icons.person_outline_rounded,
              title: _t('With a driver', 'ڈرائیور کے ساتھ'),
              subtitle: _t(
                'PKR ${vehicle.withDriverDaily!.round()} / day · no documents '
                'needed',
                'PKR ${vehicle.withDriverDaily!.round()} / دن · کاغذات کی '
                    'ضرورت نہیں',
              ),
              selected: _mode == 'WithDriver',
              onTap: () => _setMode('WithDriver'),
            ),
          if (vehicle.offersWithDriver && vehicle.offersSelfDrive)
            const SizedBox(height: 10),
          if (vehicle.offersSelfDrive)
            _ModeTile(
              icon: Icons.drive_eta_outlined,
              title: _t('Self-drive', 'خود چلائیں'),
              subtitle: _t(
                'PKR ${vehicle.selfDriveDaily!.round()} / day · CNIC and '
                'licence needed',
                'PKR ${vehicle.selfDriveDaily!.round()} / دن · شناختی کارڈ اور '
                    'لائسنس ضروری',
              ),
              selected: _mode == 'SelfDrive',
              onTap: () => _setMode('SelfDrive'),
            ),
          const SizedBox(height: 18),

          // ── the money
          if (_quote != null) ...[
            UdSectionHeader(title: _t('What it costs', 'کتنا بنے گا')),
            const SizedBox(height: 10),
            _Money(quote: _quote!, t: _t),
            const SizedBox(height: 18),
          ],

          // ── documents, self-drive only
          if (_quote?.requiresCustomerDocuments == true) ...[
            UdSectionHeader(title: _t('Your documents', 'آپ کے کاغذات')),
            const SizedBox(height: 10),
            UdBanner(
              tone: UdTone.info,
              icon: Icons.info_outline_rounded,
              text: _t(
                'You are driving, so these are required. Asked once — the next '
                'rental does not ask again. Only the owner of the car you book '
                'can see them.',
                'آپ خود چلائیں گے، اس لیے یہ لازمی ہیں۔ ایک بار دینے پر اگلی '
                    'بکنگ پر دوبارہ نہیں مانگے جاتے۔ صرف اسی گاڑی کا مالک انہیں '
                    'دیکھ سکتا ہے۔',
              ),
            ),
            const SizedBox(height: 12),
            UdListGroup(
              children: [
                _docRow('cnic-front', _t('CNIC — front', 'شناختی کارڈ — سامنے'),
                    _documents.cnicFront),
                _docRow('cnic-back', _t('CNIC — back', 'شناختی کارڈ — پیچھے'),
                    _documents.cnicBack),
                _docRow('driving-licence',
                    _t('Driving licence', 'ڈرائیونگ لائسنس'),
                    _documents.drivingLicence),
                _docRow('selfie', _t('A photo of you', 'آپ کی تصویر'),
                    _documents.selfie),
              ],
            ),
            const SizedBox(height: 18),
          ],

          // ── the terms
          UdSectionHeader(title: _t('Terms', 'شرائط')),
          const SizedBox(height: 10),
          // The wording comes from the server, not from this file. An Admin
          // changes it in the portal and every app sees the new text on the
          // next booking — without a release, a review and a wait.
          UdBanner(
            tone: UdTone.warn,
            icon: Icons.warning_amber_rounded,
            text: _terms.text(
                AppControllerScope.of(context).locale.languageCode),
          ),
          const SizedBox(height: 10),
          _Check(
            value: _papersChecked,
            onChanged: (value) => setState(() => _papersChecked = value),
            text: _t(
              'I will check the vehicle\'s papers — registration, insurance, '
              'fitness — myself. UDrive has not checked them.',
              'گاڑی کے کاغذات — رجسٹریشن، انشورنس، فٹنس — میں خود دیکھوں گا۔ '
                  'UDrive نے یہ نہیں جانچے۔',
            ),
          ),
          _Check(
            value: _liabilityAccepted,
            onChanged: (value) => setState(() => _liabilityAccepted = value),
            text: _t(
              'A fine, a crash or damage during the rental is my '
              'responsibility.',
              'کرائے کی مدت میں چالان، حادثہ یا نقصان میری ذمہ داری ہے۔',
            ),
          ),
          _Check(
            value: _conditionPhotos,
            onChanged: (value) => setState(() => _conditionPhotos = value),
            text: _t(
              'I will photograph the car\'s condition at collection — for both '
              'sides\' protection.',
              'گاڑی لیتے وقت اس کی حالت کی تصویریں لوں گا — دونوں طرف کے تحفظ '
                  'کے لیے۔',
            ),
          ),
          const SizedBox(height: 18),

          UdButton.primary(
            label: _busy
                ? _t('Working…', 'کام ہو رہا ہے…')
                : _quote == null
                    ? _t('Choose your dates first', 'پہلے تاریخیں چنیں')
                    : _t(
                        'Book — pay PKR ${_quote!.advanceAmount.round()} now',
                        'بک کریں — ابھی PKR ${_quote!.advanceAmount.round()}',
                      ),
            onPressed: _ready ? _book : null,
          ),
          const SizedBox(height: 10),
          Text(
            _t(
              'All three boxes have to be ticked. The time you accepted and '
              'which version of these terms is recorded with the booking.',
              'تینوں خانوں پر نشان ضروری ہے۔ آپ نے کب اور شرائط کا کون سا ورژن '
                  'مانا، یہ بکنگ کے ساتھ محفوظ ہوتا ہے۔',
            ),
            style: AppType.caption.copyWith(color: AppText.caption),
          ),
        ],
      ),
    );
  }

  Widget _docRow(String kind, String label, bool done) => UdListRow(
        title: label,
        subtitle: done
            ? _t('Received', 'موصول')
            : _t('Not sent yet', 'ابھی نہیں بھیجا'),
        leading: UdIconTile(
          icon: done ? Icons.check_rounded : Icons.photo_camera_outlined,
          tone: done ? UdIconTone.soft : UdIconTone.neutral,
        ),
        onTap: _busy ? null : () => _uploadDocument(kind, label),
        showChevron: !done,
      );

  static String _d(DateTime value) => '${value.day} ${_months[value.month - 1]}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

/// With a driver, or self-drive.
class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => UdCard(
        selected: selected,
        onTap: onTap,
        child: Row(
          children: [
            UdIconTile(
              icon: icon,
              tone: selected ? UdIconTone.soft : UdIconTone.neutral,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: AppType.h3.copyWith(color: AppText.primary)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style:
                          AppType.small.copyWith(color: AppText.secondary)),
                ],
              ),
            ),
          ],
        ),
      );
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
  Widget build(BuildContext context) => UdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row(
              '${quote.days} × PKR ${quote.dailyRate.round()}',
              'PKR ${quote.subtotal.round()}',
            ),
            _row(
              t('Security deposit (refundable)',
                  'سیکیورٹی ڈیپازٹ (واپس ہونے والا)'),
              'PKR ${quote.securityDeposit.round()}',
            ),
            _row(
              t('Fuel', 'پٹرول'),
              quote.fuelIncluded
                  ? t('Included', 'شامل')
                  : t('Yours', 'آپ کا'),
            ),
            if (quote.kmIncluded != null)
              _row(
                t('Kilometres included', 'شامل کلومیٹر'),
                '${quote.kmIncluded} km',
              ),
            const SizedBox(height: 10),
            Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    t('Pay now through the app', 'ابھی ایپ سے'),
                    style: AppType.body2.copyWith(color: AppText.primary),
                  ),
                ),
                Text(
                  'PKR ${quote.advanceAmount.round()}',
                  style: AppType.h2.copyWith(color: AppText.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'PKR ${quote.balanceDue.round()} and the deposit are paid to '
                'the owner in cash when you collect the car. UDrive never '
                'holds the deposit.',
                'PKR ${quote.balanceDue.round()} اور ڈیپازٹ گاڑی لیتے وقت مالک '
                    'کو نقد دیے جاتے ہیں۔ ڈیپازٹ UDrive کے پاس کبھی نہیں آتا۔',
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
            Text(value,
                style: AppType.body2.copyWith(color: AppText.primary)),
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
