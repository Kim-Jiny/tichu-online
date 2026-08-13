/**
 * What 정보통신망법 §50 ④ requires of an advertising message, in one place.
 *
 * Two rules, both of which have to hold on every single campaign:
 *   - the subject starts with "(광고)"
 *   - the body says how to stop receiving them
 *
 * They live here rather than inline in the admin route so they can be tested
 * without standing up an HTTP server, and so there is one copy to change if a
 * settings label moves or the wording is revised by counsel.
 */

/// The opt-out line appended to every marketing push.
///
/// Appended at send time rather than typed into the campaign body: it has to
/// be on all of them, and anything an admin must remember every single time is
/// eventually forgotten on one of them.
///
/// The path names a real screen — Settings > 알림 > 이벤트·혜택 알림. If that
/// label is ever renamed, this line has to be renamed with it, or the notice
/// points somewhere that does not exist.
const MARKETING_OPT_OUT_LINE =
  '\n\n* 수신거부 : 앱 설정 > 알림 > 이벤트·혜택 알림 끄기';

/// Append the opt-out line, unless it is already there.
///
/// Idempotent because a campaign can be re-sent after a failed delivery, and
/// the second attempt reads the body back out of the same row.
function withMarketingOptOut(body) {
  const text = String(body || '').trimEnd();
  if (text.includes('수신거부')) return text;
  return `${text}${MARKETING_OPT_OUT_LINE}`;
}

/// Does the subject carry the "(광고)" label the law asks for?
///
/// Accepts the full-width brackets a Korean IME produces as readily as ASCII
/// ones, and spacing inside them. Requires it at the START — the rule is about
/// what someone sees before opening the message, so a label buried mid-title
/// does not satisfy it.
function adTitleLooksLabelled(title) {
  return /^[(（]\s*광고\s*[)）]/.test(String(title || '').trim());
}

module.exports = {
  MARKETING_OPT_OUT_LINE,
  withMarketingOptOut,
  adTitleLooksLabelled,
};
