import 'package:flutter/material.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// G-13 — Help guide, in both modes and both languages.
///
/// Rendered inside `main_shell`, which draws the bar, so there is no
/// `Scaffold` here.
class HelpGuideScreen extends StatefulWidget {
  const HelpGuideScreen({required this.driverMode, super.key});

  final bool driverMode;

  @override
  State<HelpGuideScreen> createState() => _HelpGuideScreenState();
}

class _HelpGuideScreenState extends State<HelpGuideScreen> {
  bool _urdu = false;

  /// Which section is open. Null means all closed — and only one is open at a
  /// time, so a long guide does not turn into one unbroken page of steps.
  int? _open;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _urdu = AppControllerScope.of(context).locale.languageCode == 'ur';
  }

  TextDirection get _dir => _urdu ? TextDirection.rtl : TextDirection.ltr;

  @override
  Widget build(BuildContext context) {
    final sections = widget.driverMode ? _driverSections : _customerSections;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sidePadding, 6, AppSizes.sidePadding, 34),
      children: [
        UdCard(
          tone: UdCardTone.navy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const UdIconTile(
                    icon: Icons.help_center_rounded,
                    tone: UdIconTone.lime,
                  ),
                  const Spacer(),
                  // Was a Material SegmentedButton with a white/white12 style
                  // resolver. Two chips say the same thing in the kit's own
                  // shapes, and the unselected one is readable on navy.
                  _LangChip(
                    label: 'English',
                    selected: !_urdu,
                    onTap: () => setState(() => _urdu = false),
                  ),
                  const SizedBox(width: 8),
                  _LangChip(
                    label: 'اردو',
                    selected: _urdu,
                    onTap: () => setState(() => _urdu = true),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                _urdu
                    ? (widget.driverMode
                        ? 'ڈرائیور موڈ استعمال کرنے کا مکمل طریقہ'
                        : 'کسٹمر موڈ استعمال کرنے کا مکمل طریقہ')
                    : (widget.driverMode
                        ? 'How to use Driver mode'
                        : 'How to use Customer mode'),
                textDirection: _dir,
                style: AppType.h2.copyWith(color: AppText.onInk),
              ),
              const SizedBox(height: 8),
              Text(
                _urdu
                    ? 'ہر اہم کام آسان مراحل میں سمجھایا گیا ہے۔ جس سیکشن کی ضرورت ہو اسے کھولیں۔'
                    : 'Every important task is explained in simple steps. Open '
                        'the section you need.',
                textDirection: _dir,
                style: AppType.body2.copyWith(color: AppText.onInkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < sections.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _GuideTile(
              section: sections[i],
              urdu: _urdu,
              expanded: _open == i,
              onTap: () => setState(() => _open = _open == i ? null : i),
            ),
          ),
        const SizedBox(height: 6),
        UdBanner(
          tone: UdTone.warn,
          icon: Icons.support_agent_rounded,
          child: Text(
            _urdu
                ? 'اگر مسئلہ حل نہ ہو تو مینو سے Support کھولیں۔ ایمرجنسی کی صورت میں Safety Hub سے SOS استعمال کریں اور مقامی ایمرجنسی سروس سے رابطہ کریں۔'
                : 'If the issue is not resolved, open Support from the menu. In '
                    'an emergency, use SOS from Safety Hub and contact local '
                    'emergency services.',
            textDirection: _dir,
            style: AppType.body2.copyWith(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppTint.warningText,
            ),
          ),
        ),
      ],
    );
  }
}

/// The two language chips on the navy hero.
class _LangChip extends StatelessWidget {
  const _LangChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.all(AppRadii.chip),
          child: Container(
            height: AppSizes.buttonXs,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? AppColors.brand : Colors.transparent,
              borderRadius: AppRadii.all(AppRadii.chip),
              border: Border.all(
                // Lime when selected, and the muted ink otherwise — white at
                // 12% was a line nobody could see on a phone outdoors.
                color: selected ? AppColors.brand : AppText.onInkMuted,
                width: 1.5,
              ),
            ),
            child: Text(
              label,
              style: AppType.buttonSm.copyWith(
                fontSize: 14,
                color: selected ? AppText.onBrand : AppText.onInk,
              ),
            ),
          ),
        ),
      );
}

/// One guide section: a row you tap, and the numbered steps under it.
class _GuideTile extends StatelessWidget {
  const _GuideTile({
    required this.section,
    required this.urdu,
    required this.expanded,
    required this.onTap,
  });

  final _GuideSection section;
  final bool urdu;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dir = urdu ? TextDirection.rtl : TextDirection.ltr;
    final steps = urdu ? section.stepsUr : section.stepsEn;

    return UdCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadii.all(AppRadii.card),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  textDirection: dir,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UdIconTile(
                      icon: section.icon,
                      tone: expanded ? UdIconTone.lime : UdIconTone.neutral,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            urdu ? section.titleUr : section.titleEn,
                            textDirection: dir,
                            style: AppType.listTitle.copyWith(
                              fontSize: 16,
                              color: AppText.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            urdu ? section.summaryUr : section.summaryEn,
                            textDirection: dir,
                            style: AppType.small
                                .copyWith(color: AppText.secondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.expand_more_rounded,
                          size: 24, color: AppText.secondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOut,
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(
                      height: 1, thickness: 1, color: AppColors.border),
                  const SizedBox(height: 14),
                  for (var i = 0; i < steps.length; i++)
                    Padding(
                      padding:
                          EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 12),
                      child: Row(
                        textDirection: dir,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.navy,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: AppType.caption.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppText.onInk,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              steps[i],
                              textDirection: dir,
                              style: AppType.body2
                                  .copyWith(color: AppText.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideSection {
  const _GuideSection({
    required this.icon,
    required this.titleEn,
    required this.titleUr,
    required this.summaryEn,
    required this.summaryUr,
    required this.stepsEn,
    required this.stepsUr,
  });

  final IconData icon;
  final String titleEn;
  final String titleUr;
  final String summaryEn;
  final String summaryUr;
  final List<String> stepsEn;
  final List<String> stepsUr;
}

const _customerSections = <_GuideSection>[
  _GuideSection(
    icon: Icons.login_rounded,
    titleEn: 'Sign in and account',
    titleUr: 'لاگ اِن اور اکاؤنٹ',
    summaryEn: 'Sign in with your mobile number and manage your profile.',
    summaryUr: 'اپنے موبائل نمبر سے لاگ اِن کریں اور پروفائل مکمل کریں۔',
    stepsEn: ['Enter your name and Pakistan mobile number.', 'Enter the OTP received on your phone.', 'Open Profile to update your name, photo and emergency details.'],
    stepsUr: ['اپنا نام اور پاکستانی موبائل نمبر درج کریں۔', 'موبائل پر موصول ہونے والا او ٹی پی درج کریں۔', 'نام، تصویر اور ایمرجنسی معلومات کے لیے پروفائل کھولیں۔'],
  ),
  _GuideSection(
    icon: Icons.route_rounded,
    titleEn: 'Find a route and vehicle',
    titleUr: 'روٹ اور گاڑی تلاش کریں',
    summaryEn: 'Choose destination first, then select 2, 3 or 4 wheel.',
    summaryUr: 'پہلے منزل منتخب کریں، پھر 2، 3 یا 4 وہیل منتخب کریں۔',
    stepsEn: ['Select 2 Wheel, 3 Wheel or 4 Wheel.', 'Type your destination in the search box or tap View all.', 'Open a route card to check fare, seats, date and vehicle details.'],
    stepsUr: ['2 وہیل، 3 وہیل یا 4 وہیل منتخب کریں۔', 'سرچ باکس میں منزل لکھیں یا View all دبائیں۔', 'کرایہ، خالی نشستیں، تاریخ اور گاڑی کی معلومات دیکھنے کے لیے روٹ کارڈ کھولیں۔'],
  ),
  _GuideSection(
    icon: Icons.local_taxi_rounded,
    titleEn: 'Book a ride',
    titleUr: 'رائیڈ بُک کریں',
    summaryEn: 'Create a request and accept the most suitable Driver offer.',
    summaryUr: 'رائیڈ ریکوئسٹ بنائیں اور مناسب ڈرائیور آفر قبول کریں۔',
    stepsEn: ['Set pickup, destination, date, time and passenger count.', 'Choose per-seat or whole-vehicle booking where available.', 'Review Driver offers and accept one.', 'Track the Driver until pickup, verify the vehicle and share the boarding PIN.', 'Pay the remaining balance and rate the Driver after completion.'],
    stepsUr: ['پک اَپ، منزل، تاریخ، وقت اور مسافروں کی تعداد درج کریں۔', 'جہاں دستیاب ہو فی سیٹ یا پوری گاڑی منتخب کریں۔', 'ڈرائیور آفرز دیکھیں اور مناسب آفر قبول کریں۔', 'پک اَپ تک ڈرائیور کو ٹریک کریں، گاڑی کی تصدیق کریں اور بورڈنگ پن بتائیں۔', 'سفر مکمل ہونے پر باقی رقم ادا کریں اور ڈرائیور کو ریٹنگ دیں۔'],
  ),
  _GuideSection(
    icon: Icons.luggage_rounded,
    titleEn: 'Book a tourism package',
    titleUr: 'ٹورازم پیکیج بُک کریں',
    summaryEn: 'Search approved packages, reserve seats and follow the itinerary.',
    summaryUr: 'منظور شدہ پیکیج تلاش کریں، نشستیں محفوظ کریں اور پروگرام دیکھیں۔',
    stepsEn: ['Open Packages or Join Tour.', 'Check route, itinerary, inclusions, available seats and cancellation policy.', 'Select passengers and payment option.', 'Use My Trips to view booking, boarding and tour status.'],
    stepsUr: ['Packages یا Join Tour کھولیں۔', 'روٹ، روزانہ پروگرام، سہولیات، خالی نشستیں اور کینسلیشن پالیسی دیکھیں۔', 'مسافر اور ادائیگی کا طریقہ منتخب کریں۔', 'بکنگ، بورڈنگ اور ٹور اسٹیٹس دیکھنے کے لیے My Trips کھولیں۔'],
  ),
  _GuideSection(
    icon: Icons.payments_rounded,
    titleEn: 'Payments and refunds',
    titleUr: 'ادائیگی اور ریفنڈ',
    summaryEn: 'See paid, outstanding and refunded amounts.',
    summaryUr: 'ادا شدہ، بقایا اور واپس کی گئی رقم دیکھیں۔',
    stepsEn: ['Open the active booking and tap Pay balance.', 'Select the available payment method.', 'Cash and bank payments may require Admin verification.', 'Refund status appears in booking and payment history.'],
    stepsUr: ['فعال بکنگ کھولیں اور Pay balance دبائیں۔', 'دستیاب ادائیگی کا طریقہ منتخب کریں۔', 'کیش اور بینک ادائیگی کی ایڈمن تصدیق ضروری ہو سکتی ہے۔', 'ریفنڈ کا اسٹیٹس بکنگ اور ادائیگی کی ہسٹری میں نظر آئے گا۔'],
  ),
  _GuideSection(
    icon: Icons.health_and_safety_rounded,
    titleEn: 'Safety, SOS and support',
    titleUr: 'حفاظت، ایس او ایس اور مدد',
    summaryEn: 'Use trusted contacts, live tracking and emergency help.',
    summaryUr: 'ٹرسٹڈ کانٹیکٹس، لائیو ٹریکنگ اور ایمرجنسی مدد استعمال کریں۔',
    stepsEn: ['Add trusted contacts in Safety Hub.', 'Use live tracking only for your active booking.', 'Use SOS only for a real emergency.', 'Create a complaint or safety report with clear details and evidence.'],
    stepsUr: ['Safety Hub میں قابلِ اعتماد رابطے شامل کریں۔', 'لائیو ٹریکنگ صرف اپنی فعال بکنگ کے لیے استعمال کریں۔', 'ایس او ایس صرف حقیقی ایمرجنسی میں استعمال کریں۔', 'شکایت یا حفاظتی رپورٹ واضح تفصیل اور ثبوت کے ساتھ جمع کریں۔'],
  ),
];

const _driverSections = <_GuideSection>[
  _GuideSection(
    icon: Icons.verified_user_rounded,
    titleEn: 'Driver registration and verification',
    titleUr: 'ڈرائیور رجسٹریشن اور تصدیق',
    summaryEn: 'Complete personal, vehicle and document verification before working.',
    summaryUr: 'کام شروع کرنے سے پہلے ذاتی، گاڑی اور دستاویزات کی تصدیق مکمل کریں۔',
    stepsEn: ['Switch to Driver mode.', 'Complete Driver profile and upload required documents.', 'Register your vehicle and choose the correct category.', 'Wait for Admin approval before going online.'],
    stepsUr: ['Driver mode میں جائیں۔', 'ڈرائیور پروفائل مکمل کریں اور ضروری دستاویزات اپ لوڈ کریں۔', 'گاڑی رجسٹر کریں اور درست کیٹیگری منتخب کریں۔', 'آن لائن ہونے سے پہلے ایڈمن منظوری کا انتظار کریں۔'],
  ),
  _GuideSection(
    icon: Icons.two_wheeler_rounded,
    titleEn: '2-wheel, 3-wheel and 4-wheel vehicles',
    titleUr: '2 وہیل، 3 وہیل اور 4 وہیل گاڑیاں',
    summaryEn: 'Register the vehicle you own; customers book matching vehicles.',
    summaryUr: 'اپنی گاڑی رجسٹر کریں؛ کسٹمر اسی قسم کی گاڑی بُک کرے گا۔',
    stepsEn: ['For 2 Wheel select Motorcycle or Scooter.', 'For 3 Wheel select Auto Rickshaw or Tuk Tuk.', 'For 4 Wheel select Car, Sedan, SUV, Van, Hiace, Coaster, Jeep or another allowed category.', 'Set correct passenger capacity and upload vehicle documents.', 'After verification, matching customer requests will appear automatically.'],
    stepsUr: ['2 وہیل کے لیے Motorcycle یا Scooter منتخب کریں۔', '3 وہیل کے لیے Auto Rickshaw یا Tuk Tuk منتخب کریں۔', '4 وہیل کے لیے Car، Sedan، SUV، Van، Hiace، Coaster، Jeep یا دوسری منظور شدہ کیٹیگری منتخب کریں۔', 'درست مسافر گنجائش درج کریں اور گاڑی کے کاغذات اپ لوڈ کریں۔', 'تصدیق کے بعد متعلقہ کسٹمر ریکوئسٹس خود نظر آئیں گی۔'],
  ),
  _GuideSection(
    icon: Icons.notifications_active_rounded,
    titleEn: 'Accept requests and complete trips',
    titleUr: 'ریکوئسٹ قبول کریں اور سفر مکمل کریں',
    summaryEn: 'Send an offer, follow the trip stages and keep GPS active.',
    summaryUr: 'آفر بھیجیں، سفر کے مراحل مکمل کریں اور جی پی ایس فعال رکھیں۔',
    stepsEn: ['Go online and open Ride Requests.', 'Send fare/seat offer for a suitable request.', 'After acceptance, navigate to pickup and tap Arrived.', 'Verify the customer boarding PIN before starting.', 'Start trip, navigate to destination and complete only after arrival.'],
    stepsUr: ['آن لائن ہوں اور Ride Requests کھولیں۔', 'مناسب ریکوئسٹ پر کرایہ یا سیٹ آفر بھیجیں۔', 'قبول ہونے کے بعد پک اَپ پر جائیں اور Arrived دبائیں۔', 'سفر شروع کرنے سے پہلے کسٹمر کا بورڈنگ پن تصدیق کریں۔', 'Trip Start کریں، منزل تک جائیں اور پہنچنے کے بعد ہی مکمل کریں۔'],
  ),
  _GuideSection(
    icon: Icons.tour_rounded,
    titleEn: 'Create and operate tourism packages',
    titleUr: 'ٹورازم پیکیج بنائیں اور چلائیں',
    summaryEn: 'Create packages, wait for approval and manage passenger boarding.',
    summaryUr: 'پیکیج بنائیں، منظوری حاصل کریں اور مسافروں کی بورڈنگ سنبھالیں۔',
    stepsEn: ['Open Create Package and enter route, date, itinerary, seats and prices.', 'Submit the package for Admin approval.', 'After approval, monitor customer bookings in Package Bookings.', 'Open boarding, check in passengers, depart, start and complete the tour in sequence.'],
    stepsUr: ['Create Package میں روٹ، تاریخ، پروگرام، نشستیں اور قیمت درج کریں۔', 'پیکیج ایڈمن منظوری کے لیے جمع کریں۔', 'منظوری کے بعد Package Bookings میں کسٹمر بکنگ دیکھیں۔', 'ترتیب سے بورڈنگ کھولیں، مسافر چیک اِن کریں، روانگی، ٹور شروع اور مکمل کریں۔'],
  ),
  _GuideSection(
    icon: Icons.account_balance_wallet_rounded,
    titleEn: 'Earnings and payouts',
    titleUr: 'کمائی اور ادائیگی وصول کرنا',
    summaryEn: 'Track earnings, commission and payout requests.',
    summaryUr: 'کمائی، کمیشن اور پے آؤٹ ریکوئسٹ دیکھیں۔',
    stepsEn: ['Complete the trip correctly to create earnings.', 'Open Earnings to see pending and available balance.', 'Add a verified bank, Easypaisa or JazzCash payout account.', 'Submit a payout request and wait for Finance approval.'],
    stepsUr: ['کمائی بننے کے لیے سفر درست طریقے سے مکمل کریں۔', 'زیرِ التوا اور دستیاب رقم دیکھنے کے لیے Earnings کھولیں۔', 'تصدیق شدہ بینک، ایزی پیسہ یا جازکیش اکاؤنٹ شامل کریں۔', 'پے آؤٹ ریکوئسٹ جمع کریں اور فنانس منظوری کا انتظار کریں۔'],
  ),
  _GuideSection(
    icon: Icons.health_and_safety_rounded,
    titleEn: 'Driver safety and responsibilities',
    titleUr: 'ڈرائیور کی حفاظت اور ذمہ داریاں',
    summaryEn: 'Keep documents valid, GPS accurate and passengers safe.',
    summaryUr: 'دستاویزات درست، جی پی ایس فعال اور مسافروں کو محفوظ رکھیں۔',
    stepsEn: ['Keep licence, CNIC, registration, insurance and permits valid.', 'Do not start without the correct passenger and boarding PIN.', 'Keep location permission active during an assigned trip.', 'Use SOS or report a safety incident when genuine help is required.'],
    stepsUr: ['لائسنس، شناختی کارڈ، رجسٹریشن، انشورنس اور پرمٹس درست رکھیں۔', 'درست مسافر اور بورڈنگ پن کے بغیر سفر شروع نہ کریں۔', 'تفویض شدہ سفر کے دوران لوکیشن اجازت فعال رکھیں۔', 'حقیقی ضرورت پر ایس او ایس یا حفاظتی رپورٹ استعمال کریں۔'],
  ),
];
