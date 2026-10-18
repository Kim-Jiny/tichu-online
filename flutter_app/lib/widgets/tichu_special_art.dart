import 'package:flutter/material.dart';

import '../theme/cartoon.dart';

/// 티츄 특수 카드(용·봉황·개·참새) 그림. 테두리를 잘라 낸 일러스트를 카드 면에 가득 채운다.
///
/// 모서리 뱃지를 두 장에 붙인다.
///
/// - **참새**: 숫자 1 카드라서(스트레이트의 맨 앞이다) 그림만으로는 몇인지
///   알 수 없다 — 숫자 1 을 적는다.
/// - **개**: 이 카드만 "점수도 서열도 없이 선을 넘긴다" 는 전혀 다른 일을
///   한다. 그림이 작아지는 손패에서는 참새와 실루엣이 비슷해 헷갈리므로,
///   같은 자리에 발바닥을 얹어 한눈에 갈리게 한다.
///
/// 용·봉황에는 뱃지가 없다. 그 둘은 테두리 색으로 가른다(playing_card.dart).
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
    final isBird = cardId == 'special_bird';
    final isDog = cardId == 'special_dog';
    if (!isBird && !isDog) return image;
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
              child: _CornerBadge(
                size: badge,
                // 참새는 숫자, 개는 발바닥. 같은 자리·같은 틀이라
                // 두 장을 나란히 놓고 봐도 같은 종류의 표시로 읽힌다.
                text: isBird ? '1' : null,
                icon: isDog ? Icons.pets_rounded : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 크림색 동그라미에 굵은 갈색 테두리. 안에 글자나 아이콘 하나.
class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.size, this.text, this.icon})
    : assert(text != null || icon != null, '글자나 아이콘 하나는 있어야 한다');

  final double size;
  final String? text;
  final IconData? icon;

  static final _brown = Cartoon.onSurface(const Color(0xFF7A4A24));

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Cartoon.surface(const Color(0xFFFFF4DC)),
        shape: BoxShape.circle,
        border: Border.all(color: _brown, width: (size * 0.09).clamp(1.2, 3.0)),
      ),
      child: text != null
          ? Text(
              text!,
              style: TextStyle(
                fontFamily: Cartoon.font,
                fontFamilyFallback: Cartoon.fontFallback,
                fontSize: size * 0.68,
                height: 1.0,
                color: _brown,
                fontWeight: FontWeight.w800,
              ),
            )
          // 아이콘은 글자보다 여백이 적어서, 같은 비율로 두면 동그라미에
          // 꽉 차 보인다. 조금 작게 둔다.
          : Icon(icon, size: size * 0.58, color: _brown),
    );
  }
}
