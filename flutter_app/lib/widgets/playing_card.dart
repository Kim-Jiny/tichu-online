import 'package:flutter/material.dart';

class PlayingCard extends StatelessWidget {
  final String cardId;
  final bool isSelected;
  final bool isFaceUp;
  final bool isInteractive;
  final VoidCallback? onTap;
  final double width;
  final double height;

  const PlayingCard({
    super.key,
    required this.cardId,
    this.isSelected = false,
    this.isFaceUp = true,
    this.isInteractive = true,
    this.onTap,
    this.width = 60,
    this.height = 84,
  });

  static const Map<String, String> suitSymbols = {
    // Use text presentation (VS15) to avoid emoji-colored suits on Android
    'spade': '\u2660\uFE0E',
    'heart': '\u2665\uFE0E',
    'diamond': '\u2666\uFE0E',
    'club': '\u2663\uFE0E',
  };

  static const Map<String, Color> suitColors = {
    'spade': Color(0xFF2B2B2B),  // matte black
    'heart': Color(0xFFD24B4B),  // matte red
    'diamond': Color(0xFF6FB6E5), // matte sky
    'club': Color(0xFF4BAA6A),   // matte green
  };

  static const Map<String, String> specialImages = {
    'special_bird': 'assets/cards/bird.png',
    'special_dog': 'assets/cards/dog.png',
    'special_phoenix': 'assets/cards/phoenix.png',
    'special_dragon': 'assets/cards/dragon.png',
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isInteractive ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.translationValues(0, isSelected ? -8 : 0, 0),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isFaceUp ? Colors.white : const Color(0xFFFFF1F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4D99FF)
                : const Color(0xFFE6DCE8),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE1D7E6).withOpacity(0.4),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: isFaceUp ? _buildFrontFace() : _buildBackFace(),
      ),
    );
  }

  Widget _buildFrontFace() {
    if (cardId.startsWith('special_')) {
      return _buildSpecialCard();
    }
    return _buildNormalCard();
  }

  Widget _buildNormalCard() {
    final parts = cardId.split('_');
    if (parts.length < 2) return const SizedBox();

    final suit = parts[0];
    final rank = parts[1];
    final symbol = suitSymbols[suit] ?? '?';
    final color = suitColors[suit] ?? Colors.black;

    // Scale font size based on card width (base: 48)
    final scale = (width / 48).clamp(0.7, 1.3);
    final symbolSize = 14 * scale;
    final rankSize = 22 * scale;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            symbol,
            style: TextStyle(
              fontSize: symbolSize,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 2 * scale),
          Text(
            rank,
            style: TextStyle(
              fontSize: rankSize,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialCard() {
    final imagePath = specialImages[cardId];
    if (imagePath == null) {
      return const Center(child: Text('?'));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Image.asset(
        imagePath,
        fit: BoxFit.cover,
        width: width,
        height: height,
      ),
    );
  }

  Widget _buildBackFace() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE6DCE8),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE1D7E6).withOpacity(0.5),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Container(
              width: width * 0.6,
              height: height * 0.6,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFEDE2EF),
                  width: 1.5,
                ),
              ),
              child: const Center(
                child: Text(
                  '🐥',
                  style: TextStyle(fontSize: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
