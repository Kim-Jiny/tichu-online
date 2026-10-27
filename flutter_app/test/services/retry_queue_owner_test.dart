import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/services/network_service.dart';

/// 재시도 큐는 쌓은 계정에게만 되돌려 준다.
///
/// 광고 보상·출석·결제 확인은 연결이 끊겼을 때 큐에 쌓였다가 다음 로그인 뒤에 나간다.
/// 큐에 계정이 적혀 있지 않으면 A 가 쌓아 둔 요청이 다음에 로그인한 B 의 소켓으로 나가
/// B 가 보상을 받는다.

String entry(Map<String, dynamic> msg, {String? owner, int ts = 1000, bool omitOwner = false}) {
  final m = <String, dynamic>{'ts': ts, 'msg': msg};
  if (!omitOwner) m['owner'] = owner;
  return jsonEncode(m);
}

void main() {
  const now = 2000;
  final claim = {'type': 'ad_reward', 'claimId': 'c-1'};

  test('같은 계정이 쌓은 것은 보낸다', () {
    final v = NetworkService.judgeRetryEntry(entry(claim, owner: 'tok-A'), owner: 'tok-A', nowMs: now);
    expect(v.action, RetryAction.send);
    expect(v.msg, claim);
  });

  test('다른 계정이 쌓은 것은 보내지 않고 남겨 둔다', () {
    final v = NetworkService.judgeRetryEntry(entry(claim, owner: 'tok-A'), owner: 'tok-B', nowMs: now);
    expect(v.action, RetryAction.keep);
  });

  test('로그아웃 상태(계정 없음)에서도 남의 것은 나가지 않는다', () {
    final v = NetworkService.judgeRetryEntry(entry(claim, owner: 'tok-A'), owner: null, nowMs: now);
    expect(v.action, RetryAction.keep);
  });

  test('계정이 적히기 전에 쌓인 항목은 예전처럼 보낸다', () {
    final v = NetworkService.judgeRetryEntry(entry(claim, omitOwner: true), owner: 'tok-B', nowMs: now);
    expect(v.action, RetryAction.send);
  });

  test('owner 가 null 로 적힌 항목(로그인 전에 쌓임)도 예전처럼 보낸다', () {
    final v = NetworkService.judgeRetryEntry(entry(claim, owner: null), owner: 'tok-B', nowMs: now);
    expect(v.action, RetryAction.send);
  });

  test('다른 계정의 것이라도 24시간이 지나면 버린다', () {
    final old = entry(claim, owner: 'tok-A', ts: 0);
    final v = NetworkService.judgeRetryEntry(old, owner: 'tok-B', nowMs: 25 * 60 * 60 * 1000);
    expect(v.action, RetryAction.expired);
  });

  test('깨진 항목은 버린다', () {
    expect(NetworkService.judgeRetryEntry('not json', owner: 'tok-A', nowMs: now).action, RetryAction.malformed);
    expect(
      NetworkService.judgeRetryEntry(jsonEncode({'ts': 1000, 'owner': 'tok-A', 'msg': 'x'}), owner: 'tok-A', nowMs: now).action,
      RetryAction.malformed,
    );
  });
}
