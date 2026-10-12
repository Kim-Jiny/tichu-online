import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/l10n/app_localizations.dart';
import 'package:tichu_online/l10n/korean_josa.dart';

void main() {
  group('resolveKoreanJosa', () {
    test('받침 없는 이름은 가/는/를/와/로', () {
      expect(resolveKoreanJosa('홍길동이(가)'), '홍길동이'); // 동: 받침 ㅇ
      expect(resolveKoreanJosa('철수이(가) 냈다'), '철수가 냈다');
      expect(resolveKoreanJosa('철수은(는)'), '철수는');
      expect(resolveKoreanJosa('철수을(를)'), '철수를');
      expect(resolveKoreanJosa('철수과(와) 영희'), '철수와 영희');
      expect(resolveKoreanJosa('철수(으)로'), '철수로');
    });

    test('받침 있는 이름은 이/은/을/과/으로', () {
      expect(resolveKoreanJosa('민석이(가)'), '민석이');
      expect(resolveKoreanJosa('민석은(는)'), '민석은');
      expect(resolveKoreanJosa('민석을(를)'), '민석을');
      expect(resolveKoreanJosa('민석과(와)'), '민석과');
      expect(resolveKoreanJosa('민석(으)로'), '민석으로');
    });

    test('ㄹ 받침은 (으)로 가 아니라 로', () {
      expect(resolveKoreanJosa('서울(으)로'), '서울로');
      expect(resolveKoreanJosa('서울이(가)'), '서울이');
    });

    test('숫자는 읽는 소리 기준', () {
      expect(resolveKoreanJosa('13(으)로'), '13으로'); // 삼
      expect(resolveKoreanJosa('14(으)로'), '14로'); // 사
      expect(resolveKoreanJosa('11(으)로'), '11로'); // 일 (ㄹ)
      expect(resolveKoreanJosa('유저2이(가)'), '유저2가'); // 이
      expect(resolveKoreanJosa('유저1이(가)'), '유저1이'); // 일
    });

    test('한 문장 안의 여러 조사를 각각 고른다', () {
      expect(
        resolveKoreanJosa('호랑이과(와) 토끼이(가) 카드를 교환했습니다'),
        '호랑이와 토끼가 카드를 교환했습니다',
      );
    });

    test('읽는 소리를 알 수 없으면 괄호 표기를 그대로 둔다', () {
      expect(resolveKoreanJosa('Tom이(가)'), 'Tom이(가)');
      expect(resolveKoreanJosa('😀이(가)'), '😀이(가)');
      expect(resolveKoreanJosa('이(가)'), '이(가)');
    });

    test('조사 표기가 없는 문장은 그대로', () {
      expect(resolveKoreanJosa('홍길동님이 초대했습니다'), '홍길동님이 초대했습니다');
    });
  });

  // 오버라이드를 빠뜨리면 그 문장만 괄호가 그대로 보인다. 새 문자열을 추가할
  // 때 놓치지 않도록 ARB 와 소스를 직접 대조한다.
  test('조사 표기를 쓰는 모든 한국어 문자열에 오버라이드가 있다', () {
    final arb = File('lib/l10n/app_ko.arb').readAsStringSync();
    final src = File('lib/l10n/korean_josa.dart').readAsStringSync();
    final josa = RegExp(
      r'이\(가\)|\(이\)가|은\(는\)|는\(은\)|을\(를\)|를\(을\)|과\(와\)|와\(과\)|\(으\)로|으로\(로\)',
    );
    final entry = RegExp(r'^  "([A-Za-z0-9_]+)": "(.*)",?$', multiLine: true);
    final missing = <String>[];
    for (final m in entry.allMatches(arb)) {
      final key = m.group(1)!;
      if (josa.hasMatch(m.group(2)!) && !src.contains('String $key(')) {
        missing.add(key);
      }
    }
    expect(missing, isEmpty,
        reason: 'korean_josa.dart 의 L10nKoJosa 에 오버라이드 추가 필요');
  });

  testWidgets('앱에 연결되면 L10n.of 가 받침에 맞는 조사를 돌려준다', (tester) async {
    late L10n ko;
    late L10n en;
    Future<void> pump(Locale locale, void Function(L10n) grab) async {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10nJosaDelegate(),
          ...L10n.localizationsDelegates,
        ],
        supportedLocales: L10n.supportedLocales,
        home: Builder(builder: (context) {
          grab(L10n.of(context));
          return const SizedBox();
        }),
      ));
      await tester.pumpAndSettle();
    }

    await pump(const Locale('ko'), (l) => ko = l);
    expect(ko.llGuardEffect('홍길동'), '홍길동이 가드를 사용합니다...');
    expect(ko.llGuardEffect('철수'), '철수가 가드를 사용합니다...');
    expect(ko.gameDogPlayedBy('철수'), '철수가 개를 냈어');
    expect(ko.gameDogPlayedBy('민석'), '민석이 개를 냈어');

    await pump(const Locale('en'), (l) => en = l);
    expect(en.llGuardEffect('Tom'), isNot(contains('이(가)')));
  });
}
