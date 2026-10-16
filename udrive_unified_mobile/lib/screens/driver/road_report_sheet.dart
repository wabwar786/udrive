import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// "Road band hai" — a driver tells the admin a road is closed, from where he is.
///
/// The report goes to the admin's Ops board with the phone's location. Two or
/// more drivers reporting the same spot make a "Road band" card; a single
/// report shows in the board's list for the admin to confirm or reject.
Future<void> showRoadReportSheet(BuildContext context) async {
  const kinds = [
    ('Blocked', 'Road band', Icons.block_rounded),
    ('Landslide', 'Landslide', Icons.terrain_rounded),
    ('Snow', 'Barf', Icons.ac_unit_rounded),
    ('Accident', 'Accident', Icons.car_crash_outlined),
    ('Works', 'Kaam chal raha', Icons.construction_rounded),
  ];
  final note = TextEditingController();
  var kind = 'Blocked';
  final picked = await showUdSheet<String>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Road band hai?', style: AppType.h3.copyWith(color: AppText.primary)),
            const SizedBox(height: 4),
            Text('Aap ki abhi ki location ke saath admin ko jayega.',
                style: AppType.small.copyWith(color: AppText.secondary)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (key, label, icon) in kinds)
                  UdChip(label: label, icon: icon, selected: kind == key, onTap: () => setSheet(() => kind = key)),
              ],
            ),
            const SizedBox(height: 12),
            UdTextField(controller: note, label: 'Kahan / kya hua', labelSuffix: 'optional', hint: 'Kohala pul ke paas', maxLength: 200),
            const SizedBox(height: 12),
            UdButton.primary(label: 'Admin ko batayein', icon: Icons.send_rounded, onPressed: () => Navigator.pop(sheetContext, kind)),
          ],
        ),
      ),
    ),
  );
  final text = note.text.trim();
  Future<void>.delayed(const Duration(milliseconds: 600), note.dispose);
  if (picked == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final api = AppControllerScope.of(context).apiClient;
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
    final response = await api.postJson('/api/v1/ops/road-reports', {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'kind': picked,
      'note': text,
    });
    messenger.showSnackBar(SnackBar(content: Text('${response['message'] ?? 'Shukriya — admin ko bata diya.'}')));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('Report nahi gayi: $error')));
  }
}
