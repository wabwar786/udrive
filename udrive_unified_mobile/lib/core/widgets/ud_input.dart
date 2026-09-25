import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// The text field of design system v2 (`.field` + `.label` + `.help`).
///
/// 58px tall, radius 16, a 1.5px [AppColors.borderStrong] edge; focused it
/// takes a 2px navy border with a 4px [AppColors.limeGlow] ring outside it, and
/// in error a 2px danger border.
///
/// **Why this is not a themed `TextFormField`.** The focus ring is a shadow
/// *outside* the box. Material draws the helper and error text inside the same
/// `InputDecorator` as the border, so a ring applied to that widget wraps the
/// error message too. The box is therefore built here and the label, helper and
/// error are laid out around it — but validation still goes through a real
/// [FormField], so an enclosing [Form] validates this exactly as it validated
/// the `TextFormField` it replaces, with the same validator function.
///
/// The validator is handed the live controller text rather than the form
/// field's own value, so there is no second copy of the string to keep in step.
class UdTextField extends StatefulWidget {
  const UdTextField({
    this.controller,
    this.label,
    this.labelSuffix,
    this.hint,
    this.icon,
    this.suffix,
    this.helper,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.focusNode,
    this.autofillHints,
    this.onTap,
    super.key,
  });

  final TextEditingController? controller;

  /// `.label` — 14.5/700, above the box.
  final String? label;

  /// The grey half of a label: "(optional)". `.label .opt`.
  final String? labelSuffix;

  final String? hint;
  final IconData? icon;
  final Widget? suffix;

  /// `.help` — 13.5/500 secondary, below the box. Hidden while an error shows.
  final String? helper;

  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final FocusNode? focusNode;
  final Iterable<String>? autofillHints;

  /// Makes the whole box a button — a field that opens a picker rather than
  /// the keyboard. Pair with `readOnly: true`.
  final VoidCallback? onTap;

  @override
  State<UdTextField> createState() => _UdTextFieldState();
}

class _UdTextFieldState extends State<UdTextField> {
  final _fieldKey = GlobalKey<FormFieldState<String>>();

  FocusNode? _ownFocus;
  TextEditingController? _ownController;
  bool _focused = false;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());
  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _ownFocus?.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (_focus.hasFocus != _focused) setState(() => _focused = _focus.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      key: _fieldKey,
      enabled: widget.enabled,
      // The live text, not a mirrored copy. `Form.validate()` calls this with
      // the field's own value, which is ignored.
      validator: widget.validator == null
          ? null
          : (_) => widget.validator!(_controller.text),
      builder: (field) {
        final error = field.errorText;
        final multiline = widget.maxLines > 1;

        // Error wins over focus: a field can be both, and the message below it
        // is meaningless if the box still looks like an ordinary active field.
        final Color borderColour = error != null
            ? AppColors.danger
            : _focused
                ? AppColors.navy
                : AppColors.borderStrong;
        final double borderWidth = (error != null || _focused) ? 2 : 1.5;

        // Single-line fields are exactly 58px — a height, not a minimum. With
        // `isCollapsed` the inner TextField is only as tall as its own line, so
        // the box sets the height and the Row centres the text in it. Letting
        // it grow from a minimum instead made the field 61px, because the
        // paragraph line-height of the body style is not the line-height of a
        // one-line input, and every field in the app was then three pixels out.
        final box = AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: multiline ? null : AppSizes.field,
          constraints: multiline
              ? const BoxConstraints(minHeight: 110)
              : const BoxConstraints(),
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: multiline ? 14 : 0,
          ),
          decoration: BoxDecoration(
            color: widget.enabled ? AppColors.background : AppColors.surface,
            borderRadius: AppRadii.all(AppRadii.field),
            border: Border.all(color: borderColour, width: borderWidth),
            // `.field.focus` — `box-shadow: 0 0 0 4px var(--lime-glow)`.
            // spreadRadius with no blur is exactly that: a flat 4px ring.
            boxShadow: _focused && error == null
                ? const [
                    BoxShadow(
                      color: AppColors.limeGlow,
                      spreadRadius: 4,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Row(
            crossAxisAlignment:
                multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Padding(
                  padding: EdgeInsets.only(top: multiline ? 2 : 0),
                  child: Icon(
                    widget.icon,
                    size: 22,
                    color: AppText.secondary,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  readOnly: widget.readOnly,
                  autofocus: widget.autofocus,
                  obscureText: widget.obscureText,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  textCapitalization: widget.textCapitalization,
                  inputFormatters: widget.inputFormatters,
                  autofillHints: widget.autofillHints,
                  maxLines: widget.maxLines,
                  minLines: widget.minLines,
                  maxLength: widget.maxLength,
                  onTap: widget.onTap,
                  onSubmitted: widget.onSubmitted,
                  onChanged: (value) {
                    widget.onChanged?.call(value);
                    // Clear a message the customer has already acted on. Only
                    // when one is showing: validating on every keystroke would
                    // mark a half-typed number invalid before they finish it.
                    if (field.hasError) field.validate();
                  },
                  cursorColor: AppColors.navy,
                  style: AppType.body.copyWith(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    color: AppText.primary,
                    height: multiline ? 1.4 : 1.25,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                    hintText: widget.hint,
                    hintStyle: AppType.body.copyWith(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w500,
                      height: multiline ? 1.4 : 1.25,
                      color: AppText.caption,
                    ),
                  ),
                ),
              ),
              if (widget.suffix != null) ...[
                const SizedBox(width: 10),
                widget.suffix!,
              ],
            ],
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.label != null) ...[
              UdLabel(widget.label!, suffix: widget.labelSuffix),
              const SizedBox(height: 8),
            ],
            box,
            if (error != null) ...[
              const SizedBox(height: 7),
              Text(
                error,
                style: AppType.small.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.danger,
                ),
              ),
            ] else if (widget.helper != null) ...[
              const SizedBox(height: 7),
              Text(
                widget.helper!,
                style: AppType.small.copyWith(
                  fontSize: 13.5,
                  color: AppText.secondary,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// `.label` — the bold line above a field, with an optional grey tail.
class UdLabel extends StatelessWidget {
  const UdLabel(this.text, {this.suffix, super.key});

  final String text;

  /// Rendered in secondary weight and colour after a space: "(optional)".
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: text,
        children: suffix == null
            ? null
            : [
                TextSpan(
                  text: ' $suffix',
                  style: AppType.small.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: AppText.secondary,
                  ),
                ),
              ],
      ),
      style: AppType.listTitle.copyWith(
        fontSize: 14.5,
        fontWeight: FontWeight.w700,
        color: AppText.primary,
      ),
    );
  }
}

/// `.chk` — 26px, radius 8. On: lime fill, navy border, navy tick.
///
/// Drawn rather than themed because Material's checkbox is 18px inside a 48px
/// tap target and cannot be made 26px square with an 8px radius. The tap target
/// is restored by [UdCheckboxRow], or by whatever row this sits in.
class UdCheckbox extends StatelessWidget {
  const UdCheckbox({
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      checked: value,
      label: semanticLabel,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: value ? AppColors.brand : AppColors.background,
            borderRadius: AppRadii.all(8),
            border: Border.all(
              color: value ? AppColors.navy : AppColors.borderStrong,
              width: 2,
            ),
          ),
          child: value
              ? const Icon(Icons.check_rounded,
                  size: 17, color: AppColors.navy)
              : null,
        ),
      ),
    );
  }
}

/// A checkbox with something to the right of it, the whole row tappable.
///
/// The row is the tap target — 44px minimum — because a 26px square is below
/// the size a thumb can reliably hit.
class UdCheckboxRow extends StatelessWidget {
  const UdCheckboxRow({
    required this.value,
    required this.onChanged,
    required this.child,
    this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: AppRadii.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Ignores its own taps so the row keeps the gesture — otherwise the
            // box and the row would fight over it and one of them would win
            // inconsistently depending on where the finger landed.
            IgnorePointer(
              child: UdCheckbox(
                value: value,
                onChanged: onChanged,
                semanticLabel: semanticLabel,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// `.radio` — 24px. On: a 7px navy ring with white inside it.
class UdRadio extends StatelessWidget {
  const UdRadio({
    required this.selected,
    required this.onTap,
    this.semanticLabel,
    super.key,
  });

  final bool selected;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: selected,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.background,
            border: Border.all(
              color: selected ? AppColors.navy : AppColors.borderStrong,
              width: selected ? 7 : 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// `.tgl` — 54×32. On: navy track, lime knob.
///
/// Not [UdToggleSwitch] in `ud_controls.dart`, which is the v1 switch and is
/// still what the unconverted screens use. Both exist until those screens are
/// rebuilt; this is the one new work uses.
class UdSwitch extends StatelessWidget {
  const UdSwitch({
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      label: semanticLabel,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 54,
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? AppColors.navy : AppColors.borderStrong,
            borderRadius: AppRadii.all(16),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: value ? AppColors.brand : AppColors.background,
                shape: BoxShape.circle,
                boxShadow: AppShadows.card,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
