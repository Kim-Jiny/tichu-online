import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/widgets.dart';

import 'app_localizations.dart';
import 'app_localizations_ko.dart';

/// 한국어 조사(이/가, 은/는, 을/를, 과/와, (으)로)를 앞 글자 받침에 맞게 고른다.
///
/// 닉네임은 받침이 있을 수도 없을 수도 있어서 "{name}이(가)" 로 쓸 수밖에
/// 없었다. 그러면 "홍길동이(가) 가드를 사용합니다" 처럼 괄호가 그대로 보인다.
/// ARB 는 ICU 로 받침을 알 수 없고, 생성 파일(app_localizations_ko.dart)은
/// 빌드마다 다시 만들어지므로, 한국어 클래스를 상속해 완성된 문장에서
/// 조사만 고쳐 쓴다. 번역가는 ARB 에 "{name}이(가)" 형태로만 쓰면 된다.
///
/// 앞 글자가 한글·숫자가 아니면 (영문 닉네임, 이모지, 기호) 읽는 소리를
/// 알 수 없으니 괄호 표기를 그대로 둔다 — 틀린 조사보다 낫다.
final RegExp _josaPattern = RegExp(
  r'(.)(이\(가\)|\(이\)가|은\(는\)|는\(은\)|을\(를\)|를\(을\)|과\(와\)|와\(과\)|\(으\)로|으로\(로\))',
  unicode: true,
);

/// 받침 여부. 판단할 수 없으면 null.
bool? _hasBatchim(String ch) {
  final code = ch.runes.first;
  if (code >= 0xAC00 && code <= 0xD7A3) return (code - 0xAC00) % 28 != 0;
  // 숫자는 읽는 소리 기준: 영·일·삼·육·칠·팔 은 받침이 있다.
  switch (ch) {
    case '0':
    case '1':
    case '3':
    case '6':
    case '7':
    case '8':
      return true;
    case '2':
    case '4':
    case '5':
    case '9':
      return false;
  }
  return null;
}

/// 받침이 ㄹ 인지. (으)로 는 ㄹ 받침일 때 "로" 를 쓴다.
bool _isRieul(String ch) {
  final code = ch.runes.first;
  if (code >= 0xAC00 && code <= 0xD7A3) return (code - 0xAC00) % 28 == 8;
  // 일, 칠, 팔
  return ch == '1' || ch == '7' || ch == '8';
}

String resolveKoreanJosa(String s) {
  return s.replaceAllMapped(_josaPattern, (m) {
    final prev = m.group(1)!;
    final batchim = _hasBatchim(prev);
    if (batchim == null) return m.group(0)!;
    final form = m.group(2)!;
    final String josa;
    if (form == '이(가)' || form == '(이)가') {
      josa = batchim ? '이' : '가';
    } else if (form == '은(는)' || form == '는(은)') {
      josa = batchim ? '은' : '는';
    } else if (form == '을(를)' || form == '를(을)') {
      josa = batchim ? '을' : '를';
    } else if (form == '과(와)' || form == '와(과)') {
      josa = batchim ? '과' : '와';
    } else {
      josa = (batchim && !_isRieul(prev)) ? '으로' : '로';
    }
    return '$prev$josa';
  });
}

/// 조사 표기가 들어간 한국어 문장만 [resolveKoreanJosa] 를 거친다.
/// 새 ARB 문자열에 "이(가)" 류를 쓰면 여기에도 오버라이드를 추가해야 하고,
/// test/korean_josa_test.dart 가 빠뜨리면 실패하게 막아 둔다.
class L10nKoJosa extends L10nKo {
  L10nKoJosa() : super('ko');

  @override
  String gameDogPassedTo(String from, String to) =>
      resolveKoreanJosa(super.gameDogPassedTo(from, to));
  @override
  String settingsDeleteTypeNickname(String nickname) =>
      resolveKoreanJosa(super.settingsDeleteTypeNickname(nickname));
  @override
  String skGameCardViewRejected(String name) =>
      resolveKoreanJosa(super.skGameCardViewRejected(name));
  @override
  String mtChangeTrumpConfirmBody(Object points, Object suit) =>
      resolveKoreanJosa(super.mtChangeTrumpConfirmBody(points, suit));
  @override
  String mtChangeTrumpNoPenaltyBody(Object suit) =>
      resolveKoreanJosa(super.mtChangeTrumpNoPenaltyBody(suit));
  @override
  String mtKillResultKilled(Object declarer, Object target, Object victim) =>
      resolveKoreanJosa(super.mtKillResultKilled(declarer, target, victim));
  @override
  String mtKillResultSuicide(Object declarer, Object target) =>
      resolveKoreanJosa(super.mtKillResultSuicide(declarer, target));
  @override
  String llGuardEffect(String name) =>
      resolveKoreanJosa(super.llGuardEffect(name));
  @override
  String llSpyEffect(String name) => resolveKoreanJosa(super.llSpyEffect(name));
  @override
  String llBaronEffect(String name) =>
      resolveKoreanJosa(super.llBaronEffect(name));
  @override
  String llPrinceEffect(String name) =>
      resolveKoreanJosa(super.llPrinceEffect(name));
  @override
  String llKingEffect(String name) =>
      resolveKoreanJosa(super.llKingEffect(name));
  @override
  String llHandmaidEffect(String name) =>
      resolveKoreanJosa(super.llHandmaidEffect(name));
  @override
  String llBlockedByHandmaid(String name, String card) =>
      resolveKoreanJosa(super.llBlockedByHandmaid(name, card));
  @override
  String llGuardCorrect(String actor, String target) =>
      resolveKoreanJosa(super.llGuardCorrect(actor, target));
  @override
  String llGuardWrong(String actor, String target) =>
      resolveKoreanJosa(super.llGuardWrong(actor, target));
  @override
  String llSpySawYour(String actor) =>
      resolveKoreanJosa(super.llSpySawYour(actor));
  @override
  String llSpyPeeked(String actor, String target) =>
      resolveKoreanJosa(super.llSpyPeeked(actor, target));
  @override
  String llBaronTie(String actor, String target) =>
      resolveKoreanJosa(super.llBaronTie(actor, target));
  @override
  String llBaronLose(String loser, String winner) =>
      resolveKoreanJosa(super.llBaronLose(loser, winner));
  @override
  String llPrinceEliminated(String target) =>
      resolveKoreanJosa(super.llPrinceEliminated(target));
  @override
  String llPrinceDiscard(String target) =>
      resolveKoreanJosa(super.llPrinceDiscard(target));
  @override
  String llKingSwap(String actor, String target) =>
      resolveKoreanJosa(super.llKingSwap(actor, target));
  @override
  String midJoinNoticeLeft(String player, String bot) =>
      resolveKoreanJosa(super.midJoinNoticeLeft(player, bot));
  @override
  String midJoinNoticeKicked(String player, String bot) =>
      resolveKoreanJosa(super.midJoinNoticeKicked(player, bot));
  @override
  String gameDogPlayedBy(String name) =>
      resolveKoreanJosa(super.gameDogPlayedBy(name));
  @override
  String spectatorPlayedCards(String name) =>
      resolveKoreanJosa(super.spectatorPlayedCards(name));
}

/// 한국어일 때만 [L10nKoJosa] 를 돌려주고, 나머지는 생성된 델리게이트에 맡긴다.
class L10nJosaDelegate extends LocalizationsDelegate<L10n> {
  const L10nJosaDelegate();

  @override
  bool isSupported(Locale locale) => L10n.delegate.isSupported(locale);

  @override
  Future<L10n> load(Locale locale) {
    if (locale.languageCode == 'ko') {
      return SynchronousFuture<L10n>(L10nKoJosa());
    }
    return L10n.delegate.load(locale);
  }

  @override
  bool shouldReload(L10nJosaDelegate old) => false;
}
