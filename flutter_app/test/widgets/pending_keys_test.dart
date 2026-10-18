import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/utils/pending_keys.dart';

/// 구매 요청이 두 번 나가지 않게 막는 표시.
///
/// 처음에는 키 하나만 들고 있었고, 소스를 읽는 검사로는 통과했다.
/// 실제로 눌러 보면 A → B → A 에서 A 가 두 번 나간다 — 그래서 이 파일은
/// 로직을 직접 돌려 본다.
void main() {
  late List<int> changes;
  late PendingKeys p;

  setUp(() {
    changes = [];
    p = PendingKeys(
      onChanged: () => changes.add(1),
      timeout: const Duration(milliseconds: 60),
    );
  });

  tearDown(() => p.dispose());

  test('시작하면 떠 있고, 응답이 오면 풀린다', () {
    expect(p.contains('a'), isFalse);
    final id = p.begin('a');
    expect(p.contains('a'), isTrue);
    p.end('a', id: id);
    expect(p.contains('a'), isFalse);
  });

  test('A → B → A: B 를 눌러도 A 는 떠 있다', () {
    // 키 하나만 들고 있을 때 A 가 두 번 나가던 경로.
    p.begin('a');
    p.begin('b');
    expect(p.contains('a'), isTrue, reason: 'B 를 누르자 A 의 기억이 지워졌다');
    expect(p.contains('b'), isTrue);
  });

  test('한 키의 응답이 다른 키를 풀지 않는다', () {
    p.begin('a');
    p.begin('b');
    p.end('b');
    expect(p.contains('a'), isTrue, reason: 'B 응답이 A 잠금을 풀었다');
    expect(p.contains('b'), isFalse);
  });

  test('키 없는 응답은 전부 푼다 — 잠긴 채 두는 것보다 낫다', () {
    p.begin('a');
    p.begin('b');
    p.end(null);
    expect(p.isEmpty, isTrue);
  });

  test('없는 키를 풀어도 아무 일 없다', () {
    final before = changes.length;
    p.end('없음');
    expect(changes.length, before, reason: '바뀐 게 없는데 화면을 다시 그린다');
  });

  test('응답이 유실돼도 시간이 지나면 풀린다', () async {
    p.begin('a');
    expect(p.contains('a'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(p.contains('a'), isFalse, reason: '버튼이 영영 잠긴다');
  });

  test('다시 누르면 시간이 다시 센다', () async {
    p.begin('a');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    p.begin('a');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(p.contains('a'), isTrue, reason: '80ms 가 지났지만 40ms 전에 다시 눌렀다');
  });

  test('바뀔 때만 알린다', () {
    p.begin('a');
    final after = changes.length;
    p.end('b'); // 없는 키
    expect(changes.length, after);
    p.end('a');
    expect(changes.length, after + 1);
  });

  test('시간이 지나 다시 누른 뒤, 늦게 온 옛 응답이 풀지 않는다', () async {
    // 1) A 를 샀는데 응답이 안 온다  2) 시간이 지나 버튼이 열린다
    // 3) A 를 다시 누른다           4) 그제서야 첫 응답이 도착한다
    // 4번이 3번의 잠금을 풀면, 응답을 기다리는 중에 세 번째로 누를 수
    // 있게 된다 — 토큰이 또 빠진다.
    final first = p.begin('a');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(p.contains('a'), isFalse, reason: '시간이 지나면 버튼이 열려야 한다');

    final second = p.begin('a');
    expect(second, isNot(first));
    p.end('a', id: first); // 늦게 도착한 첫 응답
    expect(p.contains('a'), isTrue, reason: '옛 응답이 새 요청의 잠금을 풀었다');

    p.end('a', id: second); // 제 응답이 오면 풀린다
    expect(p.contains('a'), isFalse);
  });

  test('번호를 모르는 응답은 키로만 맞춘다 — 옛 서버와도 동작한다', () {
    final id = p.begin('a');
    expect(id, greaterThan(0));
    p.end('a'); // id 없이
    expect(p.contains('a'), isFalse);
  });

  test('같은 키를 다시 시작하면 번호가 새로 매겨진다', () {
    final a1 = p.begin('a');
    final a2 = p.begin('a');
    expect(a2, isNot(a1));
    p.end('a', id: a1);
    expect(p.contains('a'), isTrue, reason: '옛 번호로 풀렸다');
  });

  test('정리하면 타이머가 남지 않는다', () async {
    p.begin('a');
    p.dispose();
    expect(p.isEmpty, isTrue);
    // dispose 뒤에 타이머가 깨어나 onChanged 를 부르면 안 된다.
    final after = changes.length;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(changes.length, after);
  });
}
