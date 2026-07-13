import 'package:flutter/material.dart';

enum UserMode { customer, driver }

class AppController extends ChangeNotifier {
  AppController({
    UserMode initialMode = UserMode.customer,
    Locale initialLocale = const Locale('en'),
  })  : _mode = initialMode,
        _locale = initialLocale;

  UserMode _mode;
  Locale _locale;
  bool _driverApproved = true;
  bool _driverOnline = true;

  UserMode get mode => _mode;
  Locale get locale => _locale;
  bool get driverApproved => _driverApproved;
  bool get driverOnline => _driverOnline;

  void setLanguage(String code) {
    if (_locale.languageCode == code) return;
    _locale = Locale(code);
    notifyListeners();
  }

  void switchMode(UserMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  void setDriverApproved(bool value) {
    _driverApproved = value;
    notifyListeners();
  }

  void setDriverOnline(bool value) {
    _driverOnline = value;
    notifyListeners();
  }
}

class AppControllerScope extends InheritedNotifier<AppController> {
  const AppControllerScope({
    required AppController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppControllerScope>();
    assert(scope != null, 'AppControllerScope not found');
    return scope!.notifier!;
  }
}
