import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';

/// Pieces shared by the owner wizard, My vehicles and the driver invite.

/// Picks one image the same way the rental booking picks a document.
Future<PlatformFile?> pickOwnerImage() async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    withData: true,
  );
  final files = picked?.files ?? const <PlatformFile>[];
  return files.isEmpty ? null : files.first;
}

/// Reads one text from the public settings; null when missing or offline.
Future<String?> loadOwnerPublicText(ApiClient api, String key) async {
  try {
    final response =
        await api.getJson('/api/v1/settings/public', authenticated: false);
    final payload = response['data'] ?? response;
    if (payload is! Map) return null;
    final text = '${payload[key] ?? ''}'.trim();
    return text.isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}

/// The agreement in a bottom sheet.
Future<void> showOwnerAgreementSheet(
  BuildContext context, {
  required String title,
  required String text,
}) =>
    showUdSheet<void>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(title, style: AppType.h2.copyWith(color: AppText.primary)),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                text,
                style: AppType.body2.copyWith(
                  color: AppText.secondary,
                  height: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          UdButton.primary(
            label: 'Close',
            onPressed: () => Navigator.of(sheetContext).pop(),
          ),
        ],
      ),
    );

/// Formats a day as "12 Mar 2027" without pulling in intl.
String ownerDayLabel(DateTime day) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${day.day} ${months[day.month - 1]} ${day.year}';
}

String ownerMonthLabel(DateTime day) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[day.month - 1]} ${day.year}';
}

/// The navy header: back tile, an overline, a title and, for the wizard,
/// a three-part progress bar.
class OwnerNavyHeader extends StatelessWidget {
  const OwnerNavyHeader({
    required this.title,
    required this.onBack,
    this.overline,
    this.subtitle,
    this.steps = 0,
    this.current = 0,
    super.key,
  });

  final String title;
  final String? overline;
  final String? subtitle;
  final VoidCallback onBack;

  /// Zero hides the progress bar.
  final int steps;

  /// 1-based.
  final int current;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Back',
                    child: Material(
                      color: AppColors.navyLine,
                      borderRadius: AppRadii.all(14),
                      child: InkWell(
                        onTap: onBack,
                        borderRadius: AppRadii.all(14),
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(Icons.chevron_left_rounded,
                              color: AppText.onInk, size: 26),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (overline != null)
                          Text(
                            overline!,
                            style: AppType.overline.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: AppColors.brand,
                            ),
                          ),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.h2.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppText.onInk,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: AppType.small.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppText.onInkMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (steps > 0) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (var i = 1; i <= steps; i++) ...[
                      if (i > 1) const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          height: 5,
                          decoration: BoxDecoration(
                            color: i <= current
                                ? AppColors.brand
                                : AppColors.navyLine,
                            borderRadius: AppRadii.all(3),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small upper-case field label, as the mockups draw it.
class OwnerCaps extends StatelessWidget {
  const OwnerCaps(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppType.small.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: AppText.secondary,
        ),
      );
}

enum OwnerTagTone { ok, warn, err, info, gray }

/// A 26px status chip: "Rent · live", "In review", "Verified".
class OwnerTag extends StatelessWidget {
  const OwnerTag({required this.label, this.tone = OwnerTagTone.gray, super.key});

  final String label;
  final OwnerTagTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color ink) = switch (tone) {
      OwnerTagTone.ok => (AppTint.success, AppTint.successText),
      OwnerTagTone.warn => (AppTint.warning, AppTint.warningText),
      OwnerTagTone.err => (AppTint.danger, AppTint.dangerText),
      OwnerTagTone.info => (AppTint.info, AppTint.infoText),
      OwnerTagTone.gray => (AppColors.surfaceAlt, AppText.secondary),
    };
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.all(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.small.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      ),
    );
  }
}

/// One photo or document slot: tap to pick and upload.
class OwnerPhotoSlot extends StatelessWidget {
  const OwnerPhotoSlot({
    required this.label,
    required this.done,
    required this.onTap,
    this.caption,
    this.icon = Icons.photo_camera_outlined,
    this.busy = false,
    this.imageUrl,
    this.height = 104,
    super.key,
  });

  final String label;
  final String? caption;
  final IconData icon;
  final bool done;
  final bool busy;

  /// Null disables the slot.
  final VoidCallback? onTap;

  /// Shown in place of the icon once uploaded.
  final String? imageUrl;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    final Color background = done ? AppTint.success : AppColors.background;
    final Color ink = done
        ? AppTint.successText
        : enabled
            ? AppText.secondary
            : AppText.disabled;
    final Color border = done ? AppTint.successBorder : AppColors.borderStrong;

    Widget top;
    if (busy) {
      top = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      );
    } else if (done && imageUrl != null && imageUrl!.isNotEmpty) {
      top = ClipRRect(
        borderRadius: AppRadii.all(8),
        child: Image.network(
          imageUrl!,
          width: 56,
          height: 38,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.check_circle_rounded, size: 26, color: ink),
        ),
      );
    } else {
      top = Icon(done ? Icons.check_circle_rounded : icon, size: 26, color: ink);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: done ? '$label, uploaded. Tap to replace' : 'Add $label',
      child: Material(
        color: background,
        borderRadius: AppRadii.all(16),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: AppRadii.all(16),
          child: Container(
            height: height,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: AppRadii.all(16),
              border: Border.all(color: border, width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                top,
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.small.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                if (caption != null)
                  Text(
                    done ? 'Uploaded' : caption!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.small.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tappable read-only field for a date.
class OwnerDateField extends StatelessWidget {
  const OwnerDateField({
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String label;
  final DateTime? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OwnerCaps(label),
        const SizedBox(height: 6),
        Material(
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
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value == null ? 'Pick a date' : ownerDayLabel(value!),
                      style: AppType.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color:
                            value == null ? AppText.caption : AppText.primary,
                      ),
                    ),
                  ),
                  const Icon(Icons.event_rounded,
                      size: 20, color: AppText.secondary),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
