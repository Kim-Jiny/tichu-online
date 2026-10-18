import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/models/missions.dart';

/// 토큰 상점 버튼이 같은 요청을 두 번 보내지 않는지, 팔지 않는 상품을
/// 누를 수 있게 두지 않는지.
///
/// 둘 다 서버에서 막기 어렵다. 같은 상품을 연달아 두 번 사는 것 자체는
/// 정상이고(기간 연장) 두 요청을 구분할 표식이 없다. 판매 중단은 서버가
/// 거절하긴 하지만, 앱은 그걸 일반 오류로만 보여 준다.
void main() {
  group('canBuy 를 읽는다', () {
    test('서버가 false 로 주면 false', () {
      final p = TokenProduct.fromJson(const {
        'key': 'x',
        'kind': 'bubble_basic',
        'variant': 1,
        'price': 60,
        'days': 30,
        'canBuy': false,
      });
      expect(p.canBuy, isFalse);
    });

    test('없거나 true 면 살 수 있다 — 이 값을 안 주던 서버와도 맞는다', () {
      for (final j in [
        const {
          'key': 'x',
          'kind': 'bubble_basic',
          'variant': 1,
          'price': 60,
          'days': 30,
        },
        const {
          'key': 'x',
          'kind': 'bubble_basic',
          'variant': 1,
          'price': 60,
          'days': 30,
          'canBuy': true,
        },
      ]) {
        expect(TokenProduct.fromJson(j).canBuy, isTrue);
      }
    });
  });

  group('버튼이 조건을 모두 본다', () {
    final src = File('lib/screens/token_shop_screen.dart').readAsStringSync();

    test('응답을 기다리는 동안 잠긴다', () {
      expect(
        src.contains('isTokenShopPending('),
        isTrue,
        reason: '진행 중 표시를 보지 않는다 — 연타하면 토큰이 두 번 빠진다',
      );
    });

    test('판매 중단 상품은 잠긴다', () {
      expect(src.contains('p.canBuy'), isTrue, reason: 'canBuy 를 보지 않는다');
    });

    test('세 조건이 함께 걸린다', () {
      // 하나라도 빠지면 그 경로만 열린다.
      final m = RegExp(r'final enabled = ([^;]+);').firstMatch(src);
      expect(m, isNotNull, reason: '버튼 활성 조건을 한곳에 모으지 않았다');
      final cond = m!.group(1)!;
      for (final part in ['canBuy', 'canAfford', 'pending']) {
        expect(cond.contains(part), isTrue, reason: '조건에 $part 가 없다: $cond');
      }
    });
  });

  group('로딩이 영원히 돌지 않는다', () {
    final src = File('lib/services/game_service.dart').readAsStringSync();

    test('토큰 내역에도 타임아웃이 있다', () {
      // 상점 목록에는 있었는데 내역에는 없었다. 연결이 끊긴 사이에 열면
      // 요청이 유실되고, 창을 닫았다 열기 전에는 재요청도 없다.
      expect(
        src.contains('_tokenHistoryLoadTimer'),
        isTrue,
        reason: '내역 요청에 타임아웃이 없다',
      );
    });

    test('구매 잠금에도 타임아웃이 있다 — 응답이 유실돼도 풀린다', () {
      // 동작 자체는 pending_keys_test.dart 가 돌려 본다. 여기서는
      // 서비스가 그 장치를 쓰는지만 본다.
      expect(src.contains('PendingKeys('), isTrue);
    });

    test('장착 응답이 구매 잠금을 풀지 않는다', () {
      // 두 응답이 한 case 를 쓰는데 장착 응답에는 key 가 없다. 가리지
      // 않으면 다른 상품을 장착한 응답이 떠 있는 구매를 풀어 버린다.
      final i = src.indexOf("case 'token_buy_result':");
      expect(i, greaterThan(0));
      final block = src.substring(i, i + 1600);
      final end = block.indexOf('_tokenShopPending.end(');
      expect(end, greaterThan(0), reason: '구매 잠금을 푸는 곳이 없다');
      // '바로 앞' 만 본다. 블록 전체를 보면 이 case 안의 다른 비교
      // (tokenShopAction 을 정하는 줄)에 걸려 가드가 없어도 통과한다 —
      // 실제로 그렇게 거짓 통과했다.
      final justBefore = block.substring(end - 60, end);
      expect(
        justBefore.contains("if (type == 'token_buy_result') {"),
        isTrue,
        reason: '응답 종류를 가리지 않고 잠금을 푼다: $justBefore',
      );
    });

    test('내역 실패를 실패로 알린다 — 빈 내역과 다르다', () {
      // 로딩만 끄면 화면이 '내역 없음' 을 띄운다. 받지 못한 것과 정말
      // 없는 것은 다르고, 앞의 경우에는 다시 받을 방법이 있다.
      final i = src.indexOf('_armTokenHistoryTimeout');
      expect(i, greaterThan(0));
      final block = src.substring(i, i + 800);
      expect(
        block.contains('tokenHistoryFailed = true'),
        isTrue,
        reason: '타임아웃이 실패 상태를 세우지 않는다',
      );
    });

    test('타이머를 dispose 에서 정리한다', () {
      // dispose 는 길다. 고정 길이로 자르면 아래쪽 정리 줄을 놓친다.
      final i = src.indexOf('void dispose()');
      expect(i, greaterThan(0));
      final body = src.substring(i, src.indexOf('super.dispose()', i));
      expect(
        body.contains('_tokenHistoryLoadTimer?.cancel()'),
        isTrue,
        reason: '내역 타이머를 정리하지 않는다',
      );
      expect(
        body.contains('_tokenShopPending.dispose()'),
        isTrue,
        reason: '구매 잠금 타이머를 정리하지 않는다',
      );
    });
  });
}
