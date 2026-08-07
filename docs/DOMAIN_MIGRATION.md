# 도메인 이전 (tichu.jiny.shop → tichu.kr) 과 CDN

두 가지 별개의 작업을 한 문서에 둔다. 순서가 있기 때문이다:
**앱을 tichu.kr로 옮기는 게 먼저고, CDN은 그 위에 얹는 게 이득이 크다.**

---

## 배경 — 왜 한 번에 못 바꾸나

`tichu.jiny.shop`은 **이미 배포된 앱 바이너리에 컴파일되어 있다.** 유저 폰에
깔린 구버전은 서버 설정을 어떻게 바꾸든 영원히 그 호스트로 접속한다.

박혀 있는 곳 다섯 군데:

| 위치 | 용도 |
|---|---|
| `lib/services/network_service.dart:24` | `wss://` 게임 서버 주소 |
| `lib/services/invite_link_service.dart:21` | 초대 링크 호스트 검사 |
| `android/.../AndroidManifest.xml:38-39` | 앱 링크 (pathPrefix `/invite`) |
| `ios/Runner/Runner.entitlements` | Associated Domains |
| `ios/Runner/RunnerDebug.entitlements` | 위와 동일 (디버그) |

여기에 서버 쪽 `INVITE_BASE_URL`(기본값 `https://tichu.jiny.shop`)이 더해진다.

**그래서 `tichu.jiny.shop`은 "구버전 앱이 전부 사라질 때까지" 살아 있어야 한다.**
강제 업데이트로 내보내는 것도 그 호스트를 통해야 한다 — 구버전 앱은 거기로만
접속하므로, 그 서버가 죽으면 업데이트하라는 말조차 전달할 수 없다.

---

## 1단계 — 앱을 tichu.kr로 옮기기

### 코드 변경

- `network_service.dart` → `wss://tichu.kr`
- `invite_link_service.dart` → **두 호스트를 모두 허용해야 한다.** 새 앱이
  구버전 유저가 보낸 `tichu.jiny.shop/invite` 링크를 못 알아보면 안 된다.
  ```dart
  static const inviteHosts = {'tichu.kr', 'tichu.jiny.shop'};
  ```
- `AndroidManifest.xml` → `tichu.kr` **추가**(기존 것 유지). 두 `<data>` 쌍이 된다.
- `Runner.entitlements` / `RunnerDebug.entitlements` →
  `applinks:tichu.kr` **추가**(기존 것 유지)

### 서버 변경

- `INVITE_BASE_URL=https://tichu.kr` (docker-compose 환경변수)
  → 새로 만드는 초대 링크만 바뀐다. 기존 링크는 계속 동작한다.
- AASA / assetlinks.json은 경로 기반이라 **두 호스트 모두에서 이미 응답한다.**
  확인: `curl https://tichu.kr/apple-app-site-association`

### 콘솔 등록

- Firebase → 승인된 도메인에 `tichu.kr` (이미 되어 있으면 통과)
- 카카오 → 플랫폼 Web 사이트 도메인에 `https://tichu.kr`
- Apple Developer → Services ID의 Return URL은 `firebaseapp.com`이라 **무관**

### 검증

새 빌드를 스토어에 올리기 전에:

1. `tichu.kr`로 게임 한 판 (WS 연결)
2. `tichu.kr/invite?t=...` 링크가 앱을 여는지 (유니버설 링크)
3. `tichu.jiny.shop/invite?t=...` **구 링크도** 앱을 여는지
4. 구버전 앱이 여전히 `tichu.jiny.shop`으로 정상 접속하는지

---

## 2단계 — tichu.jiny.shop 은퇴

**서두를 이유가 없다.** 도메인 만료일까지는 두 호스트를 병행하는 게 안전하다.

1. 1단계 앱이 스토어에 나가고 **충분히 보급될 때까지 대기**
2. 백스테이지 → 설정 → `min_version`을 새 버전으로 올려 강제 업데이트
   - 구버전은 `tichu.jiny.shop`으로 접속해 이 지시를 받는다 →
     **그때까지 그 호스트가 살아 있어야 한다**
3. 접속 로그에서 구버전이 사실상 0이 된 것을 확인
4. 도메인 만료 시점에 nginx 블록·인증서 정리

> `min_version`은 웹에도 적용된다. 웹은 새로고침이 곧 업데이트라
> 문구·버튼이 웹 전용으로 분기되어 있다(`main.dart` 참조).

---

## 3단계 — CDN (Cloudflare)

### 왜 필요한가 — 실측

서버가 유럽(Contabo)이라 한국에서 **왕복 지연만 약 300ms**다.

```
/health   2 bytes   →  301ms      ← 순수 지연
bot1.webp 18 KB     →  292ms
ll_Princess 39 KB   →  297ms
main.dart.js 1.47MB(gzip) → 2151ms
```

크기와 무관하게 요청 하나당 ~300ms다. **이미지를 더 줄여도 효과가 없다** —
이미 85% 줄였고, 남은 건 전부 거리다. CDN이 유일한 근본 해결책이다.

### 이미 해결돼 있는 것 (걱정 안 해도 됨)

- **클라이언트 IP**: `server.js:2763`이 `X-Forwarded-For`의 **첫 항목**을 읽는다.
  Cloudflare가 실제 IP를 XFF에 넣으므로 로그인 스로틀·플러드 방지·`lastIp`가
  그대로 동작한다. 코드 수정 불필요.
- **WebSocket 유휴 끊김**: 서버가 15초마다 ping을 보낸다
  (`HEARTBEAT_INTERVAL_MS`). CF 타임아웃보다 훨씬 짧다.

### 적용 범위 — tichu.kr 부터

Cloudflare 무료 플랜은 **zone(도메인) 전체**의 네임서버를 넘겨야 한다.
서브도메인만 따로는 안 된다.

- `tichu.kr` → 이 도메인만. 다른 서비스 영향 없음
- `tichu.jiny.shop` → `jiny.shop` **전체**(coach·gto·lingo 포함)를 넘겨야 함

1단계가 끝나 앱이 `tichu.kr`을 쓰게 되면 `jiny.shop`을 건드릴 이유가 사라진다.
**그래서 앱 이전이 먼저다.**

### 절차

1. Cloudflare 사이트 추가 → `tichu.kr` → 무료 플랜.
   A 레코드가 `77.237.243.141`인지 확인
2. 카페24에서 네임서버를 Cloudflare 것으로 교체 (전파 수십 분~수 시간)
3. A 레코드 **프록시 켜기**(오렌지 구름) — 이게 켜져야 CDN이 동작
4. SSL/TLS 모드 **`Full (strict)`**.
   `Flexible`은 무한 리다이렉트를 만든다 — 절대 금물
5. **ACME 예외 규칙**: `Always Use HTTPS`가 Let's Encrypt HTTP 챌린지를
   리다이렉트해 **갱신을 실패시킨다.** Configuration Rule로
   `/.well-known/acme-challenge/*`를 제외할 것.
   빠뜨리면 90일 뒤 조용히 만료된다
6. **캐시 헤더 조정** (코드 작업):
   현재 `main.dart.js`는 `no-cache`라 CF가 매번 원본에 물어본다 →
   300ms 왕복이 그대로 남아 CDN 효과가 없다. `s-maxage`를 더해야 한다:
   ```
   Cache-Control: no-cache, s-maxage=300
   ```
   브라우저는 계속 재검증하고 CDN만 엣지에서 응답한다.
   배포 직후 최대 5분 지연 → 필요하면 배포 스텝에 CF 캐시 퍼지 추가

### 되돌리기

프록시를 회색 구름으로 끄면 즉시 원상복구. 네임서버는 카페24에서 원복.
위험도는 낮다.

---

## 참고 — 지금 당장 할 수 있는 별개 개선

CDN과 무관하게, **봇 아바타·카드가 화면보다 늦게 뜨는 것**은
`precacheImage`로 해결된다. Flutter의 `Image.asset`은 위젯이 그려질 때
비로소 요청하므로, 로비가 뜬 뒤 ~300ms 후에 이미지가 채워진다.
미리 받아두면 화면과 동시에 나타난다. CDN 없이도 체감된다.
