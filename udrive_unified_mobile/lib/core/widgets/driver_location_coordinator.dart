import 'dart:async';

import 'package:flutter/material.dart';

import '../booking/trip_operations_repository.dart';
import '../services/trip_location_service.dart';
import 'driver_tracking_suspension.dart';
import '../state/app_controller.dart';

/// Keeps authenticated Driver GPS sharing active while the app is open.
///
/// The backend still verifies the assigned Driver and active trip from JWT.
/// GPS is sent every 10 seconds only after the Driver starts an eligible trip stage.
class DriverLocationCoordinator extends StatefulWidget {
  const DriverLocationCoordinator({
    required this.enabled,
    required this.child,
    super.key,
  });

  final bool enabled;
  final Widget child;

  @override
  State<DriverLocationCoordinator> createState() =>
      _DriverLocationCoordinatorState();
}

class _DriverLocationCoordinatorState extends State<DriverLocationCoordinator>
    with WidgetsBindingObserver {
  TripOperationsRepository? _repository;
  TripLocationService? _locationService;
  Timer? _syncTimer;
  String? _activeBookingId;
  String? _activeStatus;
  bool _syncing = false;

  /// 'DriverAccepted' is here deliberately.
  ///
  /// Without it nothing published a position between the moment the customer
  /// picked this driver and the moment the driver opened their live-navigation
  /// screen — which could be a minute, or never if they left the app in their
  /// pocket. The customer's tracking map had no car on it for that whole
  /// stretch, which is precisely the stretch they are watching it.
  static const _trackableStatuses = <String>{
    'DriverAccepted',
    'DriverEnRoute',
    'DriverArrived',
    'TripStarted',
    'Emergency',
  };

  /// The live-navigation screen raises [DriverTrackingSuspension] while it is
  /// open, because it publishes the same trip itself. Without that, both would
  /// send the same fixes and the driver would pay twice in battery and data.
  ///
  /// The flag lives in its own file rather than here so neither of these two
  /// screens has to compile against the other's latest copy.

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository ??=
        TripOperationsRepository(AppControllerScope.of(context).apiClient);
    _locationService ??= TripLocationService(_repository!);
    _configure();
  }

  @override
  void didUpdateWidget(covariant DriverLocationCoordinator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _configure();
  }

  void _configure() {
    _syncTimer?.cancel();
    if (!widget.enabled) {
      _stopTracking();
      return;
    }
    _syncActiveTrip();
    _syncTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _syncActiveTrip(),
    );
  }

  Future<void> _syncActiveTrip() async {
    if (!widget.enabled || _syncing || _repository == null) return;

    // Stand down while the live screen is publishing. The timer keeps ticking,
    // so tracking picks itself back up within one interval of that screen
    // closing — no listener, nothing to forget to call.
    if (DriverTrackingSuspension.isSuspended) {
      _stopTracking();
      return;
    }

    _syncing = true;
    try {
      final trips = await _repository!.driverTrips();
      final active = trips.where((trip) {
        return _trackableStatuses.contains(trip.tripStatus);
      }).cast<dynamic>().firstOrNull;

      if (active == null) {
        _stopTracking();
        return;
      }

      final bookingId = active.bookingId as String;
      final status = active.tripStatus as String;
      if (_activeBookingId == bookingId && _activeStatus == status) return;

      _activeBookingId = bookingId;
      _activeStatus = status;
      await _locationService!.start(bookingId, status);
    } catch (_) {
      // Do not interrupt Driver UI. The offline queue and next heartbeat retry.
    } finally {
      _syncing = false;
    }
  }

  void _stopTracking() {
    _locationService?.stop();
    _activeBookingId = null;
    _activeStatus = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.enabled) {
      _syncActiveTrip();
      _locationService?.flushQueue();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _stopTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
