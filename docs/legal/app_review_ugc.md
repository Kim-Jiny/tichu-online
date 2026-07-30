# 프로필 사진(UGC) 심사 대응 메모

프로필 사진은 이용자가 직접 올리는 이미지 = UGC다. 애플 심사 가이드라인 1.2와
구글 UGC 정책은 문서에 조항이 있는 것만으로는 부족하고, **심사자가 알 수 있도록**
스토어 콘솔에 적어 넣어야 하는 항목이 따로 있다. 아래는 그 붙여넣기용 문구와
체크리스트.

## 이미 되어 있는 것 (코드 + 문서)

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

## App Store Connect에 넣을 것

### 1) App Review Notes (영문, 그대로 붙여넣기)

```
User-generated content: players may upload a profile photo (a paid, time-limited
entitlement). Moderation in place:

1. Automated screening. Every upload is checked with Google Cloud Vision
   SafeSearch before it is stored. Images flagged as adult, violent, racy or
   medical are rejected and never shown to anyone. If the screening service is
   unavailable the upload is refused rather than accepted unchecked.
2. Reporting. Any player can report a profile photo from the profile dialog or
   from the chat panel, and can block the user. A reported or blocked user's
   photo is hidden from the reporter immediately.
3. Operator action. Reports appear in our admin console; we review and remove
   violating photos within 24 hours. Repeat offenders lose the profile photo
   feature or the account.
4. Terms. Our EULA states a zero-tolerance policy for objectionable content and
   abusive users, and describes the reporting flow. The privacy policy discloses
   that photos are sent to Google Cloud Vision for screening and are not
   retained by that service.
5. Contact. kjinyz@naver.com (also available via in-app Settings > Contact Us).

To test: sign in with the review account, open the profile popup, and tap the
avatar. The profile photo entitlement is already granted on that account.
```

### 2) 연령 등급 설문 (Age Rating)

- "사용자 제작 콘텐츠" 항목 → **있음**으로 답하고, 조정(moderation) 수단이
  있다고 표시. 숨기면 리젝 사유가 된다.

### 3) 앱 개인정보 보호(App Privacy) 라벨

- **User Content → Photos or Videos**: 수집함 / 사용자 신원과 연결됨 /
  용도 App Functionality
- 채팅 메시지·닉네임도 User Content(Other User Content)로 이미 표기되어야 함

### 4) 심사용 계정

- 프로필 사진 이용권이 부여된 리뷰 계정 준비. 이용권이 없으면 심사자가
  업로드 UI 자체를 볼 수 없어 "기능을 찾을 수 없다"로 리젝될 수 있다.

## Google Play

- 앱 콘텐츠 → **사용자 제작 콘텐츠** 선언, 신고·차단 수단 기재
- 데이터 세이프티: 사진(Photos) 수집·목적·제3자 처리 표기
- 위 App Review Notes 내용을 그대로 요약해 넣으면 된다

## 문서 위치

`privacy_ko/en/de.txt`, `eula_ko/en/de.txt` — 어드민 설정 페이지에서 전문 교체
(코드 시드는 실서버에 자동 반영되지 않음, `README.md` 참고)
