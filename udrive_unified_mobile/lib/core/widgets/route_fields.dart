import 'package:flutter/material.dart';

import '../services/place_search_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Pickup and destination as editable text inputs, with the connector line and
/// dot the redesign specifies running down their left edge.
///
/// Suggestions render below the active field as a map-style address picker.
class RouteFields extends StatelessWidget {
  const RouteFields({
    required this.pickupController,
    required this.destinationController,
    required this.pickupFocus,
    required this.destinationFocus,
    required this.suggestions,
    required this.onSuggestionSelected,
    this.activeField,
    this.searching = false,
    this.pickupCaption = 'Pickup',
    this.destinationCaption = 'Destination',
    this.destinationHint = 'Type any address, area or landmark',
    this.onPickupChanged,
    this.onDestinationChanged,
    super.key,
  });

  final TextEditingController pickupController;
  final TextEditingController destinationController;
  final FocusNode pickupFocus;
  final FocusNode destinationFocus;

  /// Which field the suggestion list belongs to. Null hides the list.
  final RouteFieldKind? activeField;
  final List<PlaceSuggestion> suggestions;
  final bool searching;
  final void Function(RouteFieldKind field, PlaceSuggestion place)
      onSuggestionSelected;

  final String pickupCaption;
  final String destinationCaption;
  final String destinationHint;
  final ValueChanged<String>? onPickupChanged;
  final ValueChanged<String>? onDestinationChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _RouteConnector(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  children: [
                    _Field(
                      caption: pickupCaption,
                      controller: pickupController,
                      focusNode: pickupFocus,
                      hint: 'Detecting current address…',
                      onChanged: onPickupChanged,
                    ),
                    const SizedBox(height: 8),
                    _Field(
                      caption: destinationCaption,
                      controller: destinationController,
                      focusNode: destinationFocus,
                      hint: destinationHint,
                      onChanged: onDestinationChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (activeField != null && (suggestions.isNotEmpty || searching)) ...[
          const SizedBox(height: 8),
          _SuggestionPanel(
            searching: searching,
            suggestions: suggestions,
            onSelected: (place) => onSuggestionSelected(activeField!, place),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Suggestions are optional — you can type any address.',
              style: TextStyle(fontSize: 11.5, color: AppText.disabled),
            ),
          ),
        ],
      ],
    );
  }
}

enum RouteFieldKind { pickup, destination }

/// Green circle (pickup) → dashed line → navy square (destination).
class _RouteConnector extends StatelessWidget {
  const _RouteConnector();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      child: Column(
        children: [
          const SizedBox(height: 26),
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.secondary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Container(
              width: 1.5,
              margin: const EdgeInsets.symmetric(vertical: 4),
              color: AppColors.border,
            ),
          ),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 22),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.caption,
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.onChanged,
  });

  final String caption;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadii.all(AppRadii.field),
        border: Border.all(
          color: focusNode.hasFocus ? AppColors.secondary : AppColors.border,
          width: focusNode.hasFocus ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            caption,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppText.secondary,
            ),
          ),
          TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppText.primary,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 3),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppText.disabled,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.searching,
    required this.suggestions,
    required this.onSelected,
  });

  final bool searching;
  final List<PlaceSuggestion> suggestions;
  final ValueChanged<PlaceSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadii.all(AppRadii.row),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: searching && suggestions.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, index) {
                final place = suggestions[index];
                return InkWell(
                  onTap: () => onSelected(place),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    child: Row(
                      children: [
                        const Icon(Icons.place_outlined,
                            size: 18, color: AppText.secondary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                place.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppText.primary,
                                ),
                              ),
                              if (place.subtitle.isNotEmpty)
                                Text(
                                  place.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppText.secondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
