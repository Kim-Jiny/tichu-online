# 웹 소셜 로그인 설정

코드는 전부 들어가 있다. appId와 카카오 JS 키도 코드에 박아뒀다.
**남은 건 Firebase 웹 apiKey 하나와 콘솔 등록뿐이다.**

**키가 없으면 그 제공자의 버튼은 로그인 화면에 아예 나오지 않는다.**
눌러도 안 되는 버튼을 보여주느니 숨기는 쪽이 낫기 때문이고, 이건 정상 동작이다.
따라서 아래를 부분적으로만 해도 된다 — 구글만 켜고 카카오는 나중에 해도 무방하다.

## 왜 서버는 안 건드려도 되나

`handleSocialLogin`은 이미 이렇게 검증한다:

- `kakao` → 카카오 API에 액세스 토큰 조회
- `google` / `apple` → Firebase Admin `verifyIdToken`

웹도 Firebase Auth로 로그인하므로 **같은 종류의 ID 토큰**이 나온다. 서버 코드는
한 줄도 바뀌지 않았고, Firebase 프로젝트가 같으니 **uid도 같다** — 앱에서 구글로
가입한 계정으로 웹에서도 그대로 로그인된다.

## 1. Firebase — 구글 + 애플

Firebase 콘솔 → 프로젝트 `tichu-online-95`

1. **웹 앱 등록** (완료). appId는 코드에 들어갔다.

   **apiKey 찾는 곳** — 다음 중 아무 데나 같은 값이다:
   - ⚙️ 프로젝트 설정 → **일반** 탭 → 상단 **웹 API 키**
   - 같은 탭 아래 **내 앱** → 웹 앱 선택 → **SDK 설정 및 구성** → `구성` 라디오 →
     `firebaseConfig` 안의 `apiKey`

   `AIza...`로 시작하는 문자열이다. 이걸 `lib/firebase_options.dart`의
   `_webApiKey` 기본값에 넣거나 `FIREBASE_WEB_API_KEY` 시크릿으로 준다.

   나머지(projectId, messagingSenderId, authDomain, storageBucket)는
   이미 박혀 있다. 프로젝트 공용 값이라서다.

2. **승인된 도메인**: Authentication → Settings → 승인된 도메인에
   `tichu.jiny.shop` 추가. **이게 실질적인 보안 장치다** — 키 자체는 웹 앱이
   평문으로 내보내므로 비밀이 아니다. 로컬 테스트를 하려면 `localhost`도
   기본으로 들어가 있는지 확인.

3. **애플 제공자**: Authentication → Sign-in method → Apple 사용 설정.
   Apple Developer 쪽에서 **Services ID**와 키를 만들어 넣어야 하며,
   Return URL은 Firebase가 알려주는
   `https://tichu-online-95.firebaseapp.com/__/auth/handler` 를 Apple에 등록한다.

   > 앱(iOS)의 애플 로그인과는 **별개 설정**이다. 앱은 네이티브 시트를 쓰고
   > 웹은 OAuth 팝업을 쓴다.

## 2. 카카오

카카오 개발자 → 내 애플리케이션 → 해당 앱

1. **앱 키 → JavaScript 키** (앱의 네이티브 키와 다른 값)
   → 이미 `lib/config/social_config.dart`에 넣어뒀다. 바꿀 일이 있으면
   `KAKAO_JS_KEY` 시크릿으로 덮어쓸 수 있다.
2. **플랫폼 → Web** 에 사이트 도메인 `https://tichu.jiny.shop` 등록.
   **이게 유일하게 꼭 해야 하는 등록이다** — JS 키를 인가하는 건 이 도메인이다.
3. **카카오 로그인 활성화 ON**.

### Redirect URI는 넣을 필요 없다

콘솔이 입력을 요구하면 아무거나(`https://tichu.jiny.shop/play/`) 채워두면 되지만
**실제로 쓰이지 않는다.** 웹에서 `loginWithKakaoAccount()`는 redirect_uri 자리에
URL이 아니라 `'JS-SDK'` 라는 센티널을 넘긴다:

```dart
// kakao_flutter_sdk_user/lib/src/user_api.dart
final redirectUri = kIsWeb
    ? CommonConstants.webAccountLoginRedirectUri  // = 'JS-SDK'
    : KakaoSdk.redirectUri;                        // = 'kakao{key}://oauth'
```

JS SDK 팝업은 어디로 이동하는 대신 opener로 결과를 돌려주기 때문이다.
Redirect URI는 REST API 방식에서만 쓴다.

## 3. GitHub 시크릿

appId와 카카오 JS 키는 이미 코드에 기본값으로 들어가 있으므로 **필요 없다.**
남은 건 하나뿐:

| 이름 | 값 | 필요? |
|---|---|---|
| `FIREBASE_WEB_API_KEY` | Firebase 웹 앱 apiKey | **필요** |
| `FIREBASE_WEB_APP_ID` | 웹 앱 appId | 코드에 있음 |
| `KAKAO_JS_KEY` | 카카오 JavaScript 키 | 코드에 있음 |

시크릿을 설정하면 코드 기본값보다 우선한다(다른 Firebase 프로젝트로 돌릴 때 유용).
`.github/workflows/deploy.yml`이 `--dart-define`으로 넘긴다.

## 로컬에서 미리 확인하려면

```bash
flutter build web --release --base-href=/play/ --pwa-strategy=none \
  --dart-define=FIREBASE_WEB_API_KEY=... \
  --dart-define=FIREBASE_WEB_APP_ID=... \
  --dart-define=KAKAO_JS_KEY=...
```

Firebase 승인된 도메인에 `localhost`가 있어야 팝업이 뜬다.

## 확인 방법

로그인 화면에 버튼이 나타나면 키가 전달된 것이다. 눌렀을 때:

- 팝업이 뜨고 로그인 후 로비로 들어가면 성공
- `api-key-not-valid` → 키 오타
- `auth/unauthorized-domain` → 승인된 도메인 누락
- 카카오 `KOE006`/`KOE101` 등 → 플랫폼 Web 사이트 도메인 미등록

## 알아둘 것

- 웹 애플 로그인은 **안드로이드 브라우저에서도 뜬다.** 네이티브 시트가 아니라
  그냥 OAuth 팝업이라서다. 앱에서는 종전대로 iOS에서만 보인다.
- 팝업 차단기를 켠 브라우저에서는 구글/애플 팝업이 막힐 수 있다.
  현재는 `signInWithPopup`만 쓴다. 문제가 되면 `signInWithRedirect`로
  폴백을 넣어야 하는데, 리다이렉트는 앱 상태가 한 번 날아가므로
  실제로 불편하다는 보고가 나오기 전까지는 팝업만 유지한다.
