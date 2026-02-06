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
    'spade': '♠',
    'heart': '♥',
    'diamond': '♦',
    'club': '♣',
  };

  static const Map<String, Color> suitColors = {
    'spade': Color(0xFF252530),
    'heart': Color(0xFFD92525),
    'diamond': Color(0xFFD92525),
    'club': Color(0xFF252530),
  };

  static const Map<String, String> specialNames = {
    'special_bird': '🐦',
    'special_dog': '🐕',
    'special_phoenix': '🦅',
    'special_dragon': '🐉',
  };

  static const Map<String, Color> specialColors = {
    'special_bird': Color(0xFF1A8C1A),
    'special_dog': Color(0xFF5A5A66),
    'special_phoenix': Color(0xFFD98000),
    'special_dragon': Color(0xFFC01A1A),
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isInteractive ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.translationValues(0, isSelected ? -12 : 0, 0),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isFaceUp ? Colors.white : const Color(0xFF2A3F6F),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4D99FF)
                : Colors.grey.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 4,
              offset: const Offset(1, 2),
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

    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            symbol,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                rank,
                style: TextStyle(
                  fontSize: 20,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialCard() {
    final emoji = specialNames[cardId] ?? '?';
    final color = specialColors[cardId] ?? Colors.black;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.1),
            color.withOpacity(0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Center(
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 28),
        ),
      ),
    );
  }

  Widget _buildBackFace() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A3F6F),
            Color(0xFF1A2F5F),
          ],
        ),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: const Color(0xFF3355AA),
          width: 2,
        ),
      ),
      child: const Center(
        child: Text(
          'T',
          style: TextStyle(
            fontSize: 24,
            color: Color(0xFF6688DD),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
