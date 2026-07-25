import 'dart:async';

import 'package:flutter/material.dart';

import '../booking/trip_operations_repository.dart';
import '../services/trip_location_service.dart';
import '../state/app_controller.dart';

/// Keeps authenticated Driver GPS sharing active while the app is open.
///
/// The backend still verifies the assigned Driver and active trip from JWT.
/// GPS is sent once per minute only for an eligible active assignment.
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

  static const _trackableStatuses = <String>{
    'DriverAccepted',
    'DriverEnRoute',
    'DriverArrived',
    'TripStarted',
    'Emergency',
  };

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
      const Duration(minutes: 1),
      (_) => _syncActiveTrip(),
    );
  }

  Future<void> _syncActiveTrip() async {
    if (!widget.enabled || _syncing || _repository == null) return;
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
