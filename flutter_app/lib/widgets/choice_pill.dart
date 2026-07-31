import 'package:flutter/material.dart';

/// A single-choice pill, as used by the inquiry and report forms.
///
/// Material's ChoiceChip was doing this before: it draws its own outline, its
/// own check mark and its own selected tint, none of which match the rest of
/// these dialogs — and the two forms had drifted into two different looks for
/// the same "pick one of these" question.
class ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Colour of the selected state. Defaults to the app's violet.
  final Color accent;

  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = const Color(0xFF7E57C2),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent : const Color(0xFFF4F1F0),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF7A6E68),
            ),
          ),
        ),
      ),
    );
  }
}

/// The field label used above the inputs in those same dialogs.
Widget formFieldLabel(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Color(0xFF9A8E8A),
      ),
    ),
  );
}

/// Filled input decoration: softer than the boxed outline these forms used, and
/// the same shape in both of them.
InputDecoration formFieldDecoration(String hint, {int? maxLines}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFFB9ADA8)),
    filled: true,
    fillColor: const Color(0xFFF7F4F2),
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFCDBDE8), width: 1.5),
    ),
  );
}
