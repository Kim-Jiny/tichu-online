import 'package:flutter/material.dart';

import '../theme/cartoon.dart';

/// 티츄 특수 카드(용·봉황·개·참새) 그림. 테두리를 잘라 낸 일러스트를 카드 면에 가득 채운다.
///
/// 참새는 숫자 1 카드라서(스트레이트의 맨 앞이다) 그림만으로는 몇인지 알 수 없다 —
/// 오른쪽 아래 모서리에 숫자 1 뱃지를 하나 얹는다. 다른 특수 카드에는 숫자가 없다.
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
    final image = Image.asset(
      path,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
    if (cardId != 'special_bird') return image;
    return LayoutBuilder(
      builder: (context, c) {
        // 카드 폭에 비례하는 뱃지 — 손패(작은 카드)에서도 룰북(큰 카드)에서도 읽힌다.
        final badge = (c.maxWidth * 0.3).clamp(14.0, 40.0);
        final inset = badge * 0.14;
        return Stack(
          fit: StackFit.expand,
          children: [
            image,
            Positioned(
              right: inset,
              bottom: inset,
              child: _NumberBadge(size: badge),
            ),
          ],
        );
      },
    );
  }
}

/// 크림색 동그라미에 굵은 갈색 테두리와 숫자 1.
class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4DC),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF7A4A24),
          width: (size * 0.09).clamp(1.2, 3.0),
        ),
      ),
      child: Text(
        '1',
        style: TextStyle(
          fontFamily: Cartoon.font,
          fontFamilyFallback: Cartoon.fontFallback,
          fontSize: size * 0.68,
          height: 1.0,
          color: const Color(0xFF7A4A24),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
