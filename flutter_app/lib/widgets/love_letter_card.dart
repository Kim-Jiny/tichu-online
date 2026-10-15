import 'package:flutter/material.dart';

import '../theme/cartoon.dart';

class LoveLetterCard extends StatelessWidget {
  final String cardId;
  final bool isSelected;
  final bool isFaceUp;
  final bool isInteractive;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final bool compact;
  final double borderRadius;

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
    this.borderRadius = 14,
  });

  static const Map<String, Color> cardColors = {
    'guard': Color(0xFF78909C), // blue grey
    'spy': Color(0xFF42A5F5), // blue
    'baron': Color(0xFF66BB6A), // green
    'handmaid': Color(0xFFAB47BC), // purple
    'prince': Color(0xFFEF5350), // red
    'king': Color(0xFFFFA726), // orange
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
    return 'assets/cards/ll_$name.webp';
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
          transform: Matrix4.translationValues(0, isSelected ? -12 : 0, 0),
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
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: Cartoon.ink, width: 1.8),
          boxShadow: const [
            BoxShadow(color: Color(0xFF8C7B6C), offset: Offset(0, 2.5)),
          ],
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
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF2F7DE0)
              : Cartoon.ink.withValues(alpha: 0.7),
          width: isSelected ? 2.4 : 1.6,
        ),
        // 번지지 않는 단색 그림자를 아래로 어긋나게 깔아 종이가 떠 있는 느낌.
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? const Color(0xFF1F4F94)
                : const Color(0xFF8C7B6C),
            offset: Offset(0, isSelected ? 5 : 2.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          (borderRadius - 1).clamp(0, borderRadius),
        ),
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
