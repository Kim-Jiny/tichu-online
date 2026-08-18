import 'package:flutter/material.dart';

/// 지금 차례인 사람의 닉네임을 감싸는 노란 알약.
///
/// 티츄 판에서 쓰던 표시를 마이티·스컬킹·러브레터도 함께 쓴다. 사진
/// 테두리만으로도 차례를 말할 수는 있지만, 테두리는 역할·패 열람 같은
/// 다른 상태와 색을 나눠 쓰는 자리라 판이 복잡해지면 묻힌다. 이름에
/// 배경이 깔리는 건 그 자리 하나에만 생기는 변화라 훑을 때 바로 걸린다.
///
/// 차례가 아니면 아무것도 더하지 않는다 — 투명한 배경에 같은 여백만
/// 남아서, 차례가 오갈 때 글자가 밀리지 않는다.
class TurnNamePill extends StatelessWidget {
  const TurnNamePill({
    super.key,
    required this.isTurn,
    required this.child,
    this.horizontal = 8,
    this.vertical = 2,
  });

  final bool isTurn;
  final Widget child;
  final double horizontal;
  final double vertical;

  static const Color background = Color(0xFFFFF2B3);
  static const Color border = Color(0xFFE6C86A);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      decoration: BoxDecoration(
        color: isTurn ? background : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTurn ? border : Colors.transparent,
          width: 1,
        ),
      ),
      child: child,
    );
  }
}
