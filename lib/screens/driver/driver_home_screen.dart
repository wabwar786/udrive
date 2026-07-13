import 'package:flutter/material.dart';

import '../../core/localization/app_language.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../data/driver_dummy_data.dart';

class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.route_rounded, color: Colors.white),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.of(context, 'driverWorkspace'),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      S.of(context, 'approvedDriver'),
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const CircleAvatar(child: Text('SQ')),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: controller.driverOnline ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      controller.driverOnline
                          ? S.of(context, 'online')
                          : S.of(context, 'offline'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Switch(
                    value: controller.driverOnline,
                    onChanged: controller.setDriverOnline,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 195,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Color(0xFFDDEFE9), Color(0xFFDDE8FB)],
              ),
            ),
            child: Stack(
              children: [
                const Positioned(
                  left: 52,
                  top: 56,
                  child: Icon(
                    Icons.location_on_rounded,
                    color: AppColors.secondary,
                    size: 40,
                  ),
                ),
                const Center(
                  child: Icon(
                    Icons.directions_car_filled_rounded,
                    color: AppColors.primary,
                    size: 46,
                  ),
                ),
                Positioned(
                  right: 16,
                  top: 16,
                  child: Chip(
                    avatar: const Icon(Icons.bolt_rounded, size: 17),
                    label: Text('${rideRequests.length} nearby requests'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _DriverStatCard(
                  value: 'PKR 8,450',
                  label: S.of(context, 'todayEarnings'),
                  icon: Icons.payments_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DriverStatCard(
                  value: '6',
                  label: S.of(context, 'tripsToday'),
                  icon: Icons.route_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  S.of(context, 'newRequests'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(onPressed: () {}, child: Text(S.of(context, 'viewAll'))),
            ],
          ),
          ...rideRequests.take(2).map(
                (request) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(14),
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(
                        request.route,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        '${request.type} · ${request.distance} · '
                        '${request.passengers} passengers',
                      ),
                      trailing: Text(
                        'PKR ${request.offer}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _DriverStatCard extends StatelessWidget {
  const _DriverStatCard({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            Text(label, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}
