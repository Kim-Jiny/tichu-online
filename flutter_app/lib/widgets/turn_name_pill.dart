import 'package:flutter/material.dart';

import '../theme/cartoon.dart';

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

  /// 차례일 때의 바탕.
  ///
  /// surface 를 거친다. 밝은 한 벌에서는 지금까지와 같은 노랑이고,
  /// 어두운 한 벌에서는 노란 기가 도는 어두운 면이 된다 — 그래야 그
  /// 위의 글자(팔레트를 따라 밝아진)가 읽힌다. 바탕을 고정 노랑으로
  /// 두면 노란 바탕에 밝은 글자가 된다.
  static Color get background => Cartoon.surface(Cartoon.yellow);
  static Color get border => Cartoon.ink;

  /// 차례일 때 이 알약 위에 쓰는 글자색.
  ///
  /// 바탕이 강조색(노랑)이라 팔레트를 따라가지 않는다. 글자만 따라가면
  /// 노란 바탕에 밝은 글자가 된다 — 남의 차례 표시가 그랬다.
  /// 차례가 아니면 바탕이 투명이므로 부르는 쪽의 색을 그대로 쓴다.
  static Color? inkFor(bool isTurn) =>
      isTurn ? Cartoon.inkOn(background) : null;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      decoration: BoxDecoration(
        color: isTurn ? background : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTurn ? border : Colors.transparent,
          width: 1.6,
        ),
      ),
      child: child,
    );
  }
}
