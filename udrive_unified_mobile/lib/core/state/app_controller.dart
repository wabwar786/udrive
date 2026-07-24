import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';

class AppController extends ChangeNotifier {
  AppController();

  bool _initialized = false;
  bool _loggedIn = false;
  Locale _locale = const Locale('en');
  UserMode _mode = UserMode.customer;
  bool _driverOnline = true;
  int _walletBalance = 15700;

  final List<VehicleRecord> _vehicles = [
    VehicleRecord(
      id: 'V-1001',
      make: 'Honda',
      model: 'BR-V',
      year: 2021,
      color: 'Pearl White',
      registration: 'ICT-2190',
      category: 'SUV',
      seats: 6,
      luggage: 4,
      airConditioning: true,
      fourWheelDrive: false,
      status: VerificationStatus.verified,
      documents: {
        'Registration document': true,
        'Insurance document': true,
        'Fitness certificate': true,
        'Front photo': true,
        'Rear photo': true,
      },
    ),
  ];

  final List<TourPackage> _driverPackages = [tourPackages.first];
  final List<RideRequest> _requests = List<RideRequest>.from(rideRequests);
  final List<AdvanceBooking> _advanceBookings = [];
  final List<TourInterest> _tourInterests = [];
  final List<FamilyTourPlan> _familyPlans = [];

  bool get initialized => _initialized;
  bool get loggedIn => _loggedIn;
  Locale get locale => _locale;
  UserMode get mode => _mode;
  bool get driverOnline => _driverOnline;
  bool get driverApproved => _vehicles.any((v) => v.status == VerificationStatus.verified);
  int get walletBalance => _walletBalance;
  List<VehicleRecord> get vehicles => List.unmodifiable(_vehicles);
  List<TourPackage> get driverPackages => List.unmodifiable(_driverPackages);
  List<RideRequest> get requests => List.unmodifiable(_requests);
  List<AdvanceBooking> get advanceBookings => List.unmodifiable(_advanceBookings);
  List<TourInterest> get tourInterests => List.unmodifiable(_tourInterests);
  List<FamilyTourPlan> get familyPlans => List.unmodifiable(_familyPlans);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _loggedIn = prefs.getBool('loggedIn') ?? false;
    _locale = Locale(prefs.getString('language') ?? 'en');
    _mode = (prefs.getString('mode') ?? 'customer') == 'driver' ? UserMode.driver : UserMode.customer;
    _driverOnline = prefs.getBool('driverOnline') ?? true;
    _initialized = true;
    notifyListeners();
  }

  Future<void> login() async {
    _loggedIn = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loggedIn', true);
    notifyListeners();
  }

  Future<void> logout() async {
    _loggedIn = false;
    _mode = UserMode.customer;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loggedIn', false);
    await prefs.setString('mode', 'customer');
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    if (_locale.languageCode == code) return;
    _locale = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', code);
    notifyListeners();
  }

  Future<void> switchMode(UserMode value) async {
    _mode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mode', value.name);
    notifyListeners();
  }

  Future<void> toggleDriverOnline(bool value) async {
    _driverOnline = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('driverOnline', value);
    notifyListeners();
  }

  void addVehicle(VehicleRecord vehicle) {
    _vehicles.add(vehicle);
    notifyListeners();
  }

  void addPackage(TourPackage package) {
    _driverPackages.add(package);
    notifyListeners();
  }

  void addAdvanceBooking(AdvanceBooking booking) {
    _advanceBookings.insert(0, booking);
    notifyListeners();
  }

  void addTourInterest(TourInterest interest) {
    _tourInterests.insert(0, interest);
    notifyListeners();
  }

  void addFamilyPlan(FamilyTourPlan plan) {
    _familyPlans.insert(0, plan);
    notifyListeners();
  }

  void acceptRequest(RideRequest request) {
    request.status = 'Accepted';
    notifyListeners();
  }

  void counterRequest(RideRequest request, int amount) {
    request.status = 'Countered: PKR $amount';
    notifyListeners();
  }

  void requestPayout(int amount) {
    if (amount <= 0 || amount > _walletBalance) return;
    _walletBalance -= amount;
    notifyListeners();
  }
}

class AppControllerScope extends InheritedNotifier<AppController> {
  const AppControllerScope({required AppController controller, required super.child, super.key}) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppControllerScope>();
    assert(scope != null, 'AppControllerScope not found');
    return scope!.notifier!;
  }
}
