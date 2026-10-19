/// [스토어 스크린샷 촬영 전용] 봇을 실제 유저처럼 보이게 서버 메시지를 고쳐 쓴다.
///
/// `--dart-define=SHOTS_DISGUISE=true` 일 때만 동작한다. 닉네임의 "봇 N" 을
/// 사람 이름으로 바꾸고, isBot 을 끄고, 프로필 사진 주소와 레벨을 채운다.
/// 이 파일과 호출부는 screenshots 브랜치에만 있다.
const bool shotsDisguise = bool.fromEnvironment('SHOTS_DISGUISE');

const _aliases = <String>[
  '별빛토끼', '딸기라떼', '카드마스터', '초코우유', '구름위에서', '용의후예', '해적왕루피',
];
const _photoBase = 'http://127.0.0.1:8191';
const _myName = '티츄왕';
// 시드한 유저 닉네임 → 프로필 사진 번호(1~6).
const _seeded = <String, int>{
  '별빛토끼': 1, '달콤한곰': 2, '용의후예': 3, '카드마스터': 4, '초코우유': 5, '구름위에서': 6,
  '해적왕루피': 2, '마이티냥': 3, '하늘정원': 4, '딸기라떼': 5, '번개손': 6, '푸른여우': 1,
};
final _botName = RegExp(r'봇 ?(\d+)');

String _alias(int n) => _aliases[(n - 1).abs() % _aliases.length];
int _botNumber(String s) {
  final m = _botName.firstMatch(s);
  return m == null ? 0 : int.parse(m.group(1)!);
}

dynamic _walk(dynamic v) {
  if (v is String) {
    return v
        .replaceAllMapped(_botName, (m) => _alias(int.parse(m.group(1)!)))
        .replaceAll('bot_', 'usr_');
  }
  if (v is List) {
    for (var i = 0; i < v.length; i++) {
      v[i] = _walk(v[i]);
    }
    return v;
  }
  if (v is Map) {
    final wasBot = v['isBot'] == true;
    final raw = '${v['name'] ?? v['nickname'] ?? ''}';
    final n = _botNumber(raw);
    for (final k in v.keys.toList()) {
      final val = _walk(v[k]);
      if (k is String && k.contains('bot_')) {
        v.remove(k);
        v[k.replaceAll('bot_', 'usr_')] = val;
      } else {
        v[k] = val;
      }
    }
    if (wasBot) {
      v['isBot'] = false;
      final idx = (n == 0 ? 1 : n);
      v['photoUrl'] = '$_photoBase/p${(idx - 1) % 6 + 1}.jpg';
      v['level'] ??= 9 + idx * 4;
      v['seasonRating'] ??= 1400 + idx * 65;
    } else if (_seeded.containsKey(raw)) {
      v['photoUrl'] ??= '$_photoBase/p${_seeded[raw]}.jpg';
    } else if (raw == _myName || v['name'] == _myName) {
      v['photoUrl'] = '$_photoBase/p0.jpg';
    }
    return v;
  }
  return v;
}

Map<String, dynamic> disguiseMessage(Map<String, dynamic> json) {
  if (!shotsDisguise) return json;
  return _walk(json) as Map<String, dynamic>;
}
