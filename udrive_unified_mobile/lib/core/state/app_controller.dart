import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/auth_repository.dart';
import '../auth/session_store.dart';
import '../../models/auth_models.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';

class AppController extends ChangeNotifier {
  AppController();

  final SessionStore _sessionStore = SessionStore();
  late final AuthRepository _authRepository = AuthRepository(_sessionStore);

  bool _initialized = false;
  bool _loggedIn = false;
  bool _authBusy = false;
  String? _authError;
  CurrentUser? _currentUser;
  OtpChallenge? _lastOtp;
  DriverProfileLive? _driverProfile;
  List<LiveVehicle> _liveVehicles = const [];
  Locale _locale = const Locale('en');
  UserMode _mode = UserMode.customer;
  bool _driverOnline = true;
  int _walletBalance = 15700;
  ShareDuration _shareDuration = ShareDuration.untilDestination;

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
      heating: true,
      firstAidKit: true,
      fireExtinguisher: true,
      spareTyre: true,
      roofCarrier: true,
      childSeat: true,
      status: VerificationStatus.verified,
      routeEligibility: const ['City', 'Intercity', 'Family tours', 'Neelum Valley'],
      documents: const {
        'Registration document': true,
        'Insurance document': true,
        'Fitness certificate': true,
        'Front photo': true,
        'Rear photo': true,
        'Interior photo': true,
      },
    ),
  ];

  final List<TourPackage> _driverPackages = [tourPackages.first];
  final List<RideRequest> _requests = List<RideRequest>.from(rideRequests);
  final List<AdvanceBooking> _advanceBookings = [];
  final List<TourInterest> _tourInterests = [];
  final List<FamilyTourPlan> _familyPlans = [];
  final List<PackageBooking> _packageBookings = [
    PackageBooking(
      id: 'PB-2041',
      packageTitle: '3-Day Neelum Valley Escape',
      customer: 'Ayesha Noor',
      phone: '+92 300 555 0188',
      travelDate: '15 Aug 2026',
      bookingType: BookingType.perSeat,
      seats: 3,
      total: 36000,
      status: 'Confirmed',
    ),
    PackageBooking(
      id: 'PB-2042',
      packageTitle: '3-Day Neelum Valley Escape',
      customer: 'Hassan Ali',
      phone: '+92 333 220 1104',
      travelDate: '15 Aug 2026',
      bookingType: BookingType.perSeat,
      seats: 2,
      total: 24000,
    ),
  ];

  final List<TrustedContact> _trustedContacts = [
    TrustedContact(
      id: 'TC-1',
      name: 'Amir Qureshi',
      relationship: 'Brother',
      phone: '+92 300 555 0112',
      whatsapp: '+92 300 555 0112',
      isGuardian: true,
    ),
    TrustedContact(
      id: 'TC-2',
      name: 'Sara Ahmad',
      relationship: 'Spouse',
      phone: '+92 321 400 8891',
      whatsapp: '+92 321 400 8891',
    ),
  ];

  final LiveTripSession _liveTrip = LiveTripSession(
    id: 'TR-2048',
    route: 'Ghari Pan → Keran → Sharda',
    driver: 'Adeel Khan',
    vehicle: 'Honda BR-V 2022',
    registration: 'AJK-2190',
    destination: 'Keran, Neelum Valley',
    etaMinutes: 96,
    currentLocation: 'Near Kohala Bridge',
  );

  final List<SafetyCheckIn> _checkIns = [
    SafetyCheckIn(id: 'SC-1', tripId: 'TR-2048', prompt: 'Are you safe and comfortable?', dueLabel: 'Due in 18 minutes'),
    SafetyCheckIn(id: 'SC-2', tripId: 'TR-2048', prompt: 'Confirm arrival at the planned rest stop.', dueLabel: 'After 1 hour'),
  ];

  final List<SafetyIncident> _incidents = [];
  final List<RoadReport> _roadReports = [
    RoadReport(
      id: 'RR-101',
      route: 'Muzaffarabad → Keran',
      type: 'Light rain',
      details: 'Road is open. Daylight travel is recommended.',
      reportedAt: 'Today, 8:20 AM',
      status: 'Verified by operations',
    ),
  ];

  bool get initialized => _initialized;
  bool get loggedIn => _loggedIn;
  bool get authBusy => _authBusy;
  String? get authError => _authError;
  CurrentUser? get currentUser => _currentUser;
  OtpChallenge? get lastOtp => _lastOtp;
  DriverProfileLive? get driverProfile => _driverProfile;
  List<LiveVehicle> get liveVehicles => List.unmodifiable(_liveVehicles);
  String get currentUserName => _currentUser?.fullName ?? 'uDrive User';
  String get currentUserPhone => _currentUser?.phoneNumber ?? '';
  String get driverVerificationStatus =>
      _currentUser?.driverVerificationStatus ?? _driverProfile?.verificationStatus ?? 'Not registered';
  Locale get locale => _locale;
  UserMode get mode => _mode;
  bool get driverOnline => _driverOnline;
  bool get driverApproved => _currentUser?.driverModeAvailable == true;
  int get walletBalance => _walletBalance;
  List<VehicleRecord> get vehicles => List.unmodifiable(_vehicles);
  List<TourPackage> get driverPackages => List.unmodifiable(_driverPackages);
  List<RideRequest> get requests => List.unmodifiable(_requests);
  List<AdvanceBooking> get advanceBookings => List.unmodifiable(_advanceBookings);
  List<TourInterest> get tourInterests => List.unmodifiable(_tourInterests);
  List<FamilyTourPlan> get familyPlans => List.unmodifiable(_familyPlans);
  List<PackageBooking> get packageBookings => List.unmodifiable(_packageBookings);
  List<TrustedContact> get trustedContacts => List.unmodifiable(_trustedContacts);
  LiveTripSession get liveTrip => _liveTrip;
  List<SafetyCheckIn> get safetyCheckIns => List.unmodifiable(_checkIns);
  List<SafetyIncident> get incidents => List.unmodifiable(_incidents);
  List<RoadReport> get roadReports => List.unmodifiable(_roadReports);
  ShareDuration get shareDuration => _shareDuration;
  TrustedContact? get guardian {
    for (final contact in _trustedContacts) {
      if (contact.isGuardian) return contact;
    }
    return null;
  }

  OfflineTravelCard get offlineTravelCard => OfflineTravelCard(
        bookingId: _liveTrip.id,
        driver: _liveTrip.driver,
        driverPhone: '+92 300 901 2204',
        vehicle: _liveTrip.vehicle,
        registration: _liveTrip.registration,
        pickup: 'Ghari Pan, Muzaffarabad',
        destination: _liveTrip.destination,
        tripOtp: '6421',
        emergencyNumbers: const ['Rescue 1122', 'Police 15', 'uDrive Safety +92 300 000 1122'],
        itinerary: const ['Muzaffarabad', 'Kohala viewpoint', 'Keran', 'Sharda'],
        hotel: 'Neelum View Hotel, Keran',
        lastKnownLocation: _liveTrip.currentLocation,
      );

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _locale = Locale(prefs.getString('language') ?? 'en');
    _mode = (prefs.getString('mode') ?? 'customer') == 'driver'
        ? UserMode.driver
        : UserMode.customer;
    _driverOnline = prefs.getBool('driverOnline') ?? true;
    _liveTrip.shareEnabled = prefs.getBool('liveShareEnabled') ?? false;
    _currentUser = await _sessionStore.readUser();
    final accessToken = await _sessionStore.readAccessToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      try {
        _currentUser = await _authRepository.me();
        _loggedIn = true;
        await _loadDriverState();
      } catch (_) {
        await _sessionStore.clear();
        _currentUser = null;
        _loggedIn = false;
        _mode = UserMode.customer;
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<OtpChallenge> requestOtp(String phoneNumber) async {
    _setAuthBusy(true);
    try {
      _lastOtp = await _authRepository.requestOtp(phoneNumber);
      _authError = null;
      return _lastOtp!;
    } on ApiException catch (error) {
      _authError = error.message;
      rethrow;
    } finally {
      _setAuthBusy(false);
    }
  }

  Future<void> verifyOtp({
    required String phoneNumber,
    required String code,
    required String fullName,
  }) async {
    _setAuthBusy(true);
    try {
      _currentUser = await _authRepository.verifyOtp(
        phoneNumber: phoneNumber,
        code: code,
        fullName: fullName,
        language: _locale.languageCode,
      );
      _loggedIn = true;
      _authError = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('loggedIn', true);
      await _loadDriverState();
    } on ApiException catch (error) {
      _authError = error.message;
      rethrow;
    } finally {
      _setAuthBusy(false);
    }
  }

  Future<void> login() async {
    await requestOtp('03000000001');
    await verifyOtp(
      phoneNumber: '03000000001',
      code: '1234',
      fullName: 'uDrive Demo Driver',
    );
  }

  Future<void> refreshAccount() async {
    if (!_loggedIn) return;
    _currentUser = await _authRepository.me();
    await _loadDriverState();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _authRepository.logout();
    } catch (_) {
      await _sessionStore.clear();
    }
    _loggedIn = false;
    _currentUser = null;
    _driverProfile = null;
    _liveVehicles = const [];
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
    if (value == UserMode.driver) await _loadDriverState();
    notifyListeners();
  }

  Future<DriverProfileLive> saveDriverProfile(Map<String, dynamic> payload) async {
    _driverProfile = await _authRepository.saveDriverProfile(payload);
    _currentUser = await _authRepository.me();
    notifyListeners();
    return _driverProfile!;
  }

  Future<void> uploadDriverDocument(String type, PlatformFile file, {String? expiryDate}) async {
    await _authRepository.uploadDriverDocument(
      documentType: type,
      file: file,
      expiryDate: expiryDate,
    );
    notifyListeners();
  }

  Future<DriverProfileLive> submitDriverProfile() async {
    _driverProfile = await _authRepository.submitDriverProfile();
    _currentUser = await _authRepository.me();
    notifyListeners();
    return _driverProfile!;
  }

  Future<LiveVehicle> createLiveVehicle(Map<String, dynamic> payload) async {
    final vehicle = await _authRepository.createVehicle(payload);
    _liveVehicles = [vehicle, ..._liveVehicles.where((item) => item.id != vehicle.id)];
    notifyListeners();
    return vehicle;
  }

  Future<void> uploadLiveVehicleDocument(
    String vehicleId,
    String type,
    PlatformFile file, {
    String? expiryDate,
  }) async {
    await _authRepository.uploadVehicleDocument(
      vehicleId: vehicleId,
      documentType: type,
      file: file,
      expiryDate: expiryDate,
    );
    _liveVehicles = await _authRepository.getVehicles();
    notifyListeners();
  }

  Future<LiveVehicle> submitLiveVehicle(String vehicleId) async {
    final vehicle = await _authRepository.submitVehicle(vehicleId);
    _liveVehicles = [vehicle, ..._liveVehicles.where((item) => item.id != vehicle.id)];
    notifyListeners();
    return vehicle;
  }

  Future<void> _loadDriverState() async {
    try {
      _driverProfile = await _authRepository.getDriverProfile();
      _liveVehicles = _driverProfile == null ? const [] : await _authRepository.getVehicles();
    } catch (_) {
      _driverProfile = null;
      _liveVehicles = const [];
    }
  }

  void _setAuthBusy(bool value) {
    _authBusy = value;
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

  void updateVehicleStatus(String id, VerificationStatus status) {
    final vehicle = _vehicles.firstWhere((item) => item.id == id);
    vehicle.status = status;
    notifyListeners();
  }

  void addPackage(TourPackage package) {
    _driverPackages.insert(0, package);
    notifyListeners();
  }

  void togglePackage(String id) {
    final package = _driverPackages.firstWhere((item) => item.id == id);
    package.status = package.status == 'Active' ? 'Paused' : 'Active';
    notifyListeners();
  }

  void updatePackageBooking(String id, String status) {
    final booking = _packageBookings.firstWhere((item) => item.id == id);
    booking.status = status;
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

  void addTrustedContact(TrustedContact contact) {
    _trustedContacts.add(contact);
    notifyListeners();
  }

  void removeTrustedContact(String id) {
    _trustedContacts.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void setGuardian(String id) {
    for (final contact in _trustedContacts) {
      contact.isGuardian = contact.id == id;
    }
    notifyListeners();
  }

  Future<void> setLiveSharing(bool value, ShareDuration duration) async {
    _liveTrip.shareEnabled = value;
    _shareDuration = duration;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('liveShareEnabled', value);
    notifyListeners();
  }

  void advanceLiveTrip() {
    final next = (_liveTrip.progress + .06).clamp(0.0, 1.0).toDouble();
    applySimulatedLocation(
      label: next < .45
          ? 'Kohala Road'
          : next < .72
              ? 'Near Athmuqam'
              : next < 1
                  ? 'Approaching Keran'
                  : 'Keran, Neelum Valley',
      progress: next,
      etaMinutes: (_liveTrip.etaMinutes - 6).clamp(0, 300).toInt(),
    );
  }

  void applySimulatedLocation({required String label, required double progress, required int etaMinutes}) {
    _liveTrip.currentLocation = label;
    _liveTrip.progress = progress.clamp(0.0, 1.0).toDouble();
    _liveTrip.etaMinutes = etaMinutes.clamp(0, 300).toInt();
    _liveTrip.lastUpdated = 'Just now';
    notifyListeners();
  }

  void setRouteDeviation(bool value) {
    _liveTrip.routeDeviation = value;
    if (value) {
      createIncident(
        title: 'Route deviation detected',
        details: 'Vehicle moved away from the planned Muzaffarabad–Keran route.',
        location: _liveTrip.currentLocation,
        severity: 'Medium',
      );
    }
    notifyListeners();
  }

  void respondToCheckIn(String id, SafetyCheckInStatus status) {
    final checkIn = _checkIns.firstWhere((item) => item.id == id);
    checkIn.status = status;
    if (status == SafetyCheckInStatus.unsafe || status == SafetyCheckInStatus.medicalHelp) {
      createIncident(
        title: status == SafetyCheckInStatus.medicalHelp ? 'Medical help requested' : 'Passenger reported unsafe situation',
        details: checkIn.prompt,
        location: _liveTrip.currentLocation,
        severity: 'Critical',
      );
    }
    notifyListeners();
  }

  void createIncident({required String title, required String details, required String location, String severity = 'High'}) {
    _incidents.insert(
      0,
      SafetyIncident(
        id: 'INC-${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        details: details,
        location: location,
        createdAt: 'Just now',
        severity: severity,
      ),
    );
    notifyListeners();
  }

  void resolveIncident(String id) {
    final incident = _incidents.firstWhere((item) => item.id == id);
    incident.status = IncidentStatus.resolved;
    notifyListeners();
  }

  void addRoadReport(RoadReport report) {
    _roadReports.insert(0, report);
    notifyListeners();
  }

  String buildShareLink() => 'https://track.udrive.app/${_liveTrip.id.toLowerCase()}?demo=1';
}

class AppControllerScope extends InheritedNotifier<AppController> {
  const AppControllerScope({required AppController controller, required super.child, super.key}) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppControllerScope>();
    assert(scope != null, 'AppControllerScope not found');
    return scope!.notifier!;
  }
}
