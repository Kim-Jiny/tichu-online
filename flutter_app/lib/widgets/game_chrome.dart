import 'package:flutter/material.dart';

import '../theme/cartoon.dart';

// 게임 화면 4종이 같이 쓰는 카툰 부품. 카드·손패·테이블은 건드리지 않고,
// 그 둘레의 알림·점수 알약·버튼·패널만 같은 결로 맞춘다.

/// 게임 화면 위에 뜨는 알림 줄(오류·시간 초과·탈주 등).
/// 불투명한 색 바탕 + 진한 테두리 + 작은 단색 그림자.
class GameNoticeBar extends StatelessWidget {
  const GameNoticeBar({
    super.key,
    required this.icon,
    required this.text,
    this.color = Cartoon.red,
    this.scale = 1.0,
  });

  final IconData icon;
  final String text;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(8 * scale, 8 * scale, 14 * scale, 8 * scale),
      decoration: BoxDecoration(
        color: Cartoon.tint(color, 0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Cartoon.ink, width: 2),
        boxShadow: [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 36 * scale,
            height: 36 * scale,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Cartoon.ink, width: 1.6),
            ),
            child: Icon(icon, color: Cartoon.ink, size: 21 * scale),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Text(
              text,
              style: Cartoon.text(size: 16 * scale, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}

/// 점수·카드 카운터 같은 작은 알약의 바탕: 크림색 + 얇은 갈색 테두리(그림자 없음).
BoxDecoration gamePillDecoration({double radius = 20, Color? color}) =>
    BoxDecoration(
      color: color ?? Cartoon.cream,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Cartoon.ink, width: 1.8),
    );

/// 게임 화면 팝업 버튼(작은 카툰 버튼).
Widget gameButton(
  String label,
  VoidCallback? onPressed, {
  Color color = Cartoon.orange,
  double height = 46,
  double size = 18,
  bool expand = false,
  double hPad = 20,
}) {
  final button = CartoonButton(
    expand: expand,
    height: height,
    color: color,
    onPressed: onPressed,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: CartoonButton.label(label, size: size),
    ),
  );
  // 눌리지 않을 때는 색이 흐려져 "지금은 못 누른다"가 한눈에 보이게.
  return onPressed == null ? Opacity(opacity: 0.45, child: button) : button;
}
