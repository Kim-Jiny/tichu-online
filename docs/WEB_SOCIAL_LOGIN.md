# 웹 소셜 로그인 설정

코드도 키도 전부 들어가 있다. `flutter build web` 그대로 빌드하면 세 제공자가
모두 켜진다.

| 제공자 | 상태 |
|---|---|
| 구글 | ✅ 로컬 확인 완료 (팝업 → 로그인) |
| 애플 | ✅ 로컬 확인 완료 |
| 카카오 | 코드 완료. **로컬에서는 확인 불가** — 아래 참조. 배포 후 확인 필요 |

**키가 없으면 그 제공자의 버튼은 로그인 화면에 아예 나오지 않는다.** 눌러도 안 되는
버튼을 보여주느니 숨기는 쪽이 낫기 때문이고, 이건 정상 동작이다(`SocialConfig`).

## 왜 카카오만 로컬에서 안 되나

도메인을 검증하는 주체가 다르다.

| | 검증 주체 | `localhost` |
|---|---|---|
| 구글·애플 | Firebase 승인된 도메인 | **기본 포함** → 됨 |
| 카카오 | 카카오 플랫폼 Web 사이트 도메인 | `tichu.jiny.shop`만 등록 → 안 됨 |

구글·애플은 팝업이 `firebaseapp.com`으로 가고 Firebase가 opener 출처를 승인 도메인
목록으로 검사하는데 `localhost`가 거기 기본으로 들어 있다. 카카오는 JS 키를 등록된
사이트 도메인으로 인가하므로 `localhost:8080`은 통과하지 못한다.

로컬에서도 보고 싶으면 카카오 개발자 → 플랫폼 → Web 에 `http://localhost:8080`을
하나 더 추가하면 된다.

## 왜 서버는 안 건드려도 되나

`handleSocialLogin`은 이미 이렇게 검증한다:

- `kakao` → 카카오 API에 액세스 토큰 조회
- `google` / `apple` → Firebase Admin `verifyIdToken`

웹도 Firebase Auth로 로그인하므로 **같은 종류의 ID 토큰**이 나온다. 서버 코드는
한 줄도 바뀌지 않았고, Firebase 프로젝트가 같으니 **uid도 같다** — 앱에서 구글로
가입한 계정으로 웹에서도 그대로 로그인된다.

## 콘솔 설정 현황

### Firebase (구글 + 애플)

프로젝트 `tichu-online-95`

- ✅ **웹 앱 등록** — apiKey / appId 모두 `lib/firebase_options.dart`에 들어감
- ✅ **애플 제공자** — 동작 확인됨. iOS 앱이 쓰던 설정을 웹 OAuth도 함께 쓴다
- ⬜ **승인된 도메인에 `tichu.jiny.shop` 추가** — 배포 전 필수.
  없으면 실서버에서 구글·애플이 `auth/unauthorized-domain`으로 실패한다.
  (`localhost`는 기본 포함이라 로컬 테스트가 됐던 것)

> 폰 실기기로 LAN IP(`http://192.168.x.x:8080` 등)에 접속해 테스트하면 그 IP도
> 승인 도메인에 없으므로 구글·애플이 똑같이 실패한다. 설정 문제가 아니라 테스트
> 환경 문제다.

### 카카오

- ✅ **JavaScript 키** — `lib/config/social_config.dart`에 들어감
- ✅ **플랫폼 → Web 사이트 도메인** `https://tichu.jiny.shop` 등록
- ✅ **카카오 로그인 활성화**

#### Redirect URI는 실제로 쓰이지 않는다

콘솔이 입력을 요구해서 채워 넣을 뿐이다. 웹에서 우리가 타는 세 경로 어디에도
우리 도메인이 redirect_uri로 들어가지 않는다:

| 환경 | 호출 | 실제 redirect_uri |
|---|---|---|
| 데스크톱 | `loginWithKakaoAccount()` | `'JS-SDK'` (센티널) |
| iOS 모바일웹 | `loginWithKakaoTalk()` | `'JS-SDK'` (센티널) |
| 안드로이드 모바일웹 | `loginWithKakaoTalk()` | `https://kapi.kakao.com/cors/afterlogin.html` |

안드로이드만 진짜 URL을 쓰는데 그것도 카카오 자기네 도메인이다
(`kakao_flutter_sdk_common/lib/src/server_hosts.dart`). JS SDK 팝업은 어디로
이동하는 대신 opener로 결과를 돌려주기 때문. Redirect URI는 REST API 방식 전용이다.

## GitHub 시크릿 — 설정할 필요 없다

셋 다 코드에 기본값이 있다. **아무것도 등록하지 않아도 정상 배포된다.**

| 이름 | 기본값 위치 |
|---|---|
| `FIREBASE_WEB_API_KEY` | `lib/firebase_options.dart` |
| `FIREBASE_WEB_APP_ID` | `lib/firebase_options.dart` |
| `KAKAO_JS_KEY` | `lib/config/social_config.dart` |

시크릿은 **덮어쓸 때만** 쓴다(다른 Firebase 프로젝트, 키 교체 등).

### 함정: 빈 값은 기본값을 지운다

`--dart-define=KEY=` 는 인자를 생략한 것과 다르다. `String.fromEnvironment`는
넘겨받은 빈 문자열을 그대로 돌려주고 `defaultValue`를 쓰지 않는다:

```
define 없이     → FALLBACK
--define=KEY=   → (빈 문자열)
```

그러면 `SocialConfig`가 모든 제공자 버튼을 숨겨서, **로그인 수단이 하나도 없는
사이트**가 배포된다. 빌드 로그에는 아무 단서도 안 남는다.

그래서 워크플로는 시크릿이 비어 있으면 해당 `--dart-define`을 **아예 넘기지
않는다**. 손댈 때 이 조건을 없애지 말 것.

## 로컬에서 빌드

```bash
flutter build web --release --base-href=/ --pwa-strategy=none
```

`--base-href=/` — 웹 클라이언트는 사이트 루트에 마운트된다(`/play/*`는 301).
키는 코드에 있으므로 `--dart-define` 없이도 세 버튼이 다 나온다.

## 문제가 생기면

| 증상 | 원인 |
|---|---|
| 버튼이 안 보임 | 그 제공자의 키가 비어 있음 (`SocialConfig`) |
| `api-key-not-valid` | apiKey 오타 |
| `auth/unauthorized-domain` | Firebase 승인된 도메인에 접속 출처 누락 |
| 카카오 `KOE006`/`KOE101` | 카카오 플랫폼 Web 사이트 도메인 미등록 |
| 애플 팝업에 `invalid_client` | Services ID / Return URL 불일치 |

## 알아둘 것

- 웹 애플 로그인은 **안드로이드 브라우저에서도 뜬다.** 네이티브 시트가 아니라
  그냥 OAuth 팝업이라서다. 앱에서는 종전대로 iOS에서만 보인다.
- **카카오는 모바일 웹에서 카카오톡 앱으로 넘어간다.** `isKakaoTalkInstalled()`가
  웹에서도 동작해(모바일 true / 데스크톱 false) `loginWithKakaoTalk()`을 타기
  때문. 여기에 `kIsWeb` 예외를 넣으면 안 된다 — 넣었다가 모바일 웹에서
  아이디/비번 창만 뜨는 버그를 만든 적이 있다.
- 팝업이 닫혀도 `signInWithPopup`이 항상 reject 하지는 않는다. 그래서 "로그인 중"
  오버레이에 취소 버튼이 있고, `_socialAttempt` 카운터가 버려진 시도의 뒤늦은
  결과를 무시한다.
- 팝업 차단기를 켠 브라우저에서는 구글/애플 팝업이 막힐 수 있다. 현재는
  `signInWithPopup`만 쓴다. 문제가 되면 `signInWithRedirect` 폴백을 넣어야 하는데,
  리다이렉트는 앱 상태가 한 번 날아가므로 실제 불편 보고가 나오기 전까지는
  팝업만 유지한다.
