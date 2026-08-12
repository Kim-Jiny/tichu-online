# 그냥 두면 언젠가 깨지는 것들

기한이 있는 유지보수만 모은다. 지금 동작한다는 이유로 잊혔다가, 하필
급할 때 터지는 종류의 일들이다.

각 항목은 **왜 지금은 괜찮은지**와 **언제 안 괜찮아지는지**를 같이 적는다.
전자가 없으면 불필요하게 서두르게 되고, 후자가 없으면 영원히 미룬다.

---

## 1. GitHub Actions — Node 20 액션 (배포 파이프라인)

**상태**: 경고. 배포는 정상 동작 중.
**깨지는 시점**: GitHub 이 러너에서 Node 20 호환 레이어를 걷어낼 때.
**터지는 자리**: `.github/workflows/deploy.yml` — 즉 **실서버 배포 경로**.

### 증상

배포 성공 후에도 매번 붙는 애노테이션:

```
Node.js 20 is deprecated. The following actions target Node.js 20 but are
being forced to run on Node.js 24: actions/checkout@v4,
actions/upload-artifact@v4, actions/download-artifact@v4
```

우리 앱이나 서버 런타임과는 무관하다. 러너가 액션 스크립트를 돌리는
Node 버전 이야기다. 액션들이 매니페스트에 `using: node20` 을 적어뒀는데
GitHub 이 그걸 Node 24 로 강제 실행하고 있다.

### 지금은 왜 괜찮은가

강제 실행이 실제로 성공하고 있다. 2.8.3 배포에서 프로덕션
`main.dart.js` 의 SHA-256 이 로컬 릴리스 빌드와 바이트 단위로 일치했다 —
checkout·upload·download 가 제 할 일을 다 했다는 뜻이다.

### 해야 할 일

세 개를 메이저 버전 올린다. 전부 Node 24 를 타깃한다.

| 지금 | 바꿀 것 |
|---|---|
| `actions/checkout@v4` (deploy.yml:16) | `@v5` |
| `actions/upload-artifact@v4` (:72) | `@v5` |
| `actions/download-artifact@v4` (:82) | `@v5` |

`subosito/flutter-action@v2` 와 `appleboy/scp-action` · `appleboy/ssh-action`
은 이 경고에 안 걸린다. 건드리지 말 것.

### 왜 위험이 낮은가

`upload/download-artifact` 의 진짜 파괴적 변경(불변 아티팩트, 같은 이름
재업로드 금지)은 **v3 → v4 에서 이미 겪었다.** v4 → v5 는 사실상 런타임
버전업이다. `checkout` 도 마찬가지.

### 언제 하나

**배포할 일이 생긴 날, 그 커밋에 얹어서 한다.**

이 워크플로는 실행해봐야만 검증된다. 한가할 때 미리 바꿔두면 며칠 뒤
급한 배포에서 처음 돌아가고, 거기서 문제가 생기면 원인 후보가 둘(내
변경 + 워크플로 변경)로 늘어난다. 어차피 배포하는 날 함께 올리면 그
자리에서 결과를 본다.

### 확인 방법

`gh run watch <id> --exit-status` 로 `build-web` → `deploy` 가 모두 통과하고,
애노테이션에서 Node 경고가 사라졌는지 본다. 그리고 배포가 실제로
반영됐는지는 성공 로그가 아니라 바이트로 확인한다:

```sh
curl -s https://tichu.kr/main.dart.js | shasum -a 256 | cut -c1-16
shasum -a 256 flutter_app/build/web/main.dart.js | cut -c1-16   # 같아야 한다
```

---

## 2. INVITE_BASE_URL → tichu.kr

`docs/DOMAIN_MIGRATION.md` 2단계 참조. 여기서는 존재만 알린다 — 그 문서에
전체 순서와 왜 지금 바꾸면 안 되는지가 적혀 있다.

**한 줄 요약**: 초대 링크에 찍히는 호스트는 *받는 사람의 앱*이 앱 링크로
등록한 것이어야 하고, 앱 링크는 설치된 바이너리 안에 있다. 2.8.3 이
충분히 보급되기 전에 tichu.kr 로 바꾸면, 앱을 깔아둔 사람이 초대를 눌러도
앱이 아니라 브라우저로 간다.

**2026-08-11 확인 — 영향 범위는 2.8.2 이하다.** 태그를 직접 열어보니
2.8.3 부터 Android 매니페스트와 iOS entitlements 에 `tichu.kr` 이 이미
들어가 있다(둘 다 두 호스트 병기). 그러니 전환 시점의 기준은 "3.0.0 보급"이
아니라 "2.8.2 이하 소멸"이다.

| 버전 | 앱 링크로 등록된 호스트 |
|---|---|
| 2.8.2 이하 | `tichu.jiny.shop` 만 |
| 2.8.3 / 3.0.0 | `tichu.kr` + `tichu.jiny.shop` |

**카카오 공유는 이 설정과 무관하게 따로 논다.** 앱은 서버가 준 초대 URL 에서
토큰만 떼어 쓰고 주소는 버린다(`kakao_invite_share_service.dart`). 실제 링크는
카카오 콘솔의 **메시지 템플릿 132295 → 공통 링크 설정 → 기본 웹 도메인 /
기본 모바일 웹 도메인**이 조립한다. 그래서 `INVITE_BASE_URL` 을 바꿔도 카카오
공유 링크는 안 바뀌고, 반대로 콘솔만 바꿔도 앱·서버 배포 없이 즉시 바뀐다.
전환할 때 두 곳을 같이 손봐야 한다.

- 플랫폼 → Web 사이트 도메인은 허용 목록일 뿐이다. 여기만 바꾸면 링크는
  그대로 옛 도메인으로 나간다(2026-08-11 에 실제로 겪음: 이미지 변경은
  반영되는데 URL 만 안 바뀌는 증상).
- 카카오 로그인 Redirect URI 는 **웹 전용**이다. 앱은 `kakao{네이티브키}://oauth`
  커스텀 스킴으로 돌아오므로(`kakao_sdk.dart` `redirectUri`) 목록을 바꿔도
  설치된 앱에는 영향이 없다. 다만 `tichu.jiny.shop` 항목을 지우면 그 호스트로
  들어온 웹 사용자의 로그인이 즉시 막힌다 — 도메인 은퇴 때 함께 지운다.
