import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/theme/cartoon.dart';

/// 색 한 벌을 갈아 끼울 수 있는 구조.
///
/// 앱이 OS 다크 모드를 따라가지는 않는다. 어두운 '테마' 를 장착했을 때만
/// 어두운 한 벌로 바꾸려고 만들어 둔 것이다.
///
/// 지금은 밝은 한 벌만 쓴다 — 그래서 이 단계에서 화면은 전과 똑같아야
/// 한다. 그걸 확인하는 것이 이 파일의 첫 번째 일이다.
void main() {
  const other = CartoonPalette(
    ink: Color(0xFFEEEEEE),
    cream: Color(0xFF222222),
    paper: Color(0xFF111111),
    skyTop: Color(0xFF101010),
    skyBottom: Color(0xFF202020),
  );

  tearDown(() => Cartoon.usePalette(cartoonLight));

  group('지금 화면은 전과 같다', () {
    test('기본 한 벌의 색이 예전 상수와 같다', () {
      // 숫자를 직접 적는다. 팔레트에서 가져와 비교하면 "스스로와 같다"
      // 가 되어 색이 바뀌어도 통과한다.
      expect(Cartoon.ink, const Color(0xFF3B2A20));
      expect(Cartoon.cream, const Color(0xFFFFF4DC));
      expect(Cartoon.paper, const Color(0xFFFFFBF2));
      expect(Cartoon.skyTop, const Color(0xFF9ADCFF));
      expect(Cartoon.skyBottom, const Color(0xFFFFF1D6));
    });

    test('강조색은 팔레트에 없다 — 양쪽에서 같은 뜻이다', () {
      // 주황·파랑·초록·빨강·노랑은 바탕 밝기와 무관하게 같은 뜻으로
      // 읽힌다. 팔레트에 넣으면 테마마다 달라져 뜻이 흔들린다.
      expect(Cartoon.orange, const Color(0xFFFF9A1F));
      expect(Cartoon.blue, const Color(0xFF4DA3FF));
      expect(Cartoon.green, const Color(0xFF45C06A));
      expect(Cartoon.red, const Color(0xFFFF5A5F));
      expect(Cartoon.yellow, const Color(0xFFFFD43B));
    });
  });

  group('갈아 끼울 수 있다', () {
    test('바꾸면 토큰이 따라간다', () {
      expect(Cartoon.usePalette(other), isTrue);
      expect(Cartoon.ink, const Color(0xFFEEEEEE));
      expect(Cartoon.paper, const Color(0xFF111111));
    });

    test('같은 한 벌을 다시 넣으면 바뀌지 않았다고 답한다', () {
      Cartoon.usePalette(other);
      expect(
        Cartoon.usePalette(other),
        isFalse,
        reason: '안 바뀌었는데 화면을 다시 그리게 된다',
      );
    });

    test('되돌리면 원래 색', () {
      Cartoon.usePalette(other);
      Cartoon.usePalette(cartoonLight);
      expect(Cartoon.ink, const Color(0xFF3B2A20));
    });
  });

  group('공용 헬퍼가 팔레트를 따라간다', () {
    test('글자 기본색', () {
      expect(Cartoon.text().color, const Color(0xFF3B2A20));
      Cartoon.usePalette(other);
      expect(
        Cartoon.text().color,
        const Color(0xFFEEEEEE),
        reason: '기본값이 앱 켤 때의 색으로 굳었다',
      );
      expect(Cartoon.userText().color, const Color(0xFFEEEEEE));
    });

    test('패널 바탕색', () {
      expect(Cartoon.panelDecoration().color, const Color(0xFFFFFBF2));
      Cartoon.usePalette(other);
      expect(Cartoon.panelDecoration().color, const Color(0xFF111111));
    });

    test('넘긴 색은 그대로 쓴다', () {
      Cartoon.usePalette(other);
      expect(Cartoon.text(color: Cartoon.red).color, Cartoon.red);
      expect(Cartoon.panelDecoration(color: Cartoon.blue).color, Cartoon.blue);
    });
  });
}
