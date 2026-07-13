import 'package:flutter/material.dart';

class AppLanguageScope extends InheritedWidget {
  const AppLanguageScope({
    required this.locale,
    required this.setLanguage,
    required super.child,
    super.key,
  });

  final Locale locale;
  final ValueChanged<String> setLanguage;

  static AppLanguageScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    assert(scope != null, 'AppLanguageScope not found');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppLanguageScope oldWidget) => locale != oldWidget.locale;
}

class S {
  static const Map<String, Map<String, String>> _values = {
    'en': {
      'home': 'Home', 'explore': 'Explore', 'trips': 'Trips', 'profile': 'Profile',
      'greeting': 'Assalam-o-Alaikum, Shahzad', 'whereTo': 'Where would you like to go?',
      'localRide': 'Local Ride', 'intercity': 'Intercity', 'fullDay': 'Full-Day Vehicle',
      'packages': 'Tour Packages', 'jeep': '4×4 Jeep', 'shared': 'Shared Ride',
      'popular': 'Popular in Azad Kashmir', 'viewAll': 'View all', 'roadAlert': 'Road & weather advisory',
      'pickup': 'Pickup location', 'destination': 'Destination', 'dateTime': 'Date & time',
      'passengers': 'Passengers', 'luggage': 'Luggage', 'offerFare': 'Your fare offer',
      'requestRide': 'Request ride', 'suggestedFare': 'Suggested fare', 'offers': 'Driver offers',
      'selectDriver': 'Select driver', 'counterOffer': 'Counteroffer', 'bookNow': 'Book now',
      'upcoming': 'Upcoming', 'completed': 'Completed', 'wallet': 'Wallet', 'savedPlaces': 'Saved places',
      'safety': 'Safety centre', 'support': 'Help & support', 'language': 'Language',
      'details': 'Package details', 'included': 'Included', 'itinerary': 'Itinerary',
      'sendOffer': 'Send price offer', 'fixedPrice': 'Listed price', 'confirmBooking': 'Confirm booking',
      'rideConfirmed': 'Ride confirmed', 'driverArriving': 'Your driver is arriving',
      'english': 'English', 'urdu': 'Urdu', 'cancel': 'Cancel', 'continueText': 'Continue',
    },
    'ur': {
      'home': 'ہوم', 'explore': 'دریافت', 'trips': 'سفر', 'profile': 'پروفائل',
      'greeting': 'السلام علیکم، شہزاد', 'whereTo': 'آپ کہاں جانا چاہتے ہیں؟',
      'localRide': 'مقامی سواری', 'intercity': 'بین الاضلاعی', 'fullDay': 'پورے دن کی گاڑی',
      'packages': 'ٹور پیکجز', 'jeep': 'فور بائی فور جیپ', 'shared': 'مشترکہ سواری',
      'popular': 'آزاد کشمیر میں مقبول', 'viewAll': 'سب دیکھیں', 'roadAlert': 'سڑک اور موسم کی اطلاع',
      'pickup': 'پک اپ مقام', 'destination': 'منزل', 'dateTime': 'تاریخ اور وقت',
      'passengers': 'مسافر', 'luggage': 'سامان', 'offerFare': 'آپ کی کرایہ پیشکش',
      'requestRide': 'سواری کی درخواست', 'suggestedFare': 'تجویز کردہ کرایہ', 'offers': 'ڈرائیور آفرز',
      'selectDriver': 'ڈرائیور منتخب کریں', 'counterOffer': 'جوابی آفر', 'bookNow': 'ابھی بک کریں',
      'upcoming': 'آنے والے', 'completed': 'مکمل', 'wallet': 'والیٹ', 'savedPlaces': 'محفوظ مقامات',
      'safety': 'سیفٹی سنٹر', 'support': 'مدد اور سپورٹ', 'language': 'زبان',
      'details': 'پیکج کی تفصیل', 'included': 'شامل', 'itinerary': 'سفر کا منصوبہ',
      'sendOffer': 'قیمت کی پیشکش بھیجیں', 'fixedPrice': 'مقررہ قیمت', 'confirmBooking': 'بکنگ کی تصدیق',
      'rideConfirmed': 'سواری کی تصدیق ہوگئی', 'driverArriving': 'آپ کا ڈرائیور آ رہا ہے',
      'english': 'انگریزی', 'urdu': 'اردو', 'cancel': 'منسوخ', 'continueText': 'جاری رکھیں',
    },
  };

  static String of(BuildContext context, String key) {
    final code = Localizations.localeOf(context).languageCode;
    return _values[code]?[key] ?? _values['en']![key] ?? key;
  }
}
