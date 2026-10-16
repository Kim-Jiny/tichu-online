import 'package:flutter/material.dart';

/// 티츄 특수 카드(용·봉황·개·참새) 그림. 테두리를 잘라 낸 일러스트를 카드 면에 가득 채운다.
class TichuSpecialArt extends StatelessWidget {
  const TichuSpecialArt(this.cardId, {super.key});

  final String cardId;

  static const Map<String, String> assets = {
    'special_bird': 'assets/cards/bird.webp',
    'special_dog': 'assets/cards/dog.webp',
    'special_phoenix': 'assets/cards/phoenix.webp',
    'special_dragon': 'assets/cards/dragon.webp',
  };

  @override
  Widget build(BuildContext context) {
    final path = assets[cardId];
    if (path == null) return const SizedBox.shrink();
    return Image.asset(
      path,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
