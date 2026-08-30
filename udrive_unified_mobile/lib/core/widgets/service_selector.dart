import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// The four services offered on the redesigned Home screen.
///
/// Bus/Car/Bike are vehicle categories; Hotel branches to the hotel search.
/// Tour booking is a separate flag rather than a service — a customer can book
/// a tour with any of the three vehicle types.
enum HomeService { bus, car, bike, hotel }

extension HomeServiceInfo on HomeService {
  String get label => switch (this) {
        HomeService.bus => 'Coaster/Bus',
        HomeService.car => 'Car',
        HomeService.bike => 'Bike',
        HomeService.hotel => 'Hotel',
      };

  IconData get icon => switch (this) {
        HomeService.bus => Icons.directions_bus_rounded,
        HomeService.car => Icons.directions_car_rounded,
        HomeService.bike => Icons.two_wheeler_rounded,
        HomeService.hotel => Icons.apartment_rounded,
      };

  /// Vehicle category sent to the ride-request API. Null for Hotel.
  String? get vehicleCategory => switch (this) {
        HomeService.bus => 'Coaster',
        HomeService.car => 'Car',
        HomeService.bike => 'Bike',
        HomeService.hotel => null,
      };

  bool get isVehicle => this != HomeService.hotel;
}

class ServiceSelector extends StatelessWidget {
  const ServiceSelector({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final HomeService selected;
  final ValueChanged<HomeService> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: HomeService.values
          .map((service) => Expanded(
                child: _ServiceColumn(
                  service: service,
                  selected: service == selected,
                  onTap: () => onChanged(service),
                ),
              ))
          .toList(growable: false),
    );
  }
}

class _ServiceColumn extends StatelessWidget {
  const _ServiceColumn({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  final HomeService service;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: service.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        // Padding the whole column keeps the tap target at least 60x60,
        // rather than only the 48x48 icon tile.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected ? AppTint.brand : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                  border: Border.all(
                    color: selected ? AppColors.secondary : AppColors.border,
                    width: selected ? 1.4 : 1,
                  ),
                ),
                child: Icon(
                  service.icon,
                  size: 22,
                  color: selected ? AppColors.navy : AppText.disabled,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                service.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppColors.navy : AppText.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
