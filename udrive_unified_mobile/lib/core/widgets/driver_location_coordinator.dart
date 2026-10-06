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

  /// Held rather than looked up in the lifecycle callback.
  ///
  /// didChangeAppLifecycleState fires for `detached` as the tree is coming
  /// apart, and an inherited-widget lookup at that moment can find nothing and
  /// throw — inside a framework callback, where there is nobody to catch it.
  AppController? _controller;

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

  bool _configured = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = AppControllerScope.of(context);
    _repository ??= TripOperationsRepository(_controller!.apiClient);
    // Yields at once when the live-ride screen takes over, rather than on the
    // next sync tick — see TripLocationService.yieldToLiveScreen.
    _locationService ??=
        TripLocationService(_repository!, yieldToLiveScreen: true);

    // Once, not on every rebuild.
    //
    // didChangeDependencies runs again whenever an inherited widget above
    // changes, and this one reads AppControllerScope, which notifies on every
    // marketplace poll, every presence beat, every list refresh. So _configure
    // was re-entered several times a minute, and each call cancelled the sync
    // timer and started a new one — plus an immediate out-of-band _syncActiveTrip
    // on top of the one already scheduled. The 10-second timer never actually
    // got to 10 seconds; it was restarted before it fired and replaced by a
    // fresh burst of requests instead.
    //
    // The enabled flag still gets through: didUpdateWidget handles that, and
    // that is the only input _configure reads.
    if (_configured) return;
    _configured = true;
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
    // 20 seconds, not 10.
    //
    // This asks "has a trip been assigned to me", and the answer changes when a
    // customer picks this Driver — once in a while, not three times a minute.
    // Twenty seconds halves the requests and costs at most ten seconds before
    // the Driver's position starts publishing, which no one can perceive on a
    // tracking map.
    _syncTimer = Timer.periodic(
      const Duration(seconds: 20),
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
      // A plain loop, not `.firstOrNull`: that getter lives in
      // package:collection, which nothing in this app imports, so it would
      // only compile by accident.
      dynamic active;
      for (final trip in trips) {
        if (_trackableStatuses.contains(trip.tripStatus)) {
          active = trip;
          break;
        }
      }

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

  /// Stops the whole machine while the app is in the background.
  ///
  /// Nothing here used to stop: the sync timer and the presence beat were left
  /// running, which on Android means they may fire and on iOS means they are
  /// suspended — so the app either burned the Driver's battery polling from a
  /// pocket, or sat there while the server went on believing it was live and
  /// kept sending ride requests nothing could deliver. Neither is honest.
  ///
  /// Going quiet is the right signal. The server already closes a session that
  /// has not beaten in five minutes, so a quick trip to maps costs the Driver
  /// nothing while a long absence is correctly read as having stopped.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        if (!widget.enabled) return;
        _configure();
        _locationService?.flushQueue();
        // The server's answer decides whether the Driver is still online.
        unawaited(controller.resumePresenceBeating());

      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _syncTimer?.cancel();
        _syncTimer = null;
        _stopTracking();
        controller.pausePresenceBeating();

      case AppLifecycleState.inactive:
        // A notification shade or an incoming call. Too brief to tear down.
        break;
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
