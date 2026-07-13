import 'package:flutter/material.dart';

import '../../core/localization/app_language.dart';
import '../../core/theme/app_theme.dart';
import '../../data/driver_dummy_data.dart';
import 'create_package_screen.dart';

class DriverPackagesScreen extends StatelessWidget {
  const DriverPackagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    S.of(context, 'myPackages'),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton.filled(
                  onPressed: () => _openCreate(context),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Create and manage your tourism packages. New packages require admin approval.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            ...driverPackages.map(
              (package) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                package.title,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Chip(label: Text(package.status)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          package.route,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text('${package.days} days'),
                            const SizedBox(width: 18),
                            Text('${package.bookings} bookings'),
                            const Spacer(),
                            Text(
                              'PKR ${package.price}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreate(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(S.of(context, 'createPackage')),
      ),
    );
  }

  void _openCreate(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const CreatePackageScreen()),
    );
  }
}
