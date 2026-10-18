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
  _lightIsUntouched();
  const other = CartoonPalette(
    dark: true,
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

  group('외곽선 글자', () {
    // 외곽선이 하는 일은 '바탕과 구분' 이 아니라 '채움색을 또렷하게
    // 세우는 것' 이다. 그래서 팔레트가 아니라 채움색을 따라야 한다.
    //
    // 처음에는 ink 를 썼다. 어두운 한 벌에서 ink 가 밝아지니, 흰 글자에
    // 밝은 테두리가 둘러져 회색 자국처럼 보였다.
    Color strokeOf(Widget w) {
      final stack = w as Stack;
      final outline = stack.children.first as Text;
      return outline.style!.foreground!.color;
    }

    test('밝은 채움에는 진한 테두리 — 두 한 벌 모두', () {
      for (final p in [cartoonLight, cartoonDark]) {
        Cartoon.usePalette(p);
        final c = strokeOf(Cartoon.outlinedText('가', fill: Colors.white));
        expect(
          c.computeLuminance(),
          lessThan(0.2),
          reason: '흰 글자에 밝은 테두리가 둘러진다',
        );
      }
    });

    test('어두운 채움에는 밝은 테두리', () {
      final c = strokeOf(
        Cartoon.outlinedText('가', fill: const Color(0xFF221100)),
      );
      expect(c.computeLuminance(), greaterThan(0.6));
    });

    test('넘긴 테두리색은 그대로', () {
      final c = strokeOf(
        Cartoon.outlinedText('가', fill: Colors.white, stroke: Cartoon.red),
      );
      expect(c.toARGB32(), Cartoon.red.toARGB32());
    });
  });

  group('손으로 고른 연한 면(surface)', () {
    // 화면 곳곳에 "연녹색 칩", "연주황 뱃지" 처럼 손으로 고른 색이 있다.
    // 그 위에는 ink 로 글자를 쓰므로, 어두운 한 벌에서 면만 밝게 남으면
    // 밝은 면에 밝은 글자가 된다.
    const samples = [
      Color(0xFFE8F5E9), // 연녹색 — 골드샵 보너스 뱃지
      Color(0xFFFFF3E0), // 연주황 — 최고가 뱃지
      Color(0xFFFFE9B8), // 연노랑 — 친구 목록 칩
      Color(0xFFEDE7F6), // 연보라 — 룰북 번호 (팔레트에 대응색이 없다)
      Colors.white,
    ];

    test('밝은 한 벌에서는 받은 값 그대로 — 지금 화면이 안 바뀐다', () {
      Cartoon.usePalette(cartoonLight);
      for (final c in samples) {
        expect(
          Cartoon.surface(c).toARGB32(),
          c.toARGB32(),
          reason: '$c 가 밝은 한 벌에서 바뀐다',
        );
      }
    });

    test('어두운 한 벌에서는 어두워진다', () {
      Cartoon.usePalette(cartoonDark);
      for (final c in samples) {
        final got = Cartoon.surface(c);
        expect(
          got.computeLuminance(),
          lessThan(0.12),
          reason: '$c 가 어두운 한 벌에서도 밝다',
        );
      }
    });

    test('어두워져도 글자가 읽힌다', () {
      Cartoon.usePalette(cartoonDark);
      double ratio(Color a, Color b) {
        final v = [a.computeLuminance(), b.computeLuminance()]..sort();
        return (v[1] + 0.05) / (v[0] + 0.05);
      }

      for (final c in samples) {
        expect(
          ratio(cartoonDark.ink, Cartoon.surface(c)),
          greaterThanOrEqualTo(7.0),
          reason: '$c 위에서 글자가 안 읽힌다',
        );
      }
    });

    test('색조는 남는다 — 연녹색은 어두운 녹색이 된다', () {
      Cartoon.usePalette(cartoonDark);
      final green = HSLColor.fromColor(
        Cartoon.surface(const Color(0xFFE8F5E9)),
      );
      final orange = HSLColor.fromColor(
        Cartoon.surface(const Color(0xFFFFF3E0)),
      );
      expect((green.hue - 123).abs(), lessThan(30), reason: '녹색 기가 사라졌다');
      expect((orange.hue - 33).abs(), lessThan(30), reason: '주황 기가 사라졌다');
    });
  });

  group('팔레트가 바뀌면 신호를 보낸다', () {
    // ThemeData 안에는 색이 값으로 박힌다(다이얼로그 배경 등). 신호가
    // 없으면 화면 글자는 따라오는데 팝업만 옛 색으로 남는다.
    test('바뀔 때만 올라간다', () {
      final before = Cartoon.paletteRevision.value;
      Cartoon.usePalette(cartoonDark);
      expect(Cartoon.paletteRevision.value, before + 1);
      Cartoon.usePalette(cartoonDark);
      expect(
        Cartoon.paletteRevision.value,
        before + 1,
        reason: '같은 한 벌인데 올라갔다',
      );
      Cartoon.usePalette(cartoonLight);
      expect(Cartoon.paletteRevision.value, before + 2);
    });
  });

  group('어두운 한 벌', () {
    // 밝은 한 벌을 그대로 뒤집지 않았다. 이 앱은 두꺼운 테두리와 단색
    // 그림자로 층을 만들기 때문에, 순백·순흑은 너무 날카롭다.
    double lum(Color c) => c.computeLuminance();
    double ratio(Color a, Color b) {
      final x = [lum(a), lum(b)]..sort();
      return (x[1] + 0.05) / (x[0] + 0.05);
    }

    test('글자와 패널의 대비가 밝은 한 벌에 맞먹는다', () {
      final light = ratio(cartoonLight.ink, cartoonLight.paper);
      final dark = ratio(cartoonDark.ink, cartoonDark.paper);
      expect(dark, greaterThanOrEqualTo(7.0), reason: '글자가 패널 위에서 안 읽힌다');
      expect(
        dark,
        greaterThan(light * 0.8),
        reason: '밝은 한 벌($light)보다 많이 떨어진다($dark)',
      );
    });

    test('칩(cream)도 글자가 읽힌다', () {
      expect(
        ratio(cartoonDark.ink, cartoonDark.cream),
        greaterThanOrEqualTo(7.0),
      );
    });

    test('바탕끼리는 층 순서가 맞는다', () {
      // 패널이 배경보다 밝아야 떠 보인다. 밝은 한 벌에서는 반대로
      // 패널이 더 밝다 — 어두운 쪽도 같은 방향이어야 한다.
      expect(
        lum(cartoonDark.paper),
        greaterThan(lum(cartoonDark.skyTop)),
        reason: '패널이 배경보다 어둡다 — 가라앉아 보인다',
      );
      expect(
        lum(cartoonDark.cream),
        greaterThan(lum(cartoonDark.paper)),
        reason: '칩이 패널보다 어둡다',
      );
    });

    test('정말 어둡다', () {
      expect(lum(cartoonDark.paper), lessThan(0.2));
      expect(lum(cartoonDark.skyTop), lessThan(0.2));
      expect(lum(cartoonDark.ink), greaterThan(0.6), reason: '글자가 안 밝다');
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

/// 밝은 한 벌에서 모든 헬퍼가 '받은 값을 그대로' 돌려주는지.
///
/// 어두운 테마를 붙이면서 수백 곳의 색을 헬퍼로 감쌌다. 그 헬퍼가
/// 밝은 한 벌에서 조금이라도 다른 값을 돌려주면, 다크 테마를 쓰지 않는
/// 대부분의 사용자 화면이 바뀐다 — 그건 이 작업이 건드리면 안 되는
/// 부분이다.
void _lightIsUntouched() {
  group('밝은 한 벌에서는 아무것도 바뀌지 않는다', () {
    const probes = [
      Color(0xFFFFFFFF),
      Color(0xFFF7F2EF),
      Color(0xFFE8F5E9),
      Color(0xFFFFF1B8),
      Color(0xFFFFC9C4),
      Color(0xFF2E7D32),
      Color(0xFF212121),
      Color(0xFF4A3A32),
      Color(0xFFB07A12),
    ];

    setUp(() => Cartoon.usePalette(cartoonLight));

    test('surface 는 그대로', () {
      for (final c in probes) {
        expect(Cartoon.surface(c).toARGB32(), c.toARGB32(), reason: '$c');
      }
    });

    test('onSurface 도 그대로', () {
      for (final c in probes) {
        expect(Cartoon.onSurface(c).toARGB32(), c.toARGB32(), reason: '$c');
      }
    });

    test('내 차례 색이 예전 값 그대로', () {
      expect(Cartoon.myTurn.toARGB32(), const Color(0xFFFFF1B8).toARGB32());
      expect(
        Cartoon.myTurnUrgent.toARGB32(),
        const Color(0xFFFFC9C4).toARGB32(),
      );
    });

    test('tint 는 흰색과 섞던 때와 거의 같다', () {
      // paper(#FFFBF2)와 섞는다. 흰색과 섞던 예전 값과의 차이가 눈에
      // 띄면 안 된다.
      int diff(Color a, Color b) =>
          ((a.r - b.r).abs() * 255).round() +
          ((a.g - b.g).abs() * 255).round() +
          ((a.b - b.b).abs() * 255).round();
      for (final amount in [0.55, 0.7, 0.82]) {
        final now = Cartoon.tint(const Color(0xFFFF8A65), amount);
        final before = Color.lerp(
          const Color(0xFFFF8A65),
          Colors.white,
          amount,
        )!;
        expect(diff(now, before), lessThan(20), reason: '섞음 $amount');
      }
    });
  });
}
