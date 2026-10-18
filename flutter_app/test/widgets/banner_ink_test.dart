import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/utils/banner_ink.dart';

/// 배너 위 글자·표식이 배너 밝기에 맞게 정해지는지.
///
/// 다크 톤 배너를 올리면, 색을 지정하지 않은 배너 위에 어두운 글자가
/// 깔려 거의 안 보인다. 반대로 모든 색을 배너에 맞춰 뒤집으면 뜻이 있는
/// 색(준비 완료의 초록)까지 사라진다. 그래서 둘을 나눈다.
void main() {
  LinearGradient g(List<Color> c) => LinearGradient(colors: c);

  final dark = g(const [Color(0xFF1B1030), Color(0xFF2A1B4A)]);
  final light = g(const [Color(0xFFFFF4DC), Color(0xFFFFE0B2)]);
  // 한쪽은 어둡고 한쪽은 밝은 배너. 평균으로 한 가지 답을 낸다.
  final split = g(const [Color(0xFF101010), Color(0xFFFFFFFF)]);

  group('밝기 판정', () {
    test('어두운 배너', () => expect(isDarkBanner(dark), isTrue));
    test('밝은 배너', () => expect(isDarkBanner(light), isFalse));
    test('배너가 없으면 어둡지 않다 — 기존 밝은 화면이 기준이다', () {
      expect(isDarkBanner(null), isFalse);
      expect(isDarkBanner(g(const [])), isFalse);
    });
  });

  group('글자색 — 읽히기만 하면 되는 것', () {
    test('어두우면 흰색, 밝으면 진한 갈색', () {
      expect(profileBannerInk(dark, null), Colors.white);
      expect(profileBannerInk(light, null), bannerInkDark);
    });

    test('관리자가 지정한 색이 이긴다', () {
      const picked = Color(0xFF00FF00);
      expect(profileBannerInk(dark, picked), picked);
      expect(profileBannerInk(light, picked), picked);
    });

    test('배너가 없으면 진한 갈색 — 지금 화면 그대로', () {
      expect(profileBannerInk(null, null), bannerInkDark);
    });
  });

  group('뜻이 있는 색 — 어두울 때만 바꾼다', () {
    const readyGreen = Color(0xFF43A047);

    test('밝은 배너에서는 초록이 그대로다', () {
      // 이게 이 설계의 핵심이다. 전부 글자색으로 넘기면 배너를 쓴
      // 사람만 준비 표시가 초록이 아니게 된다.
      expect(onBannerAccent(light, null, light: readyGreen), readyGreen);
      expect(onBannerAccent(null, null, light: readyGreen), readyGreen);
    });

    test('어두운 배너에서만 읽히게 바뀐다', () {
      expect(onBannerAccent(dark, null, light: readyGreen), Colors.white);
    });

    test('관리자 지정이 있으면 그것', () {
      const picked = Color(0xFFFFD43B);
      expect(onBannerAccent(light, picked, light: readyGreen), picked);
    });
  });

  test('반반 배너는 평균으로 한 가지 답을 낸다', () {
    // 글자가 배너를 가로지르므로 한쪽 끝만 보면 답이 없다. 고르게
    // 어둡지 않은 배너는 text.color 를 직접 지정하는 편이 낫다.
    expect(isDarkBanner(split), isFalse);
  });

  group('화면들이 같은 규칙을 쓴다', () {
    // 한 화면만 빠지면 "상점에서는 읽혔는데 로비에서는 안 보인다" 가
    // 된다. 실제로 그 상태였다 — 프로필 셀·창만 이 헬퍼를 썼다.
    const screens = {
      '로비': 'lib/screens/lobby_screen.dart',
      '랭킹': 'lib/screens/ranking_screen.dart',
      '상점': 'lib/screens/shop_screen.dart',
      '프로필 셀': 'lib/widgets/profile_identity_cell.dart',
      '프로필 창': 'lib/widgets/player_profile_dialog.dart',
    };
    for (final e in screens.entries) {
      test('${e.key} 이(가) 공용 헬퍼를 쓴다', () {
        final src = File(e.value).readAsStringSync();
        expect(
          src.contains('profileBannerInk') || src.contains('onBannerAccent'),
          isTrue,
          reason: '${e.key} 이(가) 서버 지정색만 읽는다 — 비어 있으면 안 보인다',
        );
      });
    }

    test('서버 지정색을 날것으로 쓰는 곳이 남아 있지 않다', () {
      for (final e in screens.entries) {
        final src = File(e.value).readAsStringSync();
        // bannerTextColor( 의 결과를 헬퍼에 넣지 않고 그대로 색으로
        // 쓰면 그 자리만 규칙에서 빠진다.
        final raw = RegExp(r'color:\s*\w+\.bannerTextColor\(').allMatches(src);
        expect(raw, isEmpty, reason: '${e.key} 에 날것 사용이 남아 있다');
      }
    });
  });
}
