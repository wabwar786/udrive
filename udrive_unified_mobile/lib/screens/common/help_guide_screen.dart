import 'package:flutter/material.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';

class HelpGuideScreen extends StatefulWidget {
  const HelpGuideScreen({required this.driverMode, super.key});

  final bool driverMode;

  @override
  State<HelpGuideScreen> createState() => _HelpGuideScreenState();
}

class _HelpGuideScreenState extends State<HelpGuideScreen> {
  bool _urdu = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _urdu = AppControllerScope.of(context).locale.languageCode == 'ur';
  }

  @override
  Widget build(BuildContext context) {
    final sections = widget.driverMode ? _driverSections : _customerSections;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF063F32), AppColors.primary],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.help_center_rounded, color: Colors.white, size: 34),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('English')),
                      ButtonSegment(value: true, label: Text('اردو')),
                    ],
                    selected: {_urdu},
                    onSelectionChanged: (value) => setState(() => _urdu = value.first),
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected) ? Colors.white : Colors.white12,
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected) ? AppColors.primaryDark : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _urdu
                    ? (widget.driverMode ? 'ڈرائیور موڈ استعمال کرنے کا مکمل طریقہ' : 'کسٹمر موڈ استعمال کرنے کا مکمل طریقہ')
                    : (widget.driverMode ? 'How to use Driver mode' : 'How to use Customer mode'),
                textDirection: _urdu ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              Text(
                _urdu
                    ? 'ہر اہم کام آسان مراحل میں سمجھایا گیا ہے۔ جس سیکشن کی ضرورت ہو اسے کھولیں۔'
                    : 'Every important task is explained in simple steps. Open the section you need.',
                textDirection: _urdu ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...sections.map(
          (section) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: .12),
                child: Icon(section.icon, color: AppColors.primaryDark),
              ),
              title: Text(
                _urdu ? section.titleUr : section.titleEn,
                textDirection: _urdu ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                _urdu ? section.summaryUr : section.summaryEn,
                textDirection: _urdu ? TextDirection.rtl : TextDirection.ltr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: Column(
                    children: [
                      for (var i = 0; i < section.stepsEn.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            textDirection: _urdu ? TextDirection.rtl : TextDirection.ltr,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _urdu ? section.stepsUr[i] : section.stepsEn[i],
                                  textDirection: _urdu ? TextDirection.rtl : TextDirection.ltr,
                                  style: const TextStyle(height: 1.5),
                                ),
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
        ),
        Card(
          color: const Color(0xFFFFF7E8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              textDirection: _urdu ? TextDirection.rtl : TextDirection.ltr,
              children: [
                const Icon(Icons.support_agent_rounded, color: Color(0xFF9B6500)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _urdu
                        ? 'اگر مسئلہ حل نہ ہو تو مینو سے Support کھولیں۔ ایمرجنسی کی صورت میں Safety Hub سے SOS استعمال کریں اور مقامی ایمرجنسی سروس سے رابطہ کریں۔'
                        : 'If the issue is not resolved, open Support from the menu. In an emergency, use SOS from Safety Hub and contact local emergency services.',
                    textDirection: _urdu ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(height: 1.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
