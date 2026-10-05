import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../network/api_client.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/ud_kit.dart';
import 'area_repository.dart';

/// The lime-bordered "where is it based?" box: Use my location, then a
/// District and a Tehsil picker.
///
/// GPS only suggests: the nearest tehsil centre within 80 km fills both
/// pickers and a green line says so, and the owner can still change either.
/// The pickers open a sheet rather than a Material menu, the same way the
/// rest of the app's pickers do, so every row is a 64px target.
class AreaPicker extends StatefulWidget {
  const AreaPicker({
    required this.api,
    required this.onChanged,
    this.initial,
    this.initialTehsilId,
    this.title = 'WHERE IS THE VEHICLE BASED?',
    this.hint =
        'Customers nearby see it first, and your area\'s team checks it.',
    super.key,
  });

  final ApiClient api;

  /// Wins over [initialTehsilId] when both are given.
  final AreaSelection? initial;

  /// Resolved to a full selection once the districts load.
  final String? initialTehsilId;

  /// Null when the district changed and no tehsil is picked yet.
  final ValueChanged<AreaSelection?> onChanged;
  final String title;
  final String hint;

  @override
  State<AreaPicker> createState() => _AreaPickerState();
}

class _AreaPickerState extends State<AreaPicker> {
  late final AreaRepository _repo = AreaRepository(widget.api);

  List<AreaDistrict> _districts = const [];
  bool _loading = true;
  String? _loadError;

  String? _districtId;
  AreaSelection? _selection;

  bool _locating = false;
  bool _fromGps = false;
  String? _gpsError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _selection = initial;
      _districtId = initial.districtId;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final districts = await _repo.districts();
      if (!mounted) return;
      AreaSelection? resolved;
      if (_selection == null) {
        resolved = AreaRepository.find(districts, widget.initialTehsilId);
      }
      setState(() {
        _districts = districts;
        _loading = false;
        if (resolved != null) {
          _selection = resolved;
          _districtId = resolved.districtId;
        }
      });
      if (resolved != null) widget.onChanged(resolved);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Areas could not be loaded. Tap to try again.';
      });
    }
  }

  AreaDistrict? get _district {
    for (final d in _districts) {
      if (d.id == _districtId) return d;
    }
    return null;
  }

  void _set(AreaSelection? selection, {required bool fromGps}) {
    setState(() {
      _selection = selection;
      if (selection != null) _districtId = selection.districtId;
      _fromGps = fromGps;
      _gpsError = null;
    });
    widget.onChanged(selection);
  }

  Future<void> _useLocation() async {
    if (_locating || _districts.isEmpty) return;
    setState(() {
      _locating = true;
      _gpsError = null;
    });
    String? problem;
    AreaSelection? found;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        problem = 'Location is off. Turn it on, or pick the district and '
            'tehsil below.';
      } else {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          problem = 'Location permission is off. Pick the district and '
              'tehsil below.';
        } else {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          );
          found = _repo.nearest(
              _districts, position.latitude, position.longitude);
          if (found == null) {
            problem = 'No tehsil we cover is near you. Pick the district and '
                'tehsil below.';
          }
        }
      }
    } catch (_) {
      problem = 'Your location could not be found. Pick the district and '
          'tehsil below.';
    }
    if (!mounted) return;
    setState(() => _locating = false);
    if (found != null) {
      _set(found, fromGps: true);
    } else {
      setState(() {
        _gpsError = problem;
        _fromGps = false;
      });
    }
  }

  Future<void> _pickDistrict() async {
    final picked = await _choose(
      title: 'District',
      rows: [
        for (final d in _districts) (d.id, d.name, d.id == _districtId),
      ],
    );
    if (picked == null || !mounted || picked == _districtId) return;
    final district = _districts.firstWhere((d) => d.id == picked);
    // One tehsil means there is nothing to choose.
    if (district.tehsils.length == 1) {
      final tehsil = district.tehsils.first;
      _set(
        AreaSelection(
          districtId: district.id,
          districtName: district.name,
          tehsilId: tehsil.id,
          tehsilName: tehsil.name,
        ),
        fromGps: false,
      );
      return;
    }
    setState(() {
      _districtId = picked;
      _selection = null;
      _fromGps = false;
      _gpsError = null;
    });
    widget.onChanged(null);
  }

  Future<void> _pickTehsil() async {
    final district = _district;
    if (district == null) return;
    final picked = await _choose(
      title: 'Tehsil',
      rows: [
        for (final t in district.tehsils)
          (t.id, t.name, t.id == _selection?.tehsilId),
      ],
    );
    if (picked == null || !mounted) return;
    final tehsil = district.tehsils.firstWhere((t) => t.id == picked);
    _set(
      AreaSelection(
        districtId: district.id,
        districtName: district.name,
        tehsilId: tehsil.id,
        tehsilName: tehsil.name,
      ),
      fromGps: false,
    );
  }

  /// Opens a sheet of [rows] — (id, name, selected) — and returns the id.
  Future<String?> _choose({
    required String title,
    required List<(String, String, bool)> rows,
  }) =>
      showUdSheet<String>(
        context: context,
        builder: (sheetContext) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(title, style: AppType.h2.copyWith(color: AppText.primary)),
              const SizedBox(height: 14),
              UdListGroup(
                children: [
                  for (final row in rows)
                    UdListRow(
                      title: row.$2,
                      onTap: () => Navigator.pop(sheetContext, row.$1),
                      trailing: row.$3
                          ? const Icon(Icons.check_rounded,
                              size: 22, color: AppColors.brandInk)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final district = _district;
    final children = <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: AppType.small.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppText.secondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.hint,
            style: AppType.small.copyWith(
              fontSize: 12.5,
              color: AppText.secondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    ];

    if (_loading) {
      children.add(
        const SizedBox(
          height: 52,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        ),
      );
    } else if (_loadError != null) {
      children.add(
        UdBanner(
          tone: UdTone.warn,
          icon: Icons.wifi_off_rounded,
          text: _loadError,
          onTap: _load,
          trailing: const Icon(Icons.refresh_rounded,
              size: 20, color: AppTint.warningText),
        ),
      );
    } else if (_districts.isEmpty) {
      children.add(
        const UdBanner(
          tone: UdTone.warn,
          icon: Icons.info_outline_rounded,
          text: 'No areas have been published yet. Please try again later.',
        ),
      );
    } else {
      children.addAll([
        UdButton.outline(
          label: _locating ? 'Finding you…' : 'Use my location',
          icon: Icons.my_location_rounded,
          size: UdButtonSize.small,
          busy: _locating,
          onPressed: _locating ? null : _useLocation,
        ),
        _field(
          label: 'District',
          value: district?.name,
          placeholder: 'Choose district',
          onTap: _pickDistrict,
        ),
        _field(
          label: 'Tehsil',
          value: _selection?.tehsilName,
          placeholder:
              district == null ? 'Choose the district first' : 'Choose tehsil',
          onTap: district == null ? null : _pickTehsil,
        ),
        if (_gpsError != null)
          _note(Icons.location_off_rounded, _gpsError!, AppTint.warningText)
        else if (_fromGps && _selection != null)
          _note(
            Icons.check_rounded,
            'Filled from your location — change if the car is kept elsewhere.',
            AppColors.brandInk,
          ),
      ]);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTint.success,
        borderRadius: AppRadii.all(18),
        border: Border.all(color: AppColors.brand, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required String? value,
    required String placeholder,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UdLabel(label),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          enabled: enabled,
          label: value == null ? '$label, $placeholder' : '$label, $value',
          child: Material(
            color: AppColors.background,
            borderRadius: AppRadii.all(AppRadii.field),
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadii.all(AppRadii.field),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: AppRadii.all(AppRadii.field),
                  border: Border.all(color: AppColors.borderStrong, width: 1.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value ?? placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.body.copyWith(
                          fontSize: 16,
                          fontWeight:
                              value == null ? FontWeight.w500 : FontWeight.w700,
                          color: value != null
                              ? AppText.primary
                              : enabled
                                  ? AppText.caption
                                  : AppText.disabled,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.expand_more_rounded,
                        size: 22,
                        color: enabled ? AppText.secondary : AppText.disabled),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _note(IconData icon, String text, Color color) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppType.small.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1.4,
              ),
            ),
          ),
        ],
      );
}
