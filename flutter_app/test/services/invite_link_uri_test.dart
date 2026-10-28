import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/services/invite_link_service.dart';

void main() {
  String? token(String uri) =>
      InviteLinkService.inviteTokenFromUri(Uri.parse(uri));

  test('https 초대 링크', () {
    expect(token('https://tichu.kr/invite?t=abc'), 'abc');
    expect(token('https://tichu.jiny.shop/invite?t=abc'), 'abc');
  });

  test('tichuonline 스킴', () {
    expect(token('tichuonline://invite?t=abc'), 'abc');
  });

  test('카카오 공유 카드 버튼(앱 스킴)', () {
    const s = InviteLinkService.kakaoLinkScheme;
    expect(token('$s://kakaolink?type=invite&t=abc123'), 'abc123');
    expect(token('$s://kakaolink?t=abc123'), 'abc123');
  });

  test('카카오 로그인 콜백이나 다른 type 은 초대가 아니다', () {
    const s = InviteLinkService.kakaoLinkScheme;
    expect(token('$s://oauth?code=xyz&t=abc'), isNull);
    expect(token('$s://kakaolink?type=other&t=abc'), isNull);
  });

  test('토큰이 없거나 남의 주소면 null', () {
    const s = InviteLinkService.kakaoLinkScheme;
    expect(token('$s://kakaolink?type=invite'), isNull);
    expect(token('https://example.com/invite?t=abc'), isNull);
    expect(InviteLinkService.inviteTokenFromUri(null), isNull);
  });
}
