import 'package:flutter/material.dart';
class DriverLanguageScope extends InheritedWidget {
  const DriverLanguageScope({required this.locale, required this.setLanguage, required super.child, super.key});
  final Locale locale; final ValueChanged<String> setLanguage;
  static DriverLanguageScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DriverLanguageScope>()!;
  @override bool updateShouldNotify(DriverLanguageScope oldWidget) => locale != oldWidget.locale;
}
class DS {
  static const values = {
    'en': {'home':'Home','requests':'Requests','packages':'Packages','earnings':'Earnings','profile':'Profile','online':'You are online','offline':'You are offline','today':'Today','newRequests':'New ride requests','createPackage':'Create package','myPackages':'My packages','saveDraft':'Save draft','submitApproval':'Submit for approval','language':'Language','accept':'Accept','counter':'Counteroffer','decline':'Decline'},
    'ur': {'home':'ہوم','requests':'درخواستیں','packages':'پیکجز','earnings':'آمدنی','profile':'پروفائل','online':'آپ آن لائن ہیں','offline':'آپ آف لائن ہیں','today':'آج','newRequests':'نئی سواری کی درخواستیں','createPackage':'پیکج بنائیں','myPackages':'میرے پیکجز','saveDraft':'مسودہ محفوظ کریں','submitApproval':'منظوری کے لیے بھیجیں','language':'زبان','accept':'قبول کریں','counter':'جوابی آفر','decline':'رد کریں'}
  };
  static String of(BuildContext c, String k) => values[Localizations.localeOf(c).languageCode]?[k] ?? values['en']![k] ?? k;
}
