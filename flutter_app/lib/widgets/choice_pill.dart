import 'package:flutter/material.dart';

import '../theme/cartoon.dart';

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
    return CartoonPressable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent : Cartoon.paper,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Cartoon.ink, width: 1.6),
          boxShadow: [
            BoxShadow(color: Cartoon.ink, offset: Offset(0, selected ? 3 : 2)),
          ],
        ),
        child: Text(
          label,
          style: Cartoon.text(
            size: 14.5,
            color: selected ? Colors.white : Cartoon.ink,
          ),
        ),
      ),
    );
  }
}

/// The field label used above the inputs in those same dialogs.
Widget formFieldLabel(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(text, style: Cartoon.text(size: 14.5)),
  );
}

/// 카툰 입력창: 흰 바탕, 진한 테두리, 포커스는 주황.
InputDecoration formFieldDecoration(String hint, {int? maxLines}) {
  OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      fontSize: 13.5,
      color: Cartoon.ink.withValues(alpha: 0.4),
    ),
    filled: true,
    fillColor: Colors.white,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: b(Cartoon.ink, 2.5),
    enabledBorder: b(Cartoon.ink, 2.5),
    focusedBorder: b(Cartoon.orange, 3),
  );
}
