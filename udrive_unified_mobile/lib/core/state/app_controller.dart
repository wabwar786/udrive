import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/auth_repository.dart';
import '../auth/session_store.dart';
import '../booking/booking_repository.dart';
import '../network/api_client.dart';
import '../../models/auth_models.dart';
import '../../models/booking_models.dart';
import '../../data/dummy_data.dart';
import '../../data/models.dart';

class AppController extends ChangeNotifier {
  AppController();

  final SessionStore _sessionStore = SessionStore();
  late final AuthRepository _authRepository = AuthRepository(_sessionStore);
  late final BookingRepository _bookingRepository = BookingRepository(_authRepository.client);

  bool _initialized = false;
  bool _loggedIn = false;
  bool _authBusy = false;
  String? _authError;
  CurrentUser? _currentUser;
  OtpChallenge? _lastOtp;
  DriverProfileLive? _driverProfile;
  List<LiveVehicle> _liveVehicles = const [];
  List<LiveRideRequest> _liveRideRequests = const [];
  List<LiveRideRequest> _liveDriverRideRequests = const [];
  List<LiveDriverOffer> _liveDriverOffers = const [];
  List<LiveDriverRideOfferStatus> _liveDriverRideOfferStatuses = const [];
  List<LiveBooking> _liveBookings = const [];
  List<LiveTourPackage> _liveMarketplacePackages = const [];
  List<LiveTourPackage> _liveDriverPackages = const [];
  List<LivePackageOffer> _liveCustomerPackageOffers = const [];
  List<LivePackageOffer> _liveDriverPackageOffers = const [];
  List<LiveBooking> _liveDriverPackageBookings = const [];
  List<LivePackageWaitlist> _liveCustomerPackageWaitlist = const [];
  List<LivePackageWaitlist> _liveDriverPackageWaitlist = const [];
  List<LiveTourInterest> _liveTourInterests = const [];
  List<LiveTourMatch> _liveTourMatches = const [];
  bool _marketplaceBusy = false;
  String? _marketplaceError;
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

  ApiClient get apiClient => _authRepository.client;

  bool get initialized => _initialized;
  bool get loggedIn => _loggedIn;
  bool get authBusy => _authBusy;
  String? get authError => _authError;
  CurrentUser? get currentUser => _currentUser;
  OtpChallenge? get lastOtp => _lastOtp;
  DriverProfileLive? get driverProfile => _driverProfile;
  List<LiveVehicle> get liveVehicles => List.unmodifiable(_liveVehicles);
  List<LiveRideRequest> get liveRideRequests => List.unmodifiable(_liveRideRequests);
  List<LiveRideRequest> get liveDriverRideRequests => List.unmodifiable(_liveDriverRideRequests);
  List<LiveDriverOffer> get liveDriverOffers => List.unmodifiable(_liveDriverOffers);
  List<LiveDriverRideOfferStatus> get liveDriverRideOfferStatuses => List.unmodifiable(_liveDriverRideOfferStatuses);
  List<LiveBooking> get liveBookings => List.unmodifiable(_liveBookings);
  List<LiveTourPackage> get liveMarketplacePackages => List.unmodifiable(_liveMarketplacePackages);
  List<LiveTourPackage> get liveDriverPackages => List.unmodifiable(_liveDriverPackages);
  List<LivePackageOffer> get liveCustomerPackageOffers => List.unmodifiable(_liveCustomerPackageOffers);
  List<LivePackageOffer> get liveDriverPackageOffers => List.unmodifiable(_liveDriverPackageOffers);
  List<LiveBooking> get liveDriverPackageBookings => List.unmodifiable(_liveDriverPackageBookings);
  List<LivePackageWaitlist> get liveCustomerPackageWaitlist => List.unmodifiable(_liveCustomerPackageWaitlist);
  List<LivePackageWaitlist> get liveDriverPackageWaitlist => List.unmodifiable(_liveDriverPackageWaitlist);
  List<LiveTourInterest> get liveTourInterests => List.unmodifiable(_liveTourInterests);
  List<LiveTourMatch> get liveTourMatches => List.unmodifiable(_liveTourMatches);
  bool get marketplaceBusy => _marketplaceBusy;
  String? get marketplaceError => _marketplaceError;
  String get currentUserName => _currentUser?.fullName ?? 'Udrive User';
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
        emergencyNumbers: const ['Rescue 1122', 'Police 15', 'Udrive Safety +92 300 000 1122'],
        itinerary: const ['Muzaffarabad', 'Kohala viewpoint', 'Keran', 'Sharda'],
        hotel: 'Neelum View Hotel, Keran',
        lastKnownLocation: _liveTrip.currentLocation,
      );

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      _locale = Locale(prefs.getString('language') ?? 'en');
      final savedMode = prefs.getString('mode') ?? 'customer';
      _mode = savedMode == 'driver'
          ? UserMode.driver
          : savedMode == 'hotel'
              ? UserMode.hotel
              : UserMode.customer;
      _driverOnline = prefs.getBool('driverOnline') ?? true;
      _liveTrip.shareEnabled = prefs.getBool('liveShareEnabled') ?? false;
      _currentUser = await _sessionStore.readUser();
      final accessToken = await _sessionStore.readAccessToken();
      final refreshToken = await _sessionStore.readRefreshToken();
      final accessExpiry = await _sessionStore.readAccessExpiry();
      final usable = _currentUser != null &&
          accessToken != null && accessToken.isNotEmpty &&
          accessExpiry != null &&
          accessExpiry.isAfter(DateTime.now().add(const Duration(seconds: 30)));
      if (usable) {
        _loggedIn = true;
        _initialized = true;
        notifyListeners();
        unawaited(_validateCachedSession());
        return;
      }
      if ((accessToken?.isNotEmpty ?? false) || (refreshToken?.isNotEmpty ?? false)) {
        try {
          _currentUser = await _authRepository.me().timeout(const Duration(seconds: 15));
          _loggedIn = true;
          await _loadDriverState().timeout(const Duration(seconds: 10));
          await _loadPhase9State().timeout(const Duration(seconds: 15));
        } catch (_) {
          await _resetSessionSafely();
        }
      }
    } catch (_) {
      await _resetSessionSafely();
    } finally {
      if (!_initialized) {
        _initialized = true;
        notifyListeners();
      }
    }
  }

  Future<void> _validateCachedSession() async {
    try {
      _currentUser = await _authRepository.me().timeout(const Duration(seconds: 15));
      await _loadDriverState().timeout(const Duration(seconds: 10));
      await _loadPhase9State().timeout(const Duration(seconds: 15));
      _authError = null;
    } on TimeoutException {
      // Keep the valid cached session available during Railway cold starts.
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _resetSessionSafely();
      }
    } catch (_) {
      // A temporary network issue must not trap the app on Splash.
    } finally {
      notifyListeners();
    }
  }

  Future<void> _resetSessionSafely() async {
    try {
      await _sessionStore.clear().timeout(const Duration(seconds: 6));
    } catch (_) {}
    _currentUser = null;
    _driverProfile = null;
    _liveVehicles = const [];
    _loggedIn = false;
    _mode = UserMode.customer;
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
      await _loadPhase9State();
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
      fullName: 'Udrive Demo Driver',
    );
  }

  Future<void> refreshAccount() async {
    if (!_loggedIn) return;
    _currentUser = await _authRepository.me();
    await _loadDriverState();
    await _loadPhase9State();
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
    _liveRideRequests = const [];
    _liveDriverRideRequests = const [];
    _liveDriverOffers = const [];
    _liveDriverRideOfferStatuses = const [];
    _liveBookings = const [];
    _liveMarketplacePackages = const [];
    _liveDriverPackages = const [];
    _liveCustomerPackageOffers = const [];
    _liveDriverPackageOffers = const [];
    _liveDriverPackageBookings = const [];
    _liveCustomerPackageWaitlist = const [];
    _liveDriverPackageWaitlist = const [];
    _liveTourInterests = const [];
    _liveTourMatches = const [];
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
    if (value == UserMode.driver) {
      await _loadDriverState();
      await loadDriverMarketplace();
    }
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

  Future<void> _loadPhase9State() async {
    try {
      final results = await Future.wait([
        _bookingRepository.getMyRideRequests(),
        _bookingRepository.getMyBookings(),
        _bookingRepository.getPublicPackages(),
        _bookingRepository.getCustomerPackageOffers(),
        _bookingRepository.getTourInterests(),
        _bookingRepository.getTourMatches(),
        _bookingRepository.getCustomerPackageWaitlist(),
      ]);
      _liveRideRequests = results[0] as List<LiveRideRequest>;
      _liveBookings = results[1] as List<LiveBooking>;
      _liveMarketplacePackages = results[2] as List<LiveTourPackage>;
      _liveCustomerPackageOffers = results[3] as List<LivePackageOffer>;
      _liveTourInterests = results[4] as List<LiveTourInterest>;
      _liveTourMatches = results[5] as List<LiveTourMatch>;
      _liveCustomerPackageWaitlist = results[6] as List<LivePackageWaitlist>;
      if (driverApproved) await loadDriverMarketplace(notify: false);
    } catch (_) {
      // Keep the last successfully loaded live values and expose the API error on retry.
    }
  }

  Future<LiveRideRequest> createLiveRideRequest(Map<String, dynamic> payload) async {
    return _runMarketplace(() async {
      // Validate/refresh the JWT immediately before the write operation so a
      // customer does not lose a completed form because the access token
      // expired while they were filling the booking steps.
      _currentUser = await _authRepository.me();
      _loggedIn = true;

      final request = await _bookingRepository.createRideRequest(payload);
      _liveRideRequests = [
        request,
        ..._liveRideRequests.where((e) => e.id != request.id),
      ];

      // Offers may still be empty immediately after saving. Failure to load
      // offers must not turn a successfully saved ride request into an error.
      try {
        _liveDriverOffers = await _bookingRepository.getRideOffers(request.id);
      } catch (_) {
        _liveDriverOffers = const [];
      }
      notifyListeners();
      return request;
    });
  }

  Future<void> loadRideOffers(String rideRequestId) async {
    try {
      _liveDriverOffers = await _bookingRepository.getRideOffers(rideRequestId);
      _marketplaceError = null;
      notifyListeners();
    } catch (error) {
      _marketplaceError = _message(error);
      notifyListeners();
    }
  }

  Future<void> refreshCustomerRideState() async {
    try {
      final results = await Future.wait([
        _bookingRepository.getMyRideRequests(),
        _bookingRepository.getMyBookings(),
      ]);
      _liveRideRequests = results[0] as List<LiveRideRequest>;
      _liveBookings = results[1] as List<LiveBooking>;
      _marketplaceError = null;
      notifyListeners();
    } catch (error) {
      _marketplaceError = _message(error);
      notifyListeners();
    }
  }

  Future<void> declineLiveDriverOffer({
    required String rideRequestId,
    required String offerId,
    bool countTowardsDriverRejectLimit = true,
  }) async {
    await _runMarketplace(() async {
      await _bookingRepository.declineDriverOffer(
        rideRequestId: rideRequestId,
        offerId: offerId,
        countTowardsDriverRejectLimit: countTowardsDriverRejectLimit,
      );
      _liveDriverOffers = _liveDriverOffers.where((offer) => offer.id != offerId).toList(growable: false);
    });
  }

  Future<LiveBooking> selectLiveDriverOffer({
    required String rideRequestId,
    required String offerId,
    double advanceAmount = 0,
  }) async {
    return _runMarketplace(() async {
      final booking = await _bookingRepository.selectDriverOffer(
        rideRequestId: rideRequestId,
        offerId: offerId,
        advanceAmount: advanceAmount,
      );
      _liveBookings = [booking, ..._liveBookings.where((e) => e.id != booking.id)];
      _liveRideRequests = await _bookingRepository.getMyRideRequests();
      return booking;
    });
  }

  Future<void> loadDriverMarketplace({bool notify = true}) async {
    _marketplaceError = null;
    try {
      _liveDriverRideRequests = await _bookingRepository.getDriverRideRequests();
    } catch (error) {
      _marketplaceError = _message(error);
      if (notify) notifyListeners();
      return;
    }
    if (notify) notifyListeners();

    try { _liveDriverRideOfferStatuses = await _bookingRepository.getDriverRideOffers(); } catch (_) {}
    try { _liveDriverPackages = await _bookingRepository.getDriverPackages(); } catch (_) {}
    try { _liveDriverPackageOffers = await _bookingRepository.getDriverPackageOffers(); } catch (_) {}
    try { _liveDriverPackageBookings = await _bookingRepository.getDriverPackageBookings(); } catch (_) {}
    try { _liveDriverPackageWaitlist = await _bookingRepository.getDriverPackageWaitlist(); } catch (_) {}
    if (notify) notifyListeners();
  }

  Future<LiveDriverOffer> submitLiveDriverOffer({
    required String rideRequestId,
    required String vehicleId,
    required double amount,
    int etaMinutes = 20,
    String? message,
  }) async {
    return _runMarketplace(() async {
      final offer = await _bookingRepository.submitDriverOffer(
        rideRequestId: rideRequestId,
        vehicleId: vehicleId,
        amount: amount,
        estimatedArrivalMinutes: etaMinutes,
        message: message,
      );
      await loadDriverMarketplace(notify: false);
      return offer;
    });
  }

  Future<void> rejectLiveDriverRequest({
    required String rideRequestId,
    String? reason,
  }) async {
    await _runMarketplace(() async {
      await _bookingRepository.rejectDriverRideRequest(
        rideRequestId: rideRequestId,
        reason: reason,
      );
      _liveDriverRideRequests = _liveDriverRideRequests
          .where((request) => request.id != rideRequestId)
          .toList(growable: false);
    });
  }

  Future<void> refreshHomeVehicles({bool force = false}) async {
    if (_marketplaceBusy && !force) return;

    _marketplaceBusy = true;
    _marketplaceError = null;
    notifyListeners();

    try {
      _liveMarketplacePackages = await _bookingRepository
          .getPublicPackages()
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _marketplaceError =
          'Vehicles are taking longer than expected. Pull down to retry.';
    } catch (error) {
      _marketplaceError = _message(error);
    } finally {
      _marketplaceBusy = false;
      notifyListeners();
    }
  }

  Future<void> refreshPhase9Marketplace() async {
    await _loadPhase9State();
    notifyListeners();
  }

  Future<LiveBooking> cancelLiveBooking(String bookingId, String reason) async {
    return _runMarketplace(() async {
      final booking = await _bookingRepository.cancelBooking(bookingId, reason);
      _liveBookings = [booking, ..._liveBookings.where((item) => item.id != booking.id)];
      return booking;
    });
  }

  Future<LiveBooking> rescheduleLiveBooking({
    required String bookingId,
    required DateTime pickupAt,
    DateTime? returnAt,
    String? reason,
  }) async {
    return _runMarketplace(() async {
      final booking = await _bookingRepository.rescheduleBooking(
        bookingId: bookingId,
        pickupAt: pickupAt,
        returnAt: returnAt,
        reason: reason,
      );
      _liveBookings = [booking, ..._liveBookings.where((item) => item.id != booking.id)];
      return booking;
    });
  }

  Future<void> refreshLiveBookings() async {
    _liveBookings = await _bookingRepository.getMyBookings();
    notifyListeners();
  }

  Future<LivePackageHold> acquireLivePackageHold({
    required String packageId,
    required String bookingType,
    required int seats,
  }) => _runMarketplace(() => _bookingRepository.acquirePackageHold(
        packageId: packageId,
        bookingType: bookingType,
        seats: seats,
      ));

  Future<LiveBooking> confirmLivePackageBooking({
    required String packageId,
    required String holdId,
    required double advanceAmount,
    List<Map<String, dynamic>> passengers = const [],
  }) async {
    return _runMarketplace(() async {
      final booking = await _bookingRepository.confirmPackageBooking(
        packageId: packageId,
        holdId: holdId,
        advanceAmount: advanceAmount,
        passengers: passengers,
      );
      await _loadPhase9State();
      return booking;
    });
  }

  Future<LivePackageWaitlist> joinLivePackageWaitlist({
    required String packageId,
    required String bookingType,
    required int seats,
    String? notes,
  }) async {
    return _runMarketplace(() async {
      final entry = await _bookingRepository.joinPackageWaitlist(
        packageId: packageId,
        bookingType: bookingType,
        seats: seats,
        notes: notes,
      );
      _liveCustomerPackageWaitlist =
          await _bookingRepository.getCustomerPackageWaitlist();
      return entry;
    });
  }

  Future<LivePassengerManifest> loadPassengerManifest(
    String bookingId,
  ) => _runMarketplace(
        () => _bookingRepository.getPassengerManifest(bookingId),
      );

  Future<LivePackageOffer> createLivePackageOffer({
    required String packageId,
    required String bookingType,
    required int seats,
    required double amount,
    String? message,
  }) async {
    return _runMarketplace(() async {
      final offer = await _bookingRepository.createPackageOffer(
        packageId: packageId,
        bookingType: bookingType,
        seats: seats,
        amount: amount,
        message: message,
      );
      _liveCustomerPackageOffers = await _bookingRepository.getCustomerPackageOffers();
      return offer;
    });
  }

  Future<LiveBooking> confirmLivePackageOffer({
    required String offerId,
    double advanceAmount = 0,
  }) async {
    return _runMarketplace(() async {
      final booking = await _bookingRepository.confirmPackageOffer(
        offerId: offerId,
        advanceAmount: advanceAmount,
      );
      await _loadPhase9State();
      return booking;
    });
  }

  Future<LivePackageVehicleLocation> loadPackageVehicleLocation(
    String packageId,
  ) => _bookingRepository.getPackageVehicleLocation(packageId);

  Future<LiveTourPackage> createLiveDriverPackage(Map<String, dynamic> payload) async {
    return _runMarketplace(() async {
      final package = await _bookingRepository.createDriverPackage(payload);
      _liveDriverPackages = [package, ..._liveDriverPackages.where((e) => e.id != package.id)];
      return package;
    });
  }

  Future<LiveTourPackage> submitLiveDriverPackage(String packageId) async {
    return _runMarketplace(() async {
      final package = await _bookingRepository.submitDriverPackage(packageId);
      _liveDriverPackages = [package, ..._liveDriverPackages.where((e) => e.id != package.id)];
      return package;
    });
  }

  Future<LiveTourPackage> toggleLiveDriverPackage(
    String packageId,
    bool active,
  ) async {
    return _runMarketplace(() async {
      final package = await _bookingRepository.toggleDriverPackage(packageId, active);
      _liveDriverPackages = [
        package,
        ..._liveDriverPackages.where((item) => item.id != package.id),
      ];
      return package;
    });
  }

  Future<LivePackageOffer> reviewLivePackageOffer({
    required String offerId,
    required String decision,
    double? counterAmount,
    String? message,
  }) async {
    return _runMarketplace(() async {
      final offer = await _bookingRepository.reviewPackageOffer(
        offerId: offerId,
        decision: decision,
        counterAmount: counterAmount,
        message: message,
      );
      final results = await Future.wait([
        _bookingRepository.getDriverPackageOffers(),
        _bookingRepository.getDriverPackageBookings(),
        _bookingRepository.getDriverPackageWaitlist(),
      ]);
      _liveDriverPackageOffers = results[0] as List<LivePackageOffer>;
      _liveDriverPackageBookings = results[1] as List<LiveBooking>;
      _liveDriverPackageWaitlist = results[2] as List<LivePackageWaitlist>;
      return offer;
    });
  }

  Future<LiveTourInterest> createLiveTourInterest(Map<String, dynamic> payload) async {
    return _runMarketplace(() async {
      final interest = await _bookingRepository.createTourInterest(payload);
      _liveTourInterests = [interest, ..._liveTourInterests.where((e) => e.id != interest.id)];
      _liveTourMatches = await _bookingRepository.getTourMatches();
      return interest;
    });
  }

  Future<T> _runMarketplace<T>(Future<T> Function() action) async {
    _marketplaceBusy = true;
    _marketplaceError = null;
    notifyListeners();
    try {
      return await action();
    } catch (error) {
      _marketplaceError = _message(error);
      rethrow;
    } finally {
      _marketplaceBusy = false;
      notifyListeners();
    }
  }

  String _message(Object error) => error is ApiException ? error.message : 'The live marketplace request could not be completed.';

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
