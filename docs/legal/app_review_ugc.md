# UGC(프로필 사진·커스텀 칭호) 심사 대응 메모

이 앱의 UGC는 두 가지다 — 이용자가 올리는 **프로필 사진**과 이용자가 직접 쓰는
**커스텀 칭호**(4글자). 애플 심사 가이드라인 1.2와 구글 UGC 정책은 문서에 조항이
있는 것만으로는 부족하고, **심사자가 알 수 있도록** 스토어 콘솔에 적어 넣어야 하는
항목이 따로 있다. 아래는 그 붙여넣기용 문구와 체크리스트.

## 이미 되어 있는 것 (코드 + 문서)

### 프로필 사진
- 업로드 시 Google Cloud Vision SafeSearch 자동 검사 → 부적절 판정이면 **등록 자체가 거부**
  (앱 문구: "부적절한 이미지로 판단되어 등록할 수 없습니다")
- 검사 불가(외부 장애) 시에도 통과시키지 않고 재시도 유도
- 프로필 팝업·채팅에서 사진 신고 / 이용자 차단
- 신고·차단한 이용자의 사진은 신고자에게 **즉시** 미표시
- 신고 접수 시 어드민에서 확인·삭제 (약관상 24시간 내 조치)
- 사진 삭제 후에도 이용권이 남아 있으면 다른 사진 업로드 가능
- 업로드 직전 안내 문구(자동 검사·공개 고지)를 사진 선택 시트에 표시
- EXIF 등 메타데이터 제거 후 저장
- 개인정보처리방침: 제3자 처리(Google Cloud Vision) 명시 + 프로필 사진 전용 절
  (ko/en/de, 시행 2026-07-29)
- 이용약관: 불쾌한 콘텐츠·괴롭힘 무관용 원칙, 신고 처리 절차 (제6조의2)

### 커스텀 칭호 (닉네임 위 4글자, 유료 기간제)
- 입력 시점 자동 검사. 허용목록 방식이라 한글·영문·숫자만 통과하고 이모지·특수문자·
  공백은 거부된다. 그 밖에 결합 문자(zalgo), 양방향 제어 문자, 제로폭·채움 문자처럼
  화면을 깨뜨리거나 보이지 않는 칭호를 만드는 문자도 차단한다.
- 금지어 목록(스태프 사칭 "운영자"·"admin"·"GM" 등 + 욕설/혐오 표현)을 소문자 변환 후
  포함 검사. 목록은 어드민에서 편집 가능하므로 배포 없이 갱신된다.
- 색상은 8종 프리셋 중 선택만 가능(자유 RGB 불가) — 배경과 같은 색으로 보이지 않게
  하거나 시즌 보상 색을 흉내 내는 것을 막는다.
- 신고 시 어드민에서 해당 칭호만 삭제 가능(이용권은 유지). 반복 위반은 기능 정지·밴.
- 이용약관 제6조의2와 개인정보처리방침 8항에 칭호 관련 조항 반영(ko/en/de).

## App Store Connect에 넣을 것

### 1) App Review Notes (영문, 그대로 붙여넣기)

```
User-generated content: two kinds, both paid, time-limited entitlements —
a profile photo, and a custom title (up to 4 characters shown above the
nickname). Moderation in place:

1. Automated screening, photos. Every upload is checked with Google Cloud
   Vision SafeSearch before it is stored. Images flagged as adult, violent,
   racy or medical are rejected and never shown to anyone. If the screening
   service is unavailable the upload is refused rather than accepted unchecked.
2. Automated screening, titles. Titles are validated server-side against an
   allow-list: Hangul, Latin letters and digits only. Emoji, symbols, spaces,
   combining marks, bidirectional controls and zero-width or filler characters
   are all rejected, as are staff-impersonating words ("admin", "GM", and the
   Korean equivalents) and a profanity list. Colour is chosen from a fixed
   palette, so a title cannot be made invisible.
3. Reporting. Any player can report a profile photo or a title from the profile
   dialog or from the chat panel, and can block the user. A reported or blocked
   user's photo is hidden from the reporter immediately.
4. Operator action. Reports appear in our admin console; we review and remove
   violating photos and titles within 24 hours. Removing a title leaves the
   entitlement in place; repeat offenders lose the feature or the account.
5. Terms. Our EULA states a zero-tolerance policy for objectionable content and
   abusive users, and describes the reporting flow. The privacy policy discloses
   that photos are sent to Google Cloud Vision for screening and are not
   retained by that service, and that titles are shown publicly next to the
   nickname.
6. Contact. kjinyz@naver.com (also available via in-app Settings > Contact Us).

To test: sign in with the review account, open the profile popup, and tap the
avatar to change the photo; the custom title is written from Shop > Inventory >
Features. Both entitlements are already granted on that account.
```

### 2) 연령 등급 설문 (Age Rating)

- "사용자 제작 콘텐츠" 항목 → **있음**으로 답하고, 조정(moderation) 수단이
  있다고 표시. 숨기면 리젝 사유가 된다.

### 3) 앱 개인정보 보호(App Privacy) 라벨

- **User Content → Photos or Videos**: 수집함 / 사용자 신원과 연결됨 /
  용도 App Functionality
- 채팅 메시지·닉네임도 User Content(Other User Content)로 이미 표기되어야 함

### 4) 심사용 계정

- 프로필 사진 이용권 **+ 커스텀 칭호 이용권**이 부여된 리뷰 계정 준비. 이용권이
  없으면 심사자가 업로드·작성 UI 자체를 볼 수 없어 "기능을 찾을 수 없다"로 리젝될
  수 있다.
- 두 아이템은 `is_purchasable = FALSE`로 배포되므로, 심사 제출 전에 어드민에서
  판매를 켜 두거나 리뷰 계정에 직접 지급해 둘 것.

## Google Play

- 앱 콘텐츠 → **사용자 제작 콘텐츠** 선언, 신고·차단 수단 기재
- 데이터 세이프티: 사진(Photos) 수집·목적·제3자 처리 표기
- 위 App Review Notes 내용을 그대로 요약해 넣으면 된다

## 운영 스위치 (어드민 → 설정)

- **프로필 사진 자동 검수**: on/off. 끄면 검수 없이 등록되므로, 방침·이 문서와
  어긋난다. 서버 부팅 로그 첫 줄에 현재 상태가 찍힌다
  (`[profile-photo] SafeSearch screening: ENABLED/DISABLED`).
- **커스텀 칭호 금지어**: 한 줄에 하나. 비우고 저장하면 코드 기본 목록으로 복귀.

## 문서 위치

`privacy_ko/en/de.txt`, `eula_ko/en/de.txt` — 어드민 설정 페이지에서 전문 교체
(코드 시드는 실서버에 자동 반영되지 않음, `README.md` 참고)
