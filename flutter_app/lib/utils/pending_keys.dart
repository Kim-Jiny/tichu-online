import 'dart:async';

import 'package:flutter/foundation.dart';

/// "응답을 기다리는 중" 을 키마다 따로 세는 표시.
///
/// 상점 구매처럼 같은 요청이 두 번 나가면 안 되는 자리에 쓴다. 서버에서
/// 막기 어려운 종류다 — 같은 상품을 연달아 두 번 사는 것 자체는 정상이고
/// (기간 연장) 두 요청을 구분할 표식이 없다.
///
/// 키 하나만 들고 있으면 안 된다. A → B → A 로 누르면 B 를 누르는 순간
/// A 의 기억이 지워져 A 가 두 번 나간다. 한 번에 하나만 하게 막을 이유는
/// 없으므로, 막는 단위를 키별로 둔다.
///
/// 떼어 둔 이유는 돌려 볼 수 있게 하기 위해서다. 이 로직이 서비스 안에
/// 있으면 테스트에서 그 서비스를 만들 수 없어(Firebase) 소스를 읽는
/// 검사밖에 못 하는데, 위의 A → B → A 같은 건 소스를 읽어서는 보이지
/// 않는다.
class PendingKeys {
  PendingKeys({
    required this.onChanged,
    this.timeout = const Duration(seconds: 8),
  });

  /// 표시가 바뀌었을 때. 화면을 다시 그리게 한다.
  final VoidCallback onChanged;

  /// 응답이 유실되어도 영영 잠기지 않게 하는 시간.
  final Duration timeout;

  final Map<String, _Pending> _open = {};
  int _seq = 0;

  bool contains(String key) => _open.containsKey(key);

  bool get isEmpty => _open.isEmpty;

  /// 이 키의 요청을 시작하고, 그 요청의 번호를 돌려준다.
  ///
  /// 번호를 요청에 실어 보내고 응답에서 되돌려 받으면, 같은 키의 옛
  /// 요청과 새 요청을 구별할 수 있다. [end] 설명을 보라.
  int begin(String key) {
    _open.remove(key)?.timer.cancel();
    final id = ++_seq;
    _open[key] = _Pending(
      id,
      Timer(timeout, () {
        // 시간이 지나 버튼을 다시 열어 준다. 요청 자체가 취소된 것은
        // 아니므로, 뒤늦게 응답이 와도 이 번호와는 맞지 않는다.
        if (_open[key]?.id != id) return;
        _open.remove(key);
        onChanged();
      }),
    );
    onChanged();
    return id;
  }

  /// 응답이 왔다.
  ///
  /// [id] 는 [begin] 이 준 번호다. 지금 기다리는 요청의 번호와 다르면
  /// 무시한다 — 늦게 도착한 옛 응답이 새 요청의 잠금을 풀면, 응답을
  /// 기다리는 중에 한 번 더 누를 수 있게 된다.
  ///
  /// [id] 가 null 이면 번호를 모르는 응답이다(번호를 안 돌려주는 옛
  /// 서버). 그때는 키로만 맞춘다 — 지금까지와 같다.
  ///
  /// [key] 가 null 이면 어떤 요청의 응답인지 알 수 없으므로 전부 푼다
  /// (로그인이 풀린 상태의 거절 등). 잠긴 채로 두는 것보다 낫고, 어차피
  /// 시간이 지나면 풀린다.
  void end(String? key, {int? id}) {
    if (key == null) {
      if (_open.isEmpty) return;
      for (final p in _open.values) {
        p.timer.cancel();
      }
      _open.clear();
      onChanged();
      return;
    }
    final p = _open[key];
    if (p == null) return;
    if (id != null && p.id != id) return;
    _open.remove(key);
    p.timer.cancel();
    onChanged();
  }

  void dispose() {
    for (final p in _open.values) {
      p.timer.cancel();
    }
    _open.clear();
  }
}

class _Pending {
  _Pending(this.id, this.timer);
  final int id;
  final Timer timer;
}
