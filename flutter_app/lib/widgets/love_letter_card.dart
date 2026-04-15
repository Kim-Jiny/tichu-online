import 'package:flutter/material.dart';

class LoveLetterCard extends StatelessWidget {
  final String cardId;
  final bool isSelected;
  final bool isFaceUp;
  final bool isInteractive;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final bool compact;

  const LoveLetterCard({
    super.key,
    required this.cardId,
    this.isSelected = false,
    this.isFaceUp = true,
    this.isInteractive = true,
    this.onTap,
    this.width = 70,
    this.height = 100,
    this.compact = false,
  });

  static const Map<String, Color> cardColors = {
    'guard': Color(0xFF78909C),    // blue grey
    'spy': Color(0xFF42A5F5),   // blue
    'baron': Color(0xFF66BB6A),    // green
    'handmaid': Color(0xFFAB47BC), // purple
    'prince': Color(0xFFEF5350),   // red
    'king': Color(0xFFFFA726),     // orange
    'countess': Color(0xFFEC407A), // pink
    'princess': Color(0xFFFFEE58), // yellow
  };

  static const Map<String, int> cardValues = {
    'guard': 1,
    'spy': 2,
    'baron': 3,
    'handmaid': 4,
    'prince': 5,
    'king': 6,
    'countess': 7,
    'princess': 8,
  };

  static const Map<String, String> cardNames = {
    'guard': 'Guard',
    'spy': 'Spy',
    'baron': 'Baron',
    'handmaid': 'Handmaid',
    'prince': 'Prince',
    'king': 'King',
    'countess': 'Countess',
    'princess': 'Princess',
  };

  static String? getCardType(String cardId) {
    if (!cardId.startsWith('ll_')) return null;
    final rest = cardId.substring(3);
    // Handle cards with numeric suffix like ll_guard_1
    for (final type in cardColors.keys) {
      if (rest == type || rest.startsWith('${type}_')) return type;
    }
    return null;
  }

  static String _getAssetPath(String cardId) {
    final type = getCardType(cardId);
    if (type == null) return '';
    // Capitalize first letter for asset name
    final name = type[0].toUpperCase() + type.substring(1);
    return 'assets/cards/ll_$name.png';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isInteractive ? onTap : null,
      child: SizedBox(
        width: width,
        height: height,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(0, isSelected ? -8 : 0, 0),
          child: _buildCard(context),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    if (!isFaceUp) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF8B1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFB8860B), width: 1.5),
        ),
        child: const Center(
          child: Icon(Icons.favorite, color: Color(0xFFB8860B), size: 24),
        ),
      );
    }

    final type = getCardType(cardId);
    if (type == null) return const SizedBox.shrink();

    final color = cardColors[type] ?? Colors.grey;
    final assetPath = _getAssetPath(cardId);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? const Color(0xFF4D99FF) : color.withValues(alpha: 0.5),
          width: isSelected ? 2.5 : 1.5,
        ),
        boxShadow: isSelected
            ? [BoxShadow(color: const Color(0xFF4D99FF).withValues(alpha: 0.3), blurRadius: 6)]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 2, offset: const Offset(0, 1))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, e, s) => Center(
            child: Icon(Icons.favorite, color: color, size: compact ? 16 : 24),
          ),
        ),
      ),
    );
  }
}
